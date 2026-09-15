#!/bin/zsh
# Check that this platform still lets us choose the Host header ourselves.
#
# Adium relies on it: when a server hands out upload addresses on a name that does not resolve
# to the machine running the service, the file is sent to the machine we are already talking to
# while the request keeps the server's own name. ejabberd's mod_http_upload picks the handling
# process by exactly that name, so if the header were dropped the detour would fail silently.
set -e
cd "$(dirname "$0")"

PORT=8731
SERVER="${TMPDIR:-/tmp}/adium-hostheader-server.py"

cat > "$SERVER" <<'PY'
import http.server, sys
WANTED = "beispiel.example.org"
class H(http.server.BaseHTTPRequestHandler):
    def do_PUT(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        seen = (self.headers.get("Host") or "").split(":")[0]
        self.send_response(201 if seen == WANTED else 409)
        self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

python3 "$SERVER" $PORT &
SERVER_PID=$!
trap "kill $SERVER_PID 2>/dev/null" EXIT

#Give it a moment to bind before anything knocks
for i in 1 2 3 4 5 6 7 8 9 10; do
	nc -z 127.0.0.1 $PORT 2>/dev/null && break
	sleep 0.2
done

xcrun clang -fobjc-arc -framework Foundation hostheader-test.m -o /tmp/adium-hostheader
/tmp/adium-hostheader $PORT
