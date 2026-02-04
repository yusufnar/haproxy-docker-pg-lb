#!/bin/zsh

# Configuration
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

REPLICA1_IP="192.168.155.4"

echo "--- HAProxy Failover & Recovery Test ---"
echo "Check settings: inter 2s, fall 3, rise 2"
echo "Expected Detection: ~6s (3 * 2s)"
echo "Expected Recovery:  ~4s (2 * 2s)"
echo "---------------------------------------"

function get_server() {
    psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -t -c "SELECT inet_server_addr();" 2>/dev/null | xargs
}

echo "1. Current status (Normal):"
for i in {1..3}; do
    echo "  Connected to: $(get_server)"
done

echo "\n2. Stopping replica1..."
docker stop replica1 > /dev/null
START_TIME=$(date +%s)

echo "Waiting for HAProxy to detect failure..."
while true; do
    CURRENT_SERVER=$(get_server)
    if [[ "$CURRENT_SERVER" != "$REPLICA1_IP" ]]; then
        END_TIME=$(date +%s)
        DIFF=$((END_TIME - START_TIME))
        echo "SUCCESS: replica1 removed from pool in ~${DIFF} seconds."
        break
    fi
    echo -n "."
    sleep 1
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
    sleep 1
done

echo "\n--- Test Completed ---"
for i in {1..3}; do
    echo "  Connected to: $(get_server)"
done
