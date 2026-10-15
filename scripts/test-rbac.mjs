import assert from "node:assert/strict";
import { supabaseApi } from "../worker/supabase-api.js";
import { authorizationContext, authorizeRoute, requiredPermission } from "../worker/modules/authorization.js";

const env={SUPABASE_URL:"https://project.supabase.co",SUPABASE_PUBLISHABLE_KEY:"public-test-key",APP_URL:"https://nexcell.test"};
let permissions=["dashboard.operator.view","products.view","inventory.view","sales.view","sales.create","sales.ship"],groups=[{id:"g1",name:"Vendedor"}],calls=[],token="test";
globalThis.fetch=async (input,init={})=>{
  const url=String(input); calls.push({url,init});
  if(url.endsWith("/rest/v1/rpc/current_access_context"))return Response.json({user:{id:"00000000-0000-0000-0000-000000000001",email:"test@nexcell.local",full_name:"Teste",active:true},groups,permissions});
  if(url.endsWith("/rest/v1/rpc/operator_catalog"))return Response.json([{id:"p1",variant_id:"v1",name:"Capa",sku:"CAP-1",sale_price_cents:2990,available:3,image_key:null}]);
  if(url.endsWith("/rest/v1/rpc/operator_inventory"))return Response.json([{variant_id:"v1",name:"Capa",sku:"CAP-1",physical:4,reserved:1,available:3,minimum_stock:1,sale_price_cents:2990}]);
  if(url.endsWith("/rest/v1/rpc/admin_access_overview"))return Response.json({active_users:2,inactive_users:1,pending_invitations:1,groups:4});
  if(url.endsWith("/rest/v1/rpc/admin_permission_groups"))return Response.json([]);
  if(url.endsWith("/rest/v1/rpc/invitation_for_resend"))return Response.json({email:"canonical@nexcell.test",full_name:"Nome Canônico"});
  if(url.endsWith("/auth/v1/invite"))return Response.json({id:"invited-user"});
  if(url.endsWith("/auth/v1/user"))return Response.json({id:"00000000-0000-0000-0000-000000000001"});
  if(url.endsWith("/rest/v1/rpc/mark_invitation_resent"))return Response.json(null);
  if(url.includes("/rest/v1/suppliers"))return Response.json([]);
  if(url.includes("/rest/v1/products"))return Response.json([]);
  return Response.json({message:"mock não configurado: "+url},{status:500});
};
const request=(path,options={})=>new Request("https://nexcell.test"+path,{headers:{authorization:"Bearer "+token,...(options.headers||{})},method:options.method||"GET",body:options.body});
const body=async response=>({status:response.status,data:await response.json()});

let result=await body(await supabaseApi(request("/api/products"),env,new URL("https://nexcell.test/api/products")));
assert.equal(result.status,200);
for(const forbidden of ["cost_cents","historical_cost_cents","supplier_id","profit","profit_margin"])assert.equal(forbidden in result.data.items[0],false);

result=await body(await supabaseApi(request("/api/finance"),env,new URL("https://nexcell.test/api/finance")));
assert.equal(result.status,403,"finance must be denied without finance.view");

groups=[{id:"g1",name:"Vendedor"},{id:"g2",name:"Expedição"}];
permissions=[...permissions,"inventory.movements.view"];
result=await body(await supabaseApi(request("/api/inventory/movements"),env,new URL("https://nexcell.test/api/inventory/movements")));
assert.notEqual(result.status,403,"multiple groups must compose effective permissions");

permissions=[];
result=await body(await supabaseApi(request("/api/products"),env,new URL("https://nexcell.test/api/products")));
assert.equal(result.status,403,"revoked permission must take effect on the next request");

permissions=["dashboard.admin.view","suppliers.view","users.view","groups.view","audit.view"];
token="e30."+Buffer.from(JSON.stringify({aal:"aal2"})).toString("base64url")+".signature";
groups=[{id:"admin",name:"Administrador"}];
result=await body(await supabaseApi(request("/api/suppliers"),env,new URL("https://nexcell.test/api/suppliers")));
assert.equal(result.status,200,"administrator capabilities remain available");
result=await body(await supabaseApi(request("/api/admin/overview"),env,new URL("https://nexcell.test/api/admin/overview")));
assert.equal(result.status,200);
assert.equal(result.data.groups,4);
result=await body(await supabaseApi(request("/api/admin/groups"),env,new URL("https://nexcell.test/api/admin/groups")));
assert.equal(result.status,200);

permissions=["users.view"];
result=await body(await supabaseApi(request("/api/admin/groups"),env,new URL("https://nexcell.test/api/admin/groups")));
assert.equal(result.status,403,"users.view must not grant groups.view");

permissions=["users.invite"];
const callsBeforeInvite=calls.length;
result=await body(await supabaseApi(request("/api/admin/users/invite",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({fullName:"Novo Usuário",email:"novo@nexcell.test",groupIds:["admin"]})}),env,new URL("https://nexcell.test/api/admin/users/invite")));
assert.equal(result.status,403,"users.invite alone must not assign privileged groups");
assert.equal(calls.length,callsBeforeInvite+1,"denied invitation must stop after loading access context");

env.SUPABASE_SECRET_KEY="server-secret";
const resendStart=calls.length;
result=await body(await supabaseApi(request("/api/admin/invitations/inv-1/resend",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({email:"attacker@example.test",fullName:"Falso"})}),env,new URL("https://nexcell.test/api/admin/invitations/inv-1/resend")));
assert.equal(result.status,200);
const inviteCall=calls.slice(resendStart).find(x=>x.url.endsWith("/auth/v1/invite"));
assert.ok(inviteCall,"resend must invoke Supabase Auth");
assert.equal(JSON.parse(inviteCall.init.body).email,"canonical@nexcell.test","resend must ignore client-provided identity");

const ctx=authorizationContext({user:{id:"u"},groups:[],permissions:["reports.operational.view"]});
assert.equal(requiredPermission(request("/api/reports?type=revenue"),new URL("https://nexcell.test/api/reports?type=revenue"),ctx),"reports.operational.view");
assert.throws(()=>authorizeRoute(request("/api/reports?type=result"),new URL("https://nexcell.test/api/reports?type=result"),ctx),error=>error.status===403);
assert.throws(()=>authorizeRoute(request("/api/unknown"),new URL("https://nexcell.test/api/unknown"),ctx),error=>error.code==="route_denied");

console.log("rbac capabilities: safe projection, default deny, composition and revocation ok");
