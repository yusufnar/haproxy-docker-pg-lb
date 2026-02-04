#!/bin/zsh

# Configuration
DB_NAME="appdb"
DB_USER="postgres"
export PGPASSWORD="postgres"
HAPROXY_HOST="localhost"
HAPROXY_PORT="5434"

# Replica IPs (detected from docker inspect)
REPLICA1_IP="192.168.155.4"
REPLICA2_IP="192.168.155.3"

# Number of queries from argument or default to 10
NUM_QUERIES=${1:-10}

typeset -A counts
counts[replica1]=0
counts[replica2]=0

echo "--- Sending $NUM_QUERIES queries via HAProxy on port $HAPROXY_PORT ---"
echo "Mapping IPs: $REPLICA1_IP -> replica1, $REPLICA2_IP -> replica2"
echo ""

for i in {1..$NUM_QUERIES}
do
    # Get the server IP address that handled the request
    SERVER_IP=$(psql -h $HAPROXY_HOST -p $HAPROXY_PORT -U $DB_USER -d $DB_NAME -t -c "SELECT inet_server_addr();" 2>/dev/null | xargs)
    
    if [[ "$SERVER_IP" == "$REPLICA1_IP" ]]; then
        SERVER_NAME="replica1"
    elif [[ "$SERVER_IP" == "$REPLICA2_IP" ]]; then
        SERVER_NAME="replica2"
    else
        SERVER_NAME="unknown ($SERVER_IP)"
    fi
    
    echo "Query $i: Handled by $SERVER_NAME"
    if [[ -n "$SERVER_NAME" && "$SERVER_NAME" != "unknown ()" ]]; then
        ((counts[$SERVER_NAME]++))
    fi
done

echo ""
echo "--- Summary of Query Distribution ---"
for name in "${(k)counts[@]}"
do
  echo "$name: ${counts[$name]} queries"
done
