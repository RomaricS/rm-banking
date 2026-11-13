import { assert, assertEquals } from "jsr:@std/assert@1";
import { detectPaymentMethod } from "../_shared/paymentMethod.ts";
import { merchantKey, displayName } from "../_shared/normalize.ts";
import { pickCategory } from "../_shared/categorize.ts";
import { classifyKinds, isCoveredSettlement } from "../_shared/kinds.ts";
import { detectSchedule, monthFor, periodFor } from "../_shared/payPeriod.ts";
import { convert } from "../_shared/fx.ts";
import type { AccountInfo, CategoryInfo, TxInput } from "../_shared/types.ts";

const checkingUS: AccountInfo = { id: "chk", type: "depository", subtype: "checking", cardKind: "debit", currency: "USD", country: "US" };
const creditCA: AccountInfo = { id: "cc", type: "credit", subtype: "credit card", cardKind: "credit", currency: "CAD", country: "CA" };
const lbp: AccountInfo = { id: "lbp", type: "depository", subtype: "checking", cardKind: "deferred", currency: "EUR", country: "FR" };
const revolut: AccountInfo = { id: "rev", type: "depository", subtype: "checking", cardKind: "debit", currency: "EUR", country: "FR" };
const uk: AccountInfo = { id: "uk", type: "depository", subtype: "checking", cardKind: "debit", currency: "GBP", country: "GB" };

const tx = (o: Partial<TxInput>): TxInput => ({ id: crypto.randomUUID(), accountId: "chk", amount: -10, currency: "USD", date: "2026-11-10", rawName: "X", ...o });

Deno.test("payment method — France labels", () => {
  assertEquals(detectPaymentMethod(tx({ rawName: "ACHAT CB MONOPRIX 12/11 CARTE 9910", accountId: "lbp" }), lbp), "deferred_card");
  assertEquals(detectPaymentMethod(tx({ rawName: "CB CARREFOUR 03/11", accountId: "rev" }), revolut), "debit_card");
  assertEquals(detectPaymentMethod(tx({ rawName: "PRLV SEPA EDF CLIENTS PARTICULIERS" }), lbp), "direct_debit");
  assertEquals(detectPaymentMethod(tx({ rawName: "VIR INST M DUPONT" }), lbp), "transfer");
  assertEquals(detectPaymentMethod(tx({ rawName: "RETRAIT DAB 12/11 PARIS" }), lbp), "atm");
  assertEquals(detectPaymentMethod(tx({ rawName: "CHQ 1234567" }), lbp), "check");
});

Deno.test("payment method — US/CA/UK", () => {
  assertEquals(detectPaymentMethod(tx({ rawName: "Whole Foods", paymentChannel: "in store" }), checkingUS), "debit_card");
  assertEquals(detectPaymentMethod(tx({ rawName: "UBER *TRIP", accountId: "cc" }), creditCA), "credit_card");
  assertEquals(detectPaymentMethod(tx({ rawName: "INTERAC E-TRANSFER TO ALEX" }), checkingUS), "transfer");
  assertEquals(detectPaymentMethod(tx({ rawName: "IDP PURCHASE - TIM HORTONS" }), checkingUS), "debit_card");
  assertEquals(detectPaymentMethod(tx({ rawName: "DD *DOORDASH BURGERS", paymentChannel: "online" }), checkingUS), "debit_card");
  assertEquals(detectPaymentMethod(tx({ rawName: "DD BRITISH GAS" }), uk), "direct_debit");
  assertEquals(detectPaymentMethod(tx({ rawName: "Netflix", pfcDetailed: "TRANSFER_OUT_WITHDRAWAL" }), checkingUS), "atm");
});

Deno.test("merchant normalization", () => {
  assertEquals(merchantKey("ACHAT CB MONOPRIX 12/11 CARTE 9910"), "monoprix");
  assertEquals(merchantKey("SQ *BLUE BOTTLE COFFEE 0423"), "blue bottle coffee");
  assertEquals(merchantKey("PRLV SEPA EDF"), "edf");
  assertEquals(merchantKey("Uber"), merchantKey("UBER"));
  assertEquals(displayName("ACHAT CB MONOPRIX 12/11"), "Monoprix");
});

const cats: CategoryInfo[] = [
  { id: "groceries", key: "groceries", pfcMatch: ["FOOD_AND_DRINK_GROCERIES"], isIncome: false },
  { id: "restaurants", key: "restaurants", pfcMatch: ["FOOD_AND_DRINK_RESTAURANT"], isIncome: false },
  { id: "entertainment", key: "entertainment", pfcMatch: ["ENTERTAINMENT"], isIncome: false },
  { id: "subscriptions", key: "subscriptions", pfcMatch: ["ENTERTAINMENT_TV_AND_MOVIES"], isIncome: false },
  { id: "uncat", key: "uncategorized", pfcMatch: [], isIncome: false },
  { id: "pay", key: "paycheck", pfcMatch: ["INCOME_WAGES"], isIncome: true },
  { id: "oinc", key: "other_income", pfcMatch: ["INCOME"], isIncome: true },
];

Deno.test("categorize — longest PFC prefix, rules, fallback", () => {
  assertEquals(pickCategory(tx({ pfcDetailed: "ENTERTAINMENT_TV_AND_MOVIES" }), cats, []).categoryId, "subscriptions");
  assertEquals(pickCategory(tx({ pfcDetailed: "ENTERTAINMENT_CASINOS_AND_GAMBLING" }), cats, []).categoryId, "entertainment");
  const rule = [{ merchantKey: "uber", accountId: null, categoryId: "restaurants", renameTo: null }];
  const r = pickCategory(tx({ rawName: "UBER", pfcDetailed: "TRANSPORTATION_TAXIS" }), cats, rule);
  assertEquals([r.categoryId, r.source], ["restaurants", "rule"]);
  const f = pickCategory(tx({ rawName: "???" }), cats, []);
  assertEquals([f.categoryId, f.needsReview], ["uncat", true]);
  assertEquals(pickCategory(tx({ amount: 3250, pfcDetailed: "INCOME_WAGES" }), cats, []).categoryId, "pay");
});

Deno.test("kinds — transfer pairing, card payment, income, refund", () => {
  const accounts = new Map([["chk", checkingUS], ["sav", { ...checkingUS, id: "sav", subtype: "savings" }], ["cc", { ...creditCA, currency: "USD" }]]);
  const out1 = tx({ id: "a", accountId: "chk", amount: -500, date: "2026-11-12" });
  const in1 = tx({ id: "b", accountId: "sav", amount: 500, date: "2026-11-13" });
  const pay = tx({ id: "c", accountId: "chk", amount: -842.4, date: "2026-11-03" });
  const ccIn = tx({ id: "d", accountId: "cc", amount: 842.4, date: "2026-11-04" });
  const salary = tx({ id: "e", accountId: "chk", amount: 3250, pfcDetailed: "INCOME_WAGES" });
  const coffee = tx({ id: "f", accountId: "chk", amount: -6.4 });
  const refund = tx({ id: "g", accountId: "cc", amount: 20 });
  const r = classifyKinds([out1, in1, pay, ccIn, salary, coffee, refund], [], accounts);
  assertEquals(r.get("a"), { kind: "transfer", pairId: "b" });
  assertEquals(r.get("b"), { kind: "transfer", pairId: "a" });
  assertEquals(r.get("c")!.kind, "card_payment");
  assertEquals(r.get("d")!.kind, "card_payment");
  assertEquals(r.get("e")!.kind, "income");
  assertEquals(r.get("f")!.kind, "spend");
  assertEquals(r.get("g")!.kind, "refund");
});

Deno.test("kinds — deferred card settlement only when purchases are visible", () => {
  const accounts = new Map([["lbp", lbp]]);
  const ops = [120, 200, 240].map((a, i) => tx({ id: `op${i}`, accountId: "lbp", currency: "EUR", amount: -a, rawName: "ACHAT CB SHOP", date: `2026-11-1${i}` }));
  const lump = tx({ id: "lump", accountId: "lbp", currency: "EUR", amount: -560, rawName: "FACTURE CARTE DU 301126 CARTE 9910", date: "2026-11-30" });
  assertEquals(classifyKinds([lump], ops, accounts).get("lump")!.kind, "card_settlement");
  assertEquals(classifyKinds([lump], [], accounts).get("lump")!.kind, "spend");
  assert(!isCoveredSettlement(lump, ops.slice(0, 1)));
});

Deno.test("pay periods", () => {
  const bi = { frequency: "biweekly" as const, anchorDate: "2026-11-07", semimonthlyDays: [1, 15] };
  assertEquals(periodFor("2026-11-13", bi), { start: "2026-11-07", end: "2026-11-20" });
  assertEquals(periodFor("2026-11-06", bi), { start: "2026-10-24", end: "2026-11-06" });
  const semi = { frequency: "semimonthly" as const, anchorDate: "2026-11-01", semimonthlyDays: [1, 15] };
  assertEquals(periodFor("2026-11-13", semi), { start: "2026-11-01", end: "2026-11-14" });
  assertEquals(periodFor("2026-11-20", semi), { start: "2026-11-15", end: "2026-11-30" });
  const mo = { frequency: "monthly" as const, anchorDate: "2026-01-31", semimonthlyDays: [1, 15] };
  assertEquals(periodFor("2026-02-28", mo), { start: "2026-02-28", end: "2026-03-30" });
  assertEquals(periodFor("2026-02-10", mo), { start: "2026-01-31", end: "2026-02-27" });
  assertEquals(monthFor("2026-02-10"), { start: "2026-02-01", end: "2026-02-28" });
});

Deno.test("pay schedule detection", () => {
  assertEquals(detectSchedule(["2026-10-10", "2026-10-24", "2026-11-07", "2026-11-21"])!.frequency, "biweekly");
  assertEquals(detectSchedule(["2026-09-01", "2026-09-15", "2026-10-01", "2026-10-15", "2026-11-01"])!.frequency, "semimonthly");
  assertEquals(detectSchedule(["2026-08-28", "2026-09-28", "2026-10-28"])!.frequency, "monthly");
  assertEquals(detectSchedule(["2026-11-01"]), null);
});

Deno.test("fx", () => {
  const rates = new Map([["USD", 1.08], ["CAD", 1.5]]);
  assertEquals(convert(100, "EUR", "USD", rates), 108);
  assertEquals(convert(108, "USD", "EUR", rates), 100);
  assertEquals(convert(150, "CAD", "USD", rates), 108);
});
