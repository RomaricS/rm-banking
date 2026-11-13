// POST { mode: "daily" }  (cron, service role) — bills due tomorrow + payday summaries for everyone
// POST { mode: "evaluate" } (app)               — re-check budgets & goals for the caller (after edits)
import { HttpError, json, serve } from "../_shared/http.ts";
import { adminClient, isServiceCall, requireUser } from "../_shared/supabase.ts";
import { afterSync, dailyForUser } from "../_shared/notifyCore.ts";

serve(async (req, body) => {
  const admin = adminClient();
  if (body.mode === "daily") {
    if (!isServiceCall(req)) throw new HttpError(403, "service only");
    const { data: users } = await admin.from("profiles").select("id");
    for (const u of users ?? []) await dailyForUser(admin, u.id).catch(console.warn);
    return json({ users: users?.length ?? 0 });
  }
  const userId = await requireUser(req, admin);
  await afterSync(admin, userId);
  return json({ ok: true });
});
