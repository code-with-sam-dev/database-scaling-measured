#!/bin/bash
# Rerun every measurement in the video, from an empty stack, and write the
# transcripts to captures/. Needs Docker, JDK 25 and about 12 GB for Docker.
#   scripts/verify.sh
set -e
cd "$(dirname "$0")/.."
JAVA_HOME=${JAVA_HOME_25:-$HOME/.sdkman/candidates/java/25.0.4-amzn}; export JAVA_HOME
P() { docker compose exec -T primary psql -U app -d shop "$@"; }
Q="SELECT id, amount_cents, created_at FROM orders WHERE customer_id = 424242 AND status = 'PENDING' ORDER BY created_at DESC LIMIT 20"

docker compose down -v >/dev/null 2>&1 || true
docker compose up -d --wait primary redis >/dev/null
docker compose up -d replica >/dev/null
until docker compose exec -T replica pg_isready -U app >/dev/null 2>&1; do sleep 1; done

echo "== 1. ten million orders, no index"
P -q -f - < sql/00-load.sql >/dev/null 2>&1
{ echo "\$ EXPLAIN (ANALYZE, BUFFERS) $Q;"; P -c "EXPLAIN (ANALYZE, BUFFERS) $Q"; } > captures/01-plan-no-index.txt
scripts/median.sh primary "$Q" | tee captures/01-median-no-index.txt

echo "== 2. the index, wrong and right column order"
for spec in "created_at, status, customer_id" "customer_id, status, created_at"; do
  name=$( [ "${spec%%,*}" = "customer_id" ] && echo right || echo wrong )
  P -q -c "DROP INDEX IF EXISTS orders_idx" -c "CREATE INDEX orders_idx ON orders ($spec)" -c "ANALYZE orders"
  { echo "\$ CREATE INDEX orders_idx ON orders ($spec);"; P -c "EXPLAIN (ANALYZE, BUFFERS) $Q"; } > captures/02-plan-$name-order.txt
  echo -n "$name order: "; scripts/median.sh primary "$Q" | tee captures/02-median-$name-order.txt
done
scripts/insert-bill.sh

echo "== 3. the replica"
scripts/natural-lag.sh | tee captures/03-natural-lag.txt
scripts/stale-read.sh | tee captures/03-stale-read.txt
( cd app && ./mvnw -q -DskipTests package )
docker compose exec -T primary psql -U app -d shop -q -c "DROP TABLE IF EXISTS products; CREATE TABLE products (id int PRIMARY KEY, name text, price_cents int); INSERT INTO products VALUES (42, 'Mechanical keyboard', 12900);"
scripts/read-your-writes.sh | tee captures/03-read-your-writes.txt

echo "== 4. the cache stampede"
scripts/stampede.sh | tee captures/04-stampede.txt
scripts/invalidation.sh | tee captures/04-invalidation.txt

echo "== 5. partitions"
P -q -f - < sql/05-partition.sql >/dev/null 2>&1
for n in with-key:"SELECT count(*) FROM orders_p WHERE created_at >= '2026-09-01' AND created_at < '2026-10-01' AND customer_id = 424242" without-key:"SELECT count(*) FROM orders_p WHERE customer_id = 424242"; do
  k=${n%%:*}; q=${n#*:}
  { echo "\$ EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) $q;"; P -c "EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF) $q"; } > captures/05-plan-$k.txt
  echo "$k: partitions scanned $(grep -c 'on orders_p_2026' captures/05-plan-$k.txt)"
done

{ echo -n "with partition key: "; scripts/median.sh primary "SELECT count(*) FROM orders_p WHERE created_at >= '2026-09-01' AND created_at < '2026-10-01' AND customer_id = 424242"; echo -n "without partition key: "; scripts/median.sh primary "SELECT count(*) FROM orders_p WHERE customer_id = 424242"; } | tee captures/05-medians.txt
scripts/drop-vs-delete.sh | tee captures/05-drop-vs-delete.txt

echo "== 6. resharding"
"$JAVA_HOME/bin/java" sim/Resharding.java | tee captures/06-resharding.txt
echo "VERIFIED: transcripts in captures/"
