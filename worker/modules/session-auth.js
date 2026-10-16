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

export async function authApi(request, env, url) {
  if (!url.pathname.startsWith("/api/auth/")) return null;
  try {
    if (url.pathname === "/api/auth/login" && request.method === "POST") {
      const body = await request.json();
      const session = await authCall(env, "token?grant_type=password", { body: { email: String(body.email || "").trim().toLowerCase(), password: String(body.password || "") } });
      return json({ authenticated: true }, 200, sessionHeaders(session));
    }
    if (url.pathname === "/api/auth/accept-invite" && request.method === "POST") {
      const body = await request.json();
      const accessToken = String(body.accessToken || "");
      const refreshToken = String(body.refreshToken || "");
      const password = String(body.password || "");
      if (!accessToken || !refreshToken || password.length < 12) return json({ error: "Convite inválido ou senha muito curta." }, 422);
      await authCall(env, "user", { method: "PUT", token: accessToken, body: { password } });
      const session = await authCall(env, "token?grant_type=refresh_token", { body: { refresh_token: refreshToken } });
      return json({ authenticated: true }, 200, sessionHeaders(session));
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
    return json({ error: "Rota de autenticação não encontrada." }, 404);
  } catch (error) {
    const status = [400, 401, 403, 422, 429, 503].includes(error.status) ? error.status : 500;
    return json({ error: status === 429 ? "Muitas tentativas. Aguarde." : status === 503 ? "Autenticação indisponível." : "Não foi possível autenticar." }, status);
  }
}
