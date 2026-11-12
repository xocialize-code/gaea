# MES conformance report

| | |
|---|---|
| **Engine** | Gaea (`eng_gaea_dustin_s_macbook_pro_hr2bvp`) · gaea 1.5.0 |
| **URL** | http://127.0.0.1:17694/mes/v0 · open |
| **Profiles** | audio 0.1, image 0.1 |
| **Features** | uploads, sse, grants, previews, websocket, mcp, assets |
| **Suite** | MES conformance 0.1 · 2026-11-12T00:09:34Z |
| **Result** | 3 passed · 0 failed · 0 skipped |
| **Base 0.1** | ✅ conforms |
| **Audio 0.1** | ✅ conforms for the operations offered |

| Test | Checks | Spec | Result |
|---|---|---|---|
| AUDIO-019 | separate by description: a described sound returns the target and the residual, each the mixture's length; effective.describe says what ran | Audio §3.6 | ✅ pass: no separate offer has described_target |
| AUDIO-020 | separate: describe needs described_target (422); target without describe, and describe beside a labelled stem, are 400; a described-only offer without describe is refused | Audio §3.6, Base §6.4 rule 3 | ✅ pass: refused: describe without described_target; no offer has described_target |
| AUDIO-021 | separate spans: they run and effective.spans echoes them; they need supports.spans (422) and describe (400); a backwards or overlapping span is 400; one past the mixture is out_of_limits | Audio §3.6, §4.1 | ✅ pass: no separate offer takes spans |
