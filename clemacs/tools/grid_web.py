#!/usr/bin/env python3

import argparse
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


HTML = r"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>clemacs grid viewer</title>
    <style>
      :root {
        color-scheme: dark;
        --bg: #0b0f14;
        --panel: #111826;
        --fg: #d6deeb;
        --muted: #93a4c7;
        --cursor-bg: #cce6ff;
        --cursor-fg: #0b0f14;
        --border: #1e2a3d;
      }
      body {
        margin: 0;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas,
          "Liberation Mono", "Courier New", monospace;
        background: var(--bg);
        color: var(--fg);
      }
      header {
        display: flex;
        gap: 16px;
        align-items: baseline;
        padding: 12px 16px;
        background: var(--panel);
        border-bottom: 1px solid var(--border);
      }
      header .title {
        font-weight: 600;
      }
      header .meta {
        color: var(--muted);
        font-size: 12px;
      }
      main {
        padding: 12px 16px;
      }
      #grid {
        white-space: pre;
        line-height: 1.2;
        font-size: 13px;
        tab-size: 8;
        margin: 0;
      }
      .cursor {
        background: var(--cursor-bg);
        color: var(--cursor-fg);
      }
    </style>
  </head>
  <body>
    <header>
      <div class="title">clemacs grid viewer</div>
      <div class="meta" id="meta">waiting for events…</div>
    </header>
    <main>
      <pre id="grid"></pre>
    </main>
    <script>
      function clamp(n, lo, hi) {
        return Math.max(lo, Math.min(hi, n));
      }

      function padRight(s, n) {
        if (s.length >= n) return s.slice(0, n);
        return s + " ".repeat(n - s.length);
      }

      let rows = 0;
      let cols = 0;
      let cursorRow = 1;
      let cursorCol = 1;
      let grid = [];

      function ensureSize(r, c) {
        if (r > 0) rows = r;
        if (c > 0) cols = c;
        if (rows <= 0 || cols <= 0) return;
        while (grid.length < rows) grid.push("");
        if (grid.length > rows) grid = grid.slice(0, rows);
      }

      function clearAll() {
        if (rows <= 0) return;
        grid = Array.from({ length: rows }, () => "");
      }

      function putRow(row1, text) {
        if (rows <= 0) return;
        const idx = clamp(row1, 1, rows) - 1;
        grid[idx] = String(text ?? "");
      }

      function clearEol(row1, col1) {
        if (rows <= 0) return;
        const r = clamp(row1, 1, rows) - 1;
        const c0 = Math.max(0, (col1 ?? 1) - 1);
        const s = grid[r] ?? "";
        grid[r] = s.slice(0, c0);
      }

      function scrollRegion(from1, to1, n) {
        if (rows <= 0) return;
        const from = clamp(from1, 1, rows) - 1;
        const to = clamp(to1, 1, rows) - 1;
        if (from > to || !Number.isInteger(n) || n === 0) return;
        const region = grid.slice(from, to + 1);
        const h = region.length;
        let out = Array.from({ length: h }, () => "");
        for (let i = 0; i < h; i++) {
          const j = i - n;
          if (j >= 0 && j < h) out[i] = region[j];
        }
        for (let i = 0; i < h; i++) grid[from + i] = out[i];
      }

      function applyOps(ops) {
        for (const op of ops) {
          switch (op.op) {
            case "clear":
              clearAll();
              break;
            case "put-row":
              putRow(op.row, op.text);
              break;
            case "clear-eol":
              clearEol(op.row, op.col);
              break;
            case "scroll":
              scrollRegion(op.from, op.to, op.n);
              break;
            case "set-cursor":
              cursorRow = op.row ?? cursorRow;
              cursorCol = op.col ?? cursorCol;
              break;
          }
        }
      }

      function render() {
        ensureSize(rows, cols);
        const pre = document.getElementById("grid");
        while (pre.firstChild) pre.removeChild(pre.firstChild);

        const r0 = clamp(cursorRow, 1, Math.max(1, rows));
        const c0 = clamp(cursorCol, 1, Math.max(1, cols));
        const cursorIdx = c0 - 1;

        for (let i = 0; i < rows; i++) {
          const rowNum = i + 1;
          const s = padRight(grid[i] ?? "", cols);

          if (rowNum === r0) {
            pre.appendChild(document.createTextNode(s.slice(0, cursorIdx)));
            const span = document.createElement("span");
            span.className = "cursor";
            span.textContent = s.slice(cursorIdx, cursorIdx + 1);
            pre.appendChild(span);
            pre.appendChild(document.createTextNode(s.slice(cursorIdx + 1)));
          } else {
            pre.appendChild(document.createTextNode(s));
          }

          if (i < rows - 1) pre.appendChild(document.createTextNode("\n"));
        }
      }

      const meta = document.getElementById("meta");
      const source = new EventSource("/events");
      source.onmessage = (ev) => {
        const msg = JSON.parse(ev.data);
        ensureSize(msg.rows, msg.cols);
        cursorRow = msg.cursor_row ?? cursorRow;
        cursorCol = msg.cursor_col ?? cursorCol;
        applyOps(msg.ops ?? []);
        meta.textContent = `rows=${rows} cols=${cols} cursor=${cursorRow},${cursorCol} ops=${(msg.ops ?? []).length}`;
        render();
      };
      source.onerror = () => {
        meta.textContent = "disconnected (retrying)";
      };
    </script>
  </body>
</html>
"""


def tail_lines(path: str, start_at_end: bool):
  # Wait for the file to appear.
  while True:
    try:
      f = open(path, "r", encoding="utf-8", errors="replace")
      break
    except FileNotFoundError:
      time.sleep(0.05)

  with f:
    if start_at_end:
      f.seek(0, os.SEEK_END)
    while True:
      line = f.readline()
      if not line:
        time.sleep(0.02)
        continue
      yield line.rstrip("\n")


class Handler(BaseHTTPRequestHandler):
  server_version = "clemacs-grid-web/0"

  def do_GET(self):
    url = urlparse(self.path)
    if url.path == "/":
      body = HTML.encode("utf-8")
      self.send_response(200)
      self.send_header("Content-Type", "text/html; charset=utf-8")
      self.send_header("Content-Length", str(len(body)))
      self.end_headers()
      self.wfile.write(body)
      return

    if url.path == "/events":
      qs = parse_qs(url.query)
      start = qs.get("start", ["end"])[0]
      start_at_end = start != "beginning"
      path = self.server.grid_path  # type: ignore[attr-defined]

      self.send_response(200)
      self.send_header("Content-Type", "text/event-stream")
      self.send_header("Cache-Control", "no-cache")
      self.send_header("Connection", "keep-alive")
      self.end_headers()

      last_ping = 0.0
      try:
        for line in tail_lines(path, start_at_end=start_at_end):
          now = time.time()
          if now - last_ping > 10:
            self.wfile.write(b": ping\n\n")
            last_ping = now
          self.wfile.write(b"data: ")
          self.wfile.write(line.encode("utf-8", errors="replace"))
          self.wfile.write(b"\n\n")
          self.wfile.flush()
      except (BrokenPipeError, ConnectionResetError):
        return
      return

    self.send_response(404)
    self.send_header("Content-Type", "text/plain; charset=utf-8")
    self.end_headers()
    self.wfile.write(b"not found\n")

  def log_message(self, fmt, *args):
    # Keep server quiet; the viewer is usually run alongside clemacs.
    return


def main():
  ap = argparse.ArgumentParser(description="Browser viewer for CLEMACS grid patch JSONL")
  ap.add_argument(
    "--file",
    default=os.environ.get("CLEMACS_GRID_PATCH_DUMP", "build/clemacs/tmp/grid-patch.jsonl"),
    help="Path to CLEMACS_GRID_PATCH_DUMP JSONL file (default: env or build/clemacs/tmp/grid-patch.jsonl)",
  )
  ap.add_argument("--host", default="127.0.0.1")
  ap.add_argument("--port", type=int, default=7777)
  args = ap.parse_args()

  httpd = ThreadingHTTPServer((args.host, args.port), Handler)
  httpd.grid_path = os.path.abspath(args.file)
  print(f"[clemacs:grid-web] file={httpd.grid_path} url=http://{args.host}:{args.port}/")
  httpd.serve_forever()


if __name__ == "__main__":
  main()
