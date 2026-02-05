#!/bin/zsh

# Configuration
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"

echo "--- HAProxy Connection Monitor ---"
echo "Press Ctrl+C to stop"
echo "----------------------------------"

function get_server_info() {
    psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -t -c \
        "SELECT inet_server_addr(), pg_is_in_recovery();" 2>/dev/null | xargs
}

while true; do
    TIMESTAMP=$(date +"%H:%M:%S.%3N")
    RESULT=$(get_server_info)
    
    if [[ -n "$RESULT" ]]; then
        IP=$(echo $RESULT | awk -F'|' '{print $1}' | xargs)
        IS_REPLICA=$(echo $RESULT | awk -F'|' '{print $2}' | xargs)
        
        if [[ "$IS_REPLICA" == "t" ]]; then
            NODE_TYPE="REPLICA"
        else
            NODE_TYPE="PRIMARY"
        fi
        
        echo "[$TIMESTAMP] Connected to: $IP ($NODE_TYPE)"
    else
        echo "[$TIMESTAMP] Connection FAILED"
    fi
    
    sleep 1
done
