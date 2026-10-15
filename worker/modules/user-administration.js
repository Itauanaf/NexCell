export async function inviteAuthUser(env,{email,fullName,redirectTo}) {
  if(!env.SUPABASE_SECRET_KEY)throw Object.assign(new Error("SUPABASE_SECRET_KEY não configurada no servidor."),{status:503});
  const result=await fetch(`${env.SUPABASE_URL}/auth/v1/invite`,{method:"POST",headers:{apikey:env.SUPABASE_SECRET_KEY,authorization:`Bearer ${env.SUPABASE_SECRET_KEY}`,"content-type":"application/json"},body:JSON.stringify({email, data:{full_name:fullName},redirect_to:redirectTo})});
  const body=await result.json().catch(()=>null);
  if(!result.ok)throw Object.assign(new Error(body?.msg||body?.message||"Não foi possível enviar o convite."),{status:result.status});
  return body;
}
