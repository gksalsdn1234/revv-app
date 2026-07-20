import { rateLimitKey } from "../_shared/security.ts";

const jsonHeaders = { "content-type": "application/json" };
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// This claim is trusted only because supabase/config.toml requires
// verify_jwt=true for this function, so the gateway validates the signature.
const gatewayVerifiedJwtSub = (authorization: string | null): string | null => {
  const bearerPrefix = "Bearer ";
  if (!authorization?.startsWith(bearerPrefix)) return null;
  const parts = authorization.slice(bearerPrefix.length).split(".");
  if (parts.length !== 3) return null;

  try {
    const encodedPayload = parts[1]
      .replaceAll("-", "+")
      .replaceAll("_", "/")
      .padEnd(Math.ceil(parts[1].length / 4) * 4, "=");
    const decodedPayload = Uint8Array.from(
      atob(encodedPayload),
      (character) => character.charCodeAt(0),
    );
    const payload: unknown = JSON.parse(
      new TextDecoder().decode(decodedPayload),
    );
    if (
      typeof payload !== "object" || payload === null || !("sub" in payload)
    ) {
      return null;
    }
    const subject = payload.sub;
    return typeof subject === "string" && uuidPattern.test(subject)
      ? subject
      : null;
  } catch {
    return null;
  }
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const authorization = req.headers.get("authorization");
  const userId = gatewayVerifiedJwtSub(authorization);
  if (!userId) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  const rateLimitSecret = Deno.env.get("RATE_LIMIT_KEY_SECRET") ??
    serviceRoleKey;
  const edgeUserKey = await rateLimitKey("user", userId, rateLimitSecret);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(userId),
  );
  const dbUserDigest = [...new Uint8Array(digest)].map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  const dbUserKey = `db-user:${dbUserDigest}`;
  await Promise.allSettled(
    [edgeUserKey, dbUserKey].map((key) =>
      fetch(
        `${supabaseUrl}/rest/v1/edge_rate_limits?client_key=eq.${
          encodeURIComponent(key)
        }`,
        {
          method: "DELETE",
          headers: {
            apikey: serviceRoleKey,
            authorization: `Bearer ${serviceRoleKey}`,
          },
        },
      )
    ),
  );

  const response = await fetch(
    `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
    {
      method: "DELETE",
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
      },
    },
  );
  if (!response.ok && response.status !== 404) {
    return new Response(JSON.stringify({ error: "delete_failed" }), {
      status: 502,
      headers: jsonHeaders,
    });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: jsonHeaders,
  });
});
