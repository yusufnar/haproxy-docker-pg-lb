#!/bin/zsh

# Configuration
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"

# Replica IPs (detected from docker inspect) - Adjust if necessary
REPLICA1_IP="192.168.155.4"
REPLICA2_IP="192.168.155.3"

echo "--- Profiling Query via HAProxy ($HAPROXY_HOST:$HAPROXY_PORT) ---"

# Start time (nanoseconds)
START_TIME=$(date +%s%N)

# Execute query: Get Server IP and Current Timestamp from DB
# We use \\timing to get the internal execution time
# We drop -t to ensure timing footer is printed, but use -A (unaligned) for easier parsing
OUTPUT=$(psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -A -c "\\timing" -c "SELECT inet_server_addr();" 2>&1)

# End time (nanoseconds)
END_TIME=$(date +%s%N)

# Calculate duration in milliseconds (Total Client-Side)
DURATION_NS=$((END_TIME - START_TIME))
DURATION_MS=$((DURATION_NS / 1000000.0))

# Parse Output
# Output matches:
# Timing is on.
# inet_server_addr
# 192.168.155.3
# (1 row)
# Time: 0.287 ms

# Extract IP (valid IPv4)
SERVER_IP=$(echo "$OUTPUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

# Extract DB Time
DB_TIME=$(echo "$OUTPUT" | grep "Time:" | awk '{print $2 " " $3}')

# Map IP to Name
if [[ "$SERVER_IP" == "$REPLICA1_IP" ]]; then
    SERVER_NAME="replica1"
elif [[ "$SERVER_IP" == "$REPLICA2_IP" ]]; then
    SERVER_NAME="replica2"
else
    SERVER_NAME="UNKNOWN ($SERVER_IP)"
fi

echo "Connected to Node : $SERVER_NAME ($SERVER_IP)"
echo "Total Duration    : ${DURATION_MS} ms (Client + HAProxy + DB)"
echo "DB Execution Time : ${DB_TIME}"
echo "------------------------------------------------"
