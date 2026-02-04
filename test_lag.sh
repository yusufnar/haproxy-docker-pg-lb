#!/bin/bash

# Configuration
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

get_lag() {
    local replica=$1
    echo -n "Lag for $replica: "
    docker exec -e PGPASSWORD=$PGPASSWORD $replica psql -U $DB_USER -d $DB_NAME -t -c "SELECT COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0);" | xargs
}

echo "--- Initial Lag Check ---"
get_lag replica1
get_lag replica2

echo ""
echo "--- Inserting 1 record into primary ---"
docker exec -e PGPASSWORD=$PGPASSWORD primary psql -U $DB_USER -d $DB_NAME -c "INSERT INTO ynar (info) VALUES ('Test lag record at $(date)');"

echo ""
echo "--- Post-Insert Lag Check ---"
get_lag replica1
get_lag replica2

echo ""
echo "--- Verifying record count across nodes (waiting 2s for sync) ---"
sleep 2
echo -n "Primary count:  " && docker exec -e PGPASSWORD=$PGPASSWORD primary psql -U $DB_USER -d $DB_NAME -t -c "SELECT count(*) FROM ynar;" | xargs
echo -n "Replica1 count: " && docker exec -e PGPASSWORD=$PGPASSWORD replica1 psql -U $DB_USER -d $DB_NAME -t -c "SELECT count(*) FROM ynar;" | xargs
echo -n "Replica2 count: " && docker exec -e PGPASSWORD=$PGPASSWORD replica2 psql -U $DB_USER -d $DB_NAME -t -c "SELECT count(*) FROM ynar;" | xargs
