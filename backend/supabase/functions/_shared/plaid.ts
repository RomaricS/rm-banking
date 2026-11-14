import { env, HttpError } from "./http.ts";

const HOSTS: Record<string, string> = {
  sandbox: "https://sandbox.plaid.com",
  production: "https://production.plaid.com",
};

export class PlaidError extends HttpError {
  constructor(public plaidCode: string, message: string, status = 400) {
    super(status, message, plaidCode);
  }
}

export async function plaid<T = any>(path: string, body: Record<string, unknown>): Promise<T> {
  const host = HOSTS[env("PLAID_ENV", "sandbox")] ?? HOSTS.sandbox;
  const res = await fetch(host + path, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Plaid-Version": "2020-09-14" },
    body: JSON.stringify({ client_id: env("PLAID_CLIENT_ID"), secret: env("PLAID_SECRET"), ...body }),
  });
  const data = await res.json();
  if (!res.ok) {
    // Logged (no secrets) so failures are diagnosable from the function logs.
    console.error(`plaid ${path} ${res.status} ${data.error_type ?? ""} ${data.error_code ?? ""}: ${data.error_message ?? ""}`);
    throw new PlaidError(data.error_code ?? "PLAID_ERROR", data.error_message ?? "Plaid request failed", res.status >= 500 ? 502 : 400);
  }
  return data as T;
}

/** Where Plaid posts item events. PLAID_WEBHOOK_URL overrides; blank means "use our own function". */
export const webhookUrl = () => Deno.env.get("PLAID_WEBHOOK_URL") || `${env("SUPABASE_URL")}/functions/v1/plaid-webhook`;

/** Countries Plaid supports at all. */
const PLAID_COUNTRIES = ["US", "CA", "GB", "FR", "ES", "IE", "NL", "DE", "IT", "PL", "DK", "NO", "SE", "EE", "LT", "LV", "PT", "BE", "AT", "FI"];

/** Countries we open Link for: the ones this Plaid account is approved for (PLAID_COUNTRIES env,
 *  e.g. "US,CA"). One unapproved code makes Plaid reject the whole link token with INVALID_FIELD. */
export const SUPPORTED_COUNTRIES: string[] = (() => {
  const configured = (Deno.env.get("PLAID_COUNTRIES") ?? "").split(",").map((c) => c.trim().toUpperCase()).filter(Boolean);
  const allowed = configured.filter((c) => PLAID_COUNTRIES.includes(c));
  return allowed.length ? allowed : PLAID_COUNTRIES;
})();

export function plaidLanguage(locale: string | undefined): string {
  const l = (locale ?? "en").slice(0, 2).toLowerCase();
  return ["en", "fr", "es", "nl", "de", "it", "pl", "da", "no", "sv", "et", "lt", "lv", "pt", "fi"].includes(l) ? l : "en";
}
