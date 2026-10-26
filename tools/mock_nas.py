"""Bounded local DSM stub used only to verify login and Keychain persistence."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import json
import threading

PORT = 18765

class Handler(BaseHTTPRequestHandler):
    def reply(self, payload):
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        query = parse_qs(urlparse(self.path).query)
        if query.get("api") == ["SYNO.API.Info"]:
            self.reply({"success": True, "data": {"SYNO.API.Auth": {"path": "auth.cgi", "minVersion": 1, "maxVersion": 6}}})
        else:
            self.reply({"success": False, "error": {"code": 101}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        form = parse_qs(self.rfile.read(length).decode())
        api = form.get("api", [""])[0]
        if api == "SYNO.API.Auth":
            self.reply({"success": True, "data": {"sid": "keychain-smoke-session", "did": "keychain-smoke-device"}})
        elif api == "SYNO.NoteStation.Notebook":
            self.reply({"success": True, "data": {"notebooks": [
                {"object_id": "smoke-book", "title": "个人笔记本", "item_count": 1},
                {"object_id": "dragon-diary", "title": "甲辰龙年日记", "item_count": 23, "shared": True, "owned": False}
            ]}})
        elif api == "SYNO.NoteStation.Note":
            if form.get("perm_from") == ["smart"]:
                notes = [{
                    "object_id": f"shared-{index}", "title": f"共享验证笔记 {index}",
                    "content": "<p>仅用于共享笔记合并验证</p>", "brief": "共享验证",
                    "parent_id": "dragon-diary", "ctime": 1793000000, "mtime": 1793000000 + index,
                    "ver": 1, "recycle": False, "encrypt": False
                } for index in range(1, 24)]
            else:
                notes = [{
                    "object_id": "owned-1", "title": "个人验证笔记", "content": "<p>个人笔记</p>",
                    "parent_id": "smoke-book", "ctime": 1793000000, "mtime": 1793000000,
                    "ver": 1, "recycle": False, "encrypt": False
                }]
            self.reply({"success": True, "data": {"notes": notes, "total": len(notes)}})
        elif api == "SYNO.NoteStation.Tag":
            self.reply({"success": True, "data": {"tags": [], "total": 0}})
        else:
            self.reply({"success": False, "error": {"code": 101}})

    def log_message(self, *_):
        pass

server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
threading.Timer(120, server.shutdown).start()
server.serve_forever()
server.server_close()
