#!/usr/bin/env python3
"""
Hardware Diagnostics - Support Live Monitoring Server
Runs a lightweight REST API backend and serves the Web Dashboard UI.
Compatible with Python 3.8+ through Python 3.14+ (no cgi dependency).
"""

import os
import json
import time
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler

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

        elif self.path in ['/api/v1/support/devices', '/support/devices']:
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

        if self.path in ['/api/v1/support/telemetry', '/api/v1/support/telemetry/live', '/support/telemetry']:
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

        elif self.path in ['/api/v1/support/recordings', '/support/recordings']:
            try:
                content_length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(content_length)
                
                content_type = self.headers.get('Content-Type', '')
                boundary = None
                for param in content_type.split(';'):
                    if 'boundary=' in param:
                        boundary = param.split('boundary=')[1].strip().strip('"').encode('utf-8')
                        break
                
                dev_id = 'unknown_device'
                filename = f"rec_{int(time.time())}.mp4"
                file_data = b''
                
                if boundary:
                    parts = body.split(b'--' + boundary)
                    for part in parts:
                        if b'Content-Disposition' in part:
                            headers_part, _, data_part = part.partition(b'\r\n\r\n')
                            data_part = data_part.rstrip(b'\r\n--')
                            headers_str = headers_part.decode('utf-8', errors='ignore')
                            
                            if 'name="device_id"' in headers_str:
                                dev_id = data_part.decode('utf-8', errors='ignore').strip()
                            elif 'name="file"' in headers_str:
                                if 'filename="' in headers_str:
                                    fn = headers_str.split('filename="')[1].split('"')[0]
                                    if fn:
                                        filename = f"rec_{int(time.time())}_{os.path.basename(fn)}"
                                file_data = data_part

                if file_data:
                    save_path = os.path.join(UPLOADS_DIR, filename)
                    with open(save_path, 'wb') as f:
                        f.write(file_data)

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
    print(f" 💻 Port: {PORT}")
    print(f"=======================================================\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server...")
        httpd.server_close()

if __name__ == '__main__':
    run_server()
