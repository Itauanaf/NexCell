import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { Readable } from "node:stream";
import handler from "../api/handler.js";

const text=await readFile(new URL("../.env.local",import.meta.url),"utf8");
for(const line of text.split(/\r?\n/)){if(!line||line.trimStart().startsWith("#"))continue;const i=line.indexOf("=");process.env[line.slice(0,i).trim()]=line.slice(i+1).trim().replace(/^['"]|['"]$/g,"")}
const expectedUrl=process.env.SUPABASE_URL;
delete process.env.SUPABASE_URL;
delete process.env.SUPABASE_PUBLISHABLE_KEY;

async function invoke(path){
  const req=Readable.from([]);req.method="GET";req.url=path;req.headers={host:"localhost:3000","x-forwarded-proto":"http"};
  const headers={};let body;
  const res={statusCode:200,setHeader:(k,v)=>headers[k]=v,end:value=>body=Buffer.from(value||"")};
  await handler(req,res);return{status:res.statusCode,headers,body:body.toString("utf8")};
}

const page=await invoke("/api/handler?__path=");
assert.equal(page.status,200);assert.match(page.body,/NexCell ERP/);assert.match(page.body,/nexcell\.supabase\.session/);
const config=await invoke("/api/handler?__path=api%2Fconfig");
assert.equal(config.status,200);const parsed=JSON.parse(config.body);assert.equal(parsed.url,expectedUrl);assert.ok(parsed.publishableKey);
console.log("vercel adapter: ok");
