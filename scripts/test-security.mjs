import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import worker from "../worker/index.js";

const sqlite=new DatabaseSync(":memory:");sqlite.exec("PRAGMA foreign_keys=ON");
for(const name of ["0001_foundation.sql","0002_catalog.sql","0003_purchasing_inventory.sql","0004_deepen_purchasing.sql","0005_sales.sql","0006_finance.sql","0007_operational_indexes.sql"])sqlite.exec(readFileSync(new URL(`../migrations/${name}`,import.meta.url),"utf8"));
sqlite.exec("INSERT INTO profiles(id,email,full_name,role_id) VALUES('operator','op@nexcell.local','Operador','operator'),('admin','admin@nexcell.local','Admin','admin')");
const DB={prepare(sql){const statement=sqlite.prepare(sql);let values=[];return{bind(...next){values=next;return this},first(){return statement.get(...values)},all(){return{results:statement.all(...values)}},run(){return statement.run(...values)}}},batch(items){sqlite.exec("BEGIN");try{const result=items.map(x=>x.run());sqlite.exec("COMMIT");return result}catch(error){sqlite.exec("ROLLBACK");throw error}}};
const headers=id=>({"content-type":"application/json","origin":"https://nexcell.local","oai-authenticated-user-id":id,"oai-authenticated-user-email":`${id}@nexcell.local`});
const legacyEnv={DB,USE_LEGACY_D1:true};
const unauthorized=await worker.fetch(new Request("https://nexcell.local/api/session"),legacyEnv);assert.equal(unauthorized.status,401);
const operator=await worker.fetch(new Request("https://nexcell.local/api/finance/accounts",{method:"POST",headers:headers("operator"),body:JSON.stringify({name:"Banco",type:"bank",openingBalance:0})}),legacyEnv);assert.equal(operator.status,403);
const crossOrigin=await worker.fetch(new Request("https://nexcell.local/api/finance/accounts",{method:"POST",headers:{...headers("admin"),origin:"https://evil.example"},body:JSON.stringify({name:"Banco",type:"bank",openingBalance:0})}),legacyEnv);assert.equal(crossOrigin.status,403);
const page=await worker.fetch(new Request("https://nexcell.local/"),legacyEnv);assert.equal(page.status,200);assert.equal(page.headers.get("x-content-type-options"),"nosniff");assert.match(page.headers.get("permissions-policy"),/camera=\(\)/);const html=await page.text();assert.match(html,/skip-link/);assert.match(html,/aria-live/);assert.doesNotMatch(html,/<b>0<\/b>/);
console.log("security boundaries: ok");
