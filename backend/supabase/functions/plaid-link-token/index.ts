// POST { itemId?: string, locale?: string }
// → { linkToken, expiration }. With itemId: "update mode" link token to repair a broken connection.
import { env, HttpError, json, serve } from "../_shared/http.ts";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import { plaid, plaidLanguage, SUPPORTED_COUNTRIES, webhookUrl } from "../_shared/plaid.ts";

const MAX_BANKS = 4;

serve(async (req, body) => {
  const admin = adminClient();
  const userId = await requireUser(req, admin);
  const itemId = body.itemId as string | undefined;
  const locale = body.locale as string | undefined;

  const { data: profile } = await admin.from("profiles").select("country_codes").eq("id", userId).single();
  const countries = (profile?.country_codes ?? ["US", "CA", "FR"]).filter((c: string) => SUPPORTED_COUNTRIES.includes(c));

  const request: Record<string, unknown> = {
    user: { client_user_id: userId },
    client_name: "akwe",
    language: plaidLanguage(locale),
    country_codes: countries.length ? countries : SUPPORTED_COUNTRIES,
    webhook: webhookUrl(),
  };
  const redirect = Deno.env.get("PLAID_REDIRECT_URI");
  if (redirect) request.redirect_uri = redirect; // required for OAuth banks (most EU banks, some US/CA)

  if (itemId) {
    const { data: item } = await admin.from("bank_items").select("id").eq("id", itemId).eq("user_id", userId).single();
    if (!item) throw new HttpError(404, "item not found");
    const { data: secret } = await adminClient().from("plaid_secrets").select("access_token").eq("item_id", itemId).single();
    request.access_token = secret!.access_token;
  } else {
    const { count } = await admin.from("bank_items").select("id", { count: "exact", head: true }).eq("user_id", userId);
    if ((count ?? 0) >= MAX_BANKS) throw new HttpError(409, "bank limit reached", "MAX_BANKS");
    request.products = ["transactions"];
    request.transactions = { days_requested: 730 };
  }

  const res = await plaid<{ link_token: string; expiration: string }>("/link/token/create", request);
  return json({ linkToken: res.link_token, expiration: res.expiration });
});
