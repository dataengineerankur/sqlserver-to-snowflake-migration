import * as cdk from "aws-cdk-lib";
import * as dms from "aws-cdk-lib/aws-dms";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import { Construct } from "constructs";

export interface DmsCdcStackProps extends cdk.StackProps {
  projectName: string;
  dmsBucket: s3.IBucket;
  vpcId: string;
  subnetIds: string[];
  securityGroupIds: string[];
}

/**
 * DMS full-load + CDC → S3 Parquet (DMS bucket only).
 * Secret `${project}/sqlserver/source` JSON must include:
 * { "host", "port", "username", "password", "dbName", "engine":"sqlserver" } for SQL Server auth.
 */
export class DmsCdcStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: DmsCdcStackProps) {
    super(scope, id, props);

    if (!props.vpcId || props.subnetIds.length < 2) {
      throw new Error(
        "DmsCdcStack: set context vpcId and dmsSubnetIds (comma-separated, >=2 subnets)."
      );
    }

    const vpc = ec2.Vpc.fromLookup(this, "Vpc", { vpcId: props.vpcId });
    const subnets = props.subnetIds.map((sid, i) => ec2.Subnet.fromSubnetId(this, `Sn${i}`, sid));

    /**
     * Private DMS replication ENIs cannot use an IGW without a public IP. A gateway
     * endpoint lets the instance reach S3 without NAT or publiclyAccessible.
     */
    new ec2.GatewayVpcEndpoint(this, "S3GatewayEndpoint", {
      vpc,
      service: ec2.GatewayVpcEndpointAwsService.S3,
    });

    const endpointSubnets: ec2.SubnetSelection = { subnets };

    new ec2.InterfaceVpcEndpoint(this, "SecretsManagerEndpoint", {
      vpc,
      service: ec2.InterfaceVpcEndpointAwsService.SECRETS_MANAGER,
      subnets: endpointSubnets,
      privateDnsEnabled: true,
    });

    new ec2.InterfaceVpcEndpoint(this, "KmsVpcEndpoint", {
      vpc,
      service: ec2.InterfaceVpcEndpointAwsService.KMS,
      subnets: endpointSubnets,
      privateDnsEnabled: true,
    });

    const dmsSg = new ec2.SecurityGroup(this, "DmsSg", {
      vpc,
      description: "DMS replication instance egress",
      allowAllOutbound: true,
    });

    /** DMS looks up this exact role name when creating a replication subnet group (CLI/API). */
    const partition = cdk.Stack.of(this).partition;
    const dmsVpcRole = new iam.Role(this, "DmsVpcRole", {
      roleName: "dms-vpc-role",
      assumedBy: new iam.ServicePrincipal("dms.amazonaws.com"),
      managedPolicies: [
        iam.ManagedPolicy.fromManagedPolicyArn(
          this,
          "AmazonDMSVPCManagementRole",
          `arn:${partition}:iam::aws:policy/service-role/AmazonDMSVPCManagementRole`
        ),
      ],
    });

    const subnetGroup = new dms.CfnReplicationSubnetGroup(this, "DmsSubnetGroup", {
      replicationSubnetGroupDescription: `${props.projectName} dms`,
      subnetIds: subnets.map((s) => s.subnetId),
    });
    subnetGroup.node.addDependency(dmsVpcRole);

    /** DMS validates regional principal for endpoint/secret access roles (e.g. dms.us-east-1.amazonaws.com). */
    const dmsServicePrincipal = new iam.CompositePrincipal(
      new iam.ServicePrincipal("dms.amazonaws.com"),
      new iam.ServicePrincipal(`dms.${this.region}.amazonaws.com`)
    );

    const dmsS3Role = new iam.Role(this, "DmsS3Role", {
      assumedBy: dmsServicePrincipal,
    });
    props.dmsBucket.grantReadWrite(dmsS3Role);

    const sqlSecret = secretsmanager.Secret.fromSecretNameV2(
      this,
      "SqlSecret",
      `${props.projectName}/sqlserver/source`
    );

    const dmsSecretsRole = new iam.Role(this, "DmsSecretsRole", {
      assumedBy: dmsServicePrincipal,
    });
    sqlSecret.grantRead(dmsSecretsRole);

    const repl = new dms.CfnReplicationInstance(this, "Repl", {
      replicationInstanceClass: "dms.c5.large",
      replicationSubnetGroupIdentifier: subnetGroup.ref,
      vpcSecurityGroupIds: [dmsSg.securityGroupId, ...props.securityGroupIds],
      /** Public IP lets the engine reach Secrets Manager / KMS public APIs reliably in default-VPC labs. */
      publiclyAccessible: true,
      engineVersion: "3.6.1",
    });

    const source = new dms.CfnEndpoint(this, "SqlServerSrc", {
      endpointType: "source",
      engineName: "sqlserver",
      databaseName: "SnowConvertStressDB",
      microsoftSqlServerSettings: {
        databaseName: "SnowConvertStressDB",
        secretsManagerAccessRoleArn: dmsSecretsRole.roleArn,
        secretsManagerSecretId: sqlSecret.secretArn,
      },
    });
    source.node.addDependency(repl);

    const target = new dms.CfnEndpoint(this, "S3Tgt", {
      endpointType: "target",
      engineName: "s3",
      s3Settings: {
        bucketName: props.dmsBucket.bucketName,
        bucketFolder: "dms",
        compressionType: "NONE",
        dataFormat: "parquet",
        parquetVersion: "parquet-2-0",
        timestampColumnName: "DMS_COMMIT_TS",
        includeOpForFullLoad: true,
        enableStatistics: true,
        cdcInsertsAndUpdates: true,
        serviceAccessRoleArn: dmsS3Role.roleArn,
      },
      extraConnectionAttributes:
        "dataFormat=parquet;parquetVersion=parquet-2-0;encryptionMode=SSE_S3;",
    });
    target.node.addDependency(repl);

    const tableMappings = JSON.stringify({
      rules: [
        {
          "rule-type": "selection",
          "rule-id": "1",
          "rule-name": "include-dbo",
          "object-locator": { "schema-name": "dbo", "table-name": "%" },
          "rule-action": "include",
        },
      ],
    });

    const taskSettings = JSON.stringify({
      TargetMetadata: {
        SupportLobs: true,
        LimitedSizeLobMode: true,
        LobChunkSize: 64,
      },
      FullLoadSettings: {
        TargetTablePrepMode: "TRUNCATE_BEFORE_LOAD",
        MaxFullLoadSubTasks: 8,
      },
      Logging: { EnableLogging: true },
      ChangeProcessingDdlHandlingPolicy: {
        HandleSourceTableDropped: true,
        HandleSourceTableTruncated: true,
        HandleSourceTableAltered: true,
      },
    });

    new dms.CfnReplicationTask(this, "CdcTask", {
      migrationType: "full-load-and-cdc",
      replicationInstanceArn: repl.ref,
      sourceEndpointArn: source.ref,
      targetEndpointArn: target.ref,
      tableMappings,
      replicationTaskSettings: taskSettings,
    });

    new cdk.CfnOutput(this, "DmsReplicationSecurityGroupId", {
      value: dmsSg.securityGroupId,
      description: "Allow this SG as inbound source on SQL Server port 1433",
    });
  }
}
