#!/bin/bash
# The write bill: 100,000 rows into a 1,000,000 row table with 0, 1 and 3
# secondary indexes. Rolled back each run so every run starts from the same table.
cd "$(dirname "$0")/.."
P() { docker compose exec -T primary psql -U app -d shop "$@"; }
P -q -f - < sql/02-insert-bill.sql >/dev/null 2>&1
ins="INSERT INTO orders_w SELECT id + 20000000, customer_id, status, created_at, amount_cents FROM orders WHERE id BETWEEN 5000001 AND 5100000"
run() { P -tA -c "BEGIN" -c "EXPLAIN (ANALYZE, TIMING OFF) $ins" -c "ROLLBACK" | awk '/Execution Time/{print $3}'; }
out=captures/02-insert-bill.txt
echo "100,000 rows inserted into a 1,000,000 row table, one statement, 7 runs, median (this machine)" > $out
for level in 0 1 3; do
  P -q -c "DROP INDEX IF EXISTS w_a, w_b, w_c" 2>/dev/null
  [ $level -ge 1 ] && P -q -c "CREATE INDEX w_a ON orders_w (customer_id, status, created_at)"
  [ $level -ge 3 ] && P -q -c "CREATE INDEX w_b ON orders_w (created_at)" -c "CREATE INDEX w_c ON orders_w (status)"
  P -q -c "VACUUM ANALYZE orders_w"
  run >/dev/null; run >/dev/null
  med=$(for i in 1 2 3 4 5 6 7; do run; P -q -c "VACUUM orders_w"; done | sort -n | awk '{a[NR]=$1} END{print a[4]}')
  printf "%d secondary indexes: median %8.1f ms  = %7.0f rows/s\n" $level $med $(echo "100000/($med/1000)" | bc -l) | tee -a $out
done
