import os
import time
import datetime
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
import psycopg2

DB_NAME = os.environ.get('POSTGRES_DB', 'appdb')
DB_USER = os.environ.get('POSTGRES_USER', 'postgres')
DB_PASS = os.environ.get('POSTGRES_PASSWORD', 'postgres')
MAX_LAG_SECONDS = 10

class HealthCheckHandler(BaseHTTPRequestHandler):
    def log_debug(self, message):
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        print(f"[{timestamp}] {message}", flush=True)

    def do_GET(self):
        # Extract target host from path (e.g., /replica1)
        target_host = self.path.strip('/')
        if not target_host or target_host == "":
            target_host = "replica1" # Default to replica1 if no path

        self.log_debug(f"Request started for host: {target_host}")

        try:
            conn = psycopg2.connect(
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASS,
                host=target_host,
                connect_timeout=1
            )
            self.log_debug("Opening cursor...")
            cur = conn.cursor()
            
            # First, check if this is a primary or replica using pg_is_in_recovery()
            # pg_is_in_recovery() returns true for replicas, false for primary
            cur.execute("SELECT pg_is_in_recovery();")
            is_replica = cur.fetchone()[0]
            
            if is_replica:
                # REPLICA CHECK: Check replication lag
                # is_sync: true if received and replayed LSNs match
                # lag_s: time since last transaction replay in seconds (rounded to 2 decimals)
                # real_lag_s: 0 if synced, otherwise actual lag
                cur.execute("""
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
                """)
                row = cur.fetchone()
                is_sync, lag_s, real_lag_s = row
                
                cur.close()
                conn.close()

                # We use real_lag_s for HAProxy health decision
                if real_lag_s < MAX_LAG_SECONDS:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(f"OK - Host: {target_host} (replica), is_sync: {is_sync}, lag: {lag_s}s, real_lag: {real_lag_s}s".encode())
                    self.log_debug(f"Request finished: 200 OK (replica, real_lag: {real_lag_s}s)")
                else:
                    self.send_response(503)
                    self.end_headers()
                    self.wfile.write(f"Service Unavailable - Host: {target_host} (replica), is_sync: {is_sync}, lag: {lag_s}s, real_lag: {real_lag_s}s".encode())
                    self.log_debug(f"Request finished: 503 Service Unavailable (replica, real_lag: {real_lag_s}s)")
            else:
                # PRIMARY CHECK: Just run a simple query to verify connectivity
                # Already successful connection, just return 200 
                
                cur.close()
                conn.close()
                
                self.send_response(200)
                self.end_headers()
                self.wfile.write(f"OK - Host: {target_host} (primary), simple check passed".encode())
                self.log_debug(f"Request finished: 200 OK (primary, simple check)")

        except Exception as e:
            self.send_response(503)
            self.end_headers()
            self.wfile.write(f"Service Unavailable - Host: {target_host}, Error: {str(e)}".encode())
            self.log_debug(f"Request finished: 503 Exception ({str(e)})")

    def log_message(self, format, *args):
        return

def run(server_class=HTTPServer, handler_class=HealthCheckHandler, port=8008):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Starting single-threaded health check server on port {port}...")
    httpd.serve_forever()

if __name__ == "__main__":
    run()
