import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { env, HttpError } from "./http.ts";

// deno-lint-ignore no-explicit-any
export type Admin = SupabaseClient<any, any, any>;

/** Service-role client: bypasses RLS. Only used inside edge functions. */
export function adminClient(): Admin {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    db: { schema: "public" },
  });
}

export function isServiceCall(req: Request): boolean {
  const auth = req.headers.get("Authorization") ?? "";
  return auth === `Bearer ${env("SUPABASE_SERVICE_ROLE_KEY")}`;
}

/** Resolves the signed-in user from the request's JWT. */
export async function requireUser(req: Request, admin: Admin): Promise<string> {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (!token) throw new HttpError(401, "missing token");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "invalid token");
  return data.user.id;
}
