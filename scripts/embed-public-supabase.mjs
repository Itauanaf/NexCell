import { readFile, writeFile } from "node:fs/promises";

const source=await readFile(new URL("../.env.local",import.meta.url),"utf8");
const values=Object.fromEntries(source.split(/\r?\n/).filter(line=>line&&!line.trimStart().startsWith("#")).map(line=>{const index=line.indexOf("=");return[line.slice(0,index).trim(),line.slice(index+1).trim().replace(/^['"]|['"]$/g,"")]}));
if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(values.SUPABASE_URL||""))throw new Error("SUPABASE_URL inválida em .env.local");
if(!/^(sb_publishable_|eyJ)/.test(values.SUPABASE_PUBLISHABLE_KEY||""))throw new Error("SUPABASE_PUBLISHABLE_KEY inválida em .env.local");
const output=`// Configuração pública do cliente Supabase. Não adicionar credenciais privadas.\nexport const PUBLIC_SUPABASE_CONFIG=${JSON.stringify({SUPABASE_URL:values.SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY:values.SUPABASE_PUBLISHABLE_KEY})};\n`;
await writeFile(new URL("../worker/public-supabase-config.js",import.meta.url),output,"utf8");
console.log("Configuração pública do Supabase incorporada.");
