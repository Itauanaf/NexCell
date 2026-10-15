import worker from "../worker/index.js";

async function requestBody(req) {
  if (["GET", "HEAD"].includes(req.method)) return undefined;
  if (req.body !== undefined) {
    if (Buffer.isBuffer(req.body) || typeof req.body === "string") return req.body;
    return JSON.stringify(req.body);
  }
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return chunks.length ? Buffer.concat(chunks) : undefined;
}

export default async function handler(req, res) {
  try {
    const host = req.headers["x-forwarded-host"] || req.headers.host;
    const protocol = req.headers["x-forwarded-proto"] || "https";
    const incoming = new URL(req.url || "/", `${protocol}://${host}`);
    const rewrittenPath = incoming.searchParams.get("__path");
    if (rewrittenPath !== null) {
      incoming.pathname = `/${rewrittenPath}`.replace(/\/{2,}/g, "/");
      incoming.searchParams.delete("__path");
    }
    const request = new Request(incoming, {
      method: req.method,
      headers: req.headers,
      body: await requestBody(req)
    });
    const result = await worker.fetch(request, {
      SUPABASE_URL: process.env.SUPABASE_URL,
      SUPABASE_PUBLISHABLE_KEY: process.env.SUPABASE_PUBLISHABLE_KEY
    });
    res.statusCode = result.status;
    result.headers.forEach((value, key) => res.setHeader(key, value));
    res.end(Buffer.from(await result.arrayBuffer()));
  } catch (error) {
    console.error("NexCell Vercel handler failed", error);
    res.statusCode = 500;
    res.setHeader("content-type", "application/json; charset=utf-8");
    res.end(JSON.stringify({ error: "Falha interna no servidor." }));
  }
}
