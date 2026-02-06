#!/bin/bash

# =============================================================================
# Monitor Replication Lag - Real-time monitoring for all replicas
# =============================================================================

# Configuration
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Replication lag query
LAG_QUERY="
WITH stats AS (
    SELECT 
        pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() as is_sync,
        COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0) as lag_s
)
SELECT 
    is_sync,
    ROUND(lag_s::numeric, 2) as lag_s,
    CASE WHEN is_sync THEN 0 ELSE ROUND(lag_s::numeric, 2) END as real_lag_s
FROM stats;
"

# Function to get lag info for a replica
get_lag_info() {
    local replica=$1
    local result=$(docker exec -e PGPASSWORD=$PGPASSWORD $replica psql -U $DB_USER -d $DB_NAME -t -A -F'|' -c "$LAG_QUERY" 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo "ERROR|0|0"
    else
        echo "$result"
    fi
}

# Function to format output with colors
format_output() {
    local replica=$1
    local is_sync=$2
    local lag_s=$3
    local real_lag_s=$4
    
    # Determine color based on real_lag
    local color=$GREEN
    if [ "$is_sync" == "ERROR" ]; then
        color=$RED
        printf "${color}%-10s${NC} | %-8s | %-10s | %-10s\n" "$replica" "ERROR" "-" "-"
        return
    fi
    
    # Convert real_lag_s to integer for comparison
    local lag_int=$(echo "$real_lag_s" | cut -d'.' -f1)
    if [ "$lag_int" -ge 5 ]; then
        color=$RED
    elif [ "$lag_int" -ge 2 ]; then
        color=$YELLOW
    fi
    
    local sync_status="NO"
    if [ "$is_sync" == "t" ]; then
        sync_status="YES"
    fi
    
    printf "${color}%-10s${NC} | %-8s | %-10s | %-10s\n" "$replica" "$sync_status" "${lag_s}s" "${real_lag_s}s"
}

# Clear screen and print header
print_header() {
    clear
    echo -e "${CYAN}=== Replication Lag Monitor ===${NC}"
    echo -e "Refreshing every 1 second. Press Ctrl+C to exit."
    echo ""
    printf "%-10s | %-8s | %-10s | %-10s\n" "REPLICA" "IS_SYNC" "LAG" "REAL_LAG"
    echo "-----------|----------|------------|------------"
}

# Main loop
echo -e "${YELLOW}Starting replication lag monitor...${NC}"
echo ""

while true; do
    print_header
    
    # Get lag info for each replica
    for replica in replica1 replica2 replica3; do
        result=$(get_lag_info $replica)
        
        is_sync=$(echo "$result" | cut -d'|' -f1)
        lag_s=$(echo "$result" | cut -d'|' -f2)
        real_lag_s=$(echo "$result" | cut -d'|' -f3)
        
        format_output "$replica" "$is_sync" "$lag_s" "$real_lag_s"
    done
    
    echo ""
    echo -e "$(date '+%Y-%m-%d %H:%M:%S')"
    
    sleep 1
done
