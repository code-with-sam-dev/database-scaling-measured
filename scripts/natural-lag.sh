#!/bin/bash
# Replay lag on the standby, sampled from pg_stat_replication: idle, then while
# a 2,000,000 row update runs on the primary.
cd "$(dirname "$0")/.."
P() { docker compose exec -T primary psql -U app -d shop "$@"; }
echo "replay lag on the standby, sampled from pg_stat_replication (this machine)"
echo "idle: $(P -tAc "select coalesce(replay_lag::text,'0') from pg_stat_replication")"
( P -q -c "UPDATE orders SET amount_cents = amount_cents + 1 WHERE id <= 2000000" ) &
max=0; for i in $(seq 1 40); do l=$(P -tAc "select coalesce(extract(epoch from replay_lag)*1000,0)::int from pg_stat_replication"); [ "$l" -gt "$max" ] && max=$l; sleep 0.25; done; wait
echo "during a 2,000,000 row update: max sampled replay lag ${max} ms"
