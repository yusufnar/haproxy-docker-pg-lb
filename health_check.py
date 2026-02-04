import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
import psycopg2

DB_NAME = os.environ.get('POSTGRES_DB', 'appdb')
DB_USER = os.environ.get('POSTGRES_USER', 'postgres')
DB_PASS = os.environ.get('POSTGRES_PASSWORD', 'postgres')
MAX_LAG_SECONDS = 10

class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Extract target host from path (e.g., /replica1)
        target_host = self.path.strip('/')
        if not target_host or target_host == "":
            target_host = "replica1" # Default to replica1 if no path

        try:
            conn = psycopg2.connect(
                dbname=DB_NAME,
                user=DB_USER,
                password=DB_PASS,
                host=target_host,
                connect_timeout=3
            )
            cur = conn.cursor()
            
            cur = conn.cursor()
            
            # All replication logic is handled in SQL:
            # is_sync: true if received and replayed LSNs match
            # lag_s: time since last transaction replay in seconds (rounded to 1 decimal)
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
                self.wfile.write(f"OK - Host: {target_host}, is_sync: {is_sync}, lag: {lag_s}s, real_lag: {real_lag_s}s".encode())
            else:
                self.send_response(503)
                self.end_headers()
                self.wfile.write(f"Service Unavailable - Host: {target_host}, is_sync: {is_sync}, lag: {lag_s}s, real_lag: {real_lag_s}s".encode())

        except Exception as e:
            self.send_response(503)
            self.end_headers()
            self.wfile.write(f"Service Unavailable - Host: {target_host}, Error: {str(e)}".encode())

    def log_message(self, format, *args):
        return

def run(server_class=HTTPServer, handler_class=HealthCheckHandler, port=8008):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f"Starting centralized health check server on port {port}...")
    httpd.serve_forever()

if __name__ == "__main__":
    run()
