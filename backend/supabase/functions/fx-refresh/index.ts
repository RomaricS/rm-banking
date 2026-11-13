// Daily ECB rates from frankfurter.app (free, no key). First run backfills 2 years.
// POST {} (cron, service role) or { backfill: true }
import { HttpError, json, serve } from "../_shared/http.ts";
import { adminClient, isServiceCall } from "../_shared/supabase.ts";

const QUOTES = ["USD", "CAD", "GBP", "CHF", "SEK", "NOK", "DKK", "PLN", "XOF", "JPY", "AUD"]; // XOF: CFA franc (Benin)
const API = "https://api.frankfurter.app";

serve(async (req, body) => {
  if (!isServiceCall(req)) throw new HttpError(403, "service only");
  const admin = adminClient();
  const { count } = await admin.from("fx_rates").select("date", { count: "exact", head: true });
  const rows: { date: string; quote: string; rate: number }[] = [];

  if (body.backfill || !count) {
    const start = new Date(Date.now() - 730 * 86_400_000).toISOString().slice(0, 10);
    const res = await fetch(`${API}/${start}..?from=EUR&to=${QUOTES.filter((q) => q !== "XOF").join(",")}`);
    const data = await res.json();
    for (const [date, rates] of Object.entries<Record<string, number>>(data.rates)) {
      for (const [quote, rate] of Object.entries(rates)) rows.push({ date, quote, rate });
      rows.push({ date, quote: "XOF", rate: 655.957 }); // fixed peg
    }
  } else {
    const res = await fetch(`${API}/latest?from=EUR&to=${QUOTES.filter((q) => q !== "XOF").join(",")}`);
    const data = await res.json();
    for (const [quote, rate] of Object.entries<number>(data.rates)) rows.push({ date: data.date, quote, rate });
    rows.push({ date: data.date, quote: "XOF", rate: 655.957 });
  }
  for (let i = 0; i < rows.length; i += 1000) {
    const { error } = await admin.from("fx_rates").upsert(rows.slice(i, i + 1000), { onConflict: "date,quote" });
    if (error) throw error;
  }
  return json({ inserted: rows.length });
});
