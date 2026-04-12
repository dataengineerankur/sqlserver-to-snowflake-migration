#!/usr/bin/env node
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import { DataLandingStack } from "../lib/data-landing-stack";
import { DmsCdcStack } from "../lib/dms-cdc-stack";
import { TerraformStateStack } from "../lib/terraform-state-stack";

const app = new cdk.App();

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION ?? "us-east-1",
};

const project = app.node.tryGetContext("projectName") ?? "patchit-mssql-migration";

const data = new DataLandingStack(app, `${project}-DataLanding`, {
  env,
  description: "S3 buckets (DMS + Glue), SNS for Snowpipe, Secrets placeholders",
  projectName: project,
});

const deployDmsRaw = app.node.tryGetContext("deployDmsCore");
const deployDms =
  deployDmsRaw === true || String(deployDmsRaw).toLowerCase() === "true";
if (deployDms) {
  new DmsCdcStack(app, `${project}-DmsCdc`, {
    env,
    description: "DMS replication + CDC task (requires VPC context)",
    projectName: project,
    dmsBucket: data.dmsBucket,
    vpcId: app.node.tryGetContext("vpcId") as string,
    subnetIds: String(app.node.tryGetContext("dmsSubnetIds") ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
    securityGroupIds: String(app.node.tryGetContext("dmsSecurityGroupIds") ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  });
}

/* Same stack id as before so `cdk deploy` updates in place and removes CodeCommit/CodePipeline. */
new TerraformStateStack(app, `${project}-Cicd`, {
  env,
  description: "Terraform remote state S3 (Snowflake); use GitHub Actions for deploy",
  projectName: project,
});

app.synth();
