import { execFileSync } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import { deploymentPolicy, scopedBootstrap, BOUNDARY_POLICY_NAME } from "../dist/lib/deployment-access.js";

const [account, region] = process.argv.slice(2);
if (!account || !region) throw new Error("Usage: npm run prepare-access -- ACCOUNT_ID REGION");
const policy = deploymentPolicy(account, region);
const standard = JSON.parse(execFileSync(process.execPath,
  ["node_modules/aws-cdk/bin/cdk", "bootstrap", "--show-template", "--json"], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }));
await mkdir("cdk.out", { recursive: true });
await writeFile("cdk.out/deployment-policy.json", JSON.stringify(policy, null, 2) + "\n");
await writeFile("cdk.out/tempo-bootstrap.json", JSON.stringify(scopedBootstrap(standard), null, 2) + "\n");
console.log(`Create an IAM managed policy named ${BOUNDARY_POLICY_NAME} using cdk.out/deployment-policy.json, then attach it to your deployment user.`);
console.log(`Policy size excluding whitespace: ${JSON.stringify(policy).length} / 6144 characters.`);
console.log("Prepared cdk.out/tempo-bootstrap.json. No AWS permissions or resources were changed.");
