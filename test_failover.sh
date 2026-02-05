#!/bin/zsh

# Configuration
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

# Get replica1 IP dynamically from Docker
REPLICA1_IP=$(docker inspect replica1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)

echo "--- HAProxy Failover & Recovery Test ---"
echo "Check settings: inter 2s, fall 3, rise 2"
echo "Expected Detection: ~6s (3 * 2s)"
echo "Expected Recovery:  ~4s (2 * 2s)"
echo "---------------------------------------"

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
    FOUND_STILL_UP=0
    for j in {1..5}; do
        CHECK_TIME=$(date +%s)
        CHECK_ELAPSED=$((CHECK_TIME - START_TIME))
        SERVER=$(get_server)
        if [[ -n "$SERVER" ]]; then
            log "Connected to: $SERVER (Elapsed: ${CHECK_ELAPSED}s)"
            if [[ "$SERVER" == "$REPLICA1_IP" ]]; then
                FOUND_STILL_UP=1
                break
            fi
        fi
        sleep 0.5
    done

    CUR_TIME=$(date +%s)
    ELAPSED=$((CUR_TIME - START_TIME))

    if [[ $FOUND_STILL_UP -eq 0 ]]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        log "SUCCESS: replica1 removed from pool in ~${DIFF} seconds."
        break
    fi
    log "Still seeing replica1 at ${ELAPSED}s."
    sleep 1
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
        log "SUCCESS: replica1 restored to pool in ~${DIFF} seconds."
        break
    fi
    log "Still waiting for replica1... ($(($(date +%s) - START_TIME))s)"
    sleep 1
done

echo ""
log "--- Test Completed ---"
for i in {1..3}; do
    log "  Connected to: $(get_server)"
done
