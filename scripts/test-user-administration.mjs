import assert from "node:assert/strict";
import { inviteAuthUser, sendPasswordRecovery } from "../worker/modules/user-administration.js";

const originalFetch = globalThis.fetch;

async function captureHeaders(secretKey) {
  let request;
  globalThis.fetch = async (url, options) => {
    request = { url, options };
    return new Response(JSON.stringify({ id: "user-id" }), {
      status: 200,
      headers: { "content-type": "application/json" }
    });
  };

  await inviteAuthUser(
    { SUPABASE_URL: "https://example.supabase.co", SUPABASE_SECRET_KEY: secretKey },
    { email: "user@example.com", fullName: "User", redirectTo: "https://example.com/" }
  );
  return request.options.headers;
}

try {
  const modern = await captureHeaders("sb_secret_example");
  assert.equal(modern.apikey, "sb_secret_example");
  assert.equal(modern.authorization, undefined);

  const legacy = await captureHeaders("eyJlegacy-service-role-token");
  assert.equal(legacy.apikey, "eyJlegacy-service-role-token");
  assert.equal(legacy.authorization, "Bearer eyJlegacy-service-role-token");

  let recoveryRequest;
  globalThis.fetch = async (url, options) => {
    recoveryRequest = { url, options };
    return Response.json({});
  };
  await sendPasswordRecovery(
    { SUPABASE_URL: "https://example.supabase.co", SUPABASE_PUBLISHABLE_KEY: "sb_publishable_example" },
    { email: "user@example.com", redirectTo: "https://example.com/" }
  );
  assert.ok(recoveryRequest.url.endsWith("/auth/v1/recover"));
  assert.equal(recoveryRequest.options.headers.apikey, "sb_publishable_example");

  console.log("user administration: ok");
} finally {
  globalThis.fetch = originalFetch;
}
