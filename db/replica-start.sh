#!/bin/bash
# Clone the primary with pg_basebackup and start as a hot standby.
set -e
export PGDATA=/var/lib/postgresql/data
until pg_isready -h primary -U app; do sleep 1; done
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  rm -rf "$PGDATA"/*
  pg_basebackup -h primary -U replicator -D "$PGDATA" -R -X stream -P
  chown -R postgres:postgres "$PGDATA"
  chmod 700 "$PGDATA"
fi
exec gosu postgres postgres -c hot_standby=on -c shared_buffers=1GB
