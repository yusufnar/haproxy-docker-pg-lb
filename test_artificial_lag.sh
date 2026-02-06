#!/bin/bash

# =============================================================================
# Test Script: Artificial Replication Lag on Replica2 (Log-Based Detection)
# Creates replication lag by pausing WAL replay and monitors HAProxy logs
# =============================================================================

# Configuration
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"
LAG_DURATION=10  # seconds to keep lag

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Artificial Replication Lag Test (Log-Based) ===${NC}"
echo "Target: replica2"
echo "Lag Duration: ${LAG_DURATION} seconds"
echo ""

function log() {
    echo -e "[$(date +"%H:%M:%S")] $1"
}

# Function to get current lag
get_lag() {
    local replica=$1
    docker exec -e PGPASSWORD=$PGPASSWORD $replica psql -U $DB_USER -d $DB_NAME -t -c \
        "SELECT COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0)::numeric(10,2);" 2>/dev/null | xargs
}

# Function to check replay status
get_replay_status() {
    docker exec -e PGPASSWORD=$PGPASSWORD replica2 psql -U $DB_USER -d $DB_NAME -t -c \
        "SELECT pg_is_wal_replay_paused();" 2>/dev/null | xargs
}

# Function to find a log event after a given timestamp
# Args: $1 = start_time (epoch), $2 = server_name, $3 = event_type (DOWN/UP)
find_haproxy_log_event() {
    local start_time=$1
    local server_name=$2
    local event_type=$3
    local start_iso=$(TZ=UTC date -r $start_time +"%Y-%m-%dT%H:%M:%S")
    
    for attempt in {1..60}; do
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                # Extract timestamp from log (format: 2026-02-06T12:00:00.123456789Z)
                local log_time=$(echo "$line" | awk '{print $1}' | cut -d'.' -f1)
                # Compare timestamps (both in ISO format)
                if [[ "$log_time" > "$start_iso" ]] || [[ "$log_time" == "$start_iso" ]]; then
                    echo "$line"
                    return 0
                fi
            fi
        done < <(docker logs --timestamps haproxy 2>&1 | grep -i "$server_name" | grep "$event_type")
        
        sleep 0.2
    done
    return 1
}

# Step 0: Insert a record to reset lag timestamp
log "${GREEN}[0/6] Inserting initial record to sync all replicas...${NC}"
docker exec -e PGPASSWORD=$PGPASSWORD primary psql -U $DB_USER -d $DB_NAME -c \
    "INSERT INTO ynar (info) VALUES ('Sync record before lag test at $(date)');" > /dev/null 2>&1
log "  Record inserted, waiting 2s for replication..."
sleep 2

# Step 1: Initial lag check
log "${GREEN}[1/6] Initial Lag Check${NC}"
log "  Replica1 lag: $(get_lag replica1) seconds"
log "  Replica2 lag: $(get_lag replica2) seconds"
echo ""

# Step 2: Pause WAL replay on replica2
log "${GREEN}[2/6] Pausing WAL replay on replica2...${NC}"
docker exec -e PGPASSWORD=$PGPASSWORD replica2 psql -U $DB_USER -d $DB_NAME -c \
    "SELECT pg_wal_replay_pause();" > /dev/null 2>&1
PAUSE_TIME=$(date +%s)
PAUSE_ISO=$(TZ=UTC date -r $PAUSE_TIME +"%Y-%m-%dT%H:%M:%S")
log "  WAL replay paused at: $(date -r $PAUSE_TIME +"%H:%M:%S") (UTC: $PAUSE_ISO)"
echo ""

# Step 3: Insert data to primary to create lag
log "${GREEN}[3/6] Inserting test data to primary...${NC}"
for i in {1..5}; do
    docker exec -e PGPASSWORD=$PGPASSWORD primary psql -U $DB_USER -d $DB_NAME -c \
        "INSERT INTO ynar (info) VALUES ('Artificial lag test #$i at $(date)');" > /dev/null 2>&1
    log "  Inserted record $i"
done
echo ""

# Step 4: Wait for HAProxy to detect lag and mark replica2 as DOWN
log "${GREEN}[4/6] Waiting for HAProxy to detect lag (DOWN)...${NC}"
log "  Monitoring HAProxy logs for 'replica2 is DOWN'..."

DOWN_LOG=$(find_haproxy_log_event $PAUSE_TIME "replica2" "is DOWN")
if [[ -n "$DOWN_LOG" ]]; then
    DOWN_TIME=$(date +%s)
    DOWN_DIFF=$((DOWN_TIME - PAUSE_TIME))
    log "${RED}  ✓ replica2 marked DOWN in ~${DOWN_DIFF} seconds${NC}"
    log "  HAProxy log: $(echo $DOWN_LOG | cut -c1-120)..."
else
    log "${RED}  ✗ TIMEOUT: No DOWN log found for replica2${NC}"
fi
echo ""

# Step 5: Keep lag for specified duration then resume
log "${GREEN}[5/6] Keeping lag for ${LAG_DURATION} seconds...${NC}"
ELAPSED=0
while [ $ELAPSED -lt $LAG_DURATION ]; do
    LAG1=$(get_lag replica1)
    LAG2=$(get_lag replica2)
    REMAINING=$((LAG_DURATION - ELAPSED))
    log "  [${ELAPSED}s] Replica1: ${LAG1}s | ${RED}Replica2: ${LAG2}s${NC} | Remaining: ${REMAINING}s"
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
echo ""

# Step 6: Resume WAL replay and wait for UP
log "${GREEN}[6/6] Resuming WAL replay on replica2...${NC}"
docker exec -e PGPASSWORD=$PGPASSWORD replica2 psql -U $DB_USER -d $DB_NAME -c \
    "SELECT pg_wal_replay_resume();" > /dev/null 2>&1
RESUME_TIME=$(date +%s)
RESUME_ISO=$(TZ=UTC date -r $RESUME_TIME +"%Y-%m-%dT%H:%M:%S")
log "  WAL replay resumed at: $(date -r $RESUME_TIME +"%H:%M:%S") (UTC: $RESUME_ISO)"

# Insert a record to trigger immediate sync
docker exec -e PGPASSWORD=$PGPASSWORD primary psql -U $DB_USER -d $DB_NAME -c \
    "INSERT INTO ynar (info) VALUES ('Resume sync at $(date)');" > /dev/null 2>&1
log "  Inserted sync record to primary"

log "  Monitoring HAProxy logs for 'replica2 is UP'..."
UP_LOG=$(find_haproxy_log_event $RESUME_TIME "replica2" "is UP")
if [[ -n "$UP_LOG" ]]; then
    UP_TIME=$(date +%s)
    UP_DIFF=$((UP_TIME - RESUME_TIME))
    log "${GREEN}  ✓ replica2 marked UP in ~${UP_DIFF} seconds${NC}"
    log "  HAProxy log: $(echo $UP_LOG | cut -c1-120)..."
else
    log "${RED}  ✗ TIMEOUT: No UP log found for replica2${NC}"
fi
echo ""

# Final summary
log "${YELLOW}=== Test Summary ===${NC}"
log "  Replica1 lag: $(get_lag replica1) seconds"
log "  Replica2 lag: $(get_lag replica2) seconds"
if [[ -n "$DOWN_LOG" ]]; then
    log "  ${RED}DOWN detected: ~${DOWN_DIFF}s after pause${NC}"
fi
if [[ -n "$UP_LOG" ]]; then
    log "  ${GREEN}UP detected: ~${UP_DIFF}s after resume${NC}"
fi
echo ""
log "${GREEN}=== Test Complete ===${NC}"
