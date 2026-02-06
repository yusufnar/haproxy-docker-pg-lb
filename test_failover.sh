#!/bin/zsh

# Configuration
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

# Get IPs dynamically from Docker
REPLICA1_IP=$(docker inspect replica1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
REPLICA2_IP=$(docker inspect replica2 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
PRIMARY_IP=$(docker inspect primary --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

echo "--- HAProxy Failover & Recovery Test ---"
echo "Node IPs:"
echo "  Primary:  $PRIMARY_IP"
echo "  Replica1: $REPLICA1_IP"
echo "  Replica2: $REPLICA2_IP"
echo "Check settings: inter 1s, fall 2, rise 2"
echo "Expected Detection: ~2s (2 * 1s)"
echo "Expected Recovery:  ~2s (2 * 1s)"
echo "-----------------------------------------"

function log() {
    echo "[$(date +"%H:%M:%S")] $1"
}

function get_server() {
    # Added connect_timeout to psql to prevent long waits during the check loop
    psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -t -c "SELECT inet_server_addr();" -c "connect_timeout=1" 2>/dev/null | xargs
}

log "1. Current status (Normal):"
for i in {1..3}; do
    log "  Connected to: $(get_server)"
done

echo ""
log "2. Killing replica1..."
docker kill replica1 > /dev/null
START_TIME=$(date +%s)
log "Replica1 killed at: $(date -r $START_TIME +"%H:%M:%S")"

log "Waiting for HAProxy to detect failure..."
while true; do
    # each connection takes around 1 second
    # so even if all connections go to replica2
    # the whole loop will take around 4 seconds
    FOUND_STILL_UP=0
    for j in {1..4}; do
        CHECK_TIME=$(date +%s)
        CHECK_ELAPSED=$((CHECK_TIME - START_TIME))
        SERVER=$(get_server)
        if [[ -n "$SERVER" ]]; then
            log "Connected to: $SERVER (Elapsed: ${CHECK_ELAPSED}s) at $(date +'%H:%M:%S')"
            if [[ "$SERVER" == "$REPLICA1_IP" ]]; then
                FOUND_STILL_UP=1
                log "replica1 still in pool at $(date +'%H:%M:%S')"
                break
            fi
        fi
        sleep 0.1       
    done

    CUR_TIME=$(date +%s)
    ELAPSED=$((CUR_TIME - START_TIME))

    if [[ $FOUND_STILL_UP -eq 0 ]]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        log "SUCCESS: replica1 removed from pool in ~${DIFF} seconds at $(date +"%H:%M:%S")."
        
        # Check HAProxy logs for the actual DOWN event (after shutdown time)
        echo ""
        log "Checking HAProxy logs for DOWN event..."
        # Convert to UTC for comparison with Docker logs (which use UTC)
        SHUTDOWN_ISO=$(TZ=UTC date -r $START_TIME +"%Y-%m-%dT%H:%M:%S")
        log "Looking for DOWN events after: $SHUTDOWN_ISO (UTC)"
        
        FOUND_DOWN_LOG=0
        for attempt in {1..10}; do
            # Get all DOWN logs for replica1
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    # Extract timestamp from log (format: 2026-02-06T12:00:00.123456789Z)
                    LOG_TIME=$(echo "$line" | awk '{print $1}' | cut -d'.' -f1)
                    # log "Found log with timestamp: $LOG_TIME"
                    # Compare timestamps (both in ISO format)
                    if [[ "$LOG_TIME" > "$SHUTDOWN_ISO" ]] || [[ "$LOG_TIME" == "$SHUTDOWN_ISO" ]]; then
                        log "HAProxy DOWN log: $line"
                        FOUND_DOWN_LOG=1
                        break 2
                    else
                        # log "Skipping old log: LOG_TIME=$LOG_TIME < SHUTDOWN_ISO=$SHUTDOWN_ISO"
                    fi
                fi
            done < <(docker logs --timestamps haproxy 2>&1 | grep -i "replica1" | grep -i "down")
            
            log "Waiting for DOWN log... (attempt $attempt)"
            sleep 0.5
        done
        
        if [[ $FOUND_DOWN_LOG -eq 0 ]]; then
            log "No DOWN log found for replica1 after shutdown time"
        fi
        break
    fi
    log "Still seeing replica1 at ${ELAPSED}s. ($(date +'%H:%M:%S'))"
    sleep 0.5
done

echo ""
log "3. Starting replica1..."
docker start replica1 > /dev/null
START_TIME=$(date +%s)
log "Replica1 started at: $(date -r $START_TIME +"%H:%M:%S")"

log "Waiting for HAProxy to restore replica1..."
while true; do
    FOUND=0
    for i in {1..5}; do
        SERVER=$(get_server)
        if [[ "$SERVER" == "$REPLICA1_IP" ]]; then
            FOUND=1
            break
        fi
    done

    if [[ $FOUND -eq 1 ]]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        log "SUCCESS: replica1 restored to pool in ~${DIFF} seconds at $(date +"%H:%M:%S")."
        break
    fi
    log "Still waiting for replica1... ($(($(date +%s) - START_TIME))s)"
    sleep 0.5
done

echo ""
log "--- Test Completed ---"
for i in {1..3}; do
    log "  Connected to: $(get_server)"
done
