// Shared-goal actions that need cross-user privileges.
// POST { action: "invite", goalId, shareAmountVisible?, shareActivity? } → { code, url }
// POST { action: "preview", code }                                       → { goal name/target, inviter }
// POST { action: "join", code, funding?, accountId?, earmarkAmount? }    → { goalId }
// POST { action: "cheer", goalId }                                       → notifies the other members
// POST { action: "check", goalId }                                       → recompute milestones (after a manual contribution)
// POST { action: "leave", goalId }                                       → leave; the goal becomes personal again for the others
import { HttpError, json, serve } from "../_shared/http.ts";
import { adminClient, requireUser } from "../_shared/supabase.ts";
import { checkGoalMilestones, notifyNow, refreshGoals } from "../_shared/notifyCore.ts";

const INVITE_BASE = Deno.env.get("INVITE_BASE_URL") ?? "akwe://join";

serve(async (req, body) => {
  const admin = adminClient();
  const userId = await requireUser(req, admin);
  const action = body.action as string;

  const memberOf = async (goalId: string) => {
    const { data } = await admin.from("goal_members").select("role").eq("goal_id", goalId).eq("user_id", userId).single();
    if (!data) throw new HttpError(404, "goal not found");
    return data.role as string;
  };
  const displayName = async (uid: string) => {
    const { data } = await admin.from("profiles").select("display_name").eq("id", uid).single();
    return data?.display_name ?? "Your partner";
  };

  switch (action) {
    case "invite": {
      const goalId = body.goalId as string;
      if ((await memberOf(goalId)) !== "owner") throw new HttpError(403, "only the owner can invite");
      const { data: invite, error } = await admin.from("goal_invites").insert({
        goal_id: goalId, created_by: userId,
        share_amount_visible: body.shareAmountVisible !== false, share_activity: body.shareActivity !== false,
      }).select().single();
      if (error) throw error;
      // the inviter's privacy choices apply to their own member row
      await admin.from("goal_members").update({ share_amount_visible: invite.share_amount_visible, share_activity: invite.share_activity })
        .eq("goal_id", goalId).eq("user_id", userId);
      const code = encodeURIComponent(invite.code);
      return json({ code: invite.code, url: `${INVITE_BASE}?code=${code}` });
    }
    case "preview": {
      const { data: inv } = await admin.from("goal_invites").select("*, goals(name, target_amount, currency, target_date)").eq("code", body.code as string).single();
      if (!inv || inv.accepted_at || Date.parse(inv.expires_at) < Date.now()) throw new HttpError(410, "invite expired");
      return json({ goal: inv.goals, inviter: await displayName(inv.created_by) });
    }
    case "join": {
      const { data: inv } = await admin.from("goal_invites").select("*").eq("code", body.code as string).single();
      if (!inv || inv.accepted_at || Date.parse(inv.expires_at) < Date.now()) throw new HttpError(410, "invite expired");
      if (inv.created_by === userId) throw new HttpError(400, "cannot join your own goal");
      const funding = (body.funding as string) ?? "manual";
      await admin.from("goal_members").upsert({
        goal_id: inv.goal_id, user_id: userId, role: "partner", display_name: await displayName(userId), funding,
        account_id: funding === "account" ? body.accountId : null,
        earmark_amount: funding === "earmark" ? body.earmarkAmount : null,
      });
      await admin.from("goal_invites").update({ accepted_by: userId, accepted_at: new Date().toISOString() }).eq("code", inv.code);
      await admin.from("goal_events").insert({ goal_id: inv.goal_id, user_id: userId, kind: "joined" });
      const { data: goal } = await admin.from("goals").select("name").eq("id", inv.goal_id).single();
      const name = await displayName(userId);
      await notifyNow(admin, inv.created_by, (_l, t) => ({ title: t.joinedTitle({ name, goal: goal?.name ?? "" }), body: t.joinedBody({}), data: { goalId: inv.goal_id } }));
      await refreshGoals(admin, userId);
      return json({ goalId: inv.goal_id });
    }
    case "cheer": {
      const goalId = body.goalId as string;
      await memberOf(goalId);
      await admin.from("goal_events").insert({ goal_id: goalId, user_id: userId, kind: "cheer" });
      const { data: goal } = await admin.from("goals").select("name").eq("id", goalId).single();
      const { data: others } = await admin.from("goal_members").select("user_id").eq("goal_id", goalId).neq("user_id", userId);
      const name = await displayName(userId);
      for (const o of others ?? []) {
        await notifyNow(admin, o.user_id, (_l, t) => ({ title: t.cheerTitle({ name }), body: t.cheerBody({ goal: goal?.name ?? "" }), data: { goalId } }));
      }
      return json({ ok: true });
    }
    case "check": {
      await memberOf(body.goalId as string);
      await refreshGoals(admin, userId);
      await checkGoalMilestones(admin, body.goalId as string);
      return json({ ok: true });
    }
    case "leave": {
      const goalId = body.goalId as string;
      const role = await memberOf(goalId);
      if (role === "owner") {
        // hand ownership to the partner (if any) so their progress is kept
        const { data: partner } = await admin.from("goal_members").select("user_id").eq("goal_id", goalId).neq("user_id", userId).limit(1);
        if (partner?.length) {
          await admin.from("goals").update({ owner_id: partner[0].user_id }).eq("id", goalId);
          await admin.from("goal_members").update({ role: "owner" }).eq("goal_id", goalId).eq("user_id", partner[0].user_id);
        } else {
          await admin.from("goals").delete().eq("id", goalId);
          return json({ ok: true, deleted: true });
        }
      }
      await admin.from("goal_members").delete().eq("goal_id", goalId).eq("user_id", userId);
      return json({ ok: true });
    }
  }
  throw new HttpError(400, "unknown action");
});
