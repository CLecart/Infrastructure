#!/usr/bin/env bash
# Local gate, run before every commit and every push. It runs the script of
# every CI job that needs neither GitLab, AWS nor a service, in the image of
# that job, both read from the .gitlab-ci.yml files, so the gate cannot drift
# from the jobs. It adds the guards that no job holds: shellcheck on every
# script, hadolint on every recipe, Terraform of bootstrap/, no silencing
# directive, every image pinned by digest (Helm charts included), a valid
# compose.yaml, no secret in the history. It works on copies of the files Git
# tracks or would track, never writes in the repository (and checks it), and
# keeps the log of each step under ~/.local/state/infrastructure-gate/.
#   Scripts/ci-gate.sh
# Jobs run: validate, tflint, iac-scan (infra); dependency-scan, build, test,
# lint, dockerfile-lint (each application); validate-config (renovate). Not
# run: semgrep-sast and sast-gate (GitLab template), integration-test
# (PostgreSQL and RabbitMQ services), and the jobs that need GitLab or AWS.
# Needs docker, git, and python3 with PyYAML.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/infrastructure-gate"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/infrastructure-gate"
LOG_DIR="$STATE/$(date +%Y%m%d-%H%M%S)"
APPS=(api-gateway-app billing-app inventory-app)
SHELLCHECK_IMAGE="koalaman/shellcheck:v0.10.0@sha256:2097951f02e735b613f4a34de20c40f937a6c8f18ecb170612c88c34517221fb"
HELM_IMAGE="docker.io/alpine/helm:4.3.1@sha256:e3f8d5c462d75470fbb1fce79ad5c20063657096d1f98c0fcea869e2600e2e5e"
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

WORK="$(mktemp -d)"
cleanup() { rm -rf "${WORK:?}"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$LOG_DIR" "$CACHE/npm" "$CACHE/terraform" "$CACHE/trivy"
find "${STATE:?}" -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +7 -exec rm -rf {} +

# First reference of an image, with its digest, in the CI files, for the checks
# the gate adds with the tools of the jobs.
pinned() {
  local all
  all="$(grep -h -o -E "$1@sha256:[a-f0-9]{64}" "$ROOT"/repos/*/.gitlab-ci.yml || true)"
  if [[ -z "$all" ]]; then
    echo "error: no pinned $1 in repos/*/.gitlab-ci.yml" >&2
    exit 2
  fi
  printf '%s\n' "${all%%$'\n'*}"
}
TERRAFORM_IMAGE="$(pinned 'public\.ecr\.aws/hashicorp/terraform:[^@[:space:]]+')"
HADOLINT_IMAGE="$(pinned 'ghcr\.io/hadolint/hadolint:[^@[:space:]]+')"

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

# Every image the Helm charts pull, as `helm template` renders them with the
# values of platform/helm and the chart versions of scripts/deploy-platform.sh:
# each image key, a short name included, and each image passed as an argument
# (the config-reloader of the operator) must carry a digest.
helm_images_pinned() {
  local infra="$WORK/tree/repos/infra" name version rendered="" chart found list=()
  local -A repo=([kube-prometheus-stack]=https://prometheus-community.github.io/helm-charts
    [fluent-bit]=https://fluent.github.io/helm-charts [cluster-autoscaler]=https://kubernetes.github.io/autoscaler)
  for name in kube-prometheus-stack fluent-bit cluster-autoscaler; do
    # An empty version would render the newest chart, not the deployed one.
    version="$(sed -n -E "s/^${name//-/_}_VERSION=\"(.*)\"$/\1/Ip" "$infra/scripts/deploy-platform.sh")"
    [[ -n "$version" ]] || { echo "no version of $name in scripts/deploy-platform.sh"; return 1; }
    echo "== $name $version"
    chart="$("${RUN[@]}" -v "$infra:/work:ro" -w /work --entrypoint helm "$HELM_IMAGE" template "$name" "$name" \
      --repo "${repo[$name]}" --version "$version" -f "platform/helm/$name.yaml" \
      --set autoDiscovery.clusterName=gate --set awsRegion=eu-west-3)" || return 1
    rendered+="$chart"$'\n'
  done
  found="$({
    grep -E '^[[:space:]-]*image:' <<<"$rendered" | sed -E 's/^[[:space:]-]*image:[[:space:]]*//; s/"//g'
    grep -o -E '[a-z0-9.-]+\.[a-z]{2,}(:[0-9]+)?/[a-z0-9._/-]+:[A-Za-z0-9._-]+(@sha256:[a-f0-9]{64})?' <<<"$rendered"
  } | grep -v '@sha256:' | sort -u || true)"
  echo "$(grep -c -E '@sha256:' <<<"$rendered") pinned image references rendered"
  [[ -z "$found" ]] || { mapfile -t list <<<"$found"; printf 'unpinned: %s\n' "${list[@]}"; return 1; }
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

# Image and script of a CI job, read from its .gitlab-ci.yml: the image on the
# first line (the job's, else the default one, variables expanded), then the
# variables of the file and of the job as defaults, then the script. extends
# is followed; a !reference tag stops the gate instead of being skipped.
job_spec() {
  python3 -I - "$1" "$2" <<'PY_JOB'
import re, sys, yaml

class Loader(yaml.SafeLoader):
    pass

Loader.add_multi_constructor("!", lambda loader, suffix, node: {"!": suffix})
path, name = sys.argv[1], sys.argv[2]
doc = yaml.load(open(path), Loader=Loader)

def job(key):
    if not isinstance(doc.get(key), dict):
        sys.exit(f"no job {key} in {path}")
    own = dict(doc[key])
    parents = own.pop("extends", [])
    merged = {}
    for parent in [parents] if isinstance(parents, str) else parents:
        merged.update(job(parent))
    merged.update(own)
    return merged

def values(block):
    return {k: v.get("value") if isinstance(v, dict) else v for k, v in (block or {}).items()}

spec = job(name)
variables = {**values(doc.get("variables")), **values(spec.get("variables"))}
image = spec.get("image") or (doc.get("default") or {}).get("image")
image = image.get("name") if isinstance(image, dict) else image
if not image:
    sys.exit(f"no image for job {name} in {path}")
image = re.sub(r"\$\{?(\w+)\}?", lambda m: str(variables.get(m[1], m[0])), image)
lines = list(spec.get("before_script") or []) + list(spec.get("script") or [])
if not lines or any(not isinstance(line, str) for line in lines):
    sys.exit(f"job {name} in {path}: no script, or a !reference the gate cannot follow")
print(image)
for key, value in variables.items():
    text = str(value).replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`")
    print(f'export {key}="${{{key}:-{text}}}"')
print("\n".join(lines))
PY_JOB
}

# Runs a CI job as the runner would: its script, under set -e, in its image, on
# a copy of its repository. Only the caches move out of the copy (npm, Trivy,
# Terraform plugins), which speeds up the gate without changing what it checks.
run_job() {
  local ci="$1" job="$2" dir="$3" spec image
  spec="$(job_spec "$ci" "$job")" || return 1
  image="${spec%%$'\n'*}"
  echo "== job $job of ${ci#"$WORK/"*/}, image $image"
  printf '%s\n' "${spec#*$'\n'}" | sed 's/^/   | /'
  "${RUN[@]}" -v "$dir:/builds/project" -w /builds/project -e CI_PROJECT_DIR=/builds/project \
    -v "$CACHE/npm:/tmp/npm" -e npm_config_cache=/tmp/npm \
    -v "$CACHE/trivy:/tmp/trivy" -e TRIVY_CACHE_DIR=/tmp/trivy \
    -v "$CACHE/terraform:/tmp/terraform-plugins" -e TF_PLUGIN_CACHE_DIR=/tmp/terraform-plugins \
    --entrypoint sh "$image" -c "set -e
${spec#*$'\n'}"
}

terraform_in() {
  local dir="$1"
  shift
  "${RUN[@]}" -v "$dir:/work" -w /work -v "$CACHE/terraform:/cache" -e TF_PLUGIN_CACHE_DIR=/cache \
    --entrypoint terraform "$TERRAFORM_IMAGE" "$@"
}

# The checks of the validate job on bootstrap/, which no pipeline runs.
terraform_bootstrap() {
  terraform_in "$WORK/tree/bootstrap" fmt -check -diff &&
    terraform_in "$WORK/tree/bootstrap" init -backend=false -input=false -no-color >/dev/null &&
    terraform_in "$WORK/tree/bootstrap" validate -no-color
}

# Every commit of every branch, the repository mounted read-only, then the
# files not committed yet: a secret already in the history is found, a new
# one is stopped before it gets there. The repository is public on GitHub.
# The files come from a copy of their own: the terraform steps fill
# $WORK/tree with downloaded modules, whose examples hold sample keys.
secrets_in_history() {
  copy_tree "$WORK/secrets" &&
    "${RUN[@]}" -v "$ROOT:/repo:ro" --entrypoint gitleaks "$GITLEAKS_IMAGE" \
      git --no-banner --no-color --redact --verbose --log-opts=--all /repo &&
    "${RUN[@]}" -v "$WORK/secrets:/work:ro" --entrypoint gitleaks "$GITLEAKS_IMAGE" \
      dir --no-banner --no-color --redact --verbose /work
}

# The model of .env, as .env itself is never copied.
compose_config() {
  docker compose --project-directory "$WORK/tree" -f "$WORK/tree/compose.yaml" \
    --env-file "$WORK/tree/.env.example" config --quiet
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
step helm-images-pinned helm_images_pinned
step shellcheck shellcheck_every_script
step hadolint hadolint_every_recipe
step terraform-bootstrap terraform_bootstrap
infra="$WORK/tree/repos/infra"
for job in validate tflint iac-scan; do
  step "$job" run_job "$infra/.gitlab-ci.yml" "$job" "$infra"
done
# dependency-scan first: the job reads a fresh checkout, before npm ci.
for app in "${APPS[@]}"; do
  for job in dependency-scan build test lint dockerfile-lint; do
    step "$job:$app" run_job "$WORK/apps/$app/.gitlab-ci.yml" "$job" "$WORK/apps/$app"
  done
done
step validate-config run_job "$WORK/tree/repos/renovate/.gitlab-ci.yml" validate-config "$WORK/tree/repos/renovate"
step compose-config compose_config
step secrets-in-history secrets_in_history

if [[ "$(repo_state)" != "$before" ]]; then
  printf 'KO  %-34s\n' "nothing-written-in-the-repository"
  failed+=("nothing-written-in-the-repository")
fi

if ((${#failed[@]})); then
  echo "Gate refused: ${failed[*]}" >&2
  exit 1
fi
echo "Gate passed."
