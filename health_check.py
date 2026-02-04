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
            
            # Query to get replication lag in seconds
            # If receive and replay LSN match, lag is effectively 0 even if last xact is old
            cur.execute("""
                SELECT 
                    CASE 
                        WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 
                        ELSE EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) 
                    END;
            """)
            lag = cur.fetchone()[0]
            
            if lag is None:
                lag = 0
            
            cur.close()
            conn.close()

            if lag < MAX_LAG_SECONDS:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(f"OK - Host: {target_host}, Lag: {lag:.2f}s".encode())
            else:
                self.send_response(503)
                self.end_headers()
                self.wfile.write(f"Service Unavailable - Host: {target_host}, Lag too high: {lag:.2f}s".encode())

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
