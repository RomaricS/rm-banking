// Works out HOW a transaction was paid.
// US/CA: the account type tells debit vs credit; Plaid's payment_channel + PFC refine it.
// FR/EU/UK: banks put the method in the label (CB, PRLV, VIR, RETRAIT DAB, CHQ, DD, FPS, Lastschrift...).
import type { AccountInfo, PaymentMethod, TxInput } from "./types.ts";

interface LabelRule { re: RegExp; method: PaymentMethod | "card" }

// Order matters: first match wins. "card" is resolved to debit/credit/deferred from the account.
const LABEL_RULES: LabelRule[] = [
  // ATM
  { re: /\b(retrait|withdrawal|atm|dab|gab|geldautomat|bargeldauszahlung|cash\s+withdrawal)\b/i, method: "atm" },
  // Checks
  { re: /\b(chq|cheque|chèque|check\s*#?\d*|scheck)\b/i, method: "check" },
  // Direct debits
  { re: /\b(prlv|prelevement|prélèvement|sepa\s+dd|direct\s+debit|lastschrift|pre-?authorized\s+debit|pad)\b/i, method: "direct_debit" },
  // Transfers
  { re: /\b(vir|virement|transfer|xfer|e-?transfer|interac\s+e-?transfer|etfr|fps|faster\s+payment|bacs|überweisung|ueberweisung|zelle|wire|standing\s+order)\b/i, method: "transfer" },
  // Cards
  { re: /\b(cb|carte|card|kartenzahlung|visa|mastercard|mc|debit\s+card|pos|idp|interac|contactless|apple\s+pay|google\s+pay)\b/i, method: "card" },
];

function cardFor(account: AccountInfo): PaymentMethod {
  if (account.type === "credit" || account.subtype === "credit card" || account.cardKind === "credit") return "credit_card";
  if (account.cardKind === "deferred") return "deferred_card";
  return "debit_card";
}

export function detectPaymentMethod(tx: TxInput, account: AccountInfo): PaymentMethod {
  const label = `${tx.rawName}`.trim();

  // UK short codes ("DD", "SO") clash with US processors ("DD *DOORDASH"), so only apply them to UK banks.
  if (account.country === "GB") {
    if (/^dd\s/i.test(label)) return "direct_debit";
    if (/^so\s/i.test(label)) return "transfer";
  }

  // 1. Labels are the most precise source in Europe and still useful in North America.
  for (const rule of LABEL_RULES) {
    if (rule.re.test(label)) return rule.method === "card" ? cardFor(account) : rule.method;
  }

  // 2. Plaid's personal finance category.
  const pfc = (tx.pfcDetailed ?? tx.pfcPrimary ?? "").toUpperCase();
  if (pfc.startsWith("TRANSFER_OUT_WITHDRAWAL")) return "atm";
  if (pfc.startsWith("TRANSFER_IN") || pfc.startsWith("TRANSFER_OUT")) return "transfer";
  if (pfc.startsWith("LOAN_PAYMENTS")) return "transfer";

  // 3. Account type + channel (typical US/CA case where labels are plain merchant names).
  if (account.type === "credit") return "credit_card";
  if (tx.paymentChannel === "in store" || tx.paymentChannel === "online") return cardFor(account);

  return "other";
}
