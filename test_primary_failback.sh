#!/bin/zsh

# Configuration
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

PRIMARY_IP="192.168.155.2"

echo "--- HAProxy Full Replica Failure & Primary Failback Test ---"
echo "This test kills BOTH replicas and verifies traffic fails over to primary."
echo "Check settings: inter 2s, fall 3, rise 2"
echo "Expected Detection: ~6s (3 * 2s)"
echo "Expected Recovery:  ~4s (2 * 2s)"
echo "--------------------------------------------------------------"

function log() {
    echo "[$(date +"%H:%M:%S")] $1"
}

function get_server() {
    psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -t -c "SELECT inet_server_addr();" -c "connect_timeout=1" 2>/dev/null | xargs
}

function is_primary() {
    # Returns "f" for primary (not in recovery), "t" for replica
    psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -t -c "SELECT pg_is_in_recovery();" -c "connect_timeout=1" 2>/dev/null | xargs
}

log "1. Current status (Normal - should be replicas):"
for i in {1..3}; do
    SERVER=$(get_server)
    RECOVERY=$(is_primary)
    log "  Connected to: $SERVER (is_in_recovery: $RECOVERY)"
done

echo ""
log "2. Killing BOTH replicas..."
docker kill replica1 > /dev/null 2>&1
docker kill replica2 > /dev/null 2>&1
START_TIME=$(date +%s)
log "Replicas killed at: $(date -r $START_TIME +"%H:%M:%S")"

log "Waiting for HAProxy to detect failures and failback to primary..."
while true; do
    CHECK_TIME=$(date +%s)
    CHECK_ELAPSED=$((CHECK_TIME - START_TIME))
    
    SERVER=$(get_server)
    RECOVERY=$(is_primary)
    
    if [[ -n "$SERVER" ]]; then
        log "Connected to: $SERVER (is_in_recovery: $RECOVERY, Elapsed: ${CHECK_ELAPSED}s)"
        
        # Primary returns 'f' (false) for pg_is_in_recovery()
        if [[ "$RECOVERY" == "f" ]]; then
            END_TIME=$(date +%s)
            DIFF=$((END_TIME - START_TIME))
            log "SUCCESS: Failback to PRIMARY in ~${DIFF} seconds."
            break
        fi
    else
        log "No connection available (Elapsed: ${CHECK_ELAPSED}s)"
    fi
    
    if [[ $CHECK_ELAPSED -gt 30 ]]; then
        log "TIMEOUT: Failback did not happen within 30 seconds."
        break
    fi
    
    sleep 1
done

echo ""
log "3. Verifying traffic goes to primary (should see is_in_recovery: f):"
for i in {1..3}; do
    SERVER=$(get_server)
    RECOVERY=$(is_primary)
    log "  Connected to: $SERVER (is_in_recovery: $RECOVERY)"
done

echo ""
log "4. Restoring replicas..."
docker start replica1 > /dev/null 2>&1
docker start replica2 > /dev/null 2>&1
START_TIME=$(date +%s)
log "Replicas started at: $(date -r $START_TIME +"%H:%M:%S")"

log "Waiting for HAProxy to restore replicas..."
while true; do
    CHECK_TIME=$(date +%s)
    CHECK_ELAPSED=$((CHECK_TIME - START_TIME))
    
    SERVER=$(get_server)
    RECOVERY=$(is_primary)
    
    if [[ -n "$SERVER" ]]; then
        log "Connected to: $SERVER (is_in_recovery: $RECOVERY, Elapsed: ${CHECK_ELAPSED}s)"
        
        # Replica returns 't' (true) for pg_is_in_recovery()
        if [[ "$RECOVERY" == "t" ]]; then
            END_TIME=$(date +%s)
            DIFF=$((END_TIME - START_TIME))
            log "SUCCESS: Replicas restored to pool in ~${DIFF} seconds."
            break
        fi
    else
        log "No connection available (Elapsed: ${CHECK_ELAPSED}s)"
    fi
    
    if [[ $CHECK_ELAPSED -gt 60 ]]; then
        log "TIMEOUT: Replica recovery did not happen within 60 seconds."
        break
    fi
    
    sleep 1
done

echo ""
log "--- Test Completed ---"
log "Final status (should be replicas):"
for i in {1..3}; do
    SERVER=$(get_server)
    RECOVERY=$(is_primary)
    log "  Connected to: $SERVER (is_in_recovery: $RECOVERY)"
done
