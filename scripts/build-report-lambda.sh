#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LAMBDA_DIR="$INFRA_ROOT/lambda/report-event-consumer"
AWS_REGION=${AWS_REGION:-us-east-1}
LAMBDA_IMAGE_TAG=${LAMBDA_IMAGE_TAG:-latest}
ECR_REPOSITORY=barriodigital/report-event-consumer

command -v aws >/dev/null 2>&1 || fail "AWS CLI is not installed."
command -v docker >/dev/null 2>&1 || fail "Docker CLI is not installed."
[[ "$AWS_REGION" =~ ^[a-z0-9-]+$ ]] || fail "AWS_REGION is invalid."
[[ "$LAMBDA_IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] \
    || fail "LAMBDA_IMAGE_TAG is invalid."

account_id="$(aws sts get-caller-identity --query Account --output text)" \
    || fail "AWS STS could not identify the active account."
[[ "$account_id" =~ ^[0-9]{12}$ ]] || fail "AWS STS returned an invalid account ID."

registry="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"
image_uri="${registry}/${ECR_REPOSITORY}:${LAMBDA_IMAGE_TAG}"
if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1; then
    aws ecr create-repository \
        --region "$AWS_REGION" \
        --repository-name "$ECR_REPOSITORY" \
        --image-scanning-configuration scanOnPush=true \
        --image-tag-mutability MUTABLE >/dev/null \
        || aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPOSITORY" >/dev/null \
        || fail "Could not create or inspect the Lambda ECR repository."
fi

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$registry" \
    || fail "Could not authenticate Docker to ECR."

docker build --platform linux/amd64 --provenance=false --sbom=false --tag "$image_uri" "$LAMBDA_DIR" \
    || fail "Could not build the Report event consumer image."
docker push "$image_uri" || fail "Could not push the Report event consumer image."

printf 'LAMBDA_IMAGE_URI=%s\n' "$image_uri"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'image_uri=%s\n' "$image_uri" >> "$GITHUB_OUTPUT"
fi
