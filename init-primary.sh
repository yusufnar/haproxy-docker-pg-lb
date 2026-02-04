#!/bin/bash
set -e

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER $REPLICATION_USER WITH REPLICATION ENCRYPTED PASSWORD '$REPLICATION_PASSWORD';
EOSQL

# Add replication entry to pg_hba.conf to allow internal network
echo "host replication $REPLICATION_USER all md5" >> "$PGDATA/pg_hba.conf"

# Reload configuration
pg_ctl reload
