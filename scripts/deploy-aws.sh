#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: %s --env-file PATH\n' "${0##*/}"
}

ENV_FILE=""
while (($#)); do
    case "$1" in
        --env-file)
            (($# >= 2)) || fail "--env-file requires a path."
            ENV_FILE=$2
            shift 2
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

[[ -n "$ENV_FILE" ]] || {
    usage >&2
    fail "Provide an explicit environment file with --env-file."
}
[[ -f "$ENV_FILE" && -r "$ENV_FILE" ]] || fail "Cannot read environment file: $ENV_FILE"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
STACK_FILE="$INFRA_ROOT/docker-stack.aws.yml"

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
            AWS_REGION|ECR_REGISTRY|BFF_IMAGE_TAG|CATALOG_IMAGE_TAG|REQUESTS_IMAGE_TAG|CREWS_IMAGE_TAG|REPORT_IMAGE_TAG|EUREKA_IMAGE_TAG|BFF_PORT|JWT_JWK_SET_URI|CORS_ALLOWED_ORIGINS|HTTP_CONNECT_TIMEOUT|HTTP_READ_TIMEOUT|EUREKA_SERVER_URL|REQUESTS_SERVICE_URL|CATALOG_SERVICE_URL|CREWS_SERVICE_URL|REPORT_SERVICE_URL)
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
command -v docker >/dev/null 2>&1 || fail "Docker CLI is not installed."

AWS_REGION=${AWS_REGION:-us-east-1}
[[ "$AWS_REGION" =~ ^[a-z0-9-]+$ ]] || fail "AWS_REGION is invalid."
export AWS_REGION

for variable in JWT_JWK_SET_URI CORS_ALLOWED_ORIGINS; do
    [[ -n "${!variable:-}" ]] || fail "$variable must be set in $ENV_FILE."
done

[[ "$JWT_JWK_SET_URI" =~ ^https://[^/]+/.+ ]] \
    || fail "JWT_JWK_SET_URI must be a complete HTTPS URL."
case "$JWT_JWK_SET_URI" in
    *example.invalid*|*localhost*|*127.0.0.1*)
        fail "Replace the JWT_JWK_SET_URI placeholder with the real JWKS endpoint."
        ;;
esac

IFS=',' read -r -a allowed_origins <<< "$CORS_ALLOWED_ORIGINS"
((${#allowed_origins[@]} > 0)) || fail "CORS_ALLOWED_ORIGINS must contain at least one origin."
for origin in "${allowed_origins[@]}"; do
    origin="${origin#"${origin%%[![:space:]]*}"}"
    origin="${origin%"${origin##*[![:space:]]}"}"
    [[ "$origin" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] \
        || fail "Each CORS origin must be a specific HTTPS origin without a path."
    case "$origin" in
        *example.com*|*localhost*)
            fail "Replace the CORS_ALLOWED_ORIGINS placeholder with the real frontend origin."
            ;;
    esac
done

BFF_PORT=${BFF_PORT:-8080}
[[ "$BFF_PORT" =~ ^[0-9]+$ ]] && ((BFF_PORT >= 1 && BFF_PORT <= 65535)) \
    || fail "BFF_PORT must be between 1 and 65535."
export BFF_PORT

: "${HTTP_CONNECT_TIMEOUT:=2s}"
: "${HTTP_READ_TIMEOUT:=5s}"
: "${EUREKA_SERVER_URL:=http://eureka:8761/eureka/}"
: "${REQUESTS_SERVICE_URL:=http://request-ms}"
: "${CATALOG_SERVICE_URL:=http://catalog-ms}"
: "${CREWS_SERVICE_URL:=http://crews-ms}"
: "${REPORT_SERVICE_URL:=http://report-ms}"
: "${BFF_IMAGE_TAG:=latest}"
: "${CATALOG_IMAGE_TAG:=latest}"
: "${REQUESTS_IMAGE_TAG:=latest}"
: "${CREWS_IMAGE_TAG:=latest}"
: "${REPORT_IMAGE_TAG:=latest}"
: "${EUREKA_IMAGE_TAG:=latest}"
export HTTP_CONNECT_TIMEOUT HTTP_READ_TIMEOUT EUREKA_SERVER_URL
export REQUESTS_SERVICE_URL CATALOG_SERVICE_URL CREWS_SERVICE_URL REPORT_SERVICE_URL
export BFF_IMAGE_TAG CATALOG_IMAGE_TAG REQUESTS_IMAGE_TAG CREWS_IMAGE_TAG REPORT_IMAGE_TAG EUREKA_IMAGE_TAG

for variable in BFF_IMAGE_TAG CATALOG_IMAGE_TAG REQUESTS_IMAGE_TAG CREWS_IMAGE_TAG REPORT_IMAGE_TAG EUREKA_IMAGE_TAG; do
    [[ "${!variable}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] \
        || fail "$variable contains an invalid Docker image tag."
done

docker_info="$(docker info --format '{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}}')" \
    || fail "Could not read Docker Swarm status."
[[ "$docker_info" == "active true" ]] \
    || fail "Run this script on an active Docker Swarm Manager."

ready_nodes="$(docker node ls --format '{{.Status}}' | awk '$1 == "Ready" { count++ } END { print count+0 }')" \
    || fail "Could not list Docker Swarm nodes."
((ready_nodes >= 2)) || fail "At least two Ready Swarm nodes are required for this deployment."

account_id="$(aws sts get-caller-identity --query Account --output text)" \
    || fail "AWS STS could not identify the active AWS account."
[[ "$account_id" =~ ^[0-9]{12}$ ]] || fail "AWS STS returned an invalid account ID."

derived_registry="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"
if [[ -n "${ECR_REGISTRY:-}" && "$ECR_REGISTRY" != "$derived_registry" ]]; then
    fail "ECR_REGISTRY does not match the active AWS account and region."
fi
ECR_REGISTRY=$derived_registry
export ECR_REGISTRY

for secret in barriodigital_db_password barriodigital_db_app_password; do
    docker secret inspect "$secret" >/dev/null 2>&1 \
        || fail "Required Swarm secret '$secret' is missing. Create it before deploying."
done

[[ -f "$STACK_FILE" ]] || fail "AWS stack file not found: $STACK_FILE"
cd "$INFRA_ROOT"
docker stack config --compose-file "$STACK_FILE" >/dev/null \
    || fail "Docker rejected the AWS stack configuration."

aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY" \
    || fail "Could not authenticate Docker to ECR."

docker stack deploy --with-registry-auth --compose-file "$STACK_FILE" barriodigital \
    || fail "Docker Swarm could not deploy the barriodigital stack."

printf '\nCurrent stack services:\n'
docker stack services barriodigital || fail "Could not list stack services."
printf '\nCurrent stack tasks:\n'
docker stack ps barriodigital --no-trunc || fail "Could not list stack tasks."
