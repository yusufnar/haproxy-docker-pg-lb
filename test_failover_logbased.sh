#!/bin/zsh

# Configuration - same as test_failover.sh
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

# Get IPs dynamically from Docker
REPLICA1_IP=$(docker inspect replica1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
REPLICA2_IP=$(docker inspect replica2 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
PRIMARY_IP=$(docker inspect primary --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

echo "--- HAProxy Failover Test (Log-Based Detection) ---"
echo "This script detects failover by monitoring HAProxy logs"
echo "Node IPs:"
echo "  Primary:  $PRIMARY_IP"
echo "  Replica1: $REPLICA1_IP"
echo "  Replica2: $REPLICA2_IP"
echo "Check settings: inter 1s, fall 2, rise 2"
echo "Expected Detection: ~2s (2 * 1s)"
echo "Expected Recovery:  ~2s (2 * 1s)"
echo "---------------------------------------------------"

function log() {
    echo "[$(date +"%H:%M:%S")] $1"
}

# Function to find a log event after a given timestamp
# Args: $1 = start_time (epoch), $2 = server_name, $3 = event_type (down/up)
function find_haproxy_log_event() {
    local start_time=$1
    local server_name=$2
    local event_type=$3
    local shutdown_iso=$(TZ=UTC date -r $start_time +"%Y-%m-%dT%H:%M:%S")
    
    for attempt in {1..30}; do
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                # Extract timestamp from log (format: 2026-02-06T12:00:00.123456789Z)
                local log_time=$(echo "$line" | awk '{print $1}' | cut -d'.' -f1)
                # Compare timestamps (both in ISO format)
                if [[ "$log_time" > "$shutdown_iso" ]] || [[ "$log_time" == "$shutdown_iso" ]]; then
                    echo "$line"
                    return 0
                fi
            fi
        done < <(docker logs --timestamps haproxy 2>&1 | grep -i "$server_name" | grep -i "$event_type")
        
        sleep 0.2
    done
    return 1
}

log "1. Current status check..."
log "  replica1 is running: $(docker inspect replica1 --format '{{.State.Running}}' 2>/dev/null)"

echo ""
log "2. Killing replica1..."
docker kill replica1 > /dev/null 2>&1
START_TIME=$(date +%s)
SHUTDOWN_ISO=$(TZ=UTC date -r $START_TIME +"%Y-%m-%dT%H:%M:%S")
log "Replica1 killed at: $(date -r $START_TIME +"%H:%M:%S") (UTC: $SHUTDOWN_ISO)"

log "Waiting for HAProxy DOWN log..."
DOWN_LOG=$(find_haproxy_log_event $START_TIME "replica1" "down")
if [[ -n "$DOWN_LOG" ]]; then
    END_TIME=$(date +%s)
    DIFF=$((END_TIME - START_TIME))
    log "SUCCESS: replica1 marked DOWN in ~${DIFF} seconds at $(date +"%H:%M:%S")"
    log "HAProxy log: $DOWN_LOG"
else
    log "TIMEOUT: No DOWN log found for replica1"
fi

echo ""
log "3. Starting replica1..."
docker start replica1 > /dev/null 2>&1
START_TIME=$(date +%s)
STARTUP_ISO=$(TZ=UTC date -r $START_TIME +"%Y-%m-%dT%H:%M:%S")
log "Replica1 started at: $(date -r $START_TIME +"%H:%M:%S") (UTC: $STARTUP_ISO)"

log "Waiting for HAProxy UP log..."
UP_LOG=$(find_haproxy_log_event $START_TIME "replica1" "up")
if [[ -n "$UP_LOG" ]]; then
    END_TIME=$(date +%s)
    DIFF=$((END_TIME - START_TIME))
    log "SUCCESS: replica1 marked UP in ~${DIFF} seconds at $(date +"%H:%M:%S")"
    log "HAProxy log: $UP_LOG"
else
    log "TIMEOUT: No UP log found for replica1"
fi

echo ""
log "--- Test Completed ---"
log "Final status: replica1 is running: $(docker inspect replica1 --format '{{.State.Running}}' 2>/dev/null)"
