const ACCESS_COOKIE = "nexcell_access";
const REFRESH_COOKIE = "nexcell_refresh";

const json = (data, status = 200, headers = new Headers()) => {
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", "private, no-store");
  return new Response(JSON.stringify(data), { status, headers });
};

const cookies = request => Object.fromEntries((request.headers.get("cookie") || "").split(/;\s*/).filter(Boolean).map(value => {
  const separator = value.indexOf("=");
  return [decodeURIComponent(value.slice(0, separator)), decodeURIComponent(value.slice(separator + 1))];
}));

export const accessToken = request => cookies(request)[ACCESS_COOKIE] || request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") || "";

function sessionHeaders(session) {
  const headers = new Headers();
  headers.append("set-cookie", serializeCookie(ACCESS_COOKIE, session.access_token, Math.max(60, Number(session.expires_in) || 3600)));
  headers.append("set-cookie", serializeCookie(REFRESH_COOKIE, session.refresh_token, 2592000));
  return headers;
}

const serializeCookie = (name, value, maxAge) => `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAge}`;

function clearHeaders() {
  const headers = new Headers();
  headers.append("set-cookie", serializeCookie(ACCESS_COOKIE, "", 0));
  headers.append("set-cookie", serializeCookie(REFRESH_COOKIE, "", 0));
  return headers;
}

async function authCall(env, path, { method = "POST", body, token } = {}) {
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) throw Object.assign(new Error("auth_unavailable"), { status: 503 });
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/${path}`, {
    method,
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw Object.assign(new Error("auth_failed"), { status: response.status });
  return result;
}

export const tokenAal = token => {
  try {
    const encoded = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const decoded = decodeURIComponent(Array.from(atob(encoded), character => `%${character.charCodeAt(0).toString(16).padStart(2, "0")}`).join(""));
    return JSON.parse(decoded).aal || "aal1";
  }
  catch { return "aal1"; }
};

export async function verifiedTokenAal(request, env) {
  const token = accessToken(request);
  if (!token) return "aal1";
  await authCall(env, "user", { method: "GET", token });
  return tokenAal(token);
}

async function isAdministrator(env, token) {
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/current_access_context`, { method: "POST", headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, authorization: `Bearer ${token}`, "content-type": "application/json" }, body: "{}" });
  if (!response.ok) return false;
  const context = await response.json();
  return context?.permissions?.includes("dashboard.admin.view") === true;
}

export async function authApi(request, env, url) {
  if (!url.pathname.startsWith("/api/auth/")) return null;
  try {
    if (url.pathname === "/api/auth/login" && request.method === "POST") {
      const body = await request.json();
      const session = await authCall(env, "token?grant_type=password", { body: { email: String(body.email || "").trim().toLowerCase(), password: String(body.password || "") } });
      const admin = await isAdministrator(env, session.access_token);
      const factors = (session.user?.factors || []).filter(factor => factor.status === "verified" && factor.factor_type === "totp");
      return json({ authenticated: !admin || tokenAal(session.access_token) === "aal2", mfaRequired: admin && tokenAal(session.access_token) !== "aal2", enrollmentRequired: admin && factors.length === 0, factorId: factors[0]?.id || null }, 200, sessionHeaders(session));
    }
    if (url.pathname === "/api/auth/refresh" && request.method === "POST") {
      const refreshToken = cookies(request)[REFRESH_COOKIE];
      if (!refreshToken) return json({ error: "Sessão expirada." }, 401, clearHeaders());
      const session = await authCall(env, "token?grant_type=refresh_token", { body: { refresh_token: refreshToken } });
      return json({ ok: true }, 200, sessionHeaders(session));
    }
    if (url.pathname === "/api/auth/logout" && request.method === "POST") {
      let token = accessToken(request);
      const refreshToken = cookies(request)[REFRESH_COOKIE];
      if (!token && refreshToken) {
        const session = await authCall(env, "token?grant_type=refresh_token", { body: { refresh_token: refreshToken } });
        token = session.access_token;
      }
      if (token) {
        try { await authCall(env, "logout?scope=local", { token }); }
        catch (firstError) {
          if (!refreshToken) throw firstError;
          const session = await authCall(env, "token?grant_type=refresh_token", { body: { refresh_token: refreshToken } });
          token = session.access_token;
          await authCall(env, "logout?scope=local", { token });
        }
      }
      return json({ ok: true }, 200, clearHeaders());
    }
    if (url.pathname === "/api/auth/mfa/enroll" && request.method === "POST") {
      const token = accessToken(request);
      if (!token) return json({ error: "Autenticação necessária." }, 401);
      const factor = await authCall(env, "factors", { token, body: { factor_type: "totp", friendly_name: "NexCell ERP" } });
      return json({ id: factor.id, qrCode: factor.totp?.qr_code, secret: factor.totp?.secret });
    }
    if (url.pathname === "/api/auth/mfa/status" && request.method === "GET") {
      const token = accessToken(request);
      if (!token) return json({ error: "Autenticação necessária." }, 401);
      const user = await authCall(env, "user", { method: "GET", token });
      const factors = (user.factors || []).filter(factor => factor.factor_type === "totp");
      const verified = factors.find(factor => factor.status === "verified");
      return json({ enrollmentRequired: !verified, factorId: verified?.id || null });
    }
    if (url.pathname === "/api/auth/mfa/verify" && request.method === "POST") {
      const token = accessToken(request), body = await request.json();
      if (!token) return json({ error: "Autenticação necessária." }, 401);
      const challenge = await authCall(env, `factors/${encodeURIComponent(body.factorId)}/challenge`, { token, body: {} });
      const session = await authCall(env, `factors/${encodeURIComponent(body.factorId)}/verify`, { token, body: { challenge_id: challenge.id, code: String(body.code || "").trim() } });
      return json({ ok: true }, 200, sessionHeaders(session));
    }
    return json({ error: "Rota de autenticação não encontrada." }, 404);
  } catch (error) {
    const status = [400, 401, 403, 422, 429, 503].includes(error.status) ? error.status : 500;
    return json({ error: status === 429 ? "Muitas tentativas. Aguarde." : status === 503 ? "Autenticação indisponível." : "Não foi possível autenticar." }, status);
  }
}
