import * as cdk from "aws-cdk-lib";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as sns from "aws-cdk-lib/aws-sns";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import { Construct } from "constructs";

export interface DataLandingStackProps extends cdk.StackProps {
  projectName: string;
}

/**
 * Two isolated buckets + optional SNS for Snowflake auto-ingest.
 * DMS and Glue must never share a bucket.
 */
export class DataLandingStack extends cdk.Stack {
  public readonly dmsBucket: s3.Bucket;
  public readonly glueBucket: s3.Bucket;
  public readonly snsDmsTopic: sns.Topic;
  public readonly snsGlueTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: DataLandingStackProps) {
    super(scope, id, props);
    const p = props.projectName;

    // Lifecycle rule: move Parquet files to Glacier after 90 days, expire after 365.
    // Glacier IR would be cheaper for data accessed < 1/quarter; standard Glacier chosen
    // here because migration lab data is essentially write-once after the cutover window.
    const parquetLifecycle: s3.LifecycleRule = {
      id: "parquet-tiering",
      enabled: true,
      transitions: [
        { storageClass: s3.StorageClass.GLACIER, transitionAfter: cdk.Duration.days(90) },
      ],
      expiration: cdk.Duration.days(365),
    };

    this.dmsBucket = new s3.Bucket(this, "DmsMssqlBucket", {
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [parquetLifecycle],
    });

    this.glueBucket = new s3.Bucket(this, "GlueMssqlBucket", {
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [parquetLifecycle],
    });

    this.snsDmsTopic = new sns.Topic(this, "SnowpipeDmsTopic", {
      displayName: `${p}-snowpipe-dms`,
      topicName: `${p}-snowpipe-dms`.slice(0, 256),
    });

    this.snsGlueTopic = new sns.Topic(this, "SnowpipeGlueTopic", {
      displayName: `${p}-snowpipe-glue`,
      topicName: `${p}-snowpipe-glue`.slice(0, 256),
    });

    /* DMS reads this secret (keys must match AWS DMS SQL Server expectations — use dbName, not database). */
    new secretsmanager.Secret(this, "SqlServerSourceSecret", {
      secretName: `${p}/sqlserver/source`,
      description: "SQL Server for DMS — set host, port, username, password, dbName via console/CLI",
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          host: "REPLACE.sqlserver.host",
          port: "1433",
          username: "REPLACE",
          engine: "sqlserver",
          dbName: "SnowConvertStressDB",
        }),
        generateStringKey: "password",
        excludeCharacters: " %+~`#$&*()|[]{}:;<>?!'/@\"\\",
        passwordLength: 24,
      },
    });

    new cdk.CfnOutput(this, "DmsBucketName", { value: this.dmsBucket.bucketName });
    new cdk.CfnOutput(this, "GlueBucketName", { value: this.glueBucket.bucketName });
    new cdk.CfnOutput(this, "SnsDmsTopicArn", { value: this.snsDmsTopic.topicArn });
    new cdk.CfnOutput(this, "SnsGlueTopicArn", { value: this.snsGlueTopic.topicArn });
  }
}
