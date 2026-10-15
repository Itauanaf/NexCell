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

const page=await invoke("/api/handler?__path=");
assert.equal(page.status,200);assert.match(page.body,/NexCell ERP/);assert.doesNotMatch(page.body,/nexcell\.supabase\.session|localStorage/);
assert.doesNotMatch(page.body,/Criar primeira conta|\/auth\/v1\/signup/);
assert.match(page.body,/\/api\/auth\/logout/);
assert.match(page.body,/\/api\/auth\/refresh/);
assert.doesNotMatch(page.body,/mfaRequired|\/api\/auth\/mfa\/|Verificação em duas etapas|QR Code/);
assert.match(page.body,/sidebar-backdrop/);
assert.match(page.body,/body\.menu-open\{overflow:hidden\}/);
assert.match(page.body,/@media\(min-width:781px\).*\.nav-item\{font-size:14px/s);
assert.match(page.body,/#app \.data-table td\{font-size:13px/);
assert.match(page.body,/closest\('#sidebar \[data-page\]'\)/);
assert.match(page.body,/e\.key==='Escape'/);
assert.match(page.headers["content-security-policy"],/script-src 'self' 'sha256-/);
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
console.log("vercel adapter: ok");
