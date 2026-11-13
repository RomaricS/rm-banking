// POST { publicToken, institution?: { id, name } }
// Exchanges the Link public token, stores the access token server-side, runs a first sync.
import { HttpError, json, serve } from "../_shared/http.ts";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import { plaid } from "../_shared/plaid.ts";
import { syncItem } from "../_shared/syncCore.ts";
import { afterSync } from "../_shared/notifyCore.ts";

serve(async (req, body) => {
  const admin = adminClient();
  const userId = await requireUser(req, admin);
  const publicToken = body.publicToken as string;
  if (!publicToken) throw new HttpError(400, "publicToken required");

  const { count } = await admin.from("bank_items").select("id", { count: "exact", head: true }).eq("user_id", userId);
  if ((count ?? 0) >= 4) throw new HttpError(409, "bank limit reached", "MAX_BANKS");

  const ex = await plaid<{ access_token: string; item_id: string }>("/item/public_token/exchange", { public_token: publicToken });
  const itemRes = await plaid<any>("/item/get", { access_token: ex.access_token });
  const institutionId: string | null = itemRes.item.institution_id ?? (body.institution as any)?.id ?? null;

  let name = (body.institution as any)?.name as string | undefined;
  let country: string | null = null;
  if (institutionId) {
    try {
      const inst = await plaid<any>("/institutions/get_by_id", { institution_id: institutionId, country_codes: ["US", "CA", "GB", "FR", "ES", "IE", "NL", "DE", "IT", "BE", "PT"] });
      name = inst.institution.name;
      country = inst.institution.country_codes?.[0] ?? null;
    } catch (_) { /* keep client-provided name */ }
  }

  // Same bank linked twice → keep the new connection, drop the old one.
  if (institutionId) {
    const { data: dup } = await admin.from("bank_items").select("id, plaid_item_id").eq("user_id", userId).eq("institution_id", institutionId);
    for (const d of dup ?? []) {
      const { data: s } = await adminClient().from("plaid_secrets").select("access_token").eq("item_id", d.id).single();
      if (s) await plaid("/item/remove", { access_token: s.access_token }).catch(() => {});
      await admin.from("bank_items").delete().eq("id", d.id);
    }
  }

  const { data: item, error } = await admin.from("bank_items").insert({
    user_id: userId, plaid_item_id: ex.item_id, institution_id: institutionId, institution_name: name ?? "Bank", country,
  }).select().single();
  if (error) throw error;
  await adminClient().from("plaid_secrets").insert({ item_id: item.id, access_token: ex.access_token });

  // Make sure the user's Link country list includes this bank's country for next time.
  if (country) {
    const { data: profile } = await admin.from("profiles").select("country_codes").eq("id", userId).single();
    const codes = new Set<string>(profile?.country_codes ?? []);
    if (!codes.has(country)) await admin.from("profiles").update({ country_codes: [...codes, country] }).eq("id", userId);
  }

  const result = await syncItem(admin, item.id, { recurring: true }).catch((e) => ({ status: "pending", error: String(e) }));
  await afterSync(admin, userId).catch(console.warn);
  return json({ item, sync: result });
});
