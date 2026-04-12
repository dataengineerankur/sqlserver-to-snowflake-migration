import * as cdk from "aws-cdk-lib";
import * as s3 from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

export interface TerraformStateStackProps extends cdk.StackProps {
  projectName: string;
}

/**
 * S3 bucket for Terraform remote state (Snowflake module).
 * CI/CD is expected from GitHub Actions (see repo `.github/workflows/mssql-migration-infra.yml`), not CodePipeline/CodeCommit.
 */
export class TerraformStateStack extends cdk.Stack {
  public readonly tfStateBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: TerraformStateStackProps) {
    super(scope, id, props);

    this.tfStateBucket = new s3.Bucket(this, "TerraformState", {
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    cdk.Tags.of(this).add("Project", props.projectName);

    new cdk.CfnOutput(this, "TfStateBucketName", {
      value: this.tfStateBucket.bucketName,
      description: "Use as GitHub secret TF_STATE_BUCKET and as terraform init -backend-config bucket=",
    });
  }
}
