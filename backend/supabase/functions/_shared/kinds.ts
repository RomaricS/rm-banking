// Decides what a transaction IS (spend, income, transfer between own accounts, credit-card payment,
// deferred-card settlement, refund), so money moving between your own accounts never counts as spending.
import type { AccountInfo, TxInput, TxKind } from "./types.ts";

export interface KindResult {
  kind: TxKind;
  pairId: string | null;   // matching transaction on the other side (transfers / card payments)
}

const SETTLEMENT_LABEL =
  /\b(facture\s+carte|releve\s+(cb|carte)|relevé\s+(cb|carte)|debit\s+differe|débit\s+différé|depenses\s+carte|dépenses\s+carte|total\s+carte|arrete\s+carte|prlv\s+carte)\b/i;
const CARD_PAYMENT_LABEL = /\b(payment\s+thank\s+you|autopay|card\s+payment|credit\s+card\s+payment|paiement\s+carte\s+de\s+credit|pymt|remboursement\s+carte)\b/i;

const DAY = 86_400_000;
const daysBetween = (a: string, b: string) => Math.abs(Date.parse(a) - Date.parse(b)) / DAY;

/**
 * Classify a batch. `history` should contain recent transactions of the same user (≈ 45 days)
 * so pairs that straddle sync batches are still found. Returns a map id -> KindResult for `batch`.
 */
export function classifyKinds(
  batch: TxInput[],
  history: TxInput[],
  accounts: Map<string, AccountInfo>,
): Map<string, KindResult> {
  const out = new Map<string, KindResult>();
  const pool = [...history, ...batch.filter((b) => !history.some((h) => h.id === b.id))];
  const used = new Set<string>();

  // 1. Pair opposite movements between two different own accounts (same currency, |amount| equal, ≤ 4 days).
  for (const tx of batch) {
    if (used.has(tx.id)) continue;
    const match = pool.find((o) =>
      o.id !== tx.id && !used.has(o.id) && o.accountId !== tx.accountId &&
      o.currency === tx.currency && Math.abs(o.amount + tx.amount) < 0.005 && tx.amount !== 0 &&
      daysBetween(o.date, tx.date) <= 4
    );
    if (!match) continue;
    const a = accounts.get(tx.accountId);
    const b = accounts.get(match.accountId);
    const involvesCredit = a?.type === "credit" || b?.type === "credit";
    const kind: TxKind = involvesCredit ? "card_payment" : "transfer";
    out.set(tx.id, { kind, pairId: match.id });
    if (batch.some((x) => x.id === match.id)) out.set(match.id, { kind, pairId: tx.id });
    used.add(tx.id);
    used.add(match.id);
  }

  // 2. Everything else from signals.
  for (const tx of batch) {
    if (out.has(tx.id)) continue;
    const acc = accounts.get(tx.accountId);
    const pfc = (tx.pfcDetailed ?? tx.pfcPrimary ?? "").toUpperCase();
    const label = tx.rawName;

    // Paying a credit card bill (one side only linked).
    if (pfc.startsWith("LOAN_PAYMENTS_CREDIT_CARD_PAYMENT") || CARD_PAYMENT_LABEL.test(label) ||
        (acc?.type === "credit" && tx.amount > 0 && pfc.startsWith("TRANSFER_IN"))) {
      out.set(tx.id, { kind: "card_payment", pairId: null });
      continue;
    }

    // Deferred-debit card month-end lump.
    if (tx.amount < 0 && acc?.type === "depository" && SETTLEMENT_LABEL.test(label)) {
      out.set(tx.id, { kind: isCoveredSettlement(tx, pool) ? "card_settlement" : "spend", pairId: null });
      continue;
    }

    if (tx.amount > 0) {
      if (pfc.startsWith("INCOME")) out.set(tx.id, { kind: "income", pairId: null });
      else if (pfc.startsWith("TRANSFER_IN")) out.set(tx.id, { kind: "transfer", pairId: null });
      else if (acc?.type === "credit") out.set(tx.id, { kind: "refund", pairId: null });
      else if (/\b(salaire|salary|payroll|paie|gehalt|direct\s+dep)/i.test(label)) out.set(tx.id, { kind: "income", pairId: null });
      else if (/\b(refund|remboursement|avoir|return|rembt)\b/i.test(label)) out.set(tx.id, { kind: "refund", pairId: null });
      else out.set(tx.id, { kind: "income", pairId: null });
      continue;
    }

    if (pfc.startsWith("TRANSFER_OUT") && !pfc.startsWith("TRANSFER_OUT_WITHDRAWAL")) {
      out.set(tx.id, { kind: "transfer", pairId: null });
      continue;
    }

    out.set(tx.id, { kind: "spend", pairId: null });
  }
  return out;
}

/**
 * A month-end lump only counts as a settlement if we actually see the individual card purchases
 * it pays for (≥ 50 % of the amount over the previous ~35 days on the same account). Otherwise
 * the lump is the only trace of that spending, so it stays "spend".
 */
export function isCoveredSettlement(lump: TxInput, pool: TxInput[]): boolean {
  const start = Date.parse(lump.date) - 35 * DAY;
  const end = Date.parse(lump.date);
  const cardOps = pool.filter((t) =>
    t.accountId === lump.accountId && t.id !== lump.id && t.amount < 0 &&
    Date.parse(t.date) >= start && Date.parse(t.date) <= end &&
    /\b(cb|carte|card)\b/i.test(t.rawName) && !SETTLEMENT_LABEL.test(t.rawName)
  );
  const total = cardOps.reduce((s, t) => s + Math.abs(t.amount), 0);
  return total >= Math.abs(lump.amount) * 0.5;
}

/** Whether a transaction kind counts toward spending/income stats. */
export const countsInStats = (k: TxKind) => k === "spend" || k === "income" || k === "refund";
