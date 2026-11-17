#!/usr/bin/env bash
# Read-only inventory of the billable resources in every enabled AWS Region,
# run at the end of a work session by Scripts/teardown.sh. Nothing survives a
# session, the tooling stack included: anything found is reported. Counted per
# Region: instances in any state but terminated, disks, Elastic IPs, NAT
# gateways, load balancers (ALB/NLB and Classic), EKS clusters, RDS, Lambda,
# CloudWatch log groups, ECR repositories; for the whole account, the S3
# buckets of the project.
#
# Exit status: 0 when nothing is left, 1 otherwise, 2 on an AWS error.
#
# Usage: Scripts/inventory.sh
set -euo pipefail

PROJECT="movies"
COLUMNS_HEADER="REGION EC2 EBS EIP NAT ELB CLB EKS RDS LAMBDA LOGS ECR"

# Counts are computed by the AWS CLI (JMESPath length() in --query), never by
# counting lines.
count_region() {
  local region="$1"
  local common_args=(--region "$region" --output text)
  printf '%s %s %s %s %s %s %s %s %s %s %s %s\n' "$region" \
    "$(aws ec2 describe-instances "${common_args[@]}" --filters Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down --query 'length(Reservations[].Instances[])')" \
    "$(aws ec2 describe-volumes "${common_args[@]}" --query 'length(Volumes)')" \
    "$(aws ec2 describe-addresses "${common_args[@]}" --query 'length(Addresses)')" \
    "$(aws ec2 describe-nat-gateways "${common_args[@]}" --filter Name=state,Values=pending,available,deleting --query 'length(NatGateways)')" \
    "$(aws elbv2 describe-load-balancers "${common_args[@]}" --query 'length(LoadBalancers)')" \
    "$(aws elb describe-load-balancers "${common_args[@]}" --query 'length(LoadBalancerDescriptions)')" \
    "$(aws eks list-clusters "${common_args[@]}" --query 'length(clusters)')" \
    "$(aws rds describe-db-instances "${common_args[@]}" --query 'length(DBInstances)')" \
    "$(aws lambda list-functions "${common_args[@]}" --query 'length(Functions)')" \
    "$(aws logs describe-log-groups "${common_args[@]}" --query 'length(logGroups)')" \
    "$(aws ecr describe-repositories "${common_args[@]}" --query 'length(repositories)')"
}
export -f count_region

read -r -a regions <<<"$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)"
echo "# Inventory, $(date '+%F %H:%M:%S'), ${#regions[@]} Regions"

# Each line must hold the Region and eleven numbers, otherwise an AWS call failed.
if ! rows="$(printf '%s\n' "${regions[@]}" | xargs -P 8 -I{} bash -c "count_region \"\$1\"" _ {} | sort)"; then
  echo "error: an AWS call failed during the inventory" >&2
  exit 2
fi
if grep -q -v -E '^[a-z0-9-]+( [0-9]+){11}$' <<<"$rows"; then
  echo "error: unexpected AWS answer:" >&2
  grep -v -E '^[a-z0-9-]+( [0-9]+){11}$' <<<"$rows" >&2
  exit 2
fi

{ echo "$COLUMNS_HEADER"; echo "$rows"; } | column -t
left="$(awk '{ for (i = 2; i <= NF; i++) s += $i } END { print s + 0 }' <<<"$rows")"

# S3 is global: the state and OIDC buckets of bootstrap/ start with the project name.
if ! buckets="$(aws s3api list-buckets --query "length(Buckets[?starts_with(Name, '$PROJECT-')])" --output text)"; then
  echo "error: an AWS call failed during the inventory" >&2
  exit 2
fi
echo
echo "S3 buckets $PROJECT-*: $buckets"
left=$((left + buckets))

echo
if [[ "$left" -eq 0 ]]; then
  echo "OK: nothing billable is left in the ${#regions[@]} Regions."
else
  echo "WARNING: $left billable resource(s) left, see above." >&2
  exit 1
fi
