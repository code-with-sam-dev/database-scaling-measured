#!/bin/bash
# The cache stampede, three ways, same topology every time:
# two application instances, one Redis, the same 500 callers, one expired key.
set -e
cd "$(dirname "$0")/.."
JAVA=${JAVA_HOME_25:-$HOME/.sdkman/candidates/java/25.0.4-amzn}/bin/java
JAR=app/target/scaling-0.0.1-SNAPSHOT.jar
loads() { curl -s localhost:$1/stats | sed -E 's/.*"databaseLoads":([0-9]+).*/\1/'; }
modeof() { curl -s localhost:$1/stats | sed -E 's/.*"mode":"([a-z]+)".*/\1/'; }
free() { while lsof -ti tcp:$1 >/dev/null; do sleep 0.5; done; }
pkill -f "$JAR" || true
for mode in none local redis; do
  free 8081; free 8082
  for p in 8081 8082; do PORT=$p COALESCING=$mode "$JAVA" -jar $JAR > /tmp/scaling-$p.log 2>&1 & done
  for p in 8081 8082; do until curl -s localhost:$p/stats >/dev/null; do sleep 0.5; done; done
  # Warm BOTH instances (JIT, connection pools, Redis client) so neither is
  # slow on its first request, then warm the cache.
  for i in 1 2 3; do for p in 8081 8082; do curl -s localhost:$p/products/42 >/dev/null; curl -s localhost:$p/orders/1 >/dev/null; done; done
  docker compose exec -T redis redis-cli DEL product:42 >/dev/null # the key expires
  for p in 8081 8082; do curl -s -X POST localhost:$p/stats/reset; done
  [ "$(modeof 8081)" = $mode ] && [ "$(modeof 8082)" = $mode ] || { echo "instances not in mode $mode"; exit 1; }
  answered=$("$JAVA" sim/Stampede.java 500 8081 8082)
  a=$(loads 8081); b=$(loads 8082)
  printf "%-6s %s  database loads: %d (instance A %d, instance B %d)\n" "$mode" "$answered" $((a+b)) $a $b
  pkill -f "$JAR"; free 8081; free 8082
done
