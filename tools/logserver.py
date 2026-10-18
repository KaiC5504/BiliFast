# /// script
# requires-python = ">=3.12"
# dependencies = ["zeroconf"]
# ///
"""Receives BiliFast's dev logs over Wi-Fi and writes them to logs/<date>/<session>.jsonl.

Also serves the speed test plan at GET /plan (the --plan file, read again for every request), so the phone's
next 开始测试 runs whatever the file says now, without a new build.
"""
import argparse
import datetime as dt
import json
import pathlib
import socket
import socketserver
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The Swift app's service type: the phone browses exactly this one.
SERVICE_TYPE = "_bilinative-log._tcp.local."
DEFAULT_PLAN = ROOT / "tools" / "speedtest_plan.json"
COLORS = {"debug": "\033[90m", "info": "\033[0m", "warn": "\033[33m", "error": "\033[31m"}
RESET = "\033[0m"
SESSION_MAX = 64


def lan_addresses():
    addresses = set()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            # connect() on UDP sends nothing; it only picks the outbound interface.
            probe.connect(("192.0.2.1", 9))
            addresses.add(probe.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    return sorted(a for a in addresses if not a.startswith("127."))


def stamp_of(t):
    if isinstance(t, bool) or not isinstance(t, (int, float)):
        t = 0
    try:
        return dt.datetime.fromtimestamp(t).strftime("%H:%M:%S.%f")[:-3]
    except (OverflowError, OSError, ValueError):
        return "--:--:--.---"


def summarize(event):
    level = str(event.get("level", "info"))
    fields = event.get("f")
    if isinstance(fields, dict):
        fields = " ".join(f"{key}={value}" for key, value in sorted(fields.items()))
    else:
        fields = ""
    return f"{COLORS.get(level, '')}{stamp_of(event.get('t'))} {level:<5} {str(event.get('cat', '?')):<6} {event.get('msg', '')} {fields}{RESET}"


def parse_line(line):
    try:
        event = json.loads(line)
    except (ValueError, RecursionError):
        event = None
    if isinstance(event, dict):
        return event
    return {"level": "warn", "cat": "logserver", "msg": "unparsable line", "f": {"line": line[:200]}}


class LogStore:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.lock = threading.Lock()

    def append(self, events):
        day = dt.date.today().isoformat()
        with self.lock:
            for event in events:
                session = "".join(c for c in str(event.get("session", "unknown")) if c.isalnum())[:SESSION_MAX] or "unknown"
                folder = self.root / day
                try:
                    folder.mkdir(parents=True, exist_ok=True)
                    with open(folder / f"{session}.jsonl", "a", encoding="utf-8") as handle:
                        handle.write(json.dumps(event, ensure_ascii=False) + "\n")
                except OSError as error:
                    print(f"logserver: write failed: {type(error).__name__}", file=sys.stderr)


def make_handler(store, quiet, plan):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                self._reply(200, b"ok")
            elif self.path == "/plan":
                self._plan()
            else:
                self._reply(404, b"not found")

        def _plan(self):
            try:
                body = pathlib.Path(plan).read_bytes()
            except OSError:
                self._say(f"plan asked for by {self.client_address[0]}: no {plan}, the phone uses its built-in plan")
                self._reply(404, b"no plan")
                return
            self._say(f"plan sent to {self.client_address[0]}: {pathlib.Path(plan).name} ({len(body)} bytes)")
            self._reply(200, body, "application/json")

        def _say(self, text):
            if quiet:
                return
            try:
                print(f"{dt.datetime.now():%H:%M:%S} {text}", flush=True)
            except (UnicodeError, OSError, ValueError):
                pass

        def do_POST(self):
            if self.path != "/logs":
                self._reply(404, b"not found")
                return
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            # NetworkSink writes one JSON object per "\n"; str.splitlines would also break on U+2028, U+2029 and U+0085, which JSON leaves unescaped.
            events = [parse_line(line.strip()) for line in body.split("\n") if line.strip()]
            try:
                store.append(events)
            except Exception as error:
                print(f"logserver: store failed: {type(error).__name__}", file=sys.stderr)
            if not quiet:
                for event in events:
                    # The file is the record; a console that cannot show a line must not cost the reply.
                    try:
                        print(summarize(event), flush=True)
                    except (UnicodeError, OSError, ValueError):
                        pass
            self._reply(200, b"ok")

        def _reply(self, status, body, content_type="text/plain"):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    return Handler


class Server(ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer looks up this host's FQDN here, which takes a second or more on Windows; nothing uses it.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def make_server(port, root, quiet=False, plan=DEFAULT_PLAN):
    return Server(("0.0.0.0", port), make_handler(LogStore(root), quiet, plan))


def advertise(port):
    from zeroconf import ServiceInfo, Zeroconf

    zeroconf = Zeroconf()
    addresses = [socket.inet_aton(address) for address in lan_addresses()]
    name = f"BiliFast log on {socket.gethostname()}.{SERVICE_TYPE}"
    info = ServiceInfo(SERVICE_TYPE, name, addresses=addresses, port=port, properties={"path": "/logs"})
    zeroconf.register_service(info)
    return zeroconf, info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=47321)
    parser.add_argument("--plan", type=pathlib.Path, default=DEFAULT_PLAN,
                        help="speed test plan served at GET /plan (default: tools/speedtest_plan.json)")
    parser.add_argument("--no-bonjour", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    # Windows consoles default to cp1252 when stdout is redirected, which cannot encode the Chinese UI text.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    server = make_server(args.port, ROOT / "logs", args.quiet, args.plan)
    print(f"Writing to {ROOT / 'logs'}")
    print(f"Speed test plan: {args.plan}{'' if args.plan.exists() else ' (missing: the phone uses its built-in plan)'}")
    for address in lan_addresses():
        print(f"Phone: enter {address}:{args.port}")
    zeroconf = None
    if not args.no_bonjour:
        zeroconf, info = advertise(args.port)
        print("Advertised over Bonjour as", info.name)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if zeroconf:
            zeroconf.unregister_all_services()
            zeroconf.close()
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
