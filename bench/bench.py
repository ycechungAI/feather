#!/usr/bin/env python3 -I
"""Compares browsers on footprint, memory, launch speed, page loads, Speedometer and idle CPU.

Usage:
    bench/bench.py feather path/to/Feather.app [name] # a Feather build; name defaults to "feather"
                                                     # (e.g. "feather-rust" for the Rust prototype)
    bench/bench.py brave                             # Brave, with a throwaway profile
    bench/bench.py all path/to/Feather.app           # both, then a comparison table

Feather runs as a copy with its own bundle identifier (dev.feather.bench), so it gets its own
sandbox folder and never touches your real history, cache, cookies or saved tabs. Brave runs with
a temporary profile. Results are written to bench/results/<name>.json.

What each number means:
- app_mb: the app on disk. profile_mb: data the browser wrote after the run (cache, history, ...).
- launch_ms: from launch to a local test page reporting that it has loaded (median of 3).
- idle_mb: memory with one tab on a tiny local page, after 15 s. sites_mb: with the six sites below open, 60 s in.
  Memory is the "physical footprint" Activity Monitor shows, summed over the browser and all of
  its helper processes (WebKit's or Chromium's), so shared code isn't counted twice the way RSS does.
- idle_cpu_pct: CPU used by all its processes while those six tabs sit idle for 30 s
  (100% = one core).
- Page loads and Speedometer come from bench/engine/main.swift for Feather (its WebKit settings and
  blocker) and from the DevTools protocol for Brave.
"""
import base64
import ctypes
import http.server
import json
import os
import shutil
import socket
import statistics
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")
PORT = 8766
SITES = [
    "https://en.wikipedia.org/wiki/Web_browser",
    "https://github.com/WebKit/WebKit",
    "https://www.cnn.com/",
    "https://www.reddit.com/r/apple/",
    "https://www.amazon.com/",
    "https://www.youtube.com/",
]
LOAD_SITES = SITES[:5]
SPEEDOMETER = "https://browserbench.org/Speedometer3.1/?startAutomatically=true&iterationCount=5"
BRAVE = "/Applications/Brave Browser.app"
BENCH_ID = "dev.feather.bench"

# MARK: - Process accounting

libc = ctypes.CDLL(None)
libc.responsibility_get_pid_responsible_for_pid.restype = ctypes.c_int
libc.responsibility_get_pid_responsible_for_pid.argtypes = [ctypes.c_int]
libc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


_tb = Timebase()
libc.mach_timebase_info(ctypes.byref(_tb))


def rusage(pid):
    """(physical footprint in bytes, CPU time in seconds) for one process, or None."""
    buf = ctypes.create_string_buffer(512)
    if libc.proc_pid_rusage(pid, 4, buf) != 0:  # RUSAGE_INFO_V4
        return None
    user, system = struct.unpack_from("<QQ", buf, 16)
    footprint = struct.unpack_from("<Q", buf, 72)[0]
    return footprint, (user + system) * _tb.numer / _tb.denom / 1e9


def family(root):
    """The browser process and every helper macOS counts as its responsibility."""
    out = subprocess.run(["ps", "-axo", "pid="], capture_output=True, text=True).stdout
    pids = []
    for line in out.split():
        pid = int(line)
        if pid == root or libc.responsibility_get_pid_responsible_for_pid(pid) == root:
            pids.append(pid)
    return pids


def totals(root):
    mem = cpu = 0.0
    for pid in family(root):
        r = rusage(pid)
        if r:
            mem += r[0]
            cpu += r[1]
    return mem / 1e6, cpu


def wait_for_pid(match, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        out = subprocess.run(["pgrep", "-f", match], capture_output=True, text=True).stdout.split()
        if out:
            return int(out[0])
        time.sleep(0.1)
    raise RuntimeError(f"{match} didn't start")


def du_mb(path):
    if not os.path.exists(path):
        return 0.0
    out = subprocess.run(["du", "-sk", path], capture_output=True, text=True).stdout.split()
    return round(int(out[0]) / 1024, 1) if out else 0.0


# MARK: - Local test page: tells us when a browser has shown a page

class Pings:
    def __init__(self):
        self.event = threading.Event()
        handler = self.handler()
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def handler(self):
        pings = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                if self.path.startswith("/ping"):
                    pings.event.set()
                    body = b"ok"
                else:
                    body = (b"<!doctype html><title>Feather bench</title><h1>Hello</h1>"
                            b"<script>addEventListener('load',()=>requestAnimationFrame(()=>"
                            b"fetch('/ping?'+Date.now())))</script>")
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        return Handler

    @property
    def url(self):
        return f"http://127.0.0.1:{PORT}/page"


# MARK: - Browsers

class Feather:
    def __init__(self, app, name="feather"):
        self.name = name
        self.source = os.path.abspath(app)
        self.app = os.path.join(tempfile.mkdtemp(prefix="feather-bench-"), "Feather Bench.app")
        shutil.copytree(self.source, self.app, symlinks=True)
        plist = os.path.join(self.app, "Contents/Info.plist")
        subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BENCH_ID}", plist], check=True)
        entitlements = os.path.join(os.path.dirname(HERE), "Support/Feather.entitlements")
        subprocess.run(["codesign", "--force", "--options", "runtime", "--entitlements", entitlements,
                        "--sign", "-", self.app], check=True, capture_output=True)
        self.container = os.path.expanduser(f"~/Library/Containers/{BENCH_ID}")
        self.binary = os.path.join(self.app, "Contents/MacOS")
        subprocess.run(["defaults", "write", f"{self.container}/Data/Library/Preferences/{BENCH_ID}",
                        "restoreSession", "-bool", "false"], capture_output=True)
        self.proc = None

    def app_mb(self):
        return du_mb(self.source)

    def profile_mb(self):
        return du_mb(self.container)

    def launch(self, urls):
        self.proc = subprocess.Popen([os.path.join(self.binary, os.listdir(self.binary)[0]), urls[0]],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pid = self.proc.pid
        if len(urls) > 1:
            time.sleep(2)
            subprocess.run(["open", "-a", self.app] + urls[1:])
        return pid

    def quit(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None
        time.sleep(2)

    def engine(self):
        """Page loads and Speedometer, in Feather's WebKit setup (bench/engine/main.swift)."""
        exe = os.path.join(RESULTS, "engine")
        src = [os.path.join(HERE, "engine/main.swift")]
        root = os.path.dirname(HERE)
        src.append(os.path.join(root, "Sources/Feather/Blocklist.swift"))
        subprocess.run(["swiftc", "-O", "-o", exe] + src, check=True)
        out = subprocess.run([exe, json.dumps({"sites": LOAD_SITES, "speedometer": SPEEDOMETER})],
                             capture_output=True, text=True, timeout=1500).stdout
        return json.loads(out.strip().splitlines()[-1])


class Brave:
    name = "brave"

    def __init__(self):
        self.profile = tempfile.mkdtemp(prefix="brave-bench-")
        self.proc = None

    def app_mb(self):
        return du_mb(BRAVE)

    def profile_mb(self):
        return du_mb(self.profile)

    def args(self, extra=()):
        return [os.path.join(BRAVE, "Contents/MacOS/Brave Browser"), f"--user-data-dir={self.profile}",
                "--no-first-run", "--no-default-browser-check", "--disable-features=BraveRewards",
                *extra]

    def launch(self, urls, debug=False):
        extra = ["--remote-debugging-port=9333"] if debug else []
        self.proc = subprocess.Popen(self.args(extra) + urls, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return self.proc.pid

    def quit(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(15)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None
        time.sleep(2)

    def engine(self):
        self.launch(["about:blank"], debug=True)  # Chromium opens about:blank as a blank tab
        try:
            time.sleep(4)
            tab = CDP.connect()
            loads = {}
            for cold in (True, False):
                for site in LOAD_SITES:
                    loads.setdefault(site, {})["cold" if cold else "warm"] = tab.load_time(site)
            score = tab.speedometer(SPEEDOMETER)
            return {"loads": loads, "speedometer": score}
        finally:
            self.quit()


# MARK: - Minimal DevTools client (WebSocket over the standard library)

class CDP:
    def __init__(self, ws_url):
        host_port, path = ws_url[len("ws://"):].split("/", 1)
        host, port = host_port.split(":")
        self.sock = socket.create_connection((host, int(port)), timeout=60)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET /{path} HTTP/1.1\r\nHost: {host_port}\r\nUpgrade: websocket\r\n"
                           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        response = b""
        while b"\r\n\r\n" not in response:
            response += self.sock.recv(4096)
        self.buffer = response.split(b"\r\n\r\n", 1)[1]
        self.next_id = 0

    @staticmethod
    def connect():
        for _ in range(50):
            try:
                targets = json.load(urllib.request.urlopen("http://127.0.0.1:9333/json/list", timeout=2))
                page = next(t for t in targets if t["type"] == "page")
                return CDP(page["webSocketDebuggerUrl"])
            except Exception:
                time.sleep(0.2)
        raise RuntimeError("Brave's DevTools endpoint didn't answer")

    def _recv_exact(self, n):
        while len(self.buffer) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("DevTools connection closed")
            self.buffer += chunk
        data, self.buffer = self.buffer[:n], self.buffer[n:]
        return data

    def _recv_message(self):
        payload = b""
        while True:
            b1, b2 = self._recv_exact(2)
            length = b2 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._recv_exact(8))[0]
            payload += self._recv_exact(length)
            if b1 & 0x80:
                return payload

    def call(self, method, **params):
        self.next_id += 1
        msg = json.dumps({"id": self.next_id, "method": method, "params": params}).encode()
        mask = os.urandom(4)
        header = bytes([0x81])
        n = len(msg)
        header += bytes([0x80 | n]) if n < 126 else (bytes([0x80 | 126]) + struct.pack(">H", n) if n < 65536
                                                     else bytes([0x80 | 127]) + struct.pack(">Q", n))
        self.sock.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(msg)))
        while True:
            reply = json.loads(self._recv_message())
            if reply.get("id") == self.next_id:
                return reply.get("result", {})

    def eval(self, expression):
        r = self.call("Runtime.evaluate", expression=expression, returnByValue=True, awaitPromise=True)
        return r.get("result", {}).get("value")

    def load_time(self, url):
        self.call("Page.navigate", url=url)
        end = time.time() + 45
        time.sleep(0.5)
        while time.time() < end:
            value = self.eval(LOAD_METRIC)
            if value:
                return round(value)
            time.sleep(0.25)
        return None

    def speedometer(self, url):
        self.call("Page.navigate", url=url)
        end = time.time() + 1200
        while time.time() < end:
            time.sleep(5)
            value = self.eval(SPEEDOMETER_RESULT)
            if value:
                return value
        return None


LOAD_METRIC = ("(() => { const n = performance.getEntriesByType('navigation')[0];"
               " return document.readyState === 'complete' && n && n.loadEventEnd > 0 ? n.loadEventEnd : 0 })()")
SPEEDOMETER_RESULT = ("(() => { const s = document.querySelector('#summary');"
                      " const r = document.querySelector('#result-number');"
                      " return s && r && getComputedStyle(s).display !== 'none' && r.textContent.trim()"
                      " ? r.textContent.trim() : '' })()")


# MARK: - Runs

def measure(browser, pings):
    result = {"name": browser.name, "app_mb": browser.app_mb()}

    launches = []
    for i in range(4):  # the first run creates the profile, so it's left out
        pings.event.clear()
        start = time.time()
        browser.launch([pings.url])
        ok = pings.event.wait(30)
        if i > 0 and ok:
            launches.append((time.time() - start) * 1000)
        browser.quit()
    result["launch_ms"] = round(statistics.median(launches)) if launches else None

    pid = browser.launch([pings.url])
    time.sleep(15)
    result["idle_mb"] = round(totals(pid)[0])
    browser.quit()

    pid = browser.launch(SITES)
    time.sleep(60)
    result["sites_mb"] = round(totals(pid)[0])
    _, cpu0 = totals(pid)
    time.sleep(30)
    _, cpu1 = totals(pid)
    result["idle_cpu_pct"] = round((cpu1 - cpu0) / 30 * 100, 1)
    browser.quit()

    result.update(browser.engine())
    result["profile_mb"] = browser.profile_mb()
    os.makedirs(RESULTS, exist_ok=True)
    with open(os.path.join(RESULTS, f"{browser.name}.json"), "w") as f:
        json.dump(result, f, indent=2)
    return result


def table(results):
    rows = [("App on disk (MB)", "app_mb"), ("Profile after run (MB)", "profile_mb"),
            ("Launch to page shown (ms)", "launch_ms"), ("Memory, 1 blank tab (MB)", "idle_mb"),
            ("Memory, 6 sites (MB)", "sites_mb"), ("Idle CPU, 6 tabs (%)", "idle_cpu_pct"),
            ("Speedometer 3.1 (higher is better)", "speedometer")]
    names = [r["name"] for r in results]
    lines = ["| | " + " | ".join(names) + " |", "|---|" + "---|" * len(names)]
    for label, key in rows:
        lines.append(f"| {label} | " + " | ".join(str(r.get(key)) for r in results) + " |")
    for site in LOAD_SITES:
        for kind in ("cold", "warm"):
            vals = [str(r.get("loads", {}).get(site, {}).get(kind)) for r in results]
            lines.append(f"| Load {site.split('//')[1].split('/')[0]} {kind} (ms) | " + " | ".join(vals) + " |")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    what = sys.argv[1]
    pings = Pings()
    results = []
    if what in ("feather", "all"):
        results.append(measure(Feather(sys.argv[2], sys.argv[3] if what == "feather" and len(sys.argv) > 3 else "feather"), pings))
    if what in ("brave", "all"):
        results.append(measure(Brave(), pings))
    # Compare with every earlier result too (e.g. the Swift and Rust builds side by side).
    names = {r["name"] for r in results}
    for file in sorted(os.listdir(RESULTS)):
        if file.endswith(".json") and file[:-5] not in names:
            with open(os.path.join(RESULTS, file)) as f:
                results.append(json.load(f))
    print(table(results))


if __name__ == "__main__":
    main()
