#!/usr/bin/env bash
# Local gate, run before every push: replays the checks of the GitLab CI jobs
# with the images the CI files pin, plus the guards that no job holds
# (shellcheck on every script, hadolint on every recipe, no silencing
# directive, every image pinned by digest, a valid compose.yaml). It checks a copy of the files Git
# tracks or would track, never writes in the repository, and keeps the log of
# each step under ~/.local/state/infrastructure-gate/.
#   Scripts/ci-gate.sh
# Not replayed: semgrep-sast and sast-gate (GitLab template), integration-test
# (PostgreSQL and RabbitMQ services), and the jobs that need GitLab or AWS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/infrastructure-gate"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/infrastructure-gate"
LOG_DIR="$STATE/$(date +%Y%m%d-%H%M%S)"
APPS=(api-gateway-app billing-app inventory-app)
SHELLCHECK_IMAGE="koalaman/shellcheck:v0.10.0@sha256:2097951f02e735b613f4a34de20c40f937a6c8f18ecb170612c88c34517221fb"

WORK="$(mktemp -d)"
cleanup() { rm -rf "${WORK:?}"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$LOG_DIR" "$CACHE/npm" "$CACHE/terraform" "$CACHE/trivy"
find "${STATE:?}" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +7 -exec rm -rf {} +

# First reference of an image, with its digest, in the CI files: the gate runs
# exactly what the jobs run.
pinned() {
  local all
  all="$(grep -h -o -E "$1@sha256:[a-f0-9]{64}" "$ROOT"/repos/*/.gitlab-ci.yml || true)"
  if [[ -z "$all" ]]; then
    echo "error: no pinned $1 in repos/*/.gitlab-ci.yml" >&2
    exit 2
  fi
  printf '%s\n' "${all%%$'\n'*}"
}
NODE_IMAGE="$(pinned 'public\.ecr\.aws/docker/library/node:[^@[:space:]]+')"
TERRAFORM_IMAGE="$(pinned 'public\.ecr\.aws/hashicorp/terraform:[^@[:space:]]+')"
TFLINT_IMAGE="$(pinned 'ghcr\.io/terraform-linters/tflint:[^@[:space:]]+')"
TRIVY_IMAGE="$(pinned 'public\.ecr\.aws/aquasecurity/trivy:[^@[:space:]]+')"
HADOLINT_IMAGE="$(pinned 'ghcr\.io/hadolint/hadolint:[^@[:space:]]+')"
RENOVATE_IMAGE="$(pinned 'ghcr\.io/renovatebot/renovate:[0-9.]+')"

RUN=(docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp)

# Copy of the files Git tracks or would track: what the CI checks out, plus the
# files not added yet. A file deleted from the working tree is left out.
copy_tree() {
  local dest="$1"
  mkdir -p "$dest" &&
    git -C "$ROOT" ls-files -z --cached --others --exclude-standard |
    tar -C "$ROOT" --null --ignore-failed-read -T - -cf - 2>/dev/null |
      tar -C "$dest" -xf -
}

repo_state() {
  git -C "$ROOT" status --porcelain=v1 --ignored -uall &&
    git -C "$ROOT" diff | sha256sum
}

guard_no_silencing_directive() {
  local found
  found="$(cd "$WORK/tree" && {
    grep -rn -I -E \
      'shellcheck[[:space:]]+disable|hadolint[[:space:]]+ignore|eslint-disabl[e]|tflint-ignor[e]|trivy:ignor[e]|NOSONA[R]|@ts-ignor[e]|@ts-expect-erro[r]|#[[:space:]]*noqa' \
      --exclude-dir=docs --exclude-dir=.agents --exclude-dir=.git . || true
  })"
  [[ -z "$found" ]] || { printf '%s\n' "$found"; return 1; }
}

guard_every_image_pinned() {
  local found
  found="$(cd "$WORK/tree" && {
    grep -rn -E '^FROM[[:space:]]' --include='Dockerfile*' . | grep -v '@sha256:' || true
    # An image key with a short Docker Hub name too (busybox:1.37); a name key
    # (GitLab CI services) only with a registry path, as "name" also names
    # anything else.
    grep -rn -i -E \
      'image[a-z_]*[[:space:]]*[:=][[:space:]]*["'"'"']?[a-z0-9.-]+(/[a-z0-9._-]+)*:[A-Za-z0-9._-]+|name[[:space:]]*:[[:space:]]*["'"'"']?[a-z0-9.-]+(/[a-z0-9._-]+)+:[A-Za-z0-9._-]+' \
      --include='*.yml' --include='*.yaml' --include='*.sh' --exclude-dir=docs . | grep -v '@sha256:' || true
    grep -rn -E '^[[:space:]]+tag:[[:space:]]' repos/infra/platform/helm | grep -v '@sha256:' || true
  })"
  [[ -z "$found" ]] || { printf '%s\n' "$found"; return 1; }
}

shellcheck_every_script() {
  local scripts=()
  mapfile -t scripts < <(cd "$WORK/tree" && find . -name '*.sh' -not -path './docs/*' | sort) &&
    "${RUN[@]}" -v "$WORK/tree:/work:ro" -w /work --entrypoint shellcheck "$SHELLCHECK_IMAGE" "${scripts[@]}"
}

# Each recipe with the .hadolint.yaml of its repository.
hadolint_every_recipe() {
  local recipe cfg rc=0
  while IFS= read -r recipe; do
    cfg="$(dirname "$recipe")"
    while [[ ! -f "$WORK/tree/$cfg/.hadolint.yaml" && "$cfg" != . ]]; do cfg="$(dirname "$cfg")"; done
    echo "== $recipe ($cfg/.hadolint.yaml)"
    "${RUN[@]}" -v "$WORK/tree:/work:ro" -w /work --entrypoint hadolint "$HADOLINT_IMAGE" \
      --config "$cfg/.hadolint.yaml" "$recipe" || rc=1
  done < <(cd "$WORK/tree" && find . -name 'Dockerfile' -not -path './docs/*' | sort)
  return "$rc"
}

terraform_in() {
  local dir="$1"
  shift
  "${RUN[@]}" -v "$dir:/work" -w /work -v "$CACHE/terraform:/cache" -e TF_PLUGIN_CACHE_DIR=/cache \
    --entrypoint terraform "$TERRAFORM_IMAGE" "$@"
}

# Jobs validate (repos/infra) and the same checks on bootstrap/, outside the CI.
terraform_validate() {
  local infra="$WORK/tree/repos/infra" env
  terraform_in "$infra" fmt -check -recursive -diff terraform &&
    terraform_in "$WORK/tree/bootstrap" fmt -check -diff || return 1
  for env in staging prod; do
    echo "== envs/$env"
    terraform_in "$infra" -chdir="terraform/envs/$env" init -backend=false -input=false -no-color >/dev/null &&
      terraform_in "$infra" -chdir="terraform/envs/$env" validate -no-color || return 1
  done
  echo "== bootstrap"
  terraform_in "$WORK/tree/bootstrap" init -backend=false -input=false -no-color >/dev/null &&
    terraform_in "$WORK/tree/bootstrap" validate -no-color
}

tflint_infra() {
  "${RUN[@]}" -v "$WORK/tree/repos/infra:/work:ro" -w /work --entrypoint tflint "$TFLINT_IMAGE" \
    --chdir=terraform --recursive --config=/work/.tflint.hcl
}

iac_scan() {
  "${RUN[@]}" -v "$WORK/tree/repos/infra:/work:ro" -w /work -v "$CACHE/trivy:/cache" -e TRIVY_CACHE_DIR=/cache \
    --entrypoint trivy "$TRIVY_IMAGE" config --skip-check-update --skip-dirs "**/.terraform" --exit-code 1 \
    --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml terraform/
}

# Before npm ci, as the job reads a fresh checkout.
dependency_scan() {
  "${RUN[@]}" -v "$WORK/apps/$1:/work:ro" -w /work -v "$CACHE/trivy:/cache" -e TRIVY_CACHE_DIR=/cache \
    --entrypoint trivy "$TRIVY_IMAGE" fs --no-progress --scanners vuln,secret --exit-code 1 \
    --severity HIGH,CRITICAL --ignore-unfixed .
}

# Jobs lint and test.
lint_and_test() {
  "${RUN[@]}" -v "$WORK/apps/$1:/work" -w /work -v "$CACHE/npm:/tmp/.npm" -e npm_config_cache=/tmp/.npm \
    --entrypoint sh "$NODE_IMAGE" -c 'npm ci --no-audit --no-fund && npm run lint && npm test'
}

# The model of .env, as .env itself is never copied.
compose_config() {
  docker compose --project-directory "$WORK/tree" -f "$WORK/tree/compose.yaml" \
    --env-file "$WORK/tree/.env.example" config --quiet
}

renovate_config() {
  "${RUN[@]}" -v "$WORK/tree/repos/renovate:/work:ro" -w /work --entrypoint renovate-config-validator \
    "$RENOVATE_IMAGE" --strict renovate.json default.json
}

failed=()
step() {
  local name="$1" start="$SECONDS"
  shift
  if "$@" >"$LOG_DIR/$name.log" 2>&1; then
    printf 'OK  %-34s %4ss\n' "$name" "$((SECONDS - start))"
  else
    printf 'KO  %-34s %4ss  %s\n' "$name" "$((SECONDS - start))" "$LOG_DIR/$name.log"
    failed+=("$name")
  fi
}

before="$(repo_state)"
copy_tree "$WORK/tree"
for app in "${APPS[@]}"; do
  mkdir -p "$WORK/apps" && cp -a "$WORK/tree/repos/$app" "$WORK/apps/$app"
done
echo "# Gate, $(git -C "$ROOT" rev-parse --short HEAD), logs: $LOG_DIR"

step no-silencing-directive guard_no_silencing_directive
step every-image-pinned guard_every_image_pinned
step shellcheck shellcheck_every_script
step hadolint hadolint_every_recipe
step terraform-validate terraform_validate
step tflint tflint_infra
step iac-scan iac_scan
for app in "${APPS[@]}"; do
  step "dependency-scan:$app" dependency_scan "$app"
  step "lint-and-test:$app" lint_and_test "$app"
done
step renovate-config renovate_config
step compose-config compose_config

if [[ "$(repo_state)" != "$before" ]]; then
  printf 'KO  %-34s\n' "nothing-written-in-the-repository"
  failed+=("nothing-written-in-the-repository")
fi

if ((${#failed[@]})); then
  echo "Gate refused: ${failed[*]}" >&2
  exit 1
fi
echo "Gate passed."
