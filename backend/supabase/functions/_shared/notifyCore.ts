// Server-side evaluation that turns data changes into push notifications.
import type { Admin } from "./supabase.ts";
import { sendPush, type Push } from "./apns.ts";
import { convert, type RateTable } from "./fx.ts";
import { monthFor, periodFor } from "./payPeriod.ts";
import { countsInStats } from "./kinds.ts";
import type { PaySchedule } from "./types.ts";

// --------------------------------------------------------------------------- i18n
type Lang = "en" | "fr";
const T: Record<Lang, Record<string, (p: Record<string, string>) => string>> = {
  en: {
    goalReachedTitle: () => "Goal reached",
    goalReachedBody: (p) => `${p.goal} hit ${p.amount}. Nice work.`,
    milestoneTitle: (p) => `${p.goal}: ${p.pct}%`,
    milestoneBody: (p) => `${p.amount} saved of ${p.target}. Keep going.`,
    budgetWarnTitle: (p) => `${p.name} at ${p.pct}%`,
    budgetWarnBody: (p) => `${p.spent} of ${p.limit}. About ${p.perDay}/day left until ${p.until}.`,
    budgetOverTitle: (p) => `${p.name} limit passed`,
    budgetOverBody: (p) => `${p.spent} of ${p.limit} this period.`,
    billTitle: (p) => `${p.name} due tomorrow`,
    billBody: (p) => `${p.amount} from ${p.account}${p.covered === "1" ? " — balance covers it." : " — balance looks short."}`,
    paydayTitle: () => "Payday summary",
    paydayBody: (p) => `Last period you spent ${p.spent} and kept ${p.rate}% of your income.`,
    reauthTitle: (p) => `Reconnect ${p.bank}`,
    reauthBody: () => "Your bank needs you to sign in again so syncing can continue.",
    joinedTitle: (p) => `${p.name} joined ${p.goal}`,
    joinedBody: () => "You're saving together now.",
    cheerTitle: (p) => `${p.name} cheered you on`,
    cheerBody: (p) => `For ${p.goal}. Keep it up!`,
  },
  fr: {
    goalReachedTitle: () => "Objectif atteint",
    goalReachedBody: (p) => `${p.goal} a atteint ${p.amount}. Bravo !`,
    milestoneTitle: (p) => `${p.goal} : ${p.pct} %`,
    milestoneBody: (p) => `${p.amount} épargnés sur ${p.target}. Continuez !`,
    budgetWarnTitle: (p) => `${p.name} à ${p.pct} %`,
    budgetWarnBody: (p) => `${p.spent} sur ${p.limit}. Environ ${p.perDay}/jour jusqu’au ${p.until}.`,
    budgetOverTitle: (p) => `Limite ${p.name} dépassée`,
    budgetOverBody: (p) => `${p.spent} sur ${p.limit} cette période.`,
    billTitle: (p) => `${p.name} prélevé demain`,
    billBody: (p) => `${p.amount} sur ${p.account}${p.covered === "1" ? " — le solde suffit." : " — le solde semble juste."}`,
    paydayTitle: () => "Bilan de la paie",
    paydayBody: (p) => `La période dernière, vous avez dépensé ${p.spent} et gardé ${p.rate} % de vos revenus.`,
    reauthTitle: (p) => `Reconnectez ${p.bank}`,
    reauthBody: () => "Votre banque demande une nouvelle connexion pour continuer la synchronisation.",
    joinedTitle: (p) => `${p.name} a rejoint ${p.goal}`,
    joinedBody: () => "Vous épargnez maintenant à deux.",
    cheerTitle: (p) => `${p.name} vous encourage`,
    cheerBody: (p) => `Pour ${p.goal}. Continuez !`,
  },
};

export function money(amount: number, currency: string, lang: Lang): string {
  return new Intl.NumberFormat(lang === "fr" ? "fr-FR" : "en-US", { style: "currency", currency, maximumFractionDigits: Math.abs(amount) >= 1000 ? 0 : 2 }).format(amount);
}

// --------------------------------------------------------------------------- delivery
type PrefKey = "goal_reached" | "goal_milestones" | "budget_warning" | "budget_exceeded" | "bills_due" | "payday_summary" | "reauth";

/**
 * Sends once per (user, kind, ref, periodKey). `build` receives the device language.
 * Returns true if this was the first time (i.e. a push was attempted).
 */
export async function notifyOnce(
  admin: Admin, userId: string, pref: PrefKey, kind: string, ref: string, periodKey: string,
  build: (lang: Lang, t: typeof T["en"]) => Push,
): Promise<boolean> {
  const { data: prefs } = await admin.from("notification_prefs").select(pref).eq("user_id", userId).single();
  if (prefs && (prefs as any)[pref] === false) return false;
  const { error } = await admin.from("notification_log").insert({ user_id: userId, kind, ref, period_key: periodKey });
  if (error) return false; // unique violation → already sent
  const { data: devices } = await admin.from("device_tokens").select("token, environment, locale").eq("user_id", userId);
  for (const d of devices ?? []) {
    const lang: Lang = (d.locale ?? "en").startsWith("fr") ? "fr" : "en";
    const ok = await sendPush(d.token, d.environment, build(lang, T[lang]));
    if (!ok) await admin.from("device_tokens").delete().eq("token", d.token);
  }
  return true;
}

/** Push without dedupe (cheers, joins). */
export async function notifyNow(admin: Admin, userId: string, build: (lang: Lang, t: typeof T["en"]) => Push) {
  const { data: devices } = await admin.from("device_tokens").select("token, environment, locale").eq("user_id", userId);
  for (const d of devices ?? []) {
    const lang: Lang = (d.locale ?? "en").startsWith("fr") ? "fr" : "en";
    const ok = await sendPush(d.token, d.environment, build(lang, T[lang]));
    if (!ok) await admin.from("device_tokens").delete().eq("token", d.token);
  }
}

// --------------------------------------------------------------------------- FX
export async function latestRates(admin: Admin): Promise<RateTable> {
  const { data: last } = await admin.from("fx_rates").select("date").order("date", { ascending: false }).limit(1);
  if (!last?.length) return new Map();
  const { data } = await admin.from("fx_rates").select("quote, rate").eq("date", last[0].date);
  return new Map((data ?? []).map((r: any) => [r.quote, Number(r.rate)]));
}

function safeConvert(amount: number, from: string, to: string, rates: RateTable): number {
  try { return convert(amount, from, to, rates); } catch { return from === to ? amount : amount; }
}

async function scheduleFor(admin: Admin, userId: string): Promise<PaySchedule> {
  const { data } = await admin.from("pay_schedules").select("frequency, anchor_date, semimonthly_days").eq("user_id", userId).single();
  return { frequency: data?.frequency ?? "monthly", anchorDate: data?.anchor_date ?? new Date().toISOString().slice(0, 10), semimonthlyDays: data?.semimonthly_days ?? [1, 15] };
}

// --------------------------------------------------------------------------- goals
/** Recomputes current_amount for members funding with an account or an earmark, then checks milestones. */
export async function refreshGoals(admin: Admin, userId: string, rates?: RateTable) {
  rates ??= await latestRates(admin);
  const { data: members } = await admin.from("goal_members")
    .select("goal_id, user_id, funding, account_id, earmark_amount, current_amount, goals!inner(currency, archived_at)")
    .eq("user_id", userId).is("goals.archived_at", null);
  const goalIds = new Set<string>();
  for (const m of members ?? []) {
    goalIds.add(m.goal_id);
    const cur = (m as any).goals.currency as string;
    let amount: number | null = null;
    if (m.funding === "account" && m.account_id) {
      const { data: acc } = await admin.from("accounts").select("current_balance, currency").eq("id", m.account_id).single();
      if (acc?.current_balance != null) amount = Math.max(0, safeConvert(Number(acc.current_balance), acc.currency, cur, rates));
    } else if (m.funding === "earmark") {
      amount = Number(m.earmark_amount ?? 0);
    }
    if (amount !== null && Math.abs(amount - Number(m.current_amount)) > 0.004) {
      await admin.from("goal_members").update({ current_amount: amount }).eq("goal_id", m.goal_id).eq("user_id", m.user_id);
    }
  }
  for (const gid of goalIds) await checkGoalMilestones(admin, gid);
}

export async function checkGoalMilestones(admin: Admin, goalId: string) {
  const { data: goal } = await admin.from("goals").select("*").eq("id", goalId).single();
  if (!goal || goal.archived_at) return;
  const { data: members } = await admin.from("goal_members").select("user_id, current_amount").eq("goal_id", goalId);
  const total = (members ?? []).reduce((s: number, m: any) => s + Number(m.current_amount), 0);
  const pct = (total / Number(goal.target_amount)) * 100;
  const reached = [25, 50, 75, 100].filter((m) => pct >= m).pop() ?? 0;
  if (reached <= goal.last_milestone) return;

  await admin.from("goals").update({ last_milestone: reached, reached_at: reached === 100 ? new Date().toISOString() : goal.reached_at }).eq("id", goalId);
  await admin.from("goal_events").insert({ goal_id: goalId, user_id: goal.owner_id, kind: reached === 100 ? "reached" : "milestone", amount: reached });

  for (const m of members ?? []) {
    if (reached === 100) {
      await notifyOnce(admin, m.user_id, "goal_reached", "goal_reached", goalId, "100", (lang, t) => ({
        title: t.goalReachedTitle({}), body: t.goalReachedBody({ goal: goal.name, amount: money(total, goal.currency, lang) }),
        category: "GOAL_REACHED", threadId: `goal-${goalId}`, data: { goalId },
      }));
    } else {
      await notifyOnce(admin, m.user_id, "goal_milestones", "goal_milestone", goalId, String(reached), (lang, t) => ({
        title: t.milestoneTitle({ goal: goal.name, pct: String(reached) }),
        body: t.milestoneBody({ amount: money(total, goal.currency, lang), target: money(Number(goal.target_amount), goal.currency, lang) }),
        category: "GOAL_MILESTONE", threadId: `goal-${goalId}`, data: { goalId },
      }));
    }
  }
}

// --------------------------------------------------------------------------- budgets
export async function evaluateBudgets(admin: Admin, userId: string, rates?: RateTable, today = new Date().toISOString().slice(0, 10)) {
  rates ??= await latestRates(admin);
  const { data: budgets } = await admin.from("budgets").select("*").eq("user_id", userId);
  if (!budgets?.length) return;
  const sched = await scheduleFor(admin, userId);
  const pay = periodFor(today, sched);
  const month = monthFor(today);
  const from = pay.start < month.start ? pay.start : month.start;

  const { data: cats } = await admin.from("categories").select("id, pocket_id, name").eq("user_id", userId);
  const { data: pockets } = await admin.from("pockets").select("id, name").eq("user_id", userId);
  const { data: txs } = await admin.from("transactions")
    .select("amount, currency, date, category_id, kind, excluded").eq("user_id", userId).gte("date", from).lte("date", today);

  for (const b of budgets) {
    const period = b.period === "month" ? month : pay;
    const catIds = b.category_id ? [b.category_id] : (cats ?? []).filter((c: any) => c.pocket_id === b.pocket_id).map((c: any) => c.id);
    const name = b.category_id ? cats?.find((c: any) => c.id === b.category_id)?.name : pockets?.find((p: any) => p.id === b.pocket_id)?.name;
    const spent = (txs ?? [])
      .filter((t: any) => !t.excluded && countsInStats(t.kind) && t.kind !== "income" && t.date >= period.start && t.date <= period.end && catIds.includes(t.category_id))
      .reduce((s: number, t: any) => s - safeConvert(Number(t.amount), t.currency, b.currency, rates!), 0);
    const limit = Number(b.amount);
    const pct = Math.round((spent / limit) * 100);
    const daysLeft = Math.max(1, Math.round((Date.parse(period.end) - Date.parse(today)) / 86_400_000) + 1);

    if (pct >= 100) {
      await notifyOnce(admin, userId, "budget_exceeded", "budget_exceeded", b.id, period.start, (lang, t) => ({
        title: t.budgetOverTitle({ name: name ?? "" }),
        body: t.budgetOverBody({ spent: money(spent, b.currency, lang), limit: money(limit, b.currency, lang) }),
        category: "BUDGET_EXCEEDED", threadId: `budget-${b.id}`, data: { budgetId: b.id },
      }));
    } else if (pct >= 80) {
      await notifyOnce(admin, userId, "budget_warning", "budget_warning", b.id, period.start, (lang, t) => ({
        title: t.budgetWarnTitle({ name: name ?? "", pct: String(pct) }),
        body: t.budgetWarnBody({
          spent: money(spent, b.currency, lang), limit: money(limit, b.currency, lang),
          perDay: money(Math.max(0, (limit - spent) / daysLeft), b.currency, lang),
          until: new Date(period.end + "T12:00:00Z").toLocaleDateString(lang === "fr" ? "fr-FR" : "en-US", { month: "short", day: "numeric" }),
        }),
        category: "BUDGET_WARNING", threadId: `budget-${b.id}`, data: { budgetId: b.id },
      }));
    }
  }
}

/** Everything that should run after a sync for one user. */
export async function afterSync(admin: Admin, userId: string) {
  const rates = await latestRates(admin);
  await refreshGoals(admin, userId, rates);
  await evaluateBudgets(admin, userId, rates);
}

// --------------------------------------------------------------------------- daily
export async function dailyForUser(admin: Admin, userId: string, today = new Date().toISOString().slice(0, 10)) {
  const tomorrow = new Date(Date.parse(today) + 86_400_000).toISOString().slice(0, 10);
  const { data: bills } = await admin.from("recurring_streams")
    .select("id, merchant_name, description, last_amount, currency, account_id, accounts!inner(name, nickname, available_balance, current_balance)")
    .eq("user_id", userId).eq("direction", "outflow").eq("is_active", true).eq("predicted_next_date", tomorrow);
  for (const b of bills ?? []) {
    const acc = (b as any).accounts;
    const bal = Number(acc.available_balance ?? acc.current_balance ?? 0);
    await notifyOnce(admin, userId, "bills_due", "bill_due", b.id, tomorrow, (lang, t) => ({
      title: t.billTitle({ name: b.merchant_name ?? b.description }),
      body: t.billBody({ amount: money(Number(b.last_amount), b.currency, lang), account: acc.nickname ?? acc.name, covered: bal >= Number(b.last_amount) ? "1" : "0" }),
      category: "BILL_DUE", data: { streamId: b.id },
    }));
  }

  // Payday summary on the first day of a new pay period.
  const sched = await scheduleFor(admin, userId);
  const current = periodFor(today, sched);
  if (current.start !== today) return;
  const prevEnd = new Date(Date.parse(today) - 86_400_000).toISOString().slice(0, 10);
  const prev = periodFor(prevEnd, sched);
  const { data: profile } = await admin.from("profiles").select("display_currency").eq("id", userId).single();
  const cur = profile?.display_currency ?? "USD";
  const rates = await latestRates(admin);
  const { data: txs } = await admin.from("transactions").select("amount, currency, kind, excluded")
    .eq("user_id", userId).gte("date", prev.start).lte("date", prev.end);
  let spent = 0, income = 0;
  for (const t of txs ?? []) {
    if (t.excluded || !countsInStats(t.kind)) continue;
    const v = safeConvert(Number(t.amount), t.currency, cur, rates);
    if (t.kind === "income") income += v; else spent -= v;
  }
  if (spent <= 0 && income <= 0) return;
  const rate = income > 0 ? Math.max(0, Math.round(((income - spent) / income) * 100)) : 0;
  await notifyOnce(admin, userId, "payday_summary", "payday_summary", "period", prev.start, (lang, t) => ({
    title: t.paydayTitle({}), body: t.paydayBody({ spent: money(spent, cur, lang), rate: String(rate) }), category: "PAYDAY",
  }));
}

export { T as strings };
