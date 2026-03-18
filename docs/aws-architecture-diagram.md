# AWS Architecture Diagram

This diagram is derived from the current Terraform in `infra/terraform/`. It reflects the deployed topology as-is, including ECS tasks in public subnets, API Gateway VPC Link ENIs in private subnets, and the current supporting AWS services used by the three Spring Boot applications.

## Runtime Topology

```mermaid
flowchart TB
  client["Client / Demo Script"]

  subgraph aws["AWS Region us-east-2"]
    cognito["Amazon Cognito<br/>User Pool<br/>App Client<br/>Resource Server<br/>Hosted UI Domain"]
    apigw["Amazon API Gateway HTTP API<br/>$default stage<br/>JWT authorizer<br/>Routes:<br/>POST /orders<br/>GET /orders/{orderId}<br/>GET /product/{productNumber}"]
    appconfig["AWS AppConfig<br/>Application: runtime<br/>Environment: demo<br/>Hosted configuration + deployment"]
    ssm["AWS Systems Manager Parameter Store<br/>/db/username<br/>/order-created-topic<br/>/observability/cloudwatch-agent-config"]
    secrets["AWS Secrets Manager<br/>db/password secret"]
    logs["Amazon CloudWatch Logs<br/>API access logs<br/>order-service log group<br/>inventory-service log group<br/>notification-service log group"]
    xray["AWS X-Ray"]
    ecr["Amazon ECR repositories<br/>order-service<br/>inventory-service<br/>notification-service<br/>image source only"]

    subgraph vpc["Amazon VPC 10.42.0.0/16"]
      igw["Internet Gateway"]

      subgraph public["Public Subnets (2 AZs)"]
        ecs["Amazon ECS Cluster<br/>AWS Fargate<br/>Container Insights enabled"]
        order["order-service task<br/>order-service container<br/>AppConfig agent sidecar<br/>CloudWatch agent sidecar"]
        inventory["inventory-service task<br/>inventory-service container<br/>CloudWatch agent sidecar"]
        notification["notification-service task<br/>notification-service container<br/>CloudWatch agent sidecar"]
      end

      subgraph private["Private Subnets (2 AZs)"]
        vpclink["API Gateway VPC Link"]
        cloudmap["AWS Cloud Map private DNS namespace<br/>aws-modernized-demo.local<br/>+ ECS Service Connect aliases"]
        rds["Amazon RDS for PostgreSQL<br/>single-AZ db.t3.micro"]
        dbsubnet["RDS DB subnet group"]
        msk["Amazon MSK Serverless<br/>SASL/IAM authentication"]
      end
    end
  end

  client -. "Sign in / obtain JWT" .-> cognito
  client --> apigw
  apigw -. "Validate issuer + audience" .-> cognito
  apigw --> vpclink
  vpclink --> cloudmap
  cloudmap --> order

  ecs --> order
  ecs --> inventory
  ecs --> notification

  order -->|"HTTP 8080"| inventory
  order -->|"PostgreSQL 5432"| rds
  dbsubnet --> rds
  order -->|"Publish orders.created"| msk
  notification -->|"Consume orders.created"| msk

  order -. "Fetch runtime configuration" .-> appconfig
  order -. "Read username / topic / agent config" .-> ssm
  inventory -. "Read agent config" .-> ssm
  notification -. "Read topic / agent config" .-> ssm
  order -. "Read DB password" .-> secrets

  ecr -. "Container images" .-> order
  ecr -. "Container images" .-> inventory
  ecr -. "Container images" .-> notification

  apigw --> logs
  order --> logs
  inventory --> logs
  notification --> logs

  order -. "OTLP traces via sidecar" .-> xray
  inventory -. "OTLP traces via sidecar" .-> xray
  notification -. "OTLP traces via sidecar" .-> xray
```

## Access, IAM, And Security Relationships

```mermaid
flowchart LR
  execrole["IAM Role<br/>ecs_execution<br/>AmazonECSTaskExecutionRolePolicy<br/>+ SSM / Secrets / KMS read"]
  taskrole["IAM Role<br/>ecs_task<br/>AppConfig + SSM + Secrets<br/>MSK IAM auth<br/>X-Ray writes"]

  order["order-service task"]
  inventory["inventory-service task"]
  notification["notification-service task"]

  appconfig["AppConfig runtime"]
  ssm["SSM parameters"]
  secrets["Secrets Manager db/password"]
  msk["MSK Serverless"]
  xray["X-Ray"]

  apigwsg["Security Group<br/>apigw_vpc_link"]
  ecssg["Security Group<br/>ecs_tasks"]
  rdssg["Security Group<br/>rds"]
  msksg["Security Group<br/>msk"]

  execrole -->|"pull images / inject secrets"| order
  execrole -->|"pull images / inject secrets"| inventory
  execrole -->|"pull images / inject secrets"| notification

  taskrole -->|"assumed by task"| order
  taskrole -->|"assumed by task"| inventory
  taskrole -->|"assumed by task"| notification

  order --> appconfig
  order --> ssm
  inventory --> ssm
  notification --> ssm
  order --> secrets
  order --> msk
  notification --> msk
  order --> xray
  inventory --> xray
  notification --> xray

  apigwsg -->|"TCP 8080"| ecssg
  ecssg -->|"TCP 5432"| rdssg
  ecssg -->|"TCP 9098"| msksg
  ecssg -->|"self TCP 0-65535"| ecssg
```

## Component Coverage

The diagrams above cover the AWS components currently present in Terraform and runtime configuration. To keep the diagrams readable, some low-level Terraform resources are grouped under their parent service or platform box.

- API Gateway HTTP API, JWT authorizer, stage, routes, and VPC Link
- Cognito user pool, app client, resource server, and hosted UI domain
- VPC, internet gateway, public/private subnets, route tables, route table associations, and the current placement of compute and data services
- ECS cluster, Fargate services, Cloud Map service registrations, Service Connect aliases, and Cloud Map namespace
- `order-service`, `inventory-service`, and `notification-service`
- AppConfig agent and CloudWatch agent sidecars
- CloudWatch Logs, Container Insights, and X-Ray
- RDS PostgreSQL and DB subnet group
- MSK Serverless
- AppConfig application, environment, configuration profile, hosted configuration version, deployment strategy, and deployment
- SSM Parameter Store and Secrets Manager, including the generated secret version for the database password
- ECS execution/task IAM roles, policy attachment, inline policies, and the security groups defined in `security.tf`
- ECR as the image source consumed by the deployment scripts
