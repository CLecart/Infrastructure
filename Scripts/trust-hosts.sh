#!/usr/bin/env bash
# Adds the SSH host keys of GitLab and the runner to ~/.ssh/known_hosts, once
# they are proven: the key the server presents (ssh-keyscan) must be the one
# cloud-init printed on the EC2 console of the instance at first boot, which
# only an AWS identity can read. A new address or a rebuilt machine is never
# trusted on first use.
#   Scripts/trust-hosts.sh       right after terraform apply in bootstrap/,
#                                before the Ansible playbook
# cloud-init prints the keys at the first boot only: once a machine has
# rebooted (the common role of Ansible reboots after a kernel update), its
# console no longer holds them and the script stops at once. The console
# output appears a few minutes after the first boot: until then the script
# waits, up to CONSOLE_TIMEOUT seconds (default 600).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
CONSOLE_TIMEOUT="${CONSOLE_TIMEOUT:-600}"

outputs="$(terraform -chdir="$ROOT/bootstrap" output -json)"

console() {
  aws ec2 get-console-output --latest --instance-id "$1" --output text --query Output
}

# The ed25519 host key printed by cloud-init, without its comment.
console_key() {
  sed -n '/BEGIN SSH HOST KEY KEYS/,/END SSH HOST KEY KEYS/p' <<<"$1" |
    awk '$1 == "ssh-ed25519" { print $1, $2; exit }'
}

server_key() {
  ssh-keyscan -T 10 -t ed25519 "$1" 2>/dev/null | awk '$2 == "ssh-ed25519" { print $2, $3; exit }'
}

trust() {
  local name="$1" id address output="" expected presented deadline
  id="$(jq -r ".instance_ids.value.$name" <<<"$outputs")"
  address="$(jq -r ".${name}_public_ip.value" <<<"$outputs")"
  deadline=$((SECONDS + CONSOLE_TIMEOUT))
  until output="$(console "$id")" && expected="$(console_key "$output")" && [[ -n "$expected" ]]; do
    if [[ "$output" == *"Cloud-init v."*"finished at"* ]]; then
      echo "error: cloud-init of $name has finished without printing its host keys: the machine" >&2
      echo "       has rebooted since its first boot; run this script right after the apply" >&2
      return 1
    fi
    if ((SECONDS >= deadline)); then
      echo "error: no host key on the console of $name after ${CONSOLE_TIMEOUT}s" >&2
      return 1
    fi
    sleep 15
  done
  presented="$(server_key "$address")"
  if [[ "$presented" != "$expected" ]]; then
    echo "error: $name presents a host key that is not the one of its console: refused" >&2
    return 1
  fi
  ssh-keygen -R "$address" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
  printf '%s %s\n' "$address" "$expected" >>"$KNOWN_HOSTS"
  echo "$name: host key checked against the EC2 console and trusted"
}

trust gitlab
trust runner
