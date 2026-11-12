# MES conformance report

| | |
|---|---|
| **Engine** | Gaea (`eng_gaea_dustin_s_macbook_pro_tkniit`) · gaea 1.6.0 |
| **URL** | http://127.0.0.1:17694/mes/v0 · open |
| **Profiles** | audio 0.1, image 0.1 |
| **Features** | uploads, sse, grants, previews, websocket, mcp, assets |
| **Suite** | MES conformance 0.1 · 2026-11-12T01:28:00Z |
| **Result** | 3 passed · 1 failed · 0 skipped |
| **Base 0.1** | ❌ does not conform |
| **Audio 0.1** | ✅ conforms for the operations offered |

| Test | Checks | Spec | Result |
|---|---|---|---|
| BASE-019 | Users' acceptance: an offer whose licence has user_accept_required is 422 policy_unmet (terms_not_accepted) without policy.accepted, and runs with it | §10.2, §10.3 | ❌ **fail**: sam-audio-base named with policy.accepted [LicenseRef-SAM]: expected 201, got 422 unsupported_parameter {"error":{"code":"unsupported_parameter","message":"Model sam-audio-base doesn't support a stem that needs neither a speaker pick nor a description (give 'describe' to an offer that separates a descri |
| AUDIO-019 | separate by description: a described sound returns the target and the residual, each the mixture's length; effective.describe says what ran | Audio §3.6 | ✅ pass: sam-audio-base target+residual (regenerated) |
| AUDIO-020 | separate: describe needs described_target (422); target without describe, and describe beside a labelled stem, are 400; a described-only offer without describe is refused | Audio §3.6, Base §6.4 rule 3 | ✅ pass: refused: describe without described_target, target without describe, describe beside a labelled stem, a described-only offer without describe |
| AUDIO-021 | separate spans: they run and effective.spans echoes them; they need supports.spans (422) and describe (400); a backwards or overlapping span is 400; one past the mixture is out_of_limits | Audio §3.6, §4.1 | ✅ pass: sam-audio-base ran with spans, refused: spans without describe, backwards, overlapping, a span past the mixture's end |
