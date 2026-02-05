# HAProxy PostgreSQL Load Balancer with Custom Health Checking

This project demonstrates a robust high-availability setup for PostgreSQL Read Replicas using HAProxy and a custom Python-based health check service.

## Architecture

The system consists of the following Docker containers:

*   **primary**: The primary PostgreSQL instance (Read/Write).
*   **replica1 & replica2**: Two PostgreSQL read replicas streaming from the primary.
*   **healthcheck**: A multi-threaded Python service that monitors replication lag and sync status.
*   **haproxy**: A TCP load balancer that distributes read traffic to healthy replicas.

### Key Features
- **Smart Health Checks**: Verifies replication lag, sync status, and distinguishes primary from replicas.
- **Primary Failback**: When ALL replicas are down, traffic automatically fails over to the primary.
- **Multi-threaded Health Check**: Parallel health checks prevent one slow/dead replica from blocking others.
- **Kubernetes Ready**: Includes K8s manifests for migration to Kubernetes with external RDS support.

## Prerequisites

*   Docker & Docker Compose
*   (Optional) Kubernetes cluster for K8s deployment

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

## Configuration

| Setting | Value |
|---------|-------|
| HAProxy Port | `5434` |
| Primary DB Port | `5431` |
| Database Name | `appdb` |
| User/Password | `postgres` / `postgres` |

### Key HAProxy Settings (`haproxy.cfg`)
*   **`option redispatch` & `retries 3`**: Seamless failover during detection window.
*   **`backup` on primary**: Traffic goes to primary only when all replicas are down.
*   **`inter 3s fall 2 rise 2`**: Health check interval and thresholds.

## Scripts & Testing

| Script | Description |
|--------|-------------|
| `./test_lb.sh [n]` | Load balancing test - verifies round-robin distribution |
| `./test_failover.sh` | Single replica failure & recovery test |
| `./test_primary_failback.sh` | Both replicas down → failback to primary |
| `./monitor_haproxy.sh` | Continuous monitoring (Ctrl+C to stop) |
| `./profile_query.sh` | Query latency profiling |
| `./test_lag.sh` | Replication lag simulation test |

## Kubernetes Deployment

Kubernetes manifests are in the `k8s/` directory for migrating HAProxy and Healthcheck to K8s with external RDS databases.

```bash
# Build and push healthcheck image
./build_healthcheck.sh <your-registry>

# Update k8s/external-services.yaml with RDS endpoints
# Update k8s/secrets.yaml with credentials

# Deploy
kubectl apply -f k8s/
```

See `k8s/` directory for:
- `configmaps.yaml` - HAProxy configuration
- `secrets.yaml` - Database credentials
- `external-services.yaml` - RDS endpoint mappings
- `healthcheck.yaml` - Health check service deployment
- `haproxy.yaml` - HAProxy deployment

## Troubleshooting

**View Health Check Logs:**
```bash
docker logs -f healthcheck
```

**View HAProxy Logs:**
```bash
docker logs -f haproxy
```

**Check Container IPs:**
```bash
docker inspect replica1 --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
```
