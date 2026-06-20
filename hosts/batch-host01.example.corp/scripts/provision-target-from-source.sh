#!/usr/bin/env bash
#
# Provision a replacement EC2 instance from a source server and attach data volumes.
#
# Generic lift-and-replace helper. Illustrated for Linux OS generation migrations
# (e.g. Amazon Linux 2 → Amazon Linux 2023); AMI-agnostic.
#
# Volume modes:
#   --source-ami-id       Create NEW volumes from AMI snapshots (source stays running)
#   --source-instance-id  Detach volumes from live source (stops source unless --no-stop-source)
#
set -euo pipefail

REGION="${AWS_REGION:-us-east-2}"
SOURCE_AMI_ID=""
SOURCE_INSTANCE_ID=""
TARGET_AMI_ID=""
PRIVATE_IP=""
DRY_RUN=false
STOP_SOURCE=true
TARGET_NAME_SUFFIX=" (NEW)"

usage() {
  cat <<'EOF'
Usage: provision-target-from-source.sh [options]

Required:
  -t, --target-ami-id ID       Golden/target AMI for the replacement instance

Source (at least one):
  -a, --source-ami-id ID       Source AMI — create volumes from snapshots
  -s, --source-instance-id ID  Source instance — launch config + optional live detach

Optional:
  -p, --private-ip IP          Private IP for target
  -r, --region REGION          AWS region (default: us-east-2)
      --name-suffix TEXT       Appended to Name tag (default: " (NEW)")
      --no-stop-source         Live detach: do not stop source before detach
      --dry-run                Print planned actions only
  -h, --help

Example (AL2 → AL2023 illustration):
  ./provision-target-from-source.sh \
    --source-ami-id ami-0SOURCE00000000000 \
    --source-instance-id i-0source1234567890 \
    --target-ami-id ami-0TARGET0000000000 \
    --private-ip 10.30.33.221 \
    --dry-run
EOF
}

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

aws_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    log "DRY-RUN: aws $*"
    return 0
  fi
  aws --region "$REGION" "$@"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--source-ami-id) SOURCE_AMI_ID="$2"; shift 2 ;;
    -s|--source-instance-id) SOURCE_INSTANCE_ID="$2"; shift 2 ;;
    -t|--target-ami-id) TARGET_AMI_ID="$2"; shift 2 ;;
    -p|--private-ip) PRIVATE_IP="$2"; shift 2 ;;
    -r|--region) REGION="$2"; shift 2 ;;
    --name-suffix) TARGET_NAME_SUFFIX="$2"; shift 2 ;;
    --no-stop-source) STOP_SOURCE=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

command -v aws >/dev/null || die "aws CLI required"
command -v jq >/dev/null || die "jq required"
[[ -n "$TARGET_AMI_ID" ]] || die "--target-ami-id is required"
[[ -n "$SOURCE_INSTANCE_ID" || -n "$SOURCE_AMI_ID" ]] || die "Provide source instance or AMI"

resolve_config_instance() {
  if [[ -n "$SOURCE_INSTANCE_ID" ]]; then
    echo "$SOURCE_INSTANCE_ID"
    return
  fi
  local ids
  ids=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=image-id,Values=${SOURCE_AMI_ID}" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  [[ -n "$ids" && "$(wc -w <<< "$ids")" -eq 1 ]] || die "Pass --source-instance-id for launch config"
  echo "$ids"
}

CONFIG_INSTANCE=$(resolve_config_instance)
log "Launch config from instance: $CONFIG_INSTANCE"

SUBNET=$(aws_cmd ec2 describe-instances --instance-ids "$CONFIG_INSTANCE" \
  --query 'Reservations[0].Instances[0].SubnetId' --output text)
SGS=$(aws_cmd ec2 describe-instances --instance-ids "$CONFIG_INSTANCE" \
  --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text)
ITYPE=$(aws_cmd ec2 describe-instances --instance-ids "$CONFIG_INSTANCE" \
  --query 'Reservations[0].Instances[0].InstanceType' --output text)

log "Subnet=$SUBNET Type=$ITYPE"

# Build tag spec: copy non-aws: tags, append suffix to Name
TAG_FILE=$(mktemp)
aws ec2 describe-tags --region "$REGION" \
  --filters "Name=resource-id,Values=${CONFIG_INSTANCE}" --output json \
  | jq --arg suffix "$TARGET_NAME_SUFFIX" '
      [.Tags[] | select(.Key | startswith("aws:") | not)]
      | map(if .Key == "Name" then .Value += $suffix else . end)
      | {Tags: map({Key: .Key, Value: .Value})}
    ' > "$TAG_FILE"

RUN_ARGS=(
  run-instances
  --image-id "$TARGET_AMI_ID"
  --instance-type "$ITYPE"
  --subnet-id "$SUBNET"
  --tag-specifications "file://$TAG_FILE"
  --metadata-options HttpTokens=required
)

for sg in $SGS; do
  RUN_ARGS+=(--security-group-ids "$sg")
done
[[ -n "$PRIVATE_IP" ]] && RUN_ARGS+=(--private-ip-address "$PRIVATE_IP")

if [[ "$DRY_RUN" == true ]]; then
  log "Would launch: ${RUN_ARGS[*]}"
else
  TARGET_ID=$(aws "${RUN_ARGS[@]}" --query 'Instances[0].InstanceId' --output text)
  log "Launched target instance: $TARGET_ID"
  aws ec2 wait instance-running --instance-ids "$TARGET_ID"
  log "Target is running. Attach data volumes per your migration runbook."
fi

rm -f "$TAG_FILE"
log "Done."
