const memoryBuckets = new Map<string, { count: number; resetAt: number }>();

export async function consumeRateLimit(
  req: Request,
  functionName: string,
  limit: number,
  windowSeconds: number,
) {
  const key = await clientKey(req);
  const fromDb = await consumeDbRateLimit(
    functionName,
    key,
    limit,
    windowSeconds,
  );
  if (fromDb !== null) return fromDb;
  return consumeMemoryRateLimit(
    `${functionName}:${key}`,
    limit,
    windowSeconds * 1000,
  );
}

export async function clientKey(req: Request) {
  const verifiedSub = await verifiedJwtSub(req.headers.get("authorization"));
  if (verifiedSub) return `user:${verifiedSub}`;
  const forwardedFor = req.headers.get("x-forwarded-for")?.split(",")[0]
    ?.trim();
  return forwardedFor ? `ip:${forwardedFor}` : "ip:unknown";
}

async function consumeDbRateLimit(
  functionName: string,
  key: string,
  limit: number,
  windowSeconds: number,
) {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) return null;

  try {
    const response = await fetch(`${url}/rest/v1/rpc/consume_edge_rate_limit`, {
      method: "POST",
      headers: {
        "apikey": serviceRoleKey,
        "authorization": `Bearer ${serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        function_name_input: functionName,
        client_key_input: key,
        limit_count: limit,
        window_seconds: windowSeconds,
      }),
    });
    if (!response.ok) return null;
    const allowed = await response.json();
    return allowed === true;
  } catch {
    return null;
  }
}

function consumeMemoryRateLimit(key: string, limit: number, windowMs: number) {
  const now = Date.now();
  const bucket = memoryBuckets.get(key);
  if (!bucket || bucket.resetAt <= now) {
    memoryBuckets.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }
  if (bucket.count >= limit) return false;
  bucket.count += 1;
  return true;
}

async function verifiedJwtSub(authorization: string | null) {
  if (!authorization?.match(/^Bearer\s+.+/i)) return null;
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return null;

  try {
    const response = await fetch(`${url}/auth/v1/user`, {
      headers: {
        "apikey": anonKey,
        "authorization": authorization,
      },
    });
    if (!response.ok) return null;
    const user = await response.json();
    return typeof user.id === "string" ? user.id : null;
  } catch {
    return null;
  }
}
