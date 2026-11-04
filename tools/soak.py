#!/usr/bin/env python3
"""AB-T-0429's soak (G4 order 7, G-26): a running Gaea fed mixed image, audio and video jobs for a day, a worker crash
injected every hour, and one update of Gaea itself part-way through.

    python3 tools/soak.py --app <Gaea.app> --hours 24 --update-at 12 --update-to 1.0.0-rc.2 --out <dir>

It starts Gaea headless on its own folder (GAEA_HOME, short, under /tmp), with prereleases on and
GAEA_DEMO_TRAP_SEED=666, adds the plugins from GitHub, then loops:

- **the mix:** one job at a time through MES, round-robin over image (Z-Image, Klein, forge), audio (Kokoro,
  MOSS-SoundEffect) and video (RIFE, LTX compact24) jobs;
- **a crash every hour:** a demo-gradient job on seed 666, which traps in the worker. Gaea runs it once more, it traps
  again, and the job fails naming both crashes. Two crashes an hour never reach the quarantine (three in ten minutes);
- **the update:** at --update-at hours, `gaea update <version>`. Gaea waits for idle, swaps itself and execs in place;
  the loop keeps submitting, and a refused connection while it restarts is retried, not counted as a job;
- **a sample every minute:** the ledger (each worker's charge and footprint), the host's own footprint, and the Mac's
  wired memory.

Writes jobs.jsonl (one line per job), samples.jsonl, events.log, and summary.json at the end (or on SIGTERM).
"""
import argparse, json, os, signal, subprocess, sys, tempfile, time, urllib.error, urllib.request
from pathlib import Path

DEV = Path(__file__).resolve().parents[2]
PORT = 17785
API = f"http://127.0.0.1:{PORT}/mes/v0"
PLUGINS = ["demo", "z-image", "flux2-klein", "forge", "kokoro", "moss-soundeffect", "rife", "ltx"]
FOX = DEV / "gaea-plugin-forge/scripts/fixtures/fox-256.png"
CLIP = DEV / "gaea-plugin-rife/Tests/Fixtures/clip.mp4"
TRAP_SEED = 666


def mix():
    """The cycle of jobs: (name, body or a function giving one, expected outcome)."""
    return [
        ("z-image", lambda i: {"operation": "image.generate", "model": "z-image-turbo",
                               "inputs": {"prompt": "a lighthouse at dusk, photorealistic"},
                               "params": {"size": {"width": 1024, "height": 1024}, "seed": i}}),
        ("kokoro", lambda i: {"operation": "audio.speak", "model": "kokoro-82m",
                              "inputs": {"text": f"Soak job {i}: the server is still answering."},
                              "params": {"voice": "af_heart", "seed": i}}),
        ("rife", lambda i: {"operation": "video.interpolate", "model": "rife-4.25",
                            "inputs": {"video": {"upload": upload(CLIP, "video/mp4")}}, "params": {"factor": 2}}),
        ("flux2-klein", lambda i: {"operation": "image.generate", "model": "klein-4b",
                                   "inputs": {"prompt": "a fox in the snow"},
                                   "params": {"size": {"width": 512, "height": 512}, "seed": i}}),
        ("moss-soundeffect", lambda i: {"operation": "audio.generate", "model": "moss-soundeffect",
                                        "inputs": {"prompt": "Rain on a tin roof, with distant thunder."},
                                        "params": {"duration_s": 1.5, "quality": "draft", "seed": i}}),
        ("forge", lambda i: {"operation": "image.restore", "model": "nafnet-restore",
                             "inputs": {"image": {"upload": upload(FOX, "image/png")}}}),
        ("ltx", lambda i: {"operation": "video.generate", "model": "ltx-2.5-compact24",
                           "inputs": {"prompt": "A red kite flies over a green hill on a sunny day."},
                           "params": {"size": {"width": 256, "height": 256}, "duration_s": 0.375, "seed": i,
                                      "audio": False},
                           "policy": {"accepted": ["LicenseRef-LTX-2-Community"]}}),
    ]


def request(method, path, body=None, content_type="application/json", timeout=60):
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"MES-Version": "0.1", "Content-Type": content_type})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def upload(path, media_type):
    status, answer = request("POST", "/uploads", path.read_bytes(), content_type=media_type)
    if status >= 300:
        raise RuntimeError(f"upload refused: {status} {answer}")
    return answer["upload_id"]


class Soak:
    def __init__(self, args):
        self.args, self.out = args, Path(args.out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.home = Path(tempfile.mkdtemp(prefix="gsoak.", dir="/tmp"))
        self.cli = Path(args.app) / "Contents/Helpers/gaea"
        self.env = dict(os.environ, GAEA_HOME=str(self.home), GAEA_DEMO_TRAP_SEED=str(TRAP_SEED))
        self.env.setdefault("GAEA_GITHUB_TOKEN", subprocess.run(["gh", "auth", "token"], capture_output=True,
                                                                text=True).stdout.strip())
        self.jobs = open(self.out / "jobs.jsonl", "a", buffering=1)
        self.samples = open(self.out / "samples.jsonl", "a", buffering=1)
        self.events = open(self.out / "events.log", "a", buffering=1)
        self.server = None
        self.stopping = False
        self.updated = False

    def log(self, text):
        line = f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {text}"
        print(line, flush=True)
        self.events.write(line + "\n")

    def gaea(self, *args, check=True):
        r = subprocess.run([str(self.cli), *args], env=self.env, capture_output=True, text=True, timeout=1800)
        if check and r.returncode != 0:
            raise RuntimeError(f"gaea {' '.join(args)}: {r.stdout}{r.stderr}")
        return r.stdout

    def start(self):
        exe = Path(self.args.app) / "Contents/MacOS/Gaea"
        self.server = subprocess.Popen([str(exe), "--headless", "--port", str(PORT), "--no-advertise"], env=self.env,
                                       stdout=open(self.out / "server.out", "a"), stderr=subprocess.STDOUT)
        self.wait_up()
        self.log(f"Gaea up: pid {self.server.pid}, home {self.home}")

    def wait_up(self, seconds=300):
        deadline = time.time() + seconds
        while time.time() < deadline:
            try:
                if request("GET", "/operations", timeout=5)[0] == 200:
                    return
            except (urllib.error.URLError, ConnectionError, TimeoutError, OSError):
                pass
            time.sleep(2)
        raise RuntimeError("Gaea didn't answer")

    def setup(self):
        self.gaea("update", "--prereleases", "on")
        for p in PLUGINS:
            self.log(self.gaea("plugins", "add", f"https://github.com/xocialize-code/gaea-plugin-{p}").strip())
        self.gaea("models", "enable", "ltx-2.5-compact24")

    def run_job(self, name, body, injected=False):
        started = time.time()
        while True:
            try:
                status, answer = request("POST", "/jobs", body)
                break
            except (urllib.error.URLError, ConnectionError, OSError) as e:  # Gaea restarting for its update
                if time.time() - started > 600:
                    raise RuntimeError(f"no answer for 10 minutes: {e}")
                time.sleep(3)
        record = {"at": started, "name": name, "injected": injected, "submit": status}
        if status >= 300:
            record.update(outcome="refused", error=answer.get("error"))
        else:
            job_id, job = answer["id"], answer
            while job.get("state") not in ("holding", "purged"):
                try:
                    _, job = request("GET", f"/jobs/{job_id}?wait=10", timeout=30)
                except (urllib.error.URLError, ConnectionError, OSError):
                    time.sleep(3)  # the server went away for its update; the job is Gaea's to keep or fail
                    try:
                        self.wait_up()
                    except RuntimeError:
                        break
            result = job.get("result") or {}
            worker = (result.get("effective") or {}).get("model_params", {}).get("x-gaea.worker") or {}
            record.update(id=job_id, outcome=job.get("outcome"), error=job.get("error"),
                          version=worker.get("version"), lane=worker.get("lane"), requeued=worker.get("requeued"),
                          gaea=(result.get("provenance") or {}).get("engine", {}).get("version"),
                          run_ms=(result.get("provenance") or {}).get("timings", {}).get("run_ms"))
        record["seconds"] = round(time.time() - started, 2)
        self.jobs.write(json.dumps(record) + "\n")
        return record

    def sample(self):
        row = {"at": time.time()}
        try:
            row["ledger"] = json.loads(self.gaea("ledger", "--json"))
        except Exception as e:  # noqa: BLE001 - a sample during the update's restart
            row["error"] = str(e)
        vm = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
        pages = next((int(l.split()[-1].rstrip(".")) for l in vm.splitlines() if "wired down" in l), 0)
        row["wired_bytes"] = pages * 16384
        self.samples.write(json.dumps(row) + "\n")

    def update(self):
        """Gaea installs an update only after a minute with no job running or waiting (--update-grace), so the mix
        pauses, as an operator scheduling an update would, until Gaea answers on the new version."""
        asked = time.time()
        self.log(f"update to {self.args.update_to}: " + self.gaea("update", self.args.update_to, check=False).strip())
        self.updated = True
        while time.time() - asked < 1800:
            time.sleep(10)
            try:
                if f"Gaea {self.args.update_to}" in self.gaea("status", check=False):
                    self.log(f"Gaea {self.args.update_to} answering, {time.time() - asked:.0f} s after the update was asked for")
                    return
            except Exception:  # noqa: BLE001 - restarting
                pass
        self.log("the update didn't finish in 30 minutes; the soak goes on")

    def loop(self):
        cycle, i = mix(), 0
        begin = time.time()
        end = begin + self.args.hours * 3600
        next_crash, next_sample = begin + 600, begin
        while time.time() < end and not self.stopping:
            now = time.time()
            if now >= next_sample:
                self.sample()
                next_sample = now + 60
            if now >= next_crash:
                r = self.run_job("demo-trap", {"operation": "image.generate", "model": "demo-gradient",
                                               "inputs": {"prompt": "an injected crash"},
                                               "params": {"size": {"width": 256, "height": 256}, "seed": TRAP_SEED}},
                                 injected=True)
                self.log(f"injected crash: {r.get('outcome')} {((r.get('error') or {}).get('message') or '')[:160]}")
                next_crash += 3600
                continue
            if not self.updated and now >= begin + self.args.update_at * 3600:
                self.update()
            name, make = cycle[i % len(cycle)]
            i += 1
            try:
                r = self.run_job(name, make(i))
            except Exception as e:  # noqa: BLE001 - recorded, and the soak goes on
                self.log(f"job {name} raised: {e}")
                continue
            if r.get("outcome") != "succeeded":
                self.log(f"job {name}: {r.get('outcome')} {r.get('error')}")

    def summary(self):
        jobs = [json.loads(l) for l in open(self.out / "jobs.jsonl")]
        mixed = [j for j in jobs if not j["injected"]]
        by = {}
        for j in mixed:
            b = by.setdefault(j["name"], {"jobs": 0, "succeeded": 0})
            b["jobs"] += 1
            b["succeeded"] += j.get("outcome") == "succeeded"
        crashes = self.gaea("crashes", "-n", "1000", "--json", check=False)
        try:
            crashes = json.loads(crashes)
        except ValueError:
            crashes = []
        summary = {
            "hours": self.args.hours, "jobs": len(mixed),
            "succeeded": sum(j.get("outcome") == "succeeded" for j in mixed), "by_plugin": by,
            "injected": len([j for j in jobs if j["injected"]]),
            "injected_failed_as_expected": sum(j.get("outcome") == "failed" for j in jobs if j["injected"]),
            "crashes": len(crashes), "crashes_not_demo": [c for c in crashes if c.get("pluginID") != "com.xocialize.gaea.demo"],
            "gaea_versions_seen": sorted({j.get("gaea") for j in mixed if j.get("gaea")}),
            "plugins": self.gaea("plugins", check=False), "status": self.gaea("status", check=False),
        }
        (self.out / "summary.json").write_text(json.dumps(summary, indent=2))
        self.log(f"summary: {summary['succeeded']}/{summary['jobs']} mixed jobs succeeded, {summary['injected']} injected, "
                 f"{summary['crashes']} crashes, versions {summary['gaea_versions_seen']}")

    def stop(self, *_):
        self.stopping = True


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--app", required=True)
    p.add_argument("--hours", type=float, default=24)
    p.add_argument("--update-at", type=float, default=12)
    p.add_argument("--update-to", required=True)
    p.add_argument("--out", required=True)
    soak = Soak(p.parse_args())
    signal.signal(signal.SIGTERM, soak.stop)
    try:
        soak.start()
        soak.setup()
        soak.loop()
    finally:
        try:
            soak.summary()
        finally:
            subprocess.run(["pkill", "-TERM", "-f", f"Gaea --headless --port {PORT}"])


if __name__ == "__main__":
    sys.exit(main())
