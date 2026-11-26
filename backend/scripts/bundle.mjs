import { build } from "esbuild-wasm";
import { writeFile, cp } from "node:fs/promises";

for (const [entry, folder] of [["handler", "lambda"], ["admin-handler", "admin-lambda"], ["site-handler", "site-lambda"]]) {
  await build({
    entryPoints: [`src/${entry}.ts`],
    outfile: `dist/${folder}/index.js`,
    bundle: true,
    platform: "node",
    target: "node24",
    format: "cjs",
    minify: true,
    sourcemap: false,
    logLevel: "warning",
  });
  await writeFile(`dist/${folder}/package.json`, JSON.stringify({ type: "commonjs" }));
}
await cp("dashboard", "dist/site-lambda", { recursive: true });
