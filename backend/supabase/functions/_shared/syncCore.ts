// Pulls new data for one bank item from Plaid and writes enriched rows.
import type { Admin } from "./supabase.ts";
import { plaid, PlaidError } from "./plaid.ts";
import { detectPaymentMethod } from "./paymentMethod.ts";
import { pickCategory } from "./categorize.ts";
import { classifyKinds } from "./kinds.ts";
import { displayName } from "./normalize.ts";
import { detectSchedule } from "./payPeriod.ts";
import type { AccountInfo, CategoryInfo, CardKind, RuleInfo, TxInput } from "./types.ts";

export interface SyncResult { itemId: string; added: number; modified: number; removed: number; status: string }

interface PlaidTx {
  transaction_id: string;
  account_id: string;
  amount: number;
  iso_currency_code: string | null;
  unofficial_currency_code: string | null;
  date: string;
  authorized_date: string | null;
  name: string;
  original_description?: string | null;
  merchant_name: string | null;
  logo_url?: string | null;
  pending: boolean;
  pending_transaction_id: string | null;
  payment_channel: string;
  personal_finance_category?: { primary: string; detailed: string; confidence_level?: string } | null;
}

const DAY = 86_400_000;

export async function syncItem(admin: Admin, itemId: string, opts: { recurring?: boolean } = {}): Promise<SyncResult> {
  const { data: item, error: itemErr } = await admin.from("bank_items").select("*").eq("id", itemId).single();
  if (itemErr || !item) throw new Error(`item ${itemId} not found`);
  const { data: secret } = await admin.from("plaid_secrets").select("access_token, sync_cursor").eq("item_id", itemId).single();
  if (!secret) throw new Error(`no secret for item ${itemId}`);
  const userId: string = item.user_id;

  // 1. Pull all pages from /transactions/sync (restart the whole loop if Plaid reports a mutation mid-pagination).
  let added: PlaidTx[] = [], modified: PlaidTx[] = [], removed: { transaction_id: string }[] = [];
  let cursor: string | null = secret.sync_cursor;
  try {
    for (let attempt = 0; attempt < 3; attempt++) {
      added = []; modified = []; removed = [];
      let c = secret.sync_cursor as string | null;
      try {
        let hasMore = true;
        while (hasMore) {
          const page = await plaid<any>("/transactions/sync", {
            access_token: secret.access_token,
            cursor: c ?? undefined,
            count: 500,
            options: { include_original_description: true, include_personal_finance_category: true, days_requested: 730 },
          });
          added.push(...page.added); modified.push(...page.modified); removed.push(...page.removed);
          hasMore = page.has_more;
          c = page.next_cursor;
        }
        cursor = c;
        break;
      } catch (e) {
        if (e instanceof PlaidError && e.plaidCode === "TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION") continue;
        throw e;
      }
    }
  } catch (e) {
    if (e instanceof PlaidError && ["ITEM_LOGIN_REQUIRED", "PENDING_EXPIRATION", "ITEM_LOCKED"].includes(e.plaidCode)) {
      await admin.from("bank_items").update({ status: "login_required", error_code: e.plaidCode }).eq("id", itemId);
      return { itemId, added: 0, modified: 0, removed: 0, status: "login_required" };
    }
    if (e instanceof PlaidError && e.plaidCode === "PRODUCT_NOT_READY") {
      return { itemId, added: 0, modified: 0, removed: 0, status: "not_ready" };
    }
    await admin.from("bank_items").update({ status: "error", error_code: e instanceof PlaidError ? e.plaidCode : "UNKNOWN" }).eq("id", itemId);
    throw e;
  }

  // 2. Accounts & balances.
  const accRes = await plaid<any>("/accounts/get", { access_token: secret.access_token });
  const { data: existingAccounts } = await admin.from("accounts").select("id, plaid_account_id, card_kind").eq("item_id", itemId);
  const existingByPlaid = new Map((existingAccounts ?? []).map((a: any) => [a.plaid_account_id, a]));
  const accountRows = accRes.accounts.map((a: any, i: number) => {
    const prev = existingByPlaid.get(a.account_id);
    const defaultKind: CardKind = a.type === "credit" ? "credit" : (a.subtype === "checking" ? "debit" : null);
    return {
      user_id: userId,
      item_id: itemId,
      plaid_account_id: a.account_id,
      name: a.name,
      official_name: a.official_name,
      mask: a.mask,
      type: a.type,
      subtype: a.subtype,
      currency: a.balances.iso_currency_code ?? a.balances.unofficial_currency_code ?? "USD",
      // Plaid reports credit balances as positive amounts owed; store them negative (liability).
      current_balance: a.balances.current == null ? null : (a.type === "credit" || a.type === "loan" ? -a.balances.current : a.balances.current),
      available_balance: a.balances.available,
      credit_limit: a.balances.limit,
      card_kind: prev?.card_kind ?? defaultKind,
      sort: i,
    };
  });
  const { data: savedAccounts, error: accErr } = await admin.from("accounts")
    .upsert(accountRows, { onConflict: "plaid_account_id" })
    .select("id, plaid_account_id, type, subtype, card_kind, currency");
  if (accErr) throw accErr;
  const accountIdByPlaid = new Map(savedAccounts!.map((a: any) => [a.plaid_account_id, a.id]));

  // All user accounts (for cross-bank transfer pairing).
  const { data: allAccounts } = await admin.from("accounts").select("id, type, subtype, card_kind, currency, item_id").eq("user_id", userId);
  const { data: items } = await admin.from("bank_items").select("id, country").eq("user_id", userId);
  const countryByItem = new Map((items ?? []).map((i: any) => [i.id, i.country]));
  const accounts = new Map<string, AccountInfo>((allAccounts ?? []).map((a: any) => [a.id, {
    id: a.id, type: a.type, subtype: a.subtype, cardKind: a.card_kind, currency: a.currency, country: countryByItem.get(a.item_id) ?? null,
  }]));

  // 3. Context for enrichment.
  const { data: cats } = await admin.from("categories").select("id, key, pfc_match, pockets!inner(is_income)").eq("user_id", userId).eq("archived", false);
  const categories: CategoryInfo[] = (cats ?? []).map((c: any) => ({ id: c.id, key: c.key, pfcMatch: c.pfc_match ?? [], isIncome: c.pockets.is_income }));
  const { data: ruleRows } = await admin.from("rules").select("merchant_key, account_id, category_id, rename_to").eq("user_id", userId);
  const rules: RuleInfo[] = (ruleRows ?? []).map((r: any) => ({ merchantKey: r.merchant_key, accountId: r.account_id, categoryId: r.category_id, renameTo: r.rename_to }));

  const since = new Date(Date.now() - 50 * DAY).toISOString().slice(0, 10);
  const { data: hist } = await admin.from("transactions")
    .select("plaid_transaction_id, account_id, amount, currency, date, raw_name, pfc_primary, pfc_detailed")
    .eq("user_id", userId).gte("date", since).is("split_parent_id", null);
  const history: TxInput[] = (hist ?? []).filter((h: any) => h.plaid_transaction_id).map((h: any) => ({
    id: h.plaid_transaction_id, accountId: h.account_id, amount: Number(h.amount), currency: h.currency, date: h.date,
    rawName: h.raw_name, pfcPrimary: h.pfc_primary, pfcDetailed: h.pfc_detailed,
  }));

  // Existing rows (to keep user choices on modified/posted transactions).
  const touchedIds = [...added, ...modified].map((t) => t.transaction_id);
  const pendingIds = added.map((t) => t.pending_transaction_id).filter(Boolean) as string[];
  const lookupIds = [...touchedIds, ...pendingIds];
  const existingTx = new Map<string, any>();
  for (let i = 0; i < lookupIds.length; i += 500) {
    const { data } = await admin.from("transactions")
      .select("plaid_transaction_id, category_id, category_source, note, tags, excluded, merchant_name, needs_review")
      .in("plaid_transaction_id", lookupIds.slice(i, i + 500));
    for (const r of data ?? []) existingTx.set(r.plaid_transaction_id, r);
  }

  // 4. Build rows.
  const inputs: TxInput[] = [];
  const rows: any[] = [];
  for (const t of [...added, ...modified]) {
    const accountId = accountIdByPlaid.get(t.account_id);
    if (!accountId) continue;
    const account = accounts.get(accountId)!;
    const input: TxInput = {
      id: t.transaction_id,
      accountId,
      amount: -t.amount,
      currency: t.iso_currency_code ?? t.unofficial_currency_code ?? account.currency,
      date: t.authorized_date ?? t.date,
      rawName: t.original_description ?? t.name,
      merchantName: t.merchant_name,
      pfcPrimary: t.personal_finance_category?.primary ?? null,
      pfcDetailed: t.personal_finance_category?.detailed ?? null,
      paymentChannel: t.payment_channel,
      pending: t.pending,
    };
    inputs.push(input);

    const prev = existingTx.get(t.transaction_id) ?? (t.pending_transaction_id ? existingTx.get(t.pending_transaction_id) : undefined);
    const userOwned = prev && (prev.category_source === "user" || prev.category_source === "rule");
    const pick = pickCategory(input, categories, rules, t.personal_finance_category?.confidence_level ?? null);

    rows.push({
      user_id: userId,
      account_id: accountId,
      plaid_transaction_id: t.transaction_id,
      pending: t.pending,
      pending_transaction_id: t.pending_transaction_id,
      amount: input.amount,
      currency: input.currency,
      date: input.date,
      authorized_date: t.authorized_date,
      raw_name: input.rawName,
      merchant_name: prev?.merchant_name ?? pick.renameTo ?? t.merchant_name ?? displayName(input.rawName),
      logo_url: t.logo_url ?? null,
      pfc_primary: input.pfcPrimary,
      pfc_detailed: input.pfcDetailed,
      payment_channel: t.payment_channel,
      payment_method: detectPaymentMethod(input, account),
      category_id: userOwned ? prev.category_id : pick.categoryId,
      category_source: userOwned ? prev.category_source : pick.source,
      needs_review: userOwned ? false : (prev ? prev.needs_review && pick.needsReview : pick.needsReview),
      excluded: prev?.excluded ?? false,
      note: prev?.note ?? null,
      tags: prev?.tags ?? [],
    });
  }

  // 5. Kinds (transfers, card payments, settlements...) across this batch + recent history.
  const kinds = classifyKinds(inputs, history, accounts);
  for (const r of rows) {
    const k = kinds.get(r.plaid_transaction_id);
    r.kind = k?.kind ?? "spend";
    r._pair = k?.pairId ?? null;
    // A one-sided transfer the user (or their rule) gave a category is real spending/income:
    // e.g. rent paid by Interac e-Transfer, or a benefit deposit. Don't flip it back to "transfer".
    if (r.kind === "transfer" && !r._pair && (r.category_source === "user" || r.category_source === "rule")) {
      r.kind = r.amount > 0 ? "income" : "spend";
    }
    // Transfers / card payments don't need a spending category or review.
    if (r.kind === "transfer" || r.kind === "card_payment" || r.kind === "card_settlement") r.needs_review = false;
  }

  // 6. Write.
  for (let i = 0; i < rows.length; i += 500) {
    const chunk = rows.slice(i, i + 500).map(({ _pair, ...rest }) => rest);
    const { error } = await admin.from("transactions").upsert(chunk, { onConflict: "plaid_transaction_id" });
    if (error) throw error;
  }
  // transfer pair links (uuid of the other side)
  const pairs = rows.filter((r) => r._pair);
  if (pairs.length) {
    const ids = [...new Set(pairs.flatMap((r) => [r.plaid_transaction_id, r._pair]))];
    const { data: idRows } = await admin.from("transactions").select("id, plaid_transaction_id").in("plaid_transaction_id", ids);
    const uuid = new Map((idRows ?? []).map((r: any) => [r.plaid_transaction_id, r.id]));
    for (const r of pairs) {
      const self = uuid.get(r.plaid_transaction_id), other = uuid.get(r._pair);
      if (self && other) {
        await admin.from("transactions").update({ transfer_pair_id: other, kind: r.kind }).eq("id", self);
        await admin.from("transactions").update({ transfer_pair_id: self, kind: r.kind, needs_review: false }).eq("id", other);
      }
    }
  }
  // Pending rows replaced by their posted version.
  const replaced = added.map((t) => t.pending_transaction_id).filter(Boolean) as string[];
  const removedIds = [...removed.map((r) => r.transaction_id), ...replaced];
  if (removedIds.length) await admin.from("transactions").delete().in("plaid_transaction_id", removedIds);

  await admin.from("plaid_secrets").update({ sync_cursor: cursor }).eq("item_id", itemId);
  await admin.from("bank_items").update({ status: "ok", error_code: null, last_synced_at: new Date().toISOString() }).eq("id", itemId);

  if (opts.recurring || added.length > 0) await syncRecurring(admin, itemId, secret.access_token, userId, accountIdByPlaid, categories, rules).catch((e) => console.warn("recurring", e));
  await maybeDetectPaySchedule(admin, userId).catch((e) => console.warn("payschedule", e));

  return { itemId, added: added.length, modified: modified.length, removed: removedIds.length, status: "ok" };
}

async function syncRecurring(
  admin: Admin, itemId: string, accessToken: string, userId: string,
  accountIdByPlaid: Map<string, string>, categories: CategoryInfo[], rules: RuleInfo[],
) {
  const res = await plaid<any>("/transactions/recurring/get", { access_token: accessToken });
  const streams = [...res.inflow_streams.map((s: any) => ({ ...s, _dir: "inflow" })), ...res.outflow_streams.map((s: any) => ({ ...s, _dir: "outflow" }))];
  const rows = streams.filter((s: any) => accountIdByPlaid.has(s.account_id)).map((s: any) => {
    const sign = s._dir === "inflow" ? 1 : -1;
    const input: TxInput = {
      id: s.stream_id, accountId: accountIdByPlaid.get(s.account_id)!, amount: sign * Math.abs(s.average_amount.amount),
      currency: s.average_amount.iso_currency_code ?? "USD", date: s.last_date, rawName: s.description, merchantName: s.merchant_name,
      pfcPrimary: s.personal_finance_category?.primary, pfcDetailed: s.personal_finance_category?.detailed,
    };
    return {
      user_id: userId,
      account_id: input.accountId,
      plaid_stream_id: s.stream_id,
      direction: s._dir,
      description: s.description,
      merchant_name: s.merchant_name ?? displayName(s.description),
      frequency: s.frequency,
      average_amount: Math.abs(s.average_amount.amount),
      last_amount: Math.abs(s.last_amount.amount),
      previous_amount: null as number | null,
      currency: input.currency,
      last_date: s.last_date,
      predicted_next_date: s.predicted_next_date ?? null,
      is_active: s.is_active,
      category_id: pickCategory(input, categories, rules).categoryId,
      updated_at: new Date().toISOString(),
    };
  });
  // keep the previous amount to detect price increases
  const { data: prev } = await admin.from("recurring_streams").select("plaid_stream_id, last_amount").eq("user_id", userId);
  const prevMap = new Map((prev ?? []).map((p: any) => [p.plaid_stream_id, Number(p.last_amount)]));
  for (const r of rows) {
    const old = prevMap.get(r.plaid_stream_id);
    if (old !== undefined && Math.abs(old - r.last_amount) > 0.009) r.previous_amount = old;
  }
  if (rows.length) await admin.from("recurring_streams").upsert(rows, { onConflict: "plaid_stream_id" });
}

/** Auto-detects the pay schedule from paychecks unless the user already confirmed one. */
async function maybeDetectPaySchedule(admin: Admin, userId: string) {
  const { data: sched } = await admin.from("pay_schedules").select("*").eq("user_id", userId).single();
  if (sched && !sched.detected && sched.income_source) return; // user-confirmed
  const since = new Date(Date.now() - 120 * DAY).toISOString().slice(0, 10);
  const { data: income } = await admin.from("transactions")
    .select("date, amount, merchant_name, raw_name").eq("user_id", userId).eq("kind", "income").gte("date", since).gt("amount", 100);
  if (!income?.length) return;
  // biggest income source by total
  const bySource = new Map<string, { dates: string[]; total: number; amounts: number[] }>();
  for (const t of income) {
    const key = (t.merchant_name ?? t.raw_name).toUpperCase().slice(0, 24);
    const e = bySource.get(key) ?? { dates: [], total: 0, amounts: [] };
    e.dates.push(t.date); e.total += Number(t.amount); e.amounts.push(Number(t.amount));
    bySource.set(key, e);
  }
  const [source, best] = [...bySource.entries()].sort((a, b) => b[1].total - a[1].total)[0];
  const detected = detectSchedule(best.dates);
  if (!detected) return;
  const typical = best.amounts.sort((a, b) => a - b)[Math.floor(best.amounts.length / 2)];
  await admin.from("pay_schedules").upsert({
    user_id: userId, frequency: detected.frequency, anchor_date: detected.anchorDate,
    semimonthly_days: detected.semimonthlyDays, income_source: source, typical_amount: typical, detected: true,
  });
}
