import assert from "node:assert/strict";
import { supabaseApi } from "../worker/supabase-api.js";

const env={SUPABASE_URL:"https://project.supabase.co",SUPABASE_PUBLISHABLE_KEY:"public-test-key"};
let role="Operador",calls=[];
globalThis.fetch=async (input,init={})=>{
  const url=String(input); calls.push({url,init});
  if(url.endsWith("/auth/v1/user"))return Response.json({id:"00000000-0000-0000-0000-000000000001"});
  if(url.includes("/rest/v1/profiles?"))return Response.json([{id:"00000000-0000-0000-0000-000000000001",email:"test@nexcell.local",full_name:"Teste",active:true,roles:{name:role}}]);
  if(url.endsWith("/rest/v1/rpc/operator_catalog"))return Response.json([{id:"p1",variant_id:"v1",name:"Capa",sku:"CAP-1",sale_price_cents:2990,available:3,image_key:null}]);
  if(url.endsWith("/rest/v1/rpc/operator_inventory"))return Response.json([{variant_id:"v1",name:"Capa",sku:"CAP-1",physical:4,reserved:1,available:3,minimum_stock:1,sale_price_cents:2990}]);
  if(url.includes("/rest/v1/suppliers"))return Response.json([]);
  if(url.includes("/rest/v1/products"))return Response.json([]);
  return Response.json({message:"mock não configurado"},{status:500});
};
const request=(path,token=true)=>new Request("https://nexcell.test"+path,{headers:token?{authorization:"Bearer test"}:{}});
const body=async response=>({status:response.status,data:await response.json()});

let result=await body(await supabaseApi(request("/api/products"),env,new URL("https://nexcell.test/api/products")));
assert.equal(result.status,200);
assert.deepEqual(Object.keys(result.data.items[0]).sort(),["available","id","image_key","name","sale_price_cents","sku","variant_id"].sort());
for(const forbidden of ["cost_cents","historical_cost_cents","supplier_id","profit","profit_margin"])assert.equal(forbidden in result.data.items[0],false);

result=await body(await supabaseApi(request("/api/finance"),env,new URL("https://nexcell.test/api/finance")));
assert.equal(result.status,403);
result=await body(await supabaseApi(request("/api/products",false),env,new URL("https://nexcell.test/api/products")));
assert.equal(result.status,401);

role="Administrador";
result=await body(await supabaseApi(request("/api/suppliers"),env,new URL("https://nexcell.test/api/suppliers")));
assert.equal(result.status,200);

console.log("rbac api: operador filtrado, admin preservado e anônimo bloqueado");
