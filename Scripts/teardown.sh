#!/usr/bin/env bash
# End of a work session: nothing survives it, the tooling stack included, so
# the account costs nothing between sessions.
#
#   1. staging, when it exists: pipeline of movies/infra on main with
#      DESTROY=true (GitLab API, token of the Ansible vault), then wait for
#      remove-platform-staging (namespace and EBS volumes, while the cluster
#      runs) and destroy-staging (terraform destroy); approve-production stays
#      pending, there is no production
#   2. terraform destroy of bootstrap/ (GitLab, runner, ECR repositories and
#      images, state and OIDC buckets, IAM): the summary of its plan is
#      printed, then the plan is applied after confirmation
#   3. the host keys of the released Elastic IPs leave ~/.ssh/known_hosts
#   4. Scripts/inventory.sh in every Region (exit status 1 if anything is left)
#
# If GitLab cannot destroy staging, the script stops before step 2: GitLab is
# then still there to retry the destroy-staging job.
#
# Usage: Scripts/teardown.sh [--yes]
#   --yes   apply the destroy plan of bootstrap/ without asking
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="eu-west-3"
PROJECT="movies"
PIPELINE_TIMEOUT="${PIPELINE_TIMEOUT:-3600}"
CA_CERT="$HOME/.local/share/$PROJECT/pki/ca.crt"

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | cut -c3-; }

assume_yes=false
case "${1:-}" in
  "") ;;
  --yes) assume_yes=true ;;
  -h | --help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

tf_color=()
[[ -t 1 ]] || tf_color=(-no-color)

outputs="$(terraform -chdir="$ROOT/bootstrap" output -json)"
out() { jq -r ".$1.value // empty" <<<"$outputs"; }

# Cluster and VPC of staging. An AWS error must stop the script, never read as
# "no staging": a command substitution does not inherit set -e, hence the
# explicit checks.
staging_count() {
  local clusters vpcs
  clusters="$(aws eks list-clusters --region "$REGION" --query "length(clusters[?@ == '$PROJECT-staging'])" --output text)" || return 1
  vpcs="$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Project,Values=$PROJECT" \
    "Name=tag:Environment,Values=staging" --query 'length(Vpcs)' --output text)" || return 1
  [[ "$clusters" =~ ^[0-9]+$ && "$vpcs" =~ ^[0-9]+$ ]] || return 1
  echo $((clusters + vpcs))
}

# GitLab API call with the token of the Ansible vault, never printed.
gitlab() {
  local method="$1" path="$2" token
  shift 2
  token="$(cd "$ROOT/ansible" && ansible-vault view group_vars/all/vault.yml |
    python3 -I -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["vault_gitlab_api_token"])')"
  curl -fsS --cacert "$CA_CERT" -X "$method" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$token") \
    "https://$(out gitlab_public_ip)/api/v4/$path" "$@"
}

job_status() {
  gitlab GET "projects/$PROJECT%2Finfra/pipelines/$1/jobs?per_page=100" |
    jq -r --arg name "$2" '.[] | select(.name == $name) | .status'
}

# Waits for a job of the pipeline; fails unless it succeeds.
wait_job() {
  local pipeline="$1" name="$2" status="" deadline=$((SECONDS + PIPELINE_TIMEOUT))
  while ((SECONDS < deadline)); do
    status="$(job_status "$pipeline" "$name")"
    case "$status" in
      success) echo "$name: success"; return 0 ;;
      failed | canceled | skipped)
        echo "error: $name of pipeline #$pipeline is $status: retry it in GitLab, then run this script again" >&2
        return 1
        ;;
    esac
    sleep 30
  done
  echo "error: $name of pipeline #$pipeline still $status after ${PIPELINE_TIMEOUT}s" >&2
  return 1
}

echo "== 1. staging"
staging="$(staging_count)"
if ((staging > 0)); then
  if [[ -z "$(out gitlab_public_ip)" ]]; then
    echo "error: staging exists but bootstrap/ has no GitLab to destroy it" >&2
    exit 1
  fi
  pipeline="$(gitlab POST "projects/$PROJECT%2Finfra/pipeline" -H 'Content-Type: application/json' \
    -d '{"ref": "main", "variables": [{"key": "DESTROY", "value": "true"}]}' | jq -r .id)"
  [[ "$pipeline" =~ ^[0-9]+$ ]] || { echo "error: GitLab did not start the destroy pipeline" >&2; exit 1; }
  echo "pipeline #$pipeline (DESTROY=true) started"
  wait_job "$pipeline" remove-platform-staging
  wait_job "$pipeline" destroy-staging
  staging="$(staging_count)"
  if ((staging > 0)); then
    echo "error: the destroy pipeline passed but AWS still shows staging" >&2
    exit 1
  fi
else
  echo "no staging environment"
fi

echo "== 2. terraform destroy (bootstrap)"
addresses=("$(out gitlab_public_ip)" "$(out runner_public_ip)")
plan="$(mktemp)"
trap 'rm -f "${plan:?}"' EXIT
# -no-color whatever the output: Terraform colours even a pipe, and a bold
# "Plan:" would escape the grep, stopping the script before the destroy.
terraform -chdir="$ROOT/bootstrap" plan -destroy -input=false -no-color -out="$plan" | grep -E '^Plan:|No changes'
if ! $assume_yes; then
  read -r -p "Destroy the tooling stack? Type yes: " answer </dev/tty
  [[ "$answer" == yes ]] || { echo "aborted: nothing destroyed in bootstrap/" >&2; exit 1; }
fi
terraform -chdir="$ROOT/bootstrap" apply -input=false "${tf_color[@]}" "$plan"

echo "== 3. host keys of the released addresses"
for address in "${addresses[@]}"; do
  [[ -n "$address" ]] || continue
  ssh-keygen -R "$address" >/dev/null 2>&1 || true
  echo "removed $address from known_hosts"
done

echo "== 4. inventory"
"$ROOT/Scripts/inventory.sh"
