#!/usr/bin/env bash
# Build the backend image, push it to ECR and roll the ECS Fargate service
# defined in infra/backend.yaml (ALB in front, Postgres on RDS behind).
#
# Safe to re-run: the CloudFormation stack is the source of truth, so every run
# after the first is an in-place update with the new image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${ROOT}/infra/backend.yaml"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- configuration ----------------------------------------------------------

# .env is the same file Compose reads; anything already exported wins over it.
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

# A blank AWS_PROFILE is read as a profile literally named "", and blank keys
# short-circuit the credential chain - which is exactly what a .env full of
# empty placeholders hands us. Treat empty as absent.
for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done

PROJECT_NAME="${PROJECT_NAME:-peach}"
STACK_NAME="${STACK_NAME:-${PROJECT_NAME}-backend}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
[[ -n "${AWS_REGION}" ]] || die "AWS_REGION is not set (put it in .env)"
export AWS_DEFAULT_REGION="${AWS_REGION}"

ECR_REPOSITORY="${ECR_REPOSITORY:-${PROJECT_NAME}-backend}"
TASK_ARCHITECTURE="${TASK_ARCHITECTURE:-arm64}"
case "${TASK_ARCHITECTURE}" in
  arm64) CFN_ARCHITECTURE=ARM64 ;;
  amd64) CFN_ARCHITECTURE=X86_64 ;;
  *) die "TASK_ARCHITECTURE must be arm64 or amd64, got '${TASK_ARCHITECTURE}'" ;;
esac

# --- preflight --------------------------------------------------------------

for tool in aws docker python3; do
  command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
done
docker info >/dev/null 2>&1 || die "docker daemon is not running"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "no usable AWS credentials - set AWS_PROFILE or the AWS_* keys in .env"
CALLER="$(aws sts get-caller-identity --query Arn --output text)"
log "account ${ACCOUNT_ID} in ${AWS_REGION} as ${CALLER}"

# --- network ----------------------------------------------------------------

if [[ -z "${AWS_VPC_ID:-}" ]]; then
  AWS_VPC_ID="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true \
    --query 'Vpcs[0].VpcId' --output text)"
  [[ "${AWS_VPC_ID}" != "None" && -n "${AWS_VPC_ID}" ]] \
    || die "no default VPC in ${AWS_REGION} - set AWS_VPC_ID and AWS_PUBLIC_SUBNET_IDS"
  warn "AWS_VPC_ID unset, using the default VPC ${AWS_VPC_ID}"
fi

if [[ -z "${AWS_PUBLIC_SUBNET_IDS:-}" ]]; then
  AWS_PUBLIC_SUBNET_IDS="$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${AWS_VPC_ID}" "Name=default-for-az,Values=true" \
    --query 'Subnets[].SubnetId' --output text | tr '\t' ',')"
  [[ -n "${AWS_PUBLIC_SUBNET_IDS}" ]] || die "no default subnets in ${AWS_VPC_ID}"
  warn "AWS_PUBLIC_SUBNET_IDS unset, using ${AWS_PUBLIC_SUBNET_IDS}"
fi

if [[ "${AWS_PUBLIC_SUBNET_IDS}" != *,* ]]; then
  die "an ALB needs subnets in at least two availability zones"
fi

AWS_PRIVATE_SUBNET_IDS="${AWS_PRIVATE_SUBNET_IDS:-}"
# Tasks in a public subnet have no NAT gateway, so they need a public IP to
# reach ECR and Secrets Manager at all.
if [[ -z "${ECS_ASSIGN_PUBLIC_IP:-}" ]]; then
  if [[ -n "${AWS_PRIVATE_SUBNET_IDS}" ]]; then
    ECS_ASSIGN_PUBLIC_IP=DISABLED
  else
    ECS_ASSIGN_PUBLIC_IP=ENABLED
  fi
fi

# --- ecr --------------------------------------------------------------------

# The repository lives outside the stack: the service cannot be created until
# there is an image to pull, so the push has to happen first.
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
if ! aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" >/dev/null 2>&1; then
  log "creating ECR repository ${ECR_REPOSITORY}"
  aws ecr create-repository \
    --repository-name "${ECR_REPOSITORY}" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE >/dev/null
  aws ecr put-lifecycle-policy \
    --repository-name "${ECR_REPOSITORY}" \
    --lifecycle-policy-text '{"rules":[{"rulePriority":1,"description":"keep the last 3 images","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":3},"action":{"type":"expire"}}]}' \
    >/dev/null
fi

if [[ -z "${IMAGE_TAG:-}" || "${IMAGE_TAG}" == "latest" ]]; then
  if git -C "${ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
    IMAGE_TAG="$(git -C "${ROOT}" rev-parse --short=12 HEAD)"
    git -C "${ROOT}" diff --quiet HEAD -- backend || IMAGE_TAG="${IMAGE_TAG}-dirty"
  else
    IMAGE_TAG="$(date -u +%Y%m%d%H%M%S)"
  fi
fi
IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

log "building ${IMAGE_URI} for linux/${TASK_ARCHITECTURE}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null

docker build \
  --platform "linux/${TASK_ARCHITECTURE}" \
  --target runtime \
  --tag "${IMAGE_URI}" \
  --tag "${REGISTRY}/${ECR_REPOSITORY}:latest" \
  "${ROOT}/backend"

log "pushing to ECR"
docker push --quiet "${IMAGE_URI}"
docker push --quiet "${REGISTRY}/${ECR_REPOSITORY}:latest"

# --- database password ------------------------------------------------------

# CloudFormation composes DATABASE_URL from this password and the RDS endpoint,
# so it has to stay the same across deploys. Read it back from the secret the
# stack already owns; only mint a new one on the very first run.
DB_PASSWORD=""
SECRET_ARN="$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='DatabaseUrlSecretArn'].OutputValue" \
  --output text 2>/dev/null || true)"

if [[ -n "${SECRET_ARN}" && "${SECRET_ARN}" != "None" ]]; then
  DB_PASSWORD="$(aws secretsmanager get-secret-value --secret-id "${SECRET_ARN}" \
    --query SecretString --output text 2>/dev/null \
    | python3 -c 'import sys,urllib.parse; print(urllib.parse.urlsplit(sys.stdin.read().strip()).password or "")')"
fi

if [[ -z "${DB_PASSWORD}" ]]; then
  log "generating the database password"
  # No /, ", @ or space: RDS rejects those, and it keeps the URL parseable.
  DB_PASSWORD="$(python3 -c '
import secrets, string
alphabet = string.ascii_letters + string.digits + "-_.~"
print("".join(secrets.choice(alphabet) for _ in range(40)))')"
fi

# --- deploy -----------------------------------------------------------------

# Parameters go through a 0600 file rather than argv, so the password never
# shows up in `ps`.
PARAMS_FILE="$(mktemp)"
chmod 600 "${PARAMS_FILE}"
trap 'rm -f "${PARAMS_FILE}"' EXIT

PROJECT_NAME="${PROJECT_NAME}" \
VPC_ID="${AWS_VPC_ID}" \
PUBLIC_SUBNETS="${AWS_PUBLIC_SUBNET_IDS}" \
PRIVATE_SUBNETS="${AWS_PRIVATE_SUBNET_IDS}" \
IMAGE_URI="${IMAGE_URI}" \
CONTAINER_PORT="${ECS_CONTAINER_PORT:-8000}" \
TASK_CPU="${ECS_TASK_CPU:-256}" \
TASK_MEMORY="${ECS_TASK_MEMORY:-512}" \
CFN_ARCHITECTURE="${CFN_ARCHITECTURE}" \
DESIRED_COUNT="${ECS_DESIRED_COUNT:-1}" \
ASSIGN_PUBLIC_IP="${ECS_ASSIGN_PUBLIC_IP}" \
DB_NAME="${DB_NAME:-${POSTGRES_DB:-peach}}" \
DB_USERNAME="${DB_USERNAME:-${POSTGRES_USER:-peach}}" \
DB_PASSWORD="${DB_PASSWORD}" \
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-db.t4g.micro}" \
DB_ALLOCATED_STORAGE="${DB_ALLOCATED_STORAGE:-20}" \
DB_ENGINE_VERSION="${DB_ENGINE_VERSION:-17}" \
APP_ENV="${APP_ENV_AWS:-production}" \
LOG_LEVEL="${LOG_LEVEL:-info}" \
CORS_ORIGINS="${API_CORS_ORIGINS:-*}" \
ACM_CERTIFICATE_ARN="${ACM_CERTIFICATE_ARN:-}" \
DOMAIN_NAME="${DOMAIN_NAME:-}" \
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}" \
python3 - "${PARAMS_FILE}" <<'PY'
import json, os, sys

params = {
    "ProjectName": os.environ["PROJECT_NAME"],
    "VpcId": os.environ["VPC_ID"],
    "PublicSubnetIds": os.environ["PUBLIC_SUBNETS"],
    "PrivateSubnetIds": os.environ["PRIVATE_SUBNETS"],
    "ImageUri": os.environ["IMAGE_URI"],
    "ContainerPort": os.environ["CONTAINER_PORT"],
    "TaskCpu": os.environ["TASK_CPU"],
    "TaskMemory": os.environ["TASK_MEMORY"],
    "TaskCpuArchitecture": os.environ["CFN_ARCHITECTURE"],
    "DesiredCount": os.environ["DESIRED_COUNT"],
    "AssignPublicIp": os.environ["ASSIGN_PUBLIC_IP"],
    "DbName": os.environ["DB_NAME"],
    "DbUsername": os.environ["DB_USERNAME"],
    "DbPassword": os.environ["DB_PASSWORD"],
    "DbInstanceClass": os.environ["DB_INSTANCE_CLASS"],
    "DbAllocatedStorage": os.environ["DB_ALLOCATED_STORAGE"],
    "DbEngineVersion": os.environ["DB_ENGINE_VERSION"],
    "AppEnv": os.environ["APP_ENV"],
    "LogLevel": os.environ["LOG_LEVEL"],
    "CorsOrigins": os.environ["CORS_ORIGINS"],
    "AcmCertificateArn": os.environ["ACM_CERTIFICATE_ARN"],
    "DomainName": os.environ["DOMAIN_NAME"],
    "HostedZoneId": os.environ["HOSTED_ZONE_ID"],
}
with open(sys.argv[1], "w") as fh:
    json.dump(
        [{"ParameterKey": k, "ParameterValue": v} for k, v in params.items()], fh
    )
PY

if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" >/dev/null 2>&1; then
  log "first deploy - creating ${STACK_NAME} (RDS takes around 10 minutes)"
else
  log "updating ${STACK_NAME}"
fi

if ! aws cloudformation deploy \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE}" \
  --parameter-overrides "file://${PARAMS_FILE}" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags "project=${PROJECT_NAME}" "component=backend"; then
  warn "deploy failed - most recent failure reasons:"
  aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" \
    --max-items 40 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`||ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table >&2 || true
  exit 1
fi

# --- report -----------------------------------------------------------------

outputs() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

API_URL="$(outputs ApiUrl)"
log "service is stable"
echo
echo "  api        ${API_URL}"
echo "  health     ${API_URL}/health"
echo "  docs       ${API_URL}/docs"
echo "  database   $(outputs DatabaseEndpoint)"
echo "  logs       aws logs tail $(outputs LogGroupName) --follow"
echo "  shell      aws ecs execute-command --cluster $(outputs ClusterName) \\"
echo "               --task \$(aws ecs list-tasks --cluster $(outputs ClusterName) \\"
echo "               --service-name $(outputs ServiceName) --query 'taskArns[0]' --output text) \\"
echo "               --container backend --interactive --command /bin/bash"
echo

if curl -fsS --max-time 10 "${API_URL}/health" >/dev/null 2>&1; then
  log "GET /health answered"
else
  warn "GET /health did not answer yet - DNS for a fresh ALB can take a minute"
fi

echo "Point the frontend at it with NEXT_PUBLIC_API_URL=${API_URL}, then set"
echo "API_CORS_ORIGINS to the frontend's origin and re-run this to narrow CORS."
