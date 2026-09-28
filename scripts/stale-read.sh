#!/bin/bash
# A stale read, made visible on purpose.
# Local replication lag is usually well under a second, so racing a write
# against a read would be luck. Instead WAL replay on the standby is PAUSED,
# the pause is confirmed, and only then is the demonstration run.
cd "$(dirname "$0")/.."
P() { docker compose exec -T primary psql -U app -d shop -tA -c "$1"; }
R() { docker compose exec -T replica psql -U app -d shop -tA -c "$1"; }
run() { local who=primary; [ "$1" = R ] && who=replica; echo "$who \$ $2"; $1 "$2"; }
P "UPDATE orders SET status = 'PENDING' WHERE id = 1043" >/dev/null; sleep 1
echo "# REPLAY PAUSED TO MAKE THE CONSISTENCY WINDOW VISIBLE"
echo "replica \$ SELECT pg_wal_replay_pause()"; R "SELECT pg_wal_replay_pause()" >/dev/null
until [ "$(R "SELECT pg_get_wal_replay_pause_state()")" = "paused" ]; do sleep 0.1; done
run R "SELECT pg_get_wal_replay_pause_state()"
run P "UPDATE orders SET status = 'PAID' WHERE id = 1043 RETURNING status"
run P "SELECT status FROM orders WHERE id = 1043"
run R "SELECT status FROM orders WHERE id = 1043"
echo "replica \$ SELECT pg_wal_replay_resume()"; R "SELECT pg_wal_replay_resume()" >/dev/null
sleep 1
run R "SELECT status FROM orders WHERE id = 1043"
