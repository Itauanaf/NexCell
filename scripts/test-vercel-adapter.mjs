import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { Readable } from "node:stream";
import handler from "../api/handler.js";

const text=await readFile(new URL("../.env.local",import.meta.url),"utf8");
for(const line of text.split(/\r?\n/)){if(!line||line.trimStart().startsWith("#"))continue;const i=line.indexOf("=");process.env[line.slice(0,i).trim()]=line.slice(i+1).trim().replace(/^['"]|['"]$/g,"")}
const expectedUrl=process.env.SUPABASE_URL;
const handlerSource=await readFile(new URL("../api/handler.js",import.meta.url),"utf8");
delete process.env.SUPABASE_URL;
delete process.env.SUPABASE_PUBLISHABLE_KEY;

async function invoke(path,{method="GET",headers:extraHeaders={}}={}){
  const req=Readable.from([]);req.method=method;req.url=path;req.headers={host:"localhost:3000","x-forwarded-proto":"http",...extraHeaders};
  const headers={};let body;
  const res={statusCode:200,setHeader:(k,v)=>headers[k]=v,end:value=>body=Buffer.from(value||"")};
  await handler(req,res);return{status:res.statusCode,headers,body:body.toString("utf8")};
}

const loginPage=await invoke("/api/handler?__path=");
assert.equal(loginPage.status,200);
assert.match(loginPage.body,/Entrar — NexCell ERP/);
assert.match(loginPage.body,/<link rel="icon" type="image\/png" href="\/nexcell-icon\.png\?v=4">/);
assert.match(loginPage.body,/\/api\/auth\/login/);
assert.doesNotMatch(loginPage.body,/class="shell"|id="sidebar"|Central financeira|\/api\/notifications|localStorage/);
assert.match(loginPage.headers["content-security-policy"],/script-src 'self' 'sha256-/);
assert.match(loginPage.headers["content-security-policy"],/frame-ancestors 'none'/);
assert.match(loginPage.headers["content-security-policy"],/object-src 'none'/);
assert.match(loginPage.headers["strict-transport-security"],/max-age=31536000/);
assert.doesNotMatch(loginPage.headers["content-security-policy"],/script-src[^;]*unsafe-inline/);

const originalFetch=globalThis.fetch;
globalThis.fetch=async input=>String(input).includes("/rest/v1/rpc/current_access_context")
  ?Response.json({user:{id:"user-1",email:"admin@nexcell.test",full_name:"Administrador",active:true},groups:[{id:"admin",name:"Administrador"}],permissions:["dashboard.admin.view"]})
  :Response.json({message:"unexpected test request"},{status:500});
const page=await invoke("/api/handler?__path=",{headers:{cookie:"nexcell_access=test-token"}});
globalThis.fetch=originalFetch;
assert.equal(page.status,200);assert.match(page.body,/NexCell ERP/);assert.doesNotMatch(page.body,/nexcell\.supabase\.session|localStorage/);
const applicationScript=page.body.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert.ok(applicationScript);new Function(applicationScript);
assert.match(page.body,/\/api\/auth\/logout/);assert.match(page.body,/sidebar-backdrop/);assert.match(page.body,/notification-panel/);
assert.match(page.body,/body\.menu-open\{overflow:hidden\}/);assert.match(page.body,/@media\(min-width:781px\).*\.nav-item\{font-size:14px/s);
assert.match(page.body,/#sidebar nav\{scrollbar-width:thin;scrollbar-color:#b8c8d8 transparent;scrollbar-gutter:stable/);
assert.match(page.body,/#sidebar nav::-webkit-scrollbar\{width:7px\}/);
assert.match(page.body,/#sidebar nav::-webkit-scrollbar-thumb:hover\{background:#078bea\}/);
assert.match(page.body,/#sidebar nav::-webkit-scrollbar-button\{display:none;width:0;height:0\}/);
assert.match(page.body,/#app \.data-table td\{font-size:13px/);assert.match(page.body,/\/api\/notifications\/read-all/);assert.match(page.body,/setInterval\(.*60000/s);
assert.match(page.body,/closest\('#sidebar \[data-page\]'\)/);assert.match(page.body,/e\.key==='Escape'/);assert.match(page.body,/location\.hash\.match\(\/\^#module=/);
assert.match(page.body,/history\.replaceState\(null,'','#module='/);assert.match(page.body,/isAllowed\(desired\)/);assert.match(page.body,/#newTransfer\.row-actions\{display:inline-flex;align-self:center/);
assert.match(page.body,/background:#078bea;color:#fff;font-size:12px/);assert.match(page.headers["content-security-policy"],/script-src 'self' 'sha256-/);
assert.match(page.headers["content-security-policy"],/frame-ancestors 'none'/);assert.match(page.headers["strict-transport-security"],/max-age=31536000/);
assert.match(page.body,/const originalGetJson=getJson,cache=new Map\(\)/);
assert.match(page.body,/url==='\/api\/session'\?30000/);
assert.match(page.body,/method!==\'GET\'&&method!==\'HEAD\'\)cache\.clear\(\)/);
assert.match(page.body,/requestIdleCallback/);
assert.doesNotMatch(page.headers["content-security-policy"],/script-src[^;]*unsafe-inline/);

const config=await invoke("/api/handler?__path=api%2Fconfig");
assert.equal(config.status,200);const parsed=JSON.parse(config.body);assert.equal(parsed.url,expectedUrl);assert.ok(parsed.publishableKey);
assert.match(handlerSource,/SUPABASE_SECRET_KEY:\s*process\.env\.SUPABASE_SECRET_KEY/);
assert.match(handlerSource,/VERCEL_PROJECT_PRODUCTION_URL/);
assert.match(handlerSource,/MAX_REQUEST_BYTES\s*=\s*5\s*\*\s*1024\s*\*\s*1024/);

const crossSite=await invoke("/api/handler?__path=api%2Fauth%2Flogout",{method:"POST",headers:{origin:"https://evil.example","sec-fetch-site":"cross-site"}});
assert.equal(crossSite.status,403);

const oversized=Readable.from([]);oversized.method="POST";oversized.url="/api/handler?__path=api%2Fconfig";oversized.headers={host:"localhost:3000","x-forwarded-proto":"http","content-length":String(5*1024*1024+1)};
const oversizedResponse={statusCode:200,setHeader(){},end(){}};
await handler(oversized,oversizedResponse);
assert.equal(oversizedResponse.statusCode,413);
console.log("vercel adapter: unauthenticated shell isolation and authenticated rendering ok");
