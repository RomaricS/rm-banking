export type PaymentMethod =
  | "debit_card" | "credit_card" | "deferred_card" | "direct_debit" | "transfer" | "atm" | "check" | "other";

export type TxKind = "spend" | "income" | "transfer" | "card_payment" | "card_settlement" | "refund";

export type CardKind = "debit" | "credit" | "deferred" | null;

export interface AccountInfo {
  id: string;
  type: string;            // depository | credit | loan | investment | other
  subtype: string | null;  // checking | savings | credit card | ...
  cardKind: CardKind;
  currency: string;
  country?: string | null;  // institution country (US, CA, FR, GB, DE...)
}

export interface TxInput {
  id: string;
  accountId: string;
  amount: number;          // signed, user POV (negative = out)
  currency: string;
  date: string;            // YYYY-MM-DD
  rawName: string;
  merchantName?: string | null;
  pfcPrimary?: string | null;
  pfcDetailed?: string | null;
  paymentChannel?: string | null;
  pending?: boolean;
}

export interface CategoryInfo {
  id: string;
  key: string | null;
  pfcMatch: string[];
  isIncome: boolean;
}

export interface RuleInfo {
  merchantKey: string;
  accountId: string | null;
  categoryId: string;
  renameTo: string | null;
}

export type PayFrequency = "weekly" | "biweekly" | "semimonthly" | "monthly";

export interface PaySchedule {
  frequency: PayFrequency;
  anchorDate: string;          // a known payday, YYYY-MM-DD
  semimonthlyDays: number[];   // e.g. [1, 15]
}
