// Called by Plaid. Verifies the Plaid-Verification JWT (ES256) before doing anything.
import { json } from "../_shared/http.ts";
import { adminClient } from "../_shared/supabase.ts";
import { plaid } from "../_shared/plaid.ts";
import { syncItem } from "../_shared/syncCore.ts";
import { afterSync, notifyOnce } from "../_shared/notifyCore.ts";

const keyCache = new Map<string, CryptoKey>();

const b64urlDecode = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));

async function verify(req: Request, rawBody: string): Promise<boolean> {
  if (Deno.env.get("PLAID_ENV") === "sandbox" && Deno.env.get("PLAID_SKIP_WEBHOOK_VERIFY") === "1") return true;
  const jwt = req.headers.get("Plaid-Verification");
  if (!jwt) return false;
  const [h, p, s] = jwt.split(".");
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
  if (header.alg !== "ES256") return false;
  let key = keyCache.get(header.kid);
  if (!key) {
    const res = await plaid<any>("/webhook_verification_key/get", { key_id: header.kid });
    key = await crypto.subtle.importKey("jwk", res.key, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    keyCache.set(header.kid, key);
  }
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, b64urlDecode(s), new TextEncoder().encode(`${h}.${p}`));
  if (!ok) return false;
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  if (Date.now() / 1000 - claims.iat > 5 * 60) return false;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(rawBody)));
  const hex = [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex === claims.request_body_sha256;
}

Deno.serve(async (req) => {
  const raw = await req.text();
  if (!(await verify(req, raw))) return json({ error: "unverified" }, 401);
  const evt = JSON.parse(raw);
  const admin = adminClient();
  const { data: item } = await admin.from("bank_items").select("id, user_id, institution_name").eq("plaid_item_id", evt.item_id).single();
  if (!item) return json({ ok: true, ignored: "unknown item" });

  const type = `${evt.webhook_type}:${evt.webhook_code}`;
  switch (type) {
    case "TRANSACTIONS:SYNC_UPDATES_AVAILABLE":
    case "TRANSACTIONS:DEFAULT_UPDATE":
    case "TRANSACTIONS:INITIAL_UPDATE":
    case "TRANSACTIONS:HISTORICAL_UPDATE":
      await syncItem(admin, item.id);
      await afterSync(admin, item.user_id);
      break;
    case "TRANSACTIONS:RECURRING_TRANSACTIONS_UPDATE":
      await syncItem(admin, item.id, { recurring: true });
      break;
    case "ITEM:ERROR":
    case "ITEM:PENDING_EXPIRATION":
    case "ITEM:PENDING_DISCONNECT": {
      const status = evt.webhook_code === "ERROR" ? (evt.error?.error_code === "ITEM_LOGIN_REQUIRED" ? "login_required" : "error") : "pending_expiration";
      await admin.from("bank_items").update({ status, error_code: evt.error?.error_code ?? evt.webhook_code }).eq("id", item.id);
      await notifyOnce(admin, item.user_id, "reauth", "reauth", item.id, new Date().toISOString().slice(0, 7), (_lang, t) => ({
        title: t.reauthTitle({ bank: item.institution_name }), body: t.reauthBody({}), category: "REAUTH", data: { itemId: item.id },
      }));
      break;
    }
    case "ITEM:USER_PERMISSION_REVOKED":
    case "ITEM:USER_ACCOUNT_REVOKED":
      await admin.from("bank_items").update({ status: "revoked" }).eq("id", item.id);
      break;
    case "ITEM:LOGIN_REPAIRED":
      await admin.from("bank_items").update({ status: "ok", error_code: null }).eq("id", item.id);
      await syncItem(admin, item.id);
      break;
  }
  return json({ ok: true });
});
