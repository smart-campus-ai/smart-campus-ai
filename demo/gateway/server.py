"""Local demo gateway: a tiny HTTP server that drives the REAL Lambda handlers.

Purpose: a faithful local demo without AWS. HTTP requests are mapped to the actual
handlers in ``services/<fn>/app.py`` (tickets, chat, kpi). Each service is loaded
in an isolated module namespace (the services share flat module names like
``service``/``rest``/``errors``), wired to shared in-memory fakes so demo data
persists for the life of the process. Auth is a non-crypto demo bearer
``demo.<role>.<sub>`` turned into the ``requestContext.authorizer.claims`` the
handlers expect.

Python stdlib only — this is a demo aid, never shipped to AWS (prod = API Gateway
+ Cognito authorizer).
"""

from __future__ import annotations

import importlib
import importlib.util
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

SERVICES_DIR = os.environ.get("SERVICES_DIR", "/app/services")
# Flat module names the services define; cleared between isolated loads.
_FLAT = ("app", "service", "domain", "ports", "adapters", "errors", "auth", "rest", "mapping", "ulid")


def _load_isolated(fn: str):
    """Import ``services/<fn>/app.py`` and its siblings in isolation.

    Returns the loaded ``app`` module. The service dir is placed first on
    sys.path and the shared flat module names are cleared before/after so a
    later service does not reuse an earlier one's modules.
    """
    svc_dir = os.path.join(SERVICES_DIR, fn)
    for name in _FLAT:
        sys.modules.pop(name, None)
    sys.path.insert(0, svc_dir)
    try:
        spec = importlib.util.spec_from_file_location("app", os.path.join(svc_dir, "app.py"))
        app = importlib.util.module_from_spec(spec)
        sys.modules["app"] = app
        spec.loader.exec_module(app)  # type: ignore[union-attr]
        # Capture the service's own modules while they are the active flat ones.
        captured = {name: sys.modules.get(name) for name in _FLAT if name in sys.modules}
        return app, captured
    finally:
        sys.path.remove(svc_dir)
        for name in _FLAT:
            sys.modules.pop(name, None)


def _call(app, captured, event):
    """Invoke a service handler with its own flat modules active (re-entrant)."""
    saved = {name: sys.modules.get(name) for name in captured}
    sys.modules.update(captured)
    try:
        return app.handler(event, None)
    finally:
        for name in captured:
            if saved.get(name) is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = saved[name]


# ---------------------------------------------------------------------------

class Gateway:
    def __init__(self) -> None:
        self.services = {}
        for fn in ("tickets", "chat", "kpi"):
            app, captured = _load_isolated(fn)
            self.services[fn] = (app, captured)

        # Build shared services + seed, using each service's captured modules.
        import demo_wiring
        demo_wiring.wire_and_seed(self.services)

    def handle(self, root: str, event: dict) -> dict:
        app, captured = self.services[root]
        return _call(app, captured, event)


def _claims_from_auth(header):
    if not header or not header.lower().startswith("bearer "):
        return {}
    parts = header.split(" ", 1)[1].strip().split(".")
    if len(parts) != 3 or parts[0] != "demo":
        return {}
    role, sub = parts[1], parts[2]
    return {"sub": sub, "cognito:groups": "admin" if role == "admin" else "student",
            "email": f"{sub}@esiea.fr"}


def _resource_for(segs):
    if segs[:1] == ["tickets"]:
        if len(segs) == 1:
            return "/tickets", None
        if len(segs) == 2:
            return "/tickets/{ticketId}", {"ticketId": segs[1]}
        if len(segs) == 3 and segs[2] == "attachments":
            return "/tickets/{ticketId}/attachments", {"ticketId": segs[1]}
    if segs[:1] == ["chat"]:
        if segs[1:] == ["messages"]:
            return "/chat/messages", None
        if segs[1:] == ["sessions"]:
            return "/chat/sessions", None
        if len(segs) == 4 and segs[1] == "sessions" and segs[3] == "ticket-draft":
            return "/chat/sessions/{sessionId}/ticket-draft", {"sessionId": segs[2]}
        if len(segs) == 3 and segs[1] == "sessions":
            return "/chat/sessions/{sessionId}", {"sessionId": segs[2]}
    if segs[:1] == ["kpi"]:
        return "/kpi", None
    return "/" + "/".join(segs), None


GATEWAY: Gateway | None = None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _dispatch(self, method):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length).decode("utf-8") if length else None

        segs = [s for s in parsed.path.split("/") if s]
        if segs and segs[0] == "api":
            segs = segs[1:]
        root = segs[0] if segs else ""

        if root == "healthz":
            return self._send(200, {"status": "ok"}, {})
        if root not in ("tickets", "chat", "kpi"):
            return self._send(404, {"code": "not_found", "message": "Unknown route."}, {})

        resource, path_params = _resource_for(segs)
        event = {
            "httpMethod": method, "resource": resource, "path": parsed.path,
            "pathParameters": path_params,
            "queryStringParameters": {k: v[0] for k, v in query.items()} or None,
            "requestContext": {"authorizer": {"claims": _claims_from_auth(self.headers.get("Authorization"))}},
            "body": body, "isBase64Encoded": False,
        }
        try:
            resp = GATEWAY.handle(root, event)
        except Exception as exc:  # noqa: BLE001
            return self._send(500, {"code": "internal_error", "message": str(exc)}, {})

        self._send(resp.get("statusCode", 200), None, resp.get("headers") or {}, resp.get("body") or "")

    def _send(self, status, payload, headers, raw=None):
        body = raw if raw is not None else json.dumps(payload)
        data = body.encode("utf-8")
        self.send_response(status)
        sent_ct = False
        for k, v in headers.items():
            self.send_header(k, v)
            if k.lower() == "content-type":
                sent_ct = True
        if not sent_ct:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if data:
            self.wfile.write(data)

    def do_GET(self): self._dispatch("GET")
    def do_POST(self): self._dispatch("POST")
    def do_PATCH(self): self._dispatch("PATCH")
    def do_DELETE(self): self._dispatch("DELETE")

    def log_message(self, fmt, *args):
        sys.stderr.write("[gateway] " + (fmt % args) + "\n")


def main():
    global GATEWAY
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    GATEWAY = Gateway()
    port = int(os.environ.get("PORT", "8080"))
    sys.stderr.write(f"[gateway] listening on :{port}\n")
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
