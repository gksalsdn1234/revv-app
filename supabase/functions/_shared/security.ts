const memoryBuckets = new Map<string, { count: number; resetAt: number }>();

export async function consumeRateLimit(
  req: Request,
  functionName: string,
  limit: number,
  windowSeconds: number,
) {
  const keys = await clientKeys(req);
  for (const key of keys) {
    const fromDb = await consumeDbRateLimit(
      functionName,
      key,
      limit,
      windowSeconds,
    );
    const allowed = fromDb ?? consumeMemoryRateLimit(
      `${functionName}:${key}`,
      limit,
      windowSeconds * 1000,
    );
    if (!allowed) return false;
  }
  return true;
}

export async function clientKey(req: Request) {
  return (await clientKeys(req))[0];
}

async function clientKeys(req: Request): Promise<readonly string[]> {
  const verifiedSub = await verifiedJwtSub(req.headers.get("authorization"));
  const forwardedFor = req.headers.get("x-forwarded-for")?.split(",")[0]
    ?.trim() ?? null;
  return rateLimitKeys(verifiedSub, forwardedFor);
}

export function rateLimitKeys(
  verifiedSub: string | null,
  forwardedFor: string | null,
): readonly string[] {
  const keys: string[] = [];
  if (verifiedSub) keys.push(`user:${verifiedSub}`);
  keys.push(forwardedFor ? `ip:${forwardedFor}` : "ip:unknown");
  return keys;
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
