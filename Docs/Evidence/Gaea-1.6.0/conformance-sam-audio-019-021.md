# MES conformance report

| | |
|---|---|
| **Engine** | Gaea (`eng_gaea_dustin_s_macbook_pro_2z76kn`) · gaea 1.6.0 |
| **URL** | http://127.0.0.1:17694/mes/v0 · open |
| **Profiles** | audio 0.1 |
| **Features** | uploads, sse, grants, previews, websocket, mcp, assets |
| **Suite** | MES conformance 0.1 · 2026-11-12T01:06:55Z |
| **Result** | 3 passed · 0 failed · 0 skipped |
| **Base 0.1** | ✅ conforms |
| **Audio 0.1** | ✅ conforms for the operations offered |

| Test | Checks | Spec | Result |
|---|---|---|---|
| AUDIO-019 | separate by description: a described sound returns the target and the residual, each the mixture's length; effective.describe says what ran | Audio §3.6 | ✅ pass: sam-audio-base target+residual (regenerated) |
| AUDIO-020 | separate: describe needs described_target (422); target without describe, and describe beside a labelled stem, are 400; a described-only offer without describe is refused | Audio §3.6, Base §6.4 rule 3 | ✅ pass: refused: target without describe, a described-only offer without describe |
| AUDIO-021 | separate spans: they run and effective.spans echoes them; they need supports.spans (422) and describe (400); a backwards or overlapping span is 400; one past the mixture is out_of_limits | Audio §3.6, §4.1 | ✅ pass: sam-audio-base ran with spans, refused: spans without describe, backwards, overlapping, a span past the mixture's end |
