import http from "node:http";
import { readFile } from "node:fs/promises";
import worker from "../worker/index.js";

async function loadEnv(path) {
  const text = await readFile(path, "utf8");
  return Object.fromEntries(text.split(/\r?\n/).filter(line => line && !line.trimStart().startsWith("#")).map(line => {
    const index = line.indexOf("=");
    return [line.slice(0, index).trim(), line.slice(index + 1).trim().replace(/^['"]|['"]$/g, "")];
  }));
}

const env = await loadEnv(new URL("../.env.local", import.meta.url));
if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) throw new Error("Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY em .env.local.");

const port = Number(process.env.NEXCELL_PORT || 4173);
const server = http.createServer(async (incoming, outgoing) => {
  const chunks = [];
  for await (const chunk of incoming) chunks.push(chunk);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;
  const request = new Request(`http://localhost:${port}${incoming.url}`, {
    method: incoming.method,
    headers: incoming.headers,
    body: ["GET", "HEAD"].includes(incoming.method) ? undefined : body
  });
  const result = await worker.fetch(request, env);
  outgoing.writeHead(result.status, Object.fromEntries(result.headers));
  outgoing.end(Buffer.from(await result.arrayBuffer()));
});

server.listen(port, "127.0.0.1", () => {
  console.log(`NexCell com Supabase: http://localhost:${port}`);
  console.log("Pressione Ctrl+C para encerrar.");
});
