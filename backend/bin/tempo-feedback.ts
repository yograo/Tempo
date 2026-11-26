#!/usr/bin/env node
import { App, Tags } from "aws-cdk-lib";
import { DashboardStack } from "../lib/dashboard-stack.js";
import { FeedbackStack } from "../lib/feedback-stack.js";

const app = new App();
const stage: unknown = app.node.tryGetContext("stage") ?? "dev";
if (stage !== "dev" && stage !== "prod") throw new Error("stage must be dev or prod.");

const stack = new FeedbackStack(app, `TempoFeatureRequests-${stage}`, {
  description: "Feature submissions with reply emails for Tempo; private owner review through AWS IAM.",
});
Tags.of(stack).add("Application", "TempoFeatureRequests");
Tags.of(stack).add("Environment", stage);
const dashboardTable: unknown = app.node.tryGetContext("dashboardTable");
if (dashboardTable !== undefined) {
  if (typeof dashboardTable !== "string" || !/^TempoFeatureRequests-[A-Za-z0-9_-]+$/.test(dashboardTable)) {
    throw new Error("dashboardTable must be an existing TempoFeatureRequests table name.");
  }
  const dashboard = new DashboardStack(app, `TempoFeatureRequests-${stage}-Dashboard`, {
    tableName: dashboardTable, stage,
    description: "Private Tempo owner dashboard with Cognito sign-in and status management.",
  });
  Tags.of(dashboard).add("Application", "TempoFeatureRequests");
  Tags.of(dashboard).add("Environment", stage);
}
app.synth();
