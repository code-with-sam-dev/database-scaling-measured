#!/bin/bash
# Read-your-writes routing through the Spring app, with replay paused so the
# window is visible. The same order, read twice after the same write: once
# routed to the primary, once allowed to use the replica.
set -e
cd "$(dirname "$0")/.."
JAVA=${JAVA_HOME_25:-$HOME/.sdkman/candidates/java/25.0.4-amzn}/bin/java
JAR=app/target/scaling-0.0.1-SNAPSHOT.jar
P() { docker compose exec -T primary psql -U app -d shop -tA -c "$1"; }
R() { docker compose exec -T replica psql -U app -d shop -tA -c "$1"; }
pkill -f "$JAR" || true; while lsof -ti tcp:8081 >/dev/null; do sleep 0.5; done
PORT=8081 "$JAVA" -jar $JAR > /tmp/scaling-ryw.log 2>&1 &
until curl -s localhost:8081/stats >/dev/null; do sleep 0.5; done
P "UPDATE orders SET status = 'PENDING' WHERE id = 1043" >/dev/null; sleep 1
echo "# REPLAY PAUSED TO MAKE THE CONSISTENCY WINDOW VISIBLE"
R "SELECT pg_wal_replay_pause()" >/dev/null
until [ "$(R "SELECT pg_get_wal_replay_pause_state()")" = "paused" ]; do sleep 0.1; done
echo "\$ curl -X POST localhost:8081/orders/1043/pay"; curl -s -X POST localhost:8081/orders/1043/pay; echo
echo "\$ curl localhost:8081/orders/1043 -H 'X-Read-Your-Writes: true'"; curl -s localhost:8081/orders/1043 -H 'X-Read-Your-Writes: true'; echo
echo "\$ curl localhost:8081/orders/1043"; curl -s localhost:8081/orders/1043; echo
R "SELECT pg_wal_replay_resume()" >/dev/null
pkill -f "$JAR"
