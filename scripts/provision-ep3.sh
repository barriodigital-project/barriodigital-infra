#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s --env-file PATH [--apply]\n' "${0##*/}"
}

ENV_FILE=""
APPLY=false
while (($#)); do
    case "$1" in
        --env-file)
            (($# >= 2)) || fail "--env-file requires a path."
            ENV_FILE=$2
            shift 2
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "Unknown argument: $1"
            ;;
    esac
done

[[ -n "$ENV_FILE" && -f "$ENV_FILE" && -r "$ENV_FILE" ]] \
    || fail "Provide a readable environment file with --env-file."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$INFRA_ROOT/templates/ep3-stack.yaml"

load_env_file() {
    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=(.*)$ ]] \
            || fail "Invalid environment line in $ENV_FILE."
        key=${BASH_REMATCH[1]}
        value=${BASH_REMATCH[2]}
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        if ((${#value} >= 2)) &&
            { [[ "$value" == \"*\" ]] || [[ "$value" == \'*\' ]]; }; then
            value=${value:1:${#value}-2}
        fi
        case "$key" in
            AWS_REGION|EP3_STACK_NAME|MANAGER_INSTANCE_ID|WORKER_INSTANCE_ID|MANAGER_PRIVATE_IP|WORKER_PRIVATE_IP|VPC_ID|VPC_SUBNET_IDS|SWARM_SECURITY_GROUP_ID|LAMBDA_ROLE_NAME|LAMBDA_IMAGE_URI|LAMBDA_IMAGE_TAG|JWT_ISSUER_URI|JWT_CLIENT_ID|CORS_ALLOWED_ORIGINS)
                printf -v "$key" '%s' "$value"
                export "$key"
                ;;
            *)
                ;;
        esac
    done < "$ENV_FILE"
}

load_env_file
command -v aws >/dev/null 2>&1 || fail "AWS CLI is not installed."
AWS_REGION=${AWS_REGION:-us-east-1}
EP3_STACK_NAME=${EP3_STACK_NAME:-barriodigital-ep3}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME:-LabRole}

[[ "$AWS_REGION" =~ ^[a-z0-9-]+$ ]] || fail "AWS_REGION is invalid."
for variable in MANAGER_INSTANCE_ID WORKER_INSTANCE_ID MANAGER_PRIVATE_IP WORKER_PRIVATE_IP VPC_ID VPC_SUBNET_IDS \
    SWARM_SECURITY_GROUP_ID LAMBDA_IMAGE_URI JWT_ISSUER_URI JWT_CLIENT_ID CORS_ALLOWED_ORIGINS; do
    [[ -n "${!variable:-}" ]] || fail "$variable must be set in $ENV_FILE."
done

[[ "$MANAGER_INSTANCE_ID" =~ ^i-[0-9a-f]{8,17}$ ]] || fail "MANAGER_INSTANCE_ID is invalid."
[[ "$WORKER_INSTANCE_ID" =~ ^i-[0-9a-f]{8,17}$ ]] || fail "WORKER_INSTANCE_ID is invalid."
[[ "$MANAGER_INSTANCE_ID" != "$WORKER_INSTANCE_ID" ]] || fail "Manager and Worker must be different instances."
[[ "$MANAGER_PRIVATE_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "MANAGER_PRIVATE_IP is invalid."
[[ "$WORKER_PRIVATE_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "WORKER_PRIVATE_IP is invalid."
[[ "$VPC_ID" =~ ^vpc-[0-9a-f]{8,17}$ ]] || fail "VPC_ID is invalid."
[[ "$SWARM_SECURITY_GROUP_ID" =~ ^sg-[0-9a-f]{8,17}$ ]] || fail "SWARM_SECURITY_GROUP_ID is invalid."
[[ "$VPC_SUBNET_IDS" =~ ^subnet-[0-9a-f]{8,17}(,subnet-[0-9a-f]{8,17})+$ ]] \
    || fail "VPC_SUBNET_IDS must include at least two comma-separated subnet IDs."
[[ "$EP3_STACK_NAME" =~ ^[A-Za-z][A-Za-z0-9-]{0,27}$ ]] || fail "EP3_STACK_NAME must be 28 characters or fewer."
[[ "$LAMBDA_ROLE_NAME" =~ ^[A-Za-z0-9+=,.@_-]+$ && ${#LAMBDA_ROLE_NAME} -le 64 ]] \
    || fail "LAMBDA_ROLE_NAME is invalid."
[[ "$LAMBDA_IMAGE_URI" =~ ^[0-9]{12}\.dkr\.ecr\.${AWS_REGION}\.amazonaws\.com/barriodigital/report-event-consumer:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] \
    || fail "LAMBDA_IMAGE_URI must be the EP3 Lambda image in this account and region."
[[ "$JWT_ISSUER_URI" =~ ^https://cognito-idp\.[a-z0-9-]+\.amazonaws\.com/[A-Za-z0-9_-]+$ ]] \
    || fail "JWT_ISSUER_URI must be the Cognito User Pool issuer."
[[ "$JWT_CLIENT_ID" =~ ^[A-Za-z0-9]+$ ]] || fail "JWT_CLIENT_ID is invalid."
[[ "$CORS_ALLOWED_ORIGINS" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(,https://[A-Za-z0-9.-]+(:[0-9]+)?)*$ ]] \
    || fail "CORS_ALLOWED_ORIGINS must contain HTTPS origins separated by commas."
[[ -f "$TEMPLATE" ]] || fail "CloudFormation template not found: $TEMPLATE"

account_id="$(aws sts get-caller-identity --query Account --output text)" \
    || fail "AWS STS could not identify the active account."
[[ "$account_id" =~ ^[0-9]{12}$ ]] || fail "AWS STS returned an invalid account ID."
[[ "$LAMBDA_IMAGE_URI" == "${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com/"* ]] \
    || fail "LAMBDA_IMAGE_URI does not belong to the active AWS account."

queue_url="$(aws sqs get-queue-url \
    --region "$AWS_REGION" \
    --queue-name barriodigital-requests-events \
    --query QueueUrl \
    --output text)" || fail "Could not find the existing barriodigital-requests-events queue."
queue_arn="$(aws sqs get-queue-attributes \
    --region "$AWS_REGION" \
    --queue-url "$queue_url" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)" || fail "Could not read the existing request events queue ARN."
dlq_url="$(aws sqs get-queue-url \
    --region "$AWS_REGION" \
    --queue-name barriodigital-requests-dlq \
    --query QueueUrl \
    --output text)" || fail "Could not find the existing barriodigital-requests-dlq queue."
dlq_arn="$(aws sqs get-queue-attributes \
    --region "$AWS_REGION" \
    --queue-url "$dlq_url" \
    --attribute-names QueueArn \
    --query 'Attributes.QueueArn' \
    --output text)" || fail "Could not read the existing requests DLQ ARN."

for instance_id in "$MANAGER_INSTANCE_ID" "$WORKER_INSTANCE_ID"; do
    instance_details="$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].[State.Name,VpcId,PrivateIpAddress,IamInstanceProfile.Arn,MetadataOptions.HttpEndpoint,MetadataOptions.HttpPutResponseHopLimit]' \
        --output text)" || fail "Could not inspect EC2 instance $instance_id."
    read -r instance_state instance_vpc instance_ip instance_profile metadata_endpoint hop_limit <<< "$instance_details"
    [[ "$instance_state" == "running" ]] || fail "Existing instance $instance_id is not running."
    [[ "$instance_vpc" == "$VPC_ID" ]] || fail "Existing instance $instance_id is not in VPC_ID."
    [[ "$instance_profile" != "None" ]] || fail "Existing instance $instance_id has no IAM instance profile."
    instance_profile_name=${instance_profile##*/}
    instance_role_names="$(aws iam get-instance-profile \
        --instance-profile-name "$instance_profile_name" \
        --query 'InstanceProfile.Roles[].RoleName' \
        --output text)" || fail "Could not inspect IAM instance profile $instance_profile_name."
    [[ " $instance_role_names " == *" $LAMBDA_ROLE_NAME "* ]] \
        || fail "LAMBDA_ROLE_NAME must also be attached to the existing EC2 instance profile."
    [[ "$metadata_endpoint" == "enabled" && "$hop_limit" =~ ^[0-9]+$ ]] \
        && ((hop_limit >= 2)) \
        || fail "Instance $instance_id must allow IMDS access from containers (hop limit >= 2)."
    instance_security_groups="$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' \
        --output text)" || fail "Could not inspect security groups for $instance_id."
    [[ " $instance_security_groups " == *" $SWARM_SECURITY_GROUP_ID "* ]] \
        || fail "SWARM_SECURITY_GROUP_ID is not attached to existing instance $instance_id."
    if [[ "$instance_id" == "$MANAGER_INSTANCE_ID" ]]; then
        [[ "$instance_ip" == "$MANAGER_PRIVATE_IP" ]] \
            || fail "MANAGER_PRIVATE_IP does not match the existing Manager instance."
    else
        [[ "$instance_ip" == "$WORKER_PRIVATE_IP" ]] \
            || fail "WORKER_PRIVATE_IP does not match the existing Worker instance."
    fi
done

IFS=',' read -r -a subnet_ids <<< "$VPC_SUBNET_IDS"
subnet_details="$(aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --subnet-ids "${subnet_ids[@]}" \
    --query 'Subnets[].[VpcId,AvailabilityZone]' \
    --output text)" || fail "Could not inspect VPC_SUBNET_IDS."
declare -a availability_zones=()
while IFS=$'\t' read -r subnet_vpc subnet_az; do
    [[ "$subnet_vpc" == "$VPC_ID" ]] || fail "Every subnet must belong to VPC_ID."
    [[ ! " ${availability_zones[*]} " == *" $subnet_az "* ]] \
        || fail "VPC_SUBNET_IDS must span distinct Availability Zones."
    availability_zones+=("$subnet_az")
done <<< "$subnet_details"
(( ${#availability_zones[@]} >= 2 )) || fail "At least two valid VPC subnets are required."

security_group_vpc="$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --group-ids "$SWARM_SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].VpcId' \
    --output text)" || fail "Could not inspect SWARM_SECURITY_GROUP_ID."
[[ "$security_group_vpc" == "$VPC_ID" ]] || fail "The Swarm security group is not in VPC_ID."

role_trust="$(aws iam get-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json)" \
    || fail "Could not find the existing IAM role $LAMBDA_ROLE_NAME."
python3 -c '
import json
import sys
policy = json.loads(sys.argv[1])
for statement in policy.get("Statement", []):
    services = statement.get("Principal", {}).get("Service", [])
    if isinstance(services, str):
        services = [services]
    if "lambda.amazonaws.com" in services:
        sys.exit(0)
sys.exit(1)
' "$role_trust" || fail "LAMBDA_ROLE_NAME must trust lambda.amazonaws.com."
aws cloudformation validate-template \
    --region "$AWS_REGION" \
    --template-body "file://$TEMPLATE" >/dev/null \
    || fail "CloudFormation rejected the EP3 template."

if [[ "$APPLY" != true ]]; then
    printf 'Preflight passed. No AWS resources were created or changed.\n'
    printf 'Run again with --apply to create or update the EP3 stack.\n'
    exit 0
fi

queue_attributes="$(python3 -c '
import json
import sys
print(json.dumps({
    "VisibilityTimeout": "180",
    "RedrivePolicy": json.dumps({
        "deadLetterTargetArn": sys.argv[1],
        "maxReceiveCount": "5"
    })
}))
' "$dlq_arn")" || fail "Could not prepare the existing queue redrive policy."
aws sqs set-queue-attributes \
    --region "$AWS_REGION" \
    --queue-url "$queue_url" \
    --attributes "$queue_attributes" \
    || fail "Could not configure the existing queue visibility timeout and DLQ."

aws cloudformation deploy \
    --region "$AWS_REGION" \
    --stack-name "$EP3_STACK_NAME" \
    --template-file "$TEMPLATE" \
    --capabilities CAPABILITY_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides \
        "StackLabel=$EP3_STACK_NAME" \
        "SwarmVpcId=$VPC_ID" \
        "SwarmSubnetIds=$VPC_SUBNET_IDS" \
        "SwarmSecurityGroupId=$SWARM_SECURITY_GROUP_ID" \
        "ManagerInstanceId=$MANAGER_INSTANCE_ID" \
        "WorkerInstanceId=$WORKER_INSTANCE_ID" \
        "ManagerPrivateIp=$MANAGER_PRIVATE_IP" \
        "LambdaRoleName=$LAMBDA_ROLE_NAME" \
        "RequestEventsQueueUrl=$queue_url" \
        "RequestEventsQueueArn=$queue_arn" \
        "RequestEventsDlqUrl=$dlq_url" \
        "LambdaImageUri=$LAMBDA_IMAGE_URI" \
        "CognitoIssuer=$JWT_ISSUER_URI" \
        "CognitoClientId=$JWT_CLIENT_ID" \
        "ApiCorsAllowedOrigins=$CORS_ALLOWED_ORIGINS" \
    || fail "CloudFormation failed to deploy the EP3 stack."

queue_url="$(aws cloudformation describe-stacks \
    --region "$AWS_REGION" \
    --stack-name "$EP3_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='RequestEventsQueueUrl'].OutputValue | [0]" \
    --output text)" || fail "Could not read the SQS queue URL from CloudFormation."
api_endpoint="$(aws cloudformation describe-stacks \
    --region "$AWS_REGION" \
    --stack-name "$EP3_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue | [0]" \
    --output text)" || fail "Could not read the API Gateway endpoint from CloudFormation."
target_group_arn="$(aws cloudformation describe-stacks \
    --region "$AWS_REGION" \
    --stack-name "$EP3_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='BffTargetGroupArn'].OutputValue | [0]" \
    --output text)" || fail "Could not read the BFF target group from CloudFormation."
nlb_security_group_id="$(aws cloudformation describe-stacks \
    --region "$AWS_REGION" \
    --stack-name "$EP3_STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='BffLoadBalancerSecurityGroupId'].OutputValue | [0]" \
    --output text)" || fail "Could not read the NLB security group from CloudFormation."

[[ "$queue_url" == https://* && "$api_endpoint" == https://* ]] \
    || fail "CloudFormation outputs are incomplete."
printf 'REQUEST_EVENTS_QUEUE_URL=%s\n' "$queue_url"
printf 'API_ENDPOINT=%s\n' "$api_endpoint"
printf 'BFF_TARGET_GROUP_ARN=%s\n' "$target_group_arn"
printf 'BFF_NLB_SECURITY_GROUP_ID=%s\n' "$nlb_security_group_id"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        printf 'request_events_queue_url=%s\n' "$queue_url"
        printf 'api_endpoint=%s\n' "$api_endpoint"
        printf 'bff_target_group_arn=%s\n' "$target_group_arn"
        printf 'bff_nlb_security_group_id=%s\n' "$nlb_security_group_id"
    } >> "$GITHUB_OUTPUT"
fi
