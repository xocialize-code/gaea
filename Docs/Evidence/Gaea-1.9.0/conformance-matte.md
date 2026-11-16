# MES conformance report

| | |
|---|---|
| **Engine** | Gaea (`eng_gaea_dustin_s_mac_studio_ghnjn2`) · gaea 1.9.0 |
| **URL** | http://127.0.0.1:17690/mes/v0 · open |
| **Profiles** | image 0.1 |
| **Features** | uploads, sse, grants, previews, websocket, mcp, assets |
| **Suite** | MES conformance 0.1 · 2026-11-15T20:53:40Z |
| **Result** | 2 passed · 0 failed · 0 skipped |
| **Base 0.1** | ✅ conforms |
| **Image 0.1** | ✅ conforms for the operations offered |

| Test | Checks | Spec | Result |
|---|---|---|---|
| IMAGE-020 | matte with a subject covers that subject alone: a box or points on one of two balls leaves the other out of the mask and the extract; effective.subject says what ran | Image §3.3 | ✅ pass: ran: birefnet-matte box, birefnet-matte points. |
| IMAGE-021 | matte's subject is checked: both forms, an empty one, a box outside the image or without area, and points without an include are 400; a form the offer doesn't list is 422 | Image §3.3, Base §6.4 | ✅ pass: every matte offer takes both forms, so the gate's refusal wasn't sent. |
