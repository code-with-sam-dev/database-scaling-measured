#!/bin/bash
# Two copies of one value. A write that bypasses the cache leaves Redis stale
# until the TTL; a write that invalidates makes the next read reload.
set -e
cd "$(dirname "$0")/.."
JAVA=${JAVA_HOME_25:-$HOME/.sdkman/candidates/java/25.0.4-amzn}/bin/java
JAR=app/target/scaling-0.0.1-SNAPSHOT.jar
P() { docker compose exec -T primary psql -U app -d shop -tA -c "$1"; }
pkill -f "$JAR" || true; while lsof -ti tcp:8081 >/dev/null; do sleep 0.5; done
PORT=8081 "$JAVA" -jar $JAR > /tmp/scaling-inv.log 2>&1 &
until curl -s localhost:8081/stats >/dev/null; do sleep 0.5; done
P "UPDATE products SET price_cents = 12900 WHERE id = 42" >/dev/null
docker compose exec -T redis redis-cli DEL product:42 >/dev/null
say() { echo "\$ $1"; eval "$1"; echo; }
say "curl -s localhost:8081/products/42"
echo "# a write straight to Postgres, the cache is not told"
echo "\$ psql -c \"UPDATE products SET price_cents = 9900 WHERE id = 42\""; P "UPDATE products SET price_cents = 9900 WHERE id = 42" >/dev/null
say "curl -s localhost:8081/products/42"
echo "# the same change through the app: write Postgres, then delete the cache entry"
say "curl -s -X PUT localhost:8081/products/42/price/8900"
say "curl -s localhost:8081/products/42"
pkill -f "$JAR"
