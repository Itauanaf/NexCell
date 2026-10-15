import { writeFileSync } from "node:fs";
import { phase8Page } from "../worker/index.js";

const html = phase8Page();
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
for (const [, source] of scripts) new Function(source);
writeFileSync(new URL("../preview/index.html", import.meta.url), html, "utf8");
console.log(`phase8 preview: ${html.length} bytes, ${scripts.length} scripts, ok`);
