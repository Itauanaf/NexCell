import { cpSync, mkdirSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dist = resolve(root, "dist");
rmSync(dist, { recursive: true, force: true });
mkdirSync(resolve(dist, "server"), { recursive: true });
mkdirSync(resolve(dist, ".openai"), { recursive: true });
cpSync(resolve(root, "worker/index.js"), resolve(dist, "server/index.js"));
cpSync(resolve(root, "worker/modules"), resolve(dist, "server/modules"), { recursive: true });
cpSync(resolve(root, ".openai/hosting.json"), resolve(dist, ".openai/hosting.json"));
cpSync(resolve(root, "migrations"), resolve(dist, "migrations"), { recursive: true });
console.log("build: dist gerado");
