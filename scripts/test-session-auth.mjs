import assert from "node:assert/strict";
import { authApi, accessToken } from "../worker/modules/session-auth.js";

const jwt = level => `e30.${Buffer.from(JSON.stringify({ aal: level })).toString("base64url")}.signature`;
const env = { SUPABASE_URL: "https://project.supabase.co", SUPABASE_PUBLISHABLE_KEY: "public-key" };
const calls = [];
let logoutFailures = 0;
globalThis.fetch = async (input, init = {}) => {
  const url = String(input); calls.push({ url, init });
  if (url.includes("token?grant_type=password")) return Response.json({ access_token: jwt("aal1"), refresh_token: "refresh-1", expires_in: 3600, user: { factors: [] } });
  if (url.endsWith("/auth/v1/user") && init.method === "PUT") return Response.json({ id: "invited-user" });
  if (url.includes("token?grant_type=refresh_token")) return Response.json({ access_token: jwt("aal1"), refresh_token: "refresh-3", expires_in: 3600 });
  if (url.includes("logout?scope=local")) {
    if (logoutFailures > 0) { logoutFailures -= 1; return Response.json({ message: "expired" }, { status: 401 }); }
    return Response.json({});
  }
  return Response.json({ message: "unexpected mock" }, { status: 500 });
};

const request = (path, options = {}) => new Request(`https://nexcell.test${path}`, options);
let response = await authApi(request("/api/auth/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email: "admin@nexcell.test", password: "strong-password" }) }), env, new URL("https://nexcell.test/api/auth/login"));
assert.equal(response.status, 200);
assert.deepEqual(await response.json(), { authenticated: true });
const loginCookies = response.headers.getSetCookie();
assert.equal(loginCookies.length, 2);
assert.ok(loginCookies.every(cookie => /HttpOnly.*Secure.*SameSite=Lax/.test(cookie)));
assert.ok(loginCookies.every(cookie => !cookie.includes("strong-password")));

response = await authApi(request("/api/auth/accept-invite", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ accessToken: "invite-access", refreshToken: "invite-refresh", password: "Strong-password-123!" }) }), env, new URL("https://nexcell.test/api/auth/accept-invite"));
assert.equal(response.status, 200);
assert.ok(calls.some(call => call.url.endsWith("/auth/v1/user")));
assert.equal(response.headers.getSetCookie().length, 2);

const cookie = `nexcell_access=${encodeURIComponent(jwt("aal1"))}; nexcell_refresh=refresh-1`;
assert.equal(accessToken(request("/api/session", { headers: { cookie } })), jwt("aal1"));

response = await authApi(request("/api/auth/refresh", { method: "POST", headers: { cookie } }), env, new URL("https://nexcell.test/api/auth/refresh"));
assert.equal(response.status, 200);
response = await authApi(request("/api/auth/logout", { method: "POST", headers: { cookie } }), env, new URL("https://nexcell.test/api/auth/logout"));
assert.equal(response.status, 200);
assert.ok(response.headers.getSetCookie().every(value => value.includes("Max-Age=0")));

const refreshOnlyCookie = "nexcell_refresh=refresh-1";
const beforeRefreshOnlyLogout = calls.length;
response = await authApi(request("/api/auth/logout", { method: "POST", headers: { cookie: refreshOnlyCookie } }), env, new URL("https://nexcell.test/api/auth/logout"));
assert.equal(response.status, 200);
const refreshOnlyCalls = calls.slice(beforeRefreshOnlyLogout).map(call => call.url);
assert.ok(refreshOnlyCalls.some(url => url.includes("token?grant_type=refresh_token")));
assert.ok(refreshOnlyCalls.some(url => url.includes("logout?scope=local")));

logoutFailures = 1;
const beforeExpiredLogout = calls.length;
response = await authApi(request("/api/auth/logout", { method: "POST", headers: { cookie } }), env, new URL("https://nexcell.test/api/auth/logout"));
assert.equal(response.status, 200);
const expiredLogoutCalls = calls.slice(beforeExpiredLogout).map(call => call.url);
assert.equal(expiredLogoutCalls.filter(url => url.includes("logout?scope=local")).length, 2);
assert.ok(expiredLogoutCalls.some(url => url.includes("token?grant_type=refresh_token")));
assert.ok(response.headers.getSetCookie().every(value => value.includes("Max-Age=0")));
console.log("server session auth: password login, HttpOnly cookies, refresh and revoking logout ok");
