#!/bin/bash
# A replication role and the hba rule the replica needs to stream from here.
set -e
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<SQL
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replica';
SQL
echo "host replication replicator all scram-sha-256" >> "$PGDATA/pg_hba.conf"
