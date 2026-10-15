import { writeFileSync } from "node:fs";
import { phase6Page } from "../worker/index.js";

const html = phase6Page();
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
for (const [, source] of scripts) new Function(source);
writeFileSync(new URL("../preview/index.html", import.meta.url), html, "utf8");
console.log(`phase6 preview: ${html.length} bytes, ${scripts.length} scripts, ok`);
