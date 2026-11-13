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
    throw new PlaidError(data.error_code ?? "PLAID_ERROR", data.error_message ?? "Plaid request failed", res.status >= 500 ? 502 : 400);
  }
  return data as T;
}

/** Countries we open Link for (Plaid only accepts supported codes). */
export const SUPPORTED_COUNTRIES = ["US", "CA", "GB", "FR", "ES", "IE", "NL", "DE", "IT", "PL", "DK", "NO", "SE", "EE", "LT", "LV", "PT", "BE", "AT", "FI"];

export function plaidLanguage(locale: string | undefined): string {
  const l = (locale ?? "en").slice(0, 2).toLowerCase();
  return ["en", "fr", "es", "nl", "de", "it", "pl", "da", "no", "sv", "et", "lt", "lv", "pt", "fi"].includes(l) ? l : "en";
}
