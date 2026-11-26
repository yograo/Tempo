#!/usr/bin/env node
import { App, Tags } from "aws-cdk-lib";
import { FeedbackStack } from "../lib/feedback-stack.js";

const app = new App();
const stage: unknown = app.node.tryGetContext("stage") ?? "dev";
if (stage !== "dev" && stage !== "prod") throw new Error("stage must be dev or prod.");

const stack = new FeedbackStack(app, `TempoFeatureRequests-${stage}`, {
  description: "Feature submissions with reply emails for Tempo; private owner review through AWS IAM.",
});
Tags.of(stack).add("Application", "TempoFeatureRequests");
Tags.of(stack).add("Environment", stage);
app.synth();
