// Apple Push Notification service, token-based auth (.p8 key). No third-party push provider needed.
import { env } from "./http.ts";

let cached: { jwt: string; at: number } | null = null;

const b64url = (buf: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof buf === "string" ? new TextEncoder().encode(buf) : new Uint8Array(buf as ArrayBuffer);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function providerToken(): Promise<string> {
  // Apple accepts a token for up to 60 min; refresh every 50.
  if (cached && Date.now() - cached.at < 50 * 60_000) return cached.jwt;
  const pem = env("APNS_PRIVATE_KEY").replace(/\\n/g, "\n");
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: env("APNS_KEY_ID") }));
  const claims = b64url(JSON.stringify({ iss: env("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) }));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  cached = { jwt, at: Date.now() };
  return jwt;
}

export interface Push {
  title: string;
  body: string;
  category?: string;          // e.g. GOAL_REACHED, BUDGET_EXCEEDED (iOS notification categories)
  threadId?: string;
  data?: Record<string, unknown>;
}

/** Sends to one device. Returns false if the token is dead (caller should delete it). */
export async function sendPush(token: string, environment: "sandbox" | "production", push: Push): Promise<boolean> {
  if (!Deno.env.get("APNS_KEY_ID")) {
    console.log("APNs not configured, would send:", push.title, "—", push.body);
    return true;
  }
  const host = environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const res = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": env("APNS_BUNDLE_ID"),
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify({
      aps: {
        alert: { title: push.title, body: push.body },
        sound: "default",
        category: push.category,
        "thread-id": push.threadId,
        "mutable-content": 1,
      },
      ...push.data,
    }),
  });
  if (res.status === 410 || res.status === 400) {
    const err = await res.json().catch(() => ({}));
    if (res.status === 410 || err.reason === "BadDeviceToken") return false;
  }
  return true;
}
