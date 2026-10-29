#!/usr/bin/env python3 -I
"""Measures a Feather build like docs/OPTIMIZATION.md: resident memory (RSS) of the app plus the
WebKit processes it started, some seconds after opening a page.

Usage: rust/measure.py path/to/Feather.app URL SECONDS [--probe]

The app is launched with `open -n`, so it runs beside any Feather already open (that one and its
WebKit processes are left out). WebKit's helper processes aren't children of the app; they're
matched by macOS's "responsible process". CPU is sampled over 3 seconds as a sign that a video is
playing. --probe sets FEATHER_PROBE=1 (Rust build only) and prints the page's video state.
"""
import ctypes
import os
import subprocess
import sys
import tempfile
import time

PREFS = os.path.expanduser(
    "~/Library/Containers/dev.feather.browser/Data/Library/Preferences/dev.feather.browser")

libc = ctypes.CDLL(None)
responsible = libc.responsibility_get_pid_responsible_for_pid
responsible.restype = ctypes.c_int
responsible.argtypes = [ctypes.c_int]


def processes():
    out = subprocess.run(["ps", "-axo", "pid=,rss=,comm="], capture_output=True, text=True).stdout
    for line in out.splitlines():
        pid, rss, comm = line.split(None, 2)
        yield int(pid), int(rss), comm


def cpu(pids):
    """%CPU of each pid over 3 seconds (top's second sample)."""
    args = ["top", "-l", "2", "-s", "3", "-stats", "pid,cpu"]
    for pid in pids:
        args += ["-pid", str(pid)]
    out = subprocess.run(args, capture_output=True, text=True).stdout
    sample = out.rsplit("PID", 1)[-1].splitlines()[1:]
    return {int(p): float(c) for p, c in (line.split()[:2] for line in sample if line.strip())}


def main():
    app, url, wait = os.path.abspath(sys.argv[1]), sys.argv[2], int(sys.argv[3])
    probe = "--probe" in sys.argv
    exe = f"{app}/Contents/MacOS/Feather"
    before = {pid for pid, _, comm in processes() if comm == exe}
    log = tempfile.NamedTemporaryFile(suffix=".log", delete=False).name
    env = ["--env", "FEATHER_PROBE=1"] if probe else []
    # The test copy shares the real app's sandbox container: don't reopen the saved tabs.
    subprocess.run(["defaults", "write", PREFS, "restoreSession", "-bool", "false"], check=True)
    subprocess.run(["open", "-n", *env, "--stderr", log, app, "--args", url], check=True)
    app_pid = None
    for _ in range(50):
        app_pid = next((pid for pid, _, comm in processes() if comm == exe and pid not in before), None)
        if app_pid:
            break
        time.sleep(0.2)
    if not app_pid:
        sys.exit("app didn't start")
    time.sleep(wait)
    if not any(pid == app_pid for pid, *_ in processes()):
        sys.exit("app quit during the run")
    owner = responsible(app_pid)
    rows = {}
    for pid, rss, comm in processes():
        name = comm.rsplit("/", 1)[-1]
        if pid == app_pid:
            rows[pid] = ["App", rss]
        elif name.startswith("com.apple.WebKit.") and responsible(pid) == owner:
            rows[pid] = [name.removeprefix("com.apple.WebKit."), rss]
    load = cpu(rows)
    try:
        os.kill(app_pid, 15)
    except ProcessLookupError:
        print("  WARNING: app quit before the end of the run")
    total = sum(r[1] for r in rows.values())
    for pid, (name, rss) in sorted(rows.items(), key=lambda r: -r[1][1]):
        print(f"  {name:<12} {rss / 1024:8.1f} MB  cpu {load.get(pid, 0):5.1f}%")
    print(f"  {'Total':<12} {total / 1024:8.1f} MB")
    if probe:
        with open(log) as f:
            videos = [line.strip() for line in f if line.startswith("video:")]
        print("  " + (videos[-1] if videos else "video: no probe output"))
    os.unlink(log)
    time.sleep(8)  # let WebKit's processes exit before the next run


if __name__ == "__main__":
    main()
