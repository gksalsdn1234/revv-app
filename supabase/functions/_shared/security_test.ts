import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { readJsonWithLimit, RequestBodyTooLargeError } from "./bounded_json.ts";
import { rateLimitKeys } from "./security.ts";

Deno.test("bounded JSON accepts a request within its byte budget", async () => {
  const request = new Request("https://example.invalid", {
    method: "POST",
    body: JSON.stringify({ messages: [{ role: "user", content: "hello" }] }),
  });

  const result = await readJsonWithLimit(request, 1024);

  assertEquals(result, {
    messages: [{ role: "user", content: "hello" }],
  });
});

Deno.test("bounded JSON rejects a chunked request above its byte budget", async () => {
  const request = new Request("https://example.invalid", {
    method: "POST",
    body: "x".repeat(1025),
  });

  await assertRejects(
    () => readJsonWithLimit(request, 1024),
    RequestBodyTooLargeError,
  );
});

Deno.test("rate limiting hashes user and network identifiers", async () => {
  const keys = await rateLimitKeys("user-1", "203.0.113.4", "test-secret");

  assertEquals(keys.length, 2);
  assertEquals(keys[0].startsWith("user:$"), true);
  assertEquals(keys[1].startsWith("ip:$"), true);
  assertEquals(keys.some((key) => key.includes("user-1")), false);
  assertEquals(keys.some((key) => key.includes("203.0.113.4")), false);
});
