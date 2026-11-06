#!/usr/bin/env python3
"""AB-T-0456's soak (G5's exit): AuK's staged edits against a running Gaea for an hour, with the AuK worker's live
memory sampled every minute.

    python3 tools/soak-auk.py --app <Gaea.app> --hours 1 --out <dir> [--models-root /Volumes/DEV_VOL1/Models/Models]

It starts Gaea headless on its own folder (GAEA_HOME, short, under /tmp), adds AuK from GitHub, enables both models,
keeps the reference clip as an asset, and loops over one cycle at a time, one job at a time through MES:

- **speak:** AuK-Flash clones the reference asset (the worker's voice cache is keyed by it), with the text varied;
- **four staged edits:** each output is kept as an asset and edited in turn: emotion happy, speed 1.25 (snapped),
  a hum at the start, then dereverb. Each intermediate asset is deleted when the next edit has used it, so the
  worker sees asset_removed;
- **separate:** every third cycle, the second speaker of a two-speaker mixture on AuK-Flash, and every voice on Base.

Every request accepts the Qwen Research licence (users' acceptance, G-27). A sample every minute, taken between jobs
(so the worker is idle), records the ledger: the worker's phys_footprint, charge and peak, and the Mac's wired memory.

Writes jobs.jsonl, samples.jsonl, events.log, and summary.json at the end (or on SIGTERM). The summary says whether
memory stayed flat: the AuK worker's median footprint over the last 5 minutes against its median over minutes 10 to
15, after warm-up, within 5 %.
"""
import argparse, json, os, signal, statistics, subprocess, sys, tempfile, time, urllib.error, urllib.request
from pathlib import Path

DEV = Path(__file__).resolve().parents[2]
PORT = 17786
API = f"http://127.0.0.1:{PORT}/mes/v0"
FIX = DEV / "gaea-plugin-auk/scripts/fixtures"
REF, MIX = FIX / "ref-en.wav", FIX / "mix-two.wav"
REFTEXT = "The morning train was late again, so I walked along the river and watched the boats come in."
POLICY = {"accepted": ["LicenseRef-Qwen-Research"]}
EDITS = [("emotion", {"kind": "emotion", "emotion": "happy"}), ("speed", {"kind": "speed", "factor": 1.25}),
         ("hum", {"kind": "add_cue", "cue": "hum", "at": "start"}), ("dereverb", {"kind": "dereverb"})]
LINES = ["Gaea keeps answering, one staged edit after another.", "The soak is still running, and the voice holds.",
         "Each take is kept, edited, and kept again.", "Memory should stay where it settled after warm-up."]
AUK = "com.xocialize.gaea.auk"


def request(method, path, body=None, content_type="application/json", timeout=60, raw=False):
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"MES-Version": "0.1", "Content-Type": content_type})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            payload = r.read()
            return r.status, payload if raw else json.loads(payload or b"{}")
    except urllib.error.HTTPError as e:
        payload = e.read()
        return e.code, payload if raw else json.loads(payload or b"{}")


def asset(data, media_type="audio/wav"):
    status, answer = request("POST", "/assets?ttl_s=7200", data, content_type=media_type)
    if status >= 300:
        raise RuntimeError(f"asset refused: {status} {answer}")
    return answer["asset_id"]


def upload(path, media_type="audio/wav"):
    status, answer = request("POST", "/uploads", path.read_bytes(), content_type=media_type)
    if status >= 300:
        raise RuntimeError(f"upload refused: {status} {answer}")
    return answer["upload_id"]


class Soak:
    def __init__(self, args):
        self.args, self.out = args, Path(args.out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.home = Path(tempfile.mkdtemp(prefix="gsauk.", dir="/tmp"))
        self.cli = Path(args.app) / "Contents/Helpers/gaea"
        self.env = dict(os.environ, GAEA_HOME=str(self.home))
        self.jobs = open(self.out / "jobs.jsonl", "a", buffering=1)
        self.samples = open(self.out / "samples.jsonl", "a", buffering=1)
        self.events = open(self.out / "events.log", "a", buffering=1)
        self.server, self.stopping, self.begin = None, False, time.time()

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
        self.server = subprocess.Popen([str(exe), "--headless", "--port", str(PORT), "--no-advertise",
                                        "--models-root", self.args.models_root], env=self.env,
                                       stdout=open(self.out / "server.out", "a"), stderr=subprocess.STDOUT)
        deadline = time.time() + 120
        while time.time() < deadline:
            try:
                if request("GET", "/operations", timeout=5)[0] == 200:
                    break
            except (urllib.error.URLError, ConnectionError, TimeoutError, OSError):
                time.sleep(1)
        self.log(f"Gaea up: pid {self.server.pid}, home {self.home}, {self.gaea('status', check=False).splitlines()[0]}")

    def setup(self):
        self.log(self.gaea("plugins", "add", "https://github.com/xocialize-code/gaea-plugin-auk").strip())
        for model in ("auk-flash", "auk"):
            self.log(self.gaea("models", "enable", model).strip())
        self.ref = asset(REF.read_bytes())
        self.log(f"reference asset {self.ref}")

    def run_job(self, name, body):
        body = dict(body, policy=POLICY)
        started = time.time()
        status, answer = request("POST", "/jobs", body)
        record = {"at": started, "name": name, "submit": status}
        job = answer
        if status >= 300:
            record.update(outcome="refused", error=answer.get("error"))
        else:
            while job.get("state") not in ("holding", "purged"):
                _, job = request("GET", f"/jobs/{answer['id']}?wait=10", timeout=30)
            result = job.get("result") or {}
            outputs = result.get("outputs") or []
            record.update(id=answer["id"], outcome=job.get("outcome"), error=job.get("error"),
                          outputs=[(o.get("name"), o.get("duration_s")) for o in outputs],
                          run_ms=(result.get("provenance") or {}).get("timings", {}).get("run_ms"))
        record["seconds"] = round(time.time() - started, 2)
        self.jobs.write(json.dumps(record) + "\n")
        if record["outcome"] != "succeeded":
            self.log(f"job {name}: {record['outcome']} {record.get('error')}")
        return record, job

    def first_audio(self, job):
        out = next(o for o in job["result"]["outputs"] if o.get("kind") == "audio")
        status, data = request("GET", out["href"].removeprefix("/mes/v0"), raw=True, timeout=120)
        if status != 200:
            raise RuntimeError(f"output fetch {status}")
        return data

    def sample(self):
        row = {"at": time.time()}
        try:
            row["ledger"] = json.loads(self.gaea("ledger", "--json"))
        except Exception as e:  # noqa: BLE001 - recorded
            row["error"] = str(e)
        vm = subprocess.run(["vm_stat"], capture_output=True, text=True).stdout
        row["wired_bytes"] = next((int(l.split()[-1].rstrip(".")) for l in vm.splitlines() if "wired down" in l), 0) * 16384
        self.samples.write(json.dumps(row) + "\n")

    def cycle(self, n):
        line = LINES[n % len(LINES)]
        r, job = self.run_job("speak", {"operation": "audio.speak", "model": "auk-flash",
                                        "inputs": {"text": f"Cycle {n}. {line}", "voice_ref": {"asset": self.ref},
                                                   "voice_ref_text": REFTEXT}, "params": {"seed": n}})
        if r["outcome"] != "succeeded":
            return
        held = None
        for name, edit in EDITS:
            take = asset(self.first_audio(job))
            r, job = self.run_job(f"edit-{name}", {"operation": "audio.edit_speech", "model": "auk-flash",
                                                   "inputs": {"audio": {"asset": take}},
                                                   "params": {"edit": edit, "seed": n}})
            if held:
                request("DELETE", f"/assets/{held}", raw=True)
            held = take
            if r["outcome"] != "succeeded":
                break
        if held:
            request("DELETE", f"/assets/{held}", raw=True)
        if n % 3 == 0:
            self.run_job("separate-speaker", {"operation": "audio.separate", "model": "auk-flash",
                                              "inputs": {"audio": {"upload": upload(MIX)}},
                                              "params": {"stems": ["speaker"], "speaker": {"ordinal": 2}, "seed": n}})
            self.run_job("separate-voices", {"operation": "audio.separate", "model": "auk",
                                             "inputs": {"audio": {"upload": upload(MIX)}},
                                             "params": {"stems": ["voices"], "seed": n}})

    def loop(self):
        self.begin = time.time()
        end, next_sample, n = self.begin + self.args.hours * 3600, self.begin, 0
        while time.time() < end and not self.stopping:
            if time.time() >= next_sample:
                self.sample()
                next_sample = time.time() + 60
            n += 1
            try:
                self.cycle(n)
            except Exception as e:  # noqa: BLE001 - recorded, and the soak goes on
                self.log(f"cycle {n} raised: {e}")
                self.jobs.write(json.dumps({"at": time.time(), "name": "cycle", "outcome": "raised", "error": str(e)}) + "\n")
        self.sample()

    def summary(self):
        jobs = [json.loads(l) for l in open(self.out / "jobs.jsonl")]
        by = {}
        for j in jobs:
            b = by.setdefault(j["name"], {"jobs": 0, "succeeded": 0})
            b["jobs"] += 1
            b["succeeded"] += j.get("outcome") == "succeeded"
        points = []
        for l in open(self.out / "samples.jsonl"):
            s = json.loads(l)
            w = next((w for w in (s.get("ledger") or {}).get("workers", []) if w["pluginID"] == AUK), None)
            if w:
                points.append(((s["at"] - self.begin) / 60, w["physFootprintBytes"], w["pid"]))
        settled = [p for m, p, _ in points if 10 <= m <= 15]
        last_min = points[-1][0] if points else 0
        last = [p for m, p, _ in points if m >= last_min - 5]
        flat = None
        if settled and last:
            a, b = statistics.median(settled), statistics.median(last)
            flat = {"settled_gb": round(a / 1e9, 3), "last_gb": round(b / 1e9, 3), "change": round((b - a) / a, 4),
                    "within_5_percent": abs(b - a) / a <= 0.05}
        crashes = self.gaea("crashes", "-n", "1000", "--json", check=False)
        try:
            crashes = json.loads(crashes)
        except ValueError:
            crashes = []
        summary = {
            "hours": self.args.hours, "jobs": len(jobs), "succeeded": sum(j.get("outcome") == "succeeded" for j in jobs),
            "by_name": by, "crashes": len(crashes), "worker_pids": sorted({pid for _, _, pid in points}),
            "samples": len(points), "footprint": flat,
            "footprint_gb_by_minute": [(round(m, 1), round(p / 1e9, 3)) for m, p, _ in points],
            "plugins": self.gaea("plugins", check=False), "status": self.gaea("status", check=False),
        }
        (self.out / "summary.json").write_text(json.dumps(summary, indent=2))
        self.log(f"summary: {summary['succeeded']}/{summary['jobs']} jobs succeeded, {summary['crashes']} crashes, "
                 f"worker pids {summary['worker_pids']}, footprint {flat}")

    def stop(self, *_):
        self.stopping = True


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--app", required=True)
    p.add_argument("--hours", type=float, default=1)
    p.add_argument("--models-root", default="/Volumes/DEV_VOL1/Models/Models")
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
