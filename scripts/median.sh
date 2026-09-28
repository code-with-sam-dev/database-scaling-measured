#!/bin/bash
# Median execution time of a query, from EXPLAIN ANALYZE, after warm-up runs.
#   scripts/median.sh <host: primary|replica> "<sql>" [runs=9]
# Measured on this machine. Comparative, not a benchmark for your production.
host=$1; sql=$2; runs=${3:-9}
cd "$(dirname "$0")/.."
q() { docker compose exec -T "$host" psql -U app -d shop -tA -c "EXPLAIN (ANALYZE, TIMING OFF) $sql" | awk '/Execution Time/{print $3}'; }
q >/dev/null; q >/dev/null                      # warm-up
for i in $(seq "$runs"); do q; done | sort -n | awk '{a[NR]=$1} END{printf "median %.2f ms (min %.2f, max %.2f, %d runs)\n", a[int((NR+1)/2)], a[1], a[NR], NR}'
