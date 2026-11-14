// POST { itemId?: string }  — app: sync one or all of the user's banks (pull-to-refresh)
// POST { all: true }         — cron (service role): sync every bank of every user
import { json, serve } from "../_shared/http.ts";
import { adminClient, isServiceCall, requireUser } from "../_shared/supabase.ts";
import { syncItem } from "../_shared/syncCore.ts";
import { afterSync } from "../_shared/notifyCore.ts";
import { plaid, webhookUrl } from "../_shared/plaid.ts";

/** Points the item at our webhook (idempotent). Repairs banks linked while the URL was blank,
 *  which never received Plaid's history / recurring updates. */
async function ensureWebhook(admin: ReturnType<typeof adminClient>, itemId: string) {
  const { data: secret } = await admin.from("plaid_secrets").select("access_token").eq("item_id", itemId).single();
  if (!secret) return;
  await plaid("/item/webhook/update", { access_token: secret.access_token, webhook: webhookUrl() }).catch(console.warn);
}

serve(async (req, body) => {
  const admin = adminClient();

  if (body.all === true && isServiceCall(req)) {
    const { data: items } = await admin.from("bank_items").select("id, user_id").neq("status", "revoked");
    const users = new Set<string>();
    const results = [];
    for (const it of items ?? []) {
      results.push(await syncItem(admin, it.id).catch((e) => ({ itemId: it.id, status: "error", error: String(e) })));
      users.add(it.user_id);
    }
    for (const u of users) await afterSync(admin, u).catch(console.warn);
    return json({ synced: results.length });
  }

  const userId = await requireUser(req, admin);
  let query = admin.from("bank_items").select("id").eq("user_id", userId).neq("status", "revoked");
  if (body.itemId) query = query.eq("id", body.itemId as string);
  const { data: items } = await query;
  const results = [];
  for (const it of items ?? []) {
    await ensureWebhook(admin, it.id);
    results.push(await syncItem(admin, it.id).catch((e) => ({ itemId: it.id, status: "error", error: String(e) })));
  }
  await afterSync(admin, userId).catch(console.warn);
  return json({ results });
});
