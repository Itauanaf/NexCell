import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

const source=await readFile(new URL("../.env.local",import.meta.url),"utf8");
const env=Object.fromEntries(source.split(/\r?\n/).filter(x=>x&&!x.trimStart().startsWith("#")).map(line=>{const i=line.indexOf("=");return[line.slice(0,i).trim(),line.slice(i+1).trim().replace(/^['"]|['"]$/g,"")]}));
assert.match(env.SUPABASE_URL||"",/^https:\/\/[a-z0-9-]+\.supabase\.co$/);
assert.ok(env.SUPABASE_PUBLISHABLE_KEY);
const headers={apikey:env.SUPABASE_PUBLISHABLE_KEY,"content-type":"application/json"};

const table=await fetch(`${env.SUPABASE_URL}/rest/v1/products?select=id&limit=1`,{headers});
assert.ok([200,401,403].includes(table.status),`products anonymous status ${table.status}`);
if(table.status===200)assert.deepEqual(await table.json(),[],"RLS must hide every product from anonymous users");
const notifications=await fetch(`${env.SUPABASE_URL}/rest/v1/user_notifications?select=id&limit=1`,{headers});
assert.ok([200,401,403].includes(notifications.status),`notifications anonymous status ${notifications.status}`);
if(notifications.status===200)assert.deepEqual(await notifications.json(),[],"RLS must hide every notification from anonymous users");
const command=await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/create_sale`,{method:"POST",headers,body:JSON.stringify({p_customer_name:"Teste",p_order_date:"2026-10-15",p_discount_cents:0,p_shipping_cents:0,p_notes:null,p_items:[]})});
assert.ok([401,403,404].includes(command.status),`create_sale anonymous status ${command.status}`);
console.log("supabase anonymous boundaries: ok");
