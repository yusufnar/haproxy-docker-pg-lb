#!/bin/zsh

# Configuration
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

REPLICA1_IP="192.168.155.4"

echo "--- HAProxy Failover & Recovery Test ---"
echo "Check settings: inter 1s, fall 3, rise 2"
echo "Expected Detection: ~3s (3 * 1s)"
echo "Expected Recovery:  ~2s (2 * 1s)"
echo "---------------------------------------"

function get_server() {
    # Added core connect_timeout to psql itself to prevent hanging
    psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -t -c "SELECT inet_server_addr();" -c "connect_timeout=1" 2>/dev/null | xargs
}

echo "1. Current status (Normal):"
for i in {1..3}; do
    echo "  Connected to: $(get_server)"
done

echo "\n2. Killing replica1..."
docker kill replica1 > /dev/null
START_TIME=$(date +%s)

echo "Waiting for HAProxy to detect failure..."
while true; do
    LOOP_START=$(date +%s)
    FOUND_STILL_UP=0
    for j in {1..10}; do
        CURRENT_SERVER=$(get_server)
        if [[ "$CURRENT_SERVER" == "$REPLICA1_IP" ]]; then
            FOUND_STILL_UP=1
            break
        fi
    done

    if [[ $FOUND_STILL_UP -eq 0 ]]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        echo "SUCCESS: replica1 removed from pool in ~${DIFF} seconds."
        break
    fi
    CUR_TIME=$(date +%s)
    ELAPSED=$((CUR_TIME - START_TIME))
    echo -n "($ELAPSED s)"
    sleep 0.1
done

echo "\n3. Starting replica1..."
docker start replica1 > /dev/null
START_TIME=$(date +%s)

echo "Waiting for HAProxy to restore replica1..."
while true; do
    # Since it is weighted (5:1), server might not be replica1 every time.
    # We check multiple times to see if replica1 appears.
    FOUND=0
    for i in {1..5}; do
        CURRENT_SERVER=$(get_server)
        if [[ "$CURRENT_SERVER" == "$REPLICA1_IP" ]]; then
            FOUND=1
            break
        fi
    done

    if [[ $FOUND -eq 1 ]]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        echo "SUCCESS: replica1 restored to pool in ~${DIFF} seconds."
        break
    fi
    echo -n "."
    sleep 0.1
done

echo "\n--- Test Completed ---"
for i in {1..3}; do
    echo "  Connected to: $(get_server)"
done
