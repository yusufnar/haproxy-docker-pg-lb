#!/bin/bash
set -e

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Starting base backup from $PRIMARY_HOST..."
    export PGPASSWORD="$REPLICATION_PASSWORD"
    
    # Use -R to create standby.signal and postgresql.auto.conf
    until pg_basebackup -h "$PRIMARY_HOST" -D "$PGDATA" -U "$REPLICATION_USER" -vP -X stream -R; do
        echo "Waiting for primary to be ready..."
        sleep 2
    done
    echo "Base backup completed. Starting replica..."
fi

exec docker-entrypoint.sh postgres
