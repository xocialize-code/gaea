# MES client conformance report

| | |
|---|---|
| **Client** | `'/Volumes/Satechi/Development/gaea-mes-media-server/dist/Gaea Lab.app/Contents/Helpers/lab-run' --engine {url} --operation image.generate --text prompt={prompt} --out {out}` |
| **Suite** | MES client conformance 0.1 · 2026-10-29T20:17:06Z |
| **Result** | 11 passed · 0 failed |
| **Base 0.1 (client)** | ✅ conforms |

| Test | Checks | Spec | Result |
|---|---|---|---|
| CLIENT-001 | Every request names the Base version (MES-Version: 0.1) | §2 rule 3 | ✅ pass |
| CLIENT-002 | Job requests use only described inputs and parameters, valid against the descriptor | §7.1, §16 | ✅ pass |
| CLIENT-003 | One submission per task, and following the job doesn't busy-poll | §7.3, §11 | ✅ pass |
| CLIENT-004 | What the client collects, it confirms or releases: no job is left holding | §7.3, §13, §16 | ✅ pass |
| CLIENT-005 | The task completes: the job's output is fetched and the client exits 0 | §7 | ✅ pass |
| CLIENT-010 | 429 busy: waits for Retry-After, then retries and completes | §7.1, §12, §16 | ✅ pass |
| CLIENT-011 | 503 no_capacity: waits for Retry-After, then retries and completes | §12, §16 | ✅ pass |
| CLIENT-020 | A failed job is reported as a failure; no outputs are fetched and nothing is resubmitted | §7.2, §16 | ✅ pass |
| CLIENT-021 | A job cancelled on the engine is reported, and no outputs are fetched | §7.2, §16 | ✅ pass |
| CLIENT-022 | An unknown error code is handled by its HTTP class: reported, and a 4xx isn't retried | §12 | ✅ pass |
| CLIENT-023 | Outputs that are gone (410) are reported, not retried in a loop | §7.3, §13 | ✅ pass |
