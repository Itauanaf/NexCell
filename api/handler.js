import worker from "../worker/index.js";

const MAX_REQUEST_BYTES = 5 * 1024 * 1024;
const payloadTooLarge = () => Object.assign(new Error("Request body exceeds the allowed size."), { status: 413 });

async function requestBody(req) {
  if (["GET", "HEAD"].includes(req.method)) return undefined;
  if (req.body !== undefined) {
    const body = Buffer.isBuffer(req.body) || typeof req.body === "string" ? req.body : JSON.stringify(req.body);
    if (Buffer.byteLength(body) > MAX_REQUEST_BYTES) throw payloadTooLarge();
    return body;
  }
  const contentLength = Number(req.headers?.["content-length"] || 0);
  if (Number.isFinite(contentLength) && contentLength > MAX_REQUEST_BYTES) throw payloadTooLarge();
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    const bytes = Buffer.from(chunk);
    size += bytes.length;
    if (size > MAX_REQUEST_BYTES) throw payloadTooLarge();
    chunks.push(bytes);
  }
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
      SUPABASE_PUBLISHABLE_KEY: process.env.SUPABASE_PUBLISHABLE_KEY,
      SUPABASE_SECRET_KEY: process.env.SUPABASE_SECRET_KEY,
      APP_URL: process.env.APP_URL || (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` : undefined)
    });
    res.statusCode = result.status;
    result.headers.forEach((value, key) => res.setHeader(key, value));
    const setCookies = result.headers.getSetCookie?.();
    if (setCookies?.length) res.setHeader("set-cookie", setCookies);
    res.end(Buffer.from(await result.arrayBuffer()));
  } catch (error) {
    console.error("NexCell Vercel handler failed", error);
    res.statusCode = error.status || 500;
    res.setHeader("content-type", "application/json; charset=utf-8");
    res.end(JSON.stringify({ error: "Falha interna no servidor." }));
  }
}
