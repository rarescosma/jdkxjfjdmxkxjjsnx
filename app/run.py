#!/usr/bin/env python3

import http.server
import os
import re
import socketserver
import textwrap
from contextvars import ContextVar
from typing import Pattern

DEFAULT_PORT: int = 8000
SET_ROUTE: Pattern = re.compile(r"/set-response-time/([0-9]+)")
COUNTER_METRIC: str = textwrap.dedent(
    """
    # HELP example_app_cnt Pod counter metric.
    # TYPE example_app_cnt gauge
    example_app_cnt 1
    """
)
RESPONSE_TIME_METRIC: str = textwrap.dedent(
    """
    # HELP http_response_time_ms Fake latency metric.
    # TYPE http_response_time_ms gauge
    http_response_time_ms {response_time}
    """
).strip()
RESPONSE_TIME = ContextVar("response_time", default=None)


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/metrics":
            self._send_text_status(200)
            self.wfile.write(COUNTER_METRIC.encode())
            if (response_time := RESPONSE_TIME.get()) is not None:
                self.wfile.write(RESPONSE_TIME_METRIC.format(response_time=response_time).encode())
            return
        elif (set_route := SET_ROUTE.match(self.path)) is not None:
            self._send_text_status(200)
            RESPONSE_TIME.set(set_route.groups(1)[0])
            self.wfile.write(b"Ok\n")
            return

        self._send_text_status(404)
        self.wfile.write(b"Nope\n")

    def _send_text_status(self, status: int) -> None:
        self.send_response(status)
        self.send_header("Content-type", "text/plain")
        self.end_headers()


def run_server() -> None:
    try:
        port = int(os.getenv("PORT", str(DEFAULT_PORT)))
    except ValueError:
        port = DEFAULT_PORT

    with socketserver.TCPServer(("", port), Handler) as httpd:
        try:
            print(f"Serving at port {port}")
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            httpd.server_close()


if __name__ == "__main__":
    run_server()
