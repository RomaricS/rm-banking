// POST { itemId } — unlink a bank: revoke at Plaid, delete its accounts & transactions.
import { HttpError, json, serve } from "../_shared/http.ts";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import { plaid } from "../_shared/plaid.ts";

serve(async (req, body) => {
  const admin = adminClient();
  const userId = await requireUser(req, admin);
  const { data: item } = await admin.from("bank_items").select("id").eq("id", body.itemId as string).eq("user_id", userId).single();
  if (!item) throw new HttpError(404, "item not found");
  const { data: secret } = await adminClient().from("plaid_secrets").select("access_token").eq("item_id", item.id).single();
  if (secret) await plaid("/item/remove", { access_token: secret.access_token }).catch(console.warn);
  await admin.from("bank_items").delete().eq("id", item.id); // cascades to accounts, transactions, secrets
  return json({ ok: true });
});
