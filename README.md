# HAProxy PostgreSQL Load Balancer with Custom Health Checking

This project demonstrates a robust high-availability setup for PostgreSQL Read Replicas using HAProxy and a custom Python-based health check service.

## Architecture

The system consists of the following Docker containers:

*   **primary**: The primary PostgreSQL instance (Read/Write).
*   **replica1 & replica2**: Two PostgreSQL read replicas streaming from the primary.
*   **healthcheck**: A custom Python service (using `psycopg2`) that monitors replication lag and sync status of the replicas.
*   **haproxy**: A TCP load balancer that distributes read traffic to healthy replicas. It queries the `healthcheck` service to make routing decisions.

### Why Custom Health Check?
Standard TCP checks only verify if a port is open. This project uses a smart health check (`health_check.py`) that ensures:
1.  The replica is actually a replica (not a split-brain primary).
2.  The replication lag is within acceptable limits (default: <10s).
3.  The replica is fully synchronized with the primary.

## Prerequisites

*   Docker
*   Docker Compose

## Getting Started

1.  **Clone the repository:**
    ```bash
    git clone <repository_url>
    cd haproxy-docker-pg-lb
    ```

2.  **Start the environment:**
    ```bash
    docker-compose up -d --build
    ```
    *This starts the Primary, Replicas, Health Check service, and HAProxy.*

## Configuration

*   **HAProxy Port**: `5434` (Exposed to host)
*   **Primary DB Port**: `5431`
*   **Database Name**: `appdb`
*   **User/Password**: `postgres` / `postgres`

### Key HAProxy Settings (`haproxy.cfg`)
*   **`option redispatch`** & **`retries 3`**: Ensures seamless failover. If a replica fails during a request, HAProxy immediately retries another replica without returning an error to the client.
*   **`http-check expect string OK`**: Forces HAProxy to read the full health check response body, preventing `ConnectionResetError`s.

## Scripts & Testing

### 1. Load Balancing Test (`test_lb.sh`)
Sends multiple queries to HAProxy to verify that traffic is distributed between replicas (Round Robin).
```bash
./test_lb.sh [num_queries]
# Example: ./test_lb.sh 20
```

### 2. Failover Test (`test_failover.sh`)
Simulates a node failure by killing `replica1` and measuring how fast HAProxy detects and removes it from the pool. Also tests recovery time.
```bash
./test_failover.sh
```

### 3. Latency Profiling (`profile_query.sh`)
Executes a query via HAProxy and reports:
*   Which replica handled the request.
*   Total client-side duration.
*   Internal Postgres execution time (`\timing`).
```bash
./profile_query.sh
```

### 4. Replication Lag Test (`test_lag.sh`)
(Optional) Intentionally creates lag on the primary to see if the health check correctly marks replicas as unhealthy.

## Troubleshooting

**View Health Check Logs:**
See detailed decision logs (lag time, sync status) from the custom health checker:
```bash
docker logs -f healthcheck
```

**View HAProxy Logs:**
```bash
docker logs -f haproxy
```
