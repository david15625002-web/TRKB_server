#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Validate the TRKB schema against a throwaway PostgreSQL cluster.
#
#  These are behavioural tests, not a style check. They exist because three real
#  bugs were found by running them:
#    * a subquery inside a CHECK constraint (rejected by Postgres outright)
#    * profiles.is_super_admin was self-writable  -> privilege escalation
#    * the H-1 reminder fired at 08:00 WIB instead of 18:00 (timestamp vs
#      timestamptz double conversion)
#
#  Requires: postgresql-16 (or later) client + server binaries. No Supabase
#  account needed — 00-supabase-shim.sql stubs auth.uid() and the realtime
#  publication.
#
#  Usage:  ./db/tests/run.sh
# ---------------------------------------------------------------------------
set -euo pipefail

PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
WORK=${WORK:-/var/tmp/trkb-pgtest}
PORT=${PORT:-5455}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$HERE/.."

export PATH="$PGBIN:$PATH"

cleanup() { pg_ctl -D "$WORK/data" stop -m immediate >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> provisioning a throwaway cluster in $WORK"
rm -rf "$WORK"; mkdir -p "$WORK"
initdb -D "$WORK/data" --auth=trust >/dev/null
pg_ctl -D "$WORK/data" -l "$WORK/log" -o "-p $PORT -k $WORK" start >/dev/null
sleep 1

PSQL="psql -h $WORK -p $PORT -d trkb -v ON_ERROR_STOP=1 -q"
psql -h "$WORK" -p "$PORT" -d postgres -c 'create database trkb;' >/dev/null

echo "==> applying shim + schema + policies + seed"
for f in "$HERE/00-supabase-shim.sql" "$DB/schema.sql" "$DB/policies.sql" "$DB/seed.sql"; do
  printf '    %-24s' "$(basename "$f")"
  if $PSQL -f "$f" >"$WORK/$(basename "$f").out" 2>&1; then
    echo "ok"
  else
    echo "FAILED"; tail -20 "$WORK/$(basename "$f").out"; exit 1
  fi
done

echo "==> running behavioural tests"
FAILED=0
for f in "$HERE"/0[123]-*.sql; do
  echo "--- $(basename "$f") ---"
  psql -h "$WORK" -p "$PORT" -d trkb -f "$f" 2>&1 \
    | grep -Ev '^(SET|RESET|GRANT|INSERT|UPDATE|DELETE|DO|Pager)' || true
done

# Any NOTICE containing FAIL means a behavioural assertion did not hold.
for f in "$HERE"/0[123]-*.sql; do
  if psql -h "$WORK" -p "$PORT" -d trkb -f "$f" 2>&1 | grep -q 'FAIL'; then
    echo "!! assertion failure in $(basename "$f")"; FAILED=1
  fi
done

echo
if [ "$FAILED" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "THERE WERE FAILURES"; exit 1; fi
