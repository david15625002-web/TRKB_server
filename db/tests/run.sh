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

cleanup() { $AS_PG "export PATH='$PGBIN:\$PATH'; pg_ctl -D '$WORK/data' stop -m immediate" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# initdb and postgres refuse to run as root. When invoked as root (containers,
# CI images) re-exec the cluster commands as the `postgres` system user.
if [ "$(id -u)" -eq 0 ]; then
  if ! id -u postgres >/dev/null 2>&1; then
    echo "running as root and no 'postgres' user exists - run this as a normal user" >&2
    exit 1
  fi
  AS_PG="su postgres -c"
  echo "==> running as root; cluster commands will run as the postgres user"
else
  AS_PG="bash -c"
fi
run_pg() { $AS_PG "export PATH='$PGBIN:\$PATH'; $1"; }

echo "==> provisioning a throwaway cluster in $WORK"
rm -rf "$WORK"; mkdir -p "$WORK"
[ "$(id -u)" -eq 0 ] && chown -R postgres "$WORK"
run_pg "initdb -D '$WORK/data' --auth=trust" >/dev/null
run_pg "pg_ctl -D '$WORK/data' -l '$WORK/log' -o '-p $PORT -k $WORK' start" >/dev/null
sleep 1

run_pg "psql -h '$WORK' -p $PORT -d postgres -c 'create database trkb;'" >/dev/null

echo "==> applying shim + schema + policies + seed"
for f in "$HERE/00-supabase-shim.sql" "$DB/schema.sql" "$DB/policies.sql" "$DB/seed.sql"; do
  printf '    %-24s' "$(basename "$f")"
  cp "$f" "$WORK/"; [ "$(id -u)" -eq 0 ] && chown postgres "$WORK/$(basename "$f")"
  if run_pg "psql -h '$WORK' -p $PORT -d trkb -v ON_ERROR_STOP=1 -q -f '$WORK/$(basename "$f")'" \
       >"$WORK/$(basename "$f").out" 2>&1; then
    echo "ok"
  else
    echo "FAILED"; tail -20 "$WORK/$(basename "$f").out"; exit 1
  fi
done

echo "==> running behavioural tests"
FAILED=0
for f in "$HERE"/0[123]-*.sql; do
  echo "--- $(basename "$f") ---"
  cp "$f" "$WORK/"; [ "$(id -u)" -eq 0 ] && chown postgres "$WORK/$(basename "$f")"
  run_pg "psql -h '$WORK' -p $PORT -d trkb -f '$WORK/$(basename "$f")'" \
    >"$WORK/$(basename "$f").run" 2>&1 || true
  grep -Ev '^(SET|RESET|GRANT|INSERT|UPDATE|DELETE|DO|Pager)' "$WORK/$(basename "$f").run" || true
  grep -c 'ERROR' "$WORK/$(basename "$f").run" | grep -qv '^0$' && { echo "!! SQL ERROR in $(basename "$f")"; FAILED=1; } || true
done

# Any NOTICE containing FAIL means a behavioural assertion did not hold.
for f in "$HERE"/0[123]-*.sql; do
  if grep -q 'FAIL' "$WORK/$(basename "$f").run" 2>/dev/null; then
    echo "!! assertion failure in $(basename "$f")"; FAILED=1
  fi
done

echo
if [ "$FAILED" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "THERE WERE FAILURES"; exit 1; fi
