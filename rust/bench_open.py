"""bench/bench.py's memory and idle-CPU steps, but launching with `open -n` so macOS attributes
WebKit's processes to the app (a direct launch from a shell attributes them to the shell's host app).

Usage: python3 -I rust/bench_open.py path/to/bench path/to/Feather.app name
(`bench/` is on main from 2dcead4 on; this branch was cut before it.)"""
import subprocess
import sys
import time

sys.path.insert(0, sys.argv[1])
import bench  # noqa: E402


class OpenFeather(bench.Feather):
    def launch(self, urls):
        exe = None
        before = set(subprocess.run(["pgrep", "-f", self.binary], capture_output=True, text=True).stdout.split())
        subprocess.run(["open", "-n", self.app, "--args", urls[0]], check=True)
        for _ in range(100):
            now = set(subprocess.run(["pgrep", "-f", self.binary], capture_output=True, text=True).stdout.split())
            if now - before:
                exe = int(sorted(now - before)[0])
                break
            time.sleep(0.1)
        if len(urls) > 1:
            time.sleep(2)
            subprocess.run(["open", "-a", self.app] + urls[1:])
        self.pid = exe
        return exe

    def quit(self):
        subprocess.run(["kill", str(self.pid)])
        time.sleep(4)


app, name = sys.argv[2], sys.argv[3]
pings = bench.Pings()
f = OpenFeather(app, name)
pid = f.launch([pings.url])
time.sleep(15)
idle = bench.totals(pid)[0]
n_idle = len(bench.family(pid))
f.quit()
pid = f.launch(bench.SITES)
time.sleep(60)
sites, cpu0 = bench.totals(pid)
n_sites = len(bench.family(pid))
time.sleep(30)
_, cpu1 = bench.totals(pid)
f.quit()
print(f"{name}: idle {idle:.0f} MB ({n_idle} procs), 6 sites {sites:.0f} MB ({n_sites} procs), "
      f"idle CPU {(cpu1 - cpu0) / 30 * 100:.1f}%")
