import { build } from "esbuild-wasm";
import { writeFile } from "node:fs/promises";

await build({
  entryPoints: ["src/handler.ts"],
  outfile: "dist/lambda/index.js",
  bundle: true,
  platform: "node",
  target: "node24",
  format: "cjs",
  minify: true,
  sourcemap: false,
  logLevel: "warning",
});
await writeFile("dist/lambda/package.json", JSON.stringify({ type: "commonjs" }));
