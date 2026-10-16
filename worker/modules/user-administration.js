function adminHeaders(secretKey, extra = {}) {
  const headers = { apikey: secretKey, ...extra };
  // The new sb_secret_ keys are API keys, not JWTs. Only legacy service_role
  // JWTs belong in Authorization; sending sb_secret_ as Bearer causes Auth 401s.
  if (secretKey.startsWith("eyJ")) headers.authorization = `Bearer ${secretKey}`;
  return headers;
}

export async function inviteAuthUser(env,{email,fullName,redirectTo}) {
  if(!env.SUPABASE_SECRET_KEY)throw Object.assign(new Error("SUPABASE_SECRET_KEY não configurada no servidor."),{status:503});
  const result=await fetch(`${env.SUPABASE_URL}/auth/v1/invite`,{method:"POST",headers:adminHeaders(env.SUPABASE_SECRET_KEY,{"content-type":"application/json"}),body:JSON.stringify({email, data:{full_name:fullName},redirect_to:redirectTo})});
  const body=await result.json().catch(()=>null);
  if(!result.ok)throw Object.assign(new Error(body?.msg||body?.message||"Não foi possível enviar o convite."),{status:result.status});
  return body;
}

export async function sendPasswordRecovery(env, { email, redirectTo }) {
  if (!env.SUPABASE_PUBLISHABLE_KEY) throw Object.assign(new Error("SUPABASE_PUBLISHABLE_KEY não configurada no servidor."), { status: 503 });
  const result = await fetch(`${env.SUPABASE_URL}/auth/v1/recover`, {
    method: "POST",
    headers: { apikey: env.SUPABASE_PUBLISHABLE_KEY, "content-type": "application/json" },
    body: JSON.stringify({ email, redirect_to: redirectTo })
  });
  const body = await result.json().catch(() => null);
  if (!result.ok) throw Object.assign(new Error(body?.msg || body?.message || "Não foi possível reenviar o acesso."), { status: result.status });
  return body;
}

export async function deleteAuthUser(env,userId) {
  if(!env.SUPABASE_SECRET_KEY||!userId)return false;
  const result=await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`,{method:"DELETE",headers:adminHeaders(env.SUPABASE_SECRET_KEY)});
  return result.ok;
}
