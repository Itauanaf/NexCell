import assert from "node:assert/strict";
import { inviteAuthUser, createAuthUser, sendPasswordRecovery } from "../worker/modules/user-administration.js";

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

  let createRequest;
  globalThis.fetch = async (url, options) => {
    createRequest = { url, options };
    return Response.json({ id: "created-user" });
  };
  await createAuthUser(
    { SUPABASE_URL: "https://example.supabase.co", SUPABASE_SECRET_KEY: "sb_secret_example" },
    { email: "created@example.com", fullName: "Created User", password: "Strong-password-123!" }
  );
  const createBody = JSON.parse(createRequest.options.body);
  assert.ok(createRequest.url.endsWith("/auth/v1/admin/users"));
  assert.equal(createBody.email_confirm, true);
  assert.equal(createBody.user_metadata.full_name, "Created User");

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
