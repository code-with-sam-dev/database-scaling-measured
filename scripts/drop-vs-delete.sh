#!/bin/bash
# Removing one month of orders: DELETE the rows, against DROP the partition.
# Each runs inside a transaction that is rolled back, so both start from the
# same table. Three runs each, median.
cd "$(dirname "$0")/.."
t() { docker compose exec -T primary psql -U app -d shop -q -c '\timing on' -c 'BEGIN' -c "$1" -c 'ROLLBACK' | awk '/^Time:/{n++} n==2 && /^Time:/{print $2; exit}'; }
count=$(docker compose exec -T primary psql -U app -d shop -tAc "SELECT count(*) FROM orders_p_2026_09")
echo "one month of orders: $count rows (this machine, median of 3)"
d=$(for i in 1 2 3; do t "DELETE FROM orders_p WHERE created_at >= '2026-09-01' AND created_at < '2026-10-01'"; done | sort -n | sed -n 2p)
p=$(for i in 1 2 3; do t "DROP TABLE orders_p_2026_09"; done | sort -n | sed -n 2p)
echo "DELETE the month's rows : ${d} ms"
echo "DROP the month's partition: ${p} ms"
