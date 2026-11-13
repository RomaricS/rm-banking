// Currency conversion with ECB rates (units of QUOTE per 1 EUR).
export type RateTable = Map<string, number>; // quote -> rate for one date; EUR implicitly 1

export function convert(amount: number, from: string, to: string, rates: RateTable): number {
  if (from === to) return amount;
  const rFrom = from === "EUR" ? 1 : rates.get(from);
  const rTo = to === "EUR" ? 1 : rates.get(to);
  if (!rFrom || !rTo) throw new Error(`missing FX rate ${from}->${to}`);
  return Math.round((amount / rFrom) * rTo * 100) / 100;
}

/** Frankfurter (ECB) response -> rows */
export function parseFrankfurter(json: { date: string; rates: Record<string, number> }) {
  return Object.entries(json.rates).map(([quote, rate]) => ({ date: json.date, quote, rate }));
}
