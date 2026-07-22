#!/usr/bin/env python3
"""
Hardware Diagnostics - Support Live Monitoring Server
Runs a lightweight REST API backend and serves the Web Dashboard UI on port 8080.
"""

import os
import json
import time
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import cgi

PORT = int(os.environ.get('PORT', 8080))
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOADS_DIR = os.path.join(SCRIPT_DIR, 'uploads')
os.makedirs(UPLOADS_DIR, exist_ok=True)

# In-memory data store for live monitoring
devices_store = {}
recordings_store = []
total_telemetry_count = 0

class SupportDashboardHandler(BaseHTTPRequestHandler):
    def _set_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')

    def do_OPTIONS(self):
        self.send_response(200)
        self._set_cors_headers()
        self.end_headers()

    def do_GET(self):
        global devices_store, recordings_store, total_telemetry_count

        if self.path == '/' or self.path == '/index.html':
            html_path = os.path.join(SCRIPT_DIR, 'index.html')
            if os.path.exists(html_path):
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self._set_cors_headers()
                self.end_headers()
                with open(html_path, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_error(404, "Dashboard HTML not found")

        elif self.path.startswith('/uploads/'):
            filename = os.path.basename(self.path)
            file_path = os.path.join(UPLOADS_DIR, filename)
            if os.path.exists(file_path):
                self.send_response(200)
                self.send_header('Content-Type', 'video/mp4')
                self._set_cors_headers()
                self.end_headers()
                with open(file_path, 'rb') as f:
                    self.wfile.write(f.read())
            else:
                self.send_error(404, "File not found")

        elif self.path == '/api/v1/support/devices':
            now_ts = time.time()
            devices_list = []
            active_count = 0

            for dev_id, data in devices_store.items():
                last_seen = data.get('last_seen_ts', 0)
                is_online = (now_ts - last_seen) < 15  # Online if pinged in last 15 seconds
                if is_online:
                    active_count += 1

                devices_list.append({
                    'device_id': dev_id,
                    'is_online': is_online,
                    'app_version': data.get('app_version', '1.2.0'),
                    'location': data.get('location', {}),
                    'device_info': data.get('device_info', {}),
                    'last_ping': datetime.fromtimestamp(last_seen).strftime('%H:%M:%S (%Y-%m-%d)'),
                })

            response_data = {
                'total_devices': len(devices_store),
                'active_devices': active_count,
                'total_telemetry': total_telemetry_count,
                'devices': sorted(devices_list, key=lambda x: x['is_online'], reverse=True),
                'recordings': recordings_store,
            }

            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self._set_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps(response_data).encode('utf-8'))

        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        global devices_store, recordings_store, total_telemetry_count

        if self.path in ['/api/v1/support/telemetry', '/api/v1/support/telemetry/live']:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)
            
            try:
                payload = json.loads(body.decode('utf-8'))
                dev_id = payload.get('device_id', 'unknown_device')
                
                payload['last_seen_ts'] = time.time()
                devices_store[dev_id] = payload
                total_telemetry_count += 1

                print(f"[{datetime.now().strftime('%H:%M:%S')}] Telemetry received from: {dev_id} ({payload.get('location', {}).get('address', 'No location')})")

                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"status": "success", "message": "Telemetry received"}).encode('utf-8'))
            except Exception as e:
                self.send_response(400)
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"status": "error", "message": str(e)}).encode('utf-8'))

        elif self.path == '/api/v1/support/recordings':
            try:
                form = cgi.FieldStorage(
                    fp=self.rfile,
                    headers=self.headers,
                    environ={'REQUEST_METHOD': 'POST', 'CONTENT_TYPE': self.headers['Content-Type']}
                )

                dev_id = form.getvalue('device_id', 'unknown_device')
                file_field = form['file'] if 'file' in form else None

                if file_field is not None and file_field.filename:
                    filename = f"rec_{int(time.time())}_{os.path.basename(file_field.filename)}"
                    save_path = os.path.join(UPLOADS_DIR, filename)

                    with open(save_path, 'wb') as f:
                        f.write(file_field.file.read())

                    rec_info = {
                        'filename': filename,
                        'device_id': dev_id,
                        'url': f'/uploads/{filename}',
                        'uploaded_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    }
                    recordings_store.insert(0, rec_info)

                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Screen recording uploaded by: {dev_id} ({filename})")

                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self._set_cors_headers()
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "success", "file_url": rec_info['url']}).encode('utf-8'))
                    return

                self.send_response(400)
                self.end_headers()
            except Exception as e:
                self.send_response(500)
                self._set_cors_headers()
                self.end_headers()
                self.wfile.write(json.dumps({"status": "error", "message": str(e)}).encode('utf-8'))

        else:
            self.send_error(404, "Endpoint Not Found")

def run_server():
    server_address = ('0.0.0.0', PORT)
    httpd = HTTPServer(server_address, SupportDashboardHandler)
    print(f"\n=======================================================")
    print(f" 🚀 Hardware Diagnostics Support Live Server Running")
    print(f" 💻 Laptop Web UI: http://localhost:{PORT}")
    print(f" 📱 Mobile API Endpoint: http://<YOUR_LAPTOP_IP>:{PORT}/api/v1")
    print(f"=======================================================\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server...")
        httpd.server_close()

if __name__ == '__main__':
    run_server()
