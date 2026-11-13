// POST {} — unlink every bank at Plaid, then delete the user (all rows cascade).
import { json, serve } from "../_shared/http.ts";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import { plaid } from "../_shared/plaid.ts";

serve(async (req) => {
  const admin = adminClient();
  const userId = await requireUser(req, admin);
  const { data: items } = await admin.from("bank_items").select("id").eq("user_id", userId);
  for (const it of items ?? []) {
    const { data: s } = await adminClient().from("plaid_secrets").select("access_token").eq("item_id", it.id).single();
    if (s) await plaid("/item/remove", { access_token: s.access_token }).catch(console.warn);
  }
  // Goals owned with partners: hand them over instead of deleting the partner's progress.
  const { data: owned } = await admin.from("goals").select("id").eq("owner_id", userId);
  for (const g of owned ?? []) {
    const { data: partner } = await admin.from("goal_members").select("user_id").eq("goal_id", g.id).neq("user_id", userId).limit(1);
    if (partner?.length) {
      await admin.from("goals").update({ owner_id: partner[0].user_id }).eq("id", g.id);
      await admin.from("goal_members").update({ role: "owner" }).eq("goal_id", g.id).eq("user_id", partner[0].user_id);
    }
  }
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) throw error;
  return json({ ok: true });
});
