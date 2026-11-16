#!/usr/bin/env bash
# Checks the local Docker Compose environment (compose.yaml), once it is up:
#
#   1. the API answers on the loopback interface only
#   2. POST /api/movies/ -> 201, then GET /api/movies/?title= finds it
#   3. POST /api/billing/ -> 200, the order lands in billing-db
#   4. billing-app stopped: the order waits in RabbitMQ, then is stored once
#      billing-app is back
#   5. network isolation, over the 30 ordered pairs of services: a connection
#      opens only between services that share a network, and only for the
#      pairs below, tried on every address of the target, not only through
#      DNS; only api-gateway has a route out of the host
#   6. hardening: no service runs as root, and each one has a read-only root
#      filesystem, no capability and no privilege escalation
#
# Usage: docker compose up -d --build --wait && Scripts/compose-test.sh
# Exits 1 as soon as one check has failed, after running them all.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose --project-directory "$ROOT" -f "$ROOT/compose.yaml")
SERVICES=(api-gateway inventory-app billing-app inventory-db billing-db rabbitmq)
declare -A PORT=([api-gateway]=3000 [inventory-app]=8080 [billing-app]=8080
  [inventory-db]=5432 [billing-db]=5432 [rabbitmq]=5672)
# The pairs that share a network. A network carries both directions: Compose
# cannot filter by direction or port, as a NetworkPolicy does.
SHARED=(api-gateway:inventory-app api-gateway:rabbitmq billing-app:rabbitmq
  inventory-app:inventory-db billing-app:billing-db)
WAIT_TIMEOUT="${WAIT_TIMEOUT:-60}"

failures=0
pass() { printf 'OK  %s\n' "$*"; }
fail() {
  printf 'KO  %s\n' "$*"
  failures=$((failures + 1))
}
check() {
  local label="$1"
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

# Polls a command until it succeeds or WAIT_TIMEOUT runs out.
eventually() {
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  until "$@"; do
    ((SECONDS < deadline)) || return 1
    sleep 2
  done
}

sql() {
  "${COMPOSE[@]}" exec -T "$1" psql -tAc "$2"
}

# TCP connection from a container (busybox nc, in every image).
connects() {
  "${COMPOSE[@]}" exec -T "$1" nc -z -w 2 "$2" "$3" </dev/null >/dev/null 2>&1
}

# network=address, one per network a service is attached to.
attachments() {
  docker inspect -f '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}={{$conf.IPAddress}} {{end}}' \
    "$("${COMPOSE[@]}" ps -q "$1")"
}

shares_network() {
  local pair
  for pair in "${SHARED[@]}"; do
    [[ "$pair" == "$1:$2" || "$pair" == "$2:$1" ]] && return 0
  done
  return 1
}

has_default_route() {
  "${COMPOSE[@]}" exec -T "$1" cat /proc/net/route | awk '$2 == "00000000" { found = 1 } END { exit !found }'
}
has_no_default_route() { ! has_default_route "$1"; }

finds_movie() {
  local body
  body="$(curl -fsS "$URL/api/movies/?title=$1")" && [[ "$body" == *"$1"* ]]
}

for service in "${SERVICES[@]}"; do
  if [[ -z "$("${COMPOSE[@]}" ps -q --status running "$service")" ]]; then
    echo "error: $service is not running (docker compose up -d --build --wait)" >&2
    exit 2
  fi
done
binding="$("${COMPOSE[@]}" port api-gateway 3000)"
URL="http://$binding"
stamp="compose-test-$(date +%s)-$$"

echo "== 1. Entry point"
check "api-gateway published on the loopback only ($binding)" test "${binding%%:*}" = 127.0.0.1
check "GET /health -> 200" curl -fsS -o /dev/null "$URL/health"

echo "== 2. Inventory"
created="$(curl -sS -w '\n%{http_code}' -H 'Content-Type: application/json' \
  -d "{\"title\":\"$stamp\",\"description\":\"compose test\"}" "$URL/api/movies/")"
check "POST /api/movies/ -> 201" test "${created##*$'\n'}" = 201
movie_id="$(printf '%s' "${created%$'\n'*}" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')"
check "GET /api/movies/?title= finds the movie" finds_movie "$stamp"

echo "== 3. Billing"
order_count() { sql billing-db "SELECT count(*) FROM orders WHERE user_id = $1"; }
order_is() { [[ "$(order_count "$1")" == "$2" ]]; }
post_order() {
  curl -fsS -o /dev/null -H 'Content-Type: application/json' \
    -d "{\"user_id\":\"$1\",\"number_of_items\":\"1\",\"total_amount\":\"9.99\"}" "$URL/api/billing/"
}
user="$((900000000 + RANDOM))"
check "POST /api/billing/ -> 200" post_order "$user"
check "the order lands in billing-db" eventually order_is "$user" 1

echo "== 4. Billing while billing-app is down"
queued() { [[ "$("${COMPOSE[@]}" exec -T rabbitmq rabbitmqctl -q list_queues name messages | awk '$1 == "billing_queue" { print $2 }')" == 1 ]]; }
"${COMPOSE[@]}" stop billing-app >/dev/null 2>&1
check "POST /api/billing/ -> 200 with billing-app stopped" post_order "$((user + 1))"
check "the order waits in billing_queue" eventually queued
"${COMPOSE[@]}" start billing-app >/dev/null 2>&1
check "billing-app back: the order is stored" eventually order_is "$((user + 1))" 1

echo "== 5. Network isolation"
for from in "${SERVICES[@]}"; do
  from_networks=" $(attachments "$from") "
  for to in "${SERVICES[@]}"; do
    [[ "$to" != "$from" ]] || continue
    port="${PORT[$to]}"
    if shares_network "$from" "$to"; then
      check "$from -> $to:$port by name: open" connects "$from" "$to" "$port"
    fi
    for attachment in $(attachments "$to"); do
      network="${attachment%%=*}" address="${attachment#*=}" expected=closed
      if shares_network "$from" "$to" && [[ "$from_networks" == *" $network="* ]]; then expected=open; fi
      if connects "$from" "$address" "$port"; then got=open; else got=closed; fi
      check "$from -> $to:$port at $address (${network#movies_}): $expected" test "$got" = "$expected"
    done
  done
done
check "api-gateway has a route out of the host (edge)" has_default_route api-gateway
for service in inventory-app billing-app inventory-db billing-db rabbitmq; do
  check "$service has no route out of the host" has_no_default_route "$service"
done

echo "== 6. Hardening"
for service in "${SERVICES[@]}"; do
  uid="$("${COMPOSE[@]}" exec -T "$service" id -u)"
  check "$service runs as uid $uid, not root" test "$uid" != 0
  # Read from the container settings: a write attempt would also fail on the
  # permissions of /, read-only or not.
  settings="$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}}' \
    "$("${COMPOSE[@]}" ps -q "$service")")"
  check "$service: read-only root, all capabilities dropped, no-new-privileges ($settings)" \
    test "$settings" = "true [ALL] [no-new-privileges:true]"
done

[[ -z "$movie_id" ]] || curl -fsS -o /dev/null -X DELETE "$URL/api/movies/$movie_id" || true
sql billing-db "DELETE FROM orders WHERE user_id IN ($user, $((user + 1)))" >/dev/null || true

if ((failures)); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "All checks passed."
