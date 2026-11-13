// Picks a category: user rule > Plaid PFC mapping (longest prefix) > fallback.
import type { CategoryInfo, RuleInfo, TxInput } from "./types.ts";
import { merchantKey } from "./normalize.ts";

export interface CategoryPick {
  categoryId: string | null;
  source: "rule" | "plaid" | "default";
  needsReview: boolean;
  renameTo: string | null;
}

export function pickCategory(
  tx: TxInput,
  categories: CategoryInfo[],
  rules: RuleInfo[],
  pfcConfidence?: string | null,
): CategoryPick {
  const key = merchantKey(tx.merchantName || tx.rawName);

  // 1. Rules: account-specific first, then global.
  const rule = rules.find((r) => r.merchantKey === key && r.accountId === tx.accountId) ??
    rules.find((r) => r.merchantKey === key && r.accountId === null);
  if (rule) return { categoryId: rule.categoryId, source: "rule", needsReview: false, renameTo: rule.renameTo };

  // 2. Plaid PFC, longest matching prefix wins (detailed beats primary).
  const pfc = (tx.pfcDetailed ?? tx.pfcPrimary ?? "").toUpperCase();
  let best: CategoryInfo | null = null;
  let bestLen = 0;
  if (pfc) {
    for (const c of categories) {
      for (const prefix of c.pfcMatch) {
        if (pfc.startsWith(prefix) && prefix.length > bestLen) {
          best = c;
          bestLen = prefix.length;
        }
      }
    }
  }
  // Incoming money never lands in a spending category and vice versa.
  if (best && best.isIncome !== tx.amount > 0) best = null;

  if (best) {
    const lowConfidence = pfcConfidence === "LOW" || pfcConfidence === "UNKNOWN";
    return { categoryId: best.id, source: "plaid", needsReview: lowConfidence, renameTo: null };
  }

  const fallbackKey = tx.amount > 0 ? "other_income" : "uncategorized";
  const fallback = categories.find((c) => c.key === fallbackKey) ?? null;
  return { categoryId: fallback?.id ?? null, source: "default", needsReview: true, renameTo: null };
}
