# MES conformance report

| | |
|---|---|
| **Engine** | Gaea (`eng_gaea_dustin_s_mac_studio_jt9uh3`) · gaea 1.7.0 |
| **URL** | http://127.0.0.1:17703/mes/v0 · open |
| **Profiles** | mesh 0.1 |
| **Features** | uploads, sse, grants, previews, websocket, mcp, assets |
| **Suite** | MES conformance 0.1 · 2026-11-14T05:35:21Z |
| **Result** | 41 passed · 1 failed · 74 skipped |
| **Base 0.1** | ✅ conforms |
| **Image 0.1** | ❌ does not conform |
| **Mesh 0.1** | ✅ conforms for the operations offered |

| Test | Checks | Spec | Result |
|---|---|---|---|
| BASE-001 | Engine information validates; uploads and SSE are claimed; Base 0.1 is offered | §4 | ✅ pass |
| BASE-002 | Responses echo MES-Version and carry MES-Request-Id, on success and on error | §2, §3.2 | ✅ pass |
| BASE-003 | An unsupported MES-Version is refused with 400 unsupported_version | §2 | ✅ pass |
| BASE-004 | A request from a browser origin outside the allowlist is refused with 403 origin_not_allowed | §3.2 | ✅ pass |
| BASE-005 | Paired mode: the handshake needs no token; everything else answers 401 without one | §3.3 | ➖ skip: open mode |
| BASE-006 | Paired mode: the certificate served is the one tls.fingerprint_sha256 names | §3.3, §5 | ➖ skip: open mode |
| BASE-010 | Descriptors validate, name their profile, and offer at least one licensed model | §6, §10.2 | ✅ pass |
| BASE-013 | Adapter offers are consistent: an id names one adapter everywhere, defaults lie in their ranges | §6.3 | ➖ skip: no model offer lists adapters |
| BASE-011 | The operations list has an ETag, and If-None-Match answers 304 | §6 | ✅ pass |
| BASE-012 | One descriptor by name matches the list; an unknown one is 404 unknown_operation | §6 | ✅ pass |
| BASE-020 | A job: 201 with Location, then held with a valid result, plan and provenance | §7, §10 | ✅ pass |
| BASE-021 | Request errors: 400 invalid_request, 404 unknown_operation, 422 unsupported_parameter, with valid error bodies | §7.1, §12 | ✅ pass |
| BASE-022 | An Idempotency-Key repeated returns the original job | §7.1 | ✅ pass |
| BASE-023 | A long poll on a held job answers at once with a valid snapshot | §7.3 | ✅ pass |
| BASE-024 | GET jobs lists the caller's jobs and filters by state | §7.3 | ✅ pass |
| BASE-025 | An output: its media type, its bytes and an ETag of its SHA-256 | §7.3 | ✅ pass |
| BASE-026 | Outputs serve byte ranges: 206 with Content-Range, suffixes, and 416 beyond the end | §7.3 | ✅ pass |
| BASE-027 | Confirm purges: the job is purged and succeeded, its outputs answer 410 gone | §7.3, §13 | ✅ pass |
| BASE-028 | Release is idempotent; a released job's outputs answer 410 | §7.3, §13 | ✅ pass |
| BASE-029 | Adapters: a run lists them in provenance with licence and strength; unknown, out-of-range and policy-failing ones are refused | §6.3, §10 | ➖ skip: no model offer lists adapters |
| BASE-030 | Uploads: 201 with the right size and SHA-256, at most an hour's expiry, and single use | §8 | ✅ pass |
| BASE-031 | An upload whose Content-Digest doesn't match is refused | §8 | ✅ pass |
| BASE-040 | Grants: the engine pulls with the bearer token, and fails the job on a wrong SHA-256 | §9 | ✅ pass |
| BASE-050 | SSE: framed events that validate, rising seq, output_ready, then job.ended after confirm | §11 | ✅ pass |
| BASE-051 | SSE resumes after Last-Event-ID | §11 | ✅ pass |
| BASE-052 | WebSocket: pong, engine.health on "*", the client's job events, error messages | §11 | ✅ pass |
| BASE-060 | Health validates | §14 | ✅ pass |
| BASE-070 | Retention deadlines respect the engine's TTLs | §13 | ✅ pass |
| BASE-071 | Outputs expire: after outputs_ttl_s the job is expired and its outputs answer 410 | §13 rule 2 | ➖ skip: outputs_ttl_s is 3600 s (observed only up to 30 s) |
| BASE-080 | MCP: a session lists one tool per operation (dots → underscores) and the four helpers | §15 | ✅ pass |
| BASE-014 | Offers' declarations are consistent: Base supports keys typed, offer limits within the operation's | §6.4 | ✅ pass |
| BASE-015 | A gate the named model lacks is 422 unsupported_parameter; with no model named, the plan names an offer that has it | §6.4 rules 2–3 | ➖ skip: no operation has both a streaming offer and a gate to test it by |
| BASE-016 | A voice implies its model: the plan lists it and provenance names it; an unlisted voice, or one the named model lacks, is 422 | §6.5, §10.1 | ➖ skip: no offer has preset voices |
| BASE-017 | supports.seed false: a request with a seed runs, and warns seed_ignored | §6.4 | ➖ skip: no offer the suite can drive declares supports.seed false |
| BASE-018 | Voice lists: as many voices as supports.voices, with an ETag and 304; unique ids; a model without voices, or not offered, is 404 | §6.5 | ➖ skip: no offer has preset voices |
| BASE-019 | Users' acceptance: an offer whose licence has user_accept_required is 422 policy_unmet (terms_not_accepted) without policy.accepted, and runs with it | §10.2, §10.3 | ➖ skip: no offer the suite can drive needs its users' acceptance |
| BASE-032 | Assets: 201 with the right size and SHA-256 and an expiry within max_asset_ttl_s; listed; two jobs use it; DELETE, then 422 and 404 | §8.1, §13 rule 6 | ✅ pass |
| BASE-033 | An asset whose Content-Digest doesn't match is refused, and one without ttl_s is 400 | §8.1 | ✅ pass |
| BASE-034 | An asset expires: one created with ttl_s=60 is gone after its expires_at | §8.1, §13 rule 6 | ➖ skip: asset expiry takes 60 s; run with --max-ttl-wait 75 or more |
| BASE-035 | Paired mode, a second pairing: another client's asset isn't listed, can't be read, and is 422 in a job | §8.1 | ➖ skip: open mode |
| BASE-053 | Stream declarations: only on audio outputs with max 1; streaming is claimed exactly when some offer streams | §6, §6.4 | ✅ pass |
| BASE-054 | A streamed job: plan.streams gives the format; chunks from 0 with no gaps, whole frames, one final, before output_ready; the output is the chunks | §7.2, §10.1, §11 | ➖ skip: the engine doesn't claim `streaming` |
| BASE-055 | Release mid-stream: the outcome is cancelled, no final chunk is sent, and none follows the cancelled state | §7.3, §11 rule 5 | ➖ skip: the engine doesn't claim `streaming` |
| BASE-056 | stream on an output that can't stream, or to a named model that doesn't stream, is 422 unsupported_parameter | §7.1 | ➖ skip: the engine doesn't claim `streaming` |
| BASE-057 | After confirm, a replayed chunk carries no data | §11 rule 4, §13 rule 2 | ➖ skip: the engine doesn't claim `streaming` |
| IMAGE-001 | fill and erase keep black-mask pixels byte-identical | Image §1.7 | ➖ skip: the engine doesn't offer the Image profile |
| IMAGE-002 | upscale returns exactly input size × scale, for each scale offered | Image §3 | ➖ skip: the engine doesn't offer the Image profile |
| IMAGE-003 | Image operations keep the input size (except upscale and extend) | Image §1.8, §3 | ➖ skip: no size-keeping image operation is offered |
| IMAGE-004 | matte masks are 8-bit grey; extract carries alpha | Image §1.5, §1.6 | ➖ skip: the engine doesn't offer the Image profile |
| IMAGE-005 | EXIF orientation is applied; outputs are upright with no rotation flag | Image §1.4 | ➖ skip: no size-keeping image operation is offered |
| IMAGE-006 | A non-sRGB input is converted: a color_converted warning and an output tagged sRGB | Image §1.3, §4 | ➖ skip: no size-keeping image operation is offered |
| IMAGE-007 | The seed is reported, and the same seed reproduces the result | Image §2 | ❌ **fail**: POST jobs (mesh.generate_part): expected 201, got 422 unsupported_parameter {"error":{"code":"unsupported_parameter","message":"No model of mesh.generate_part this request may use at the standard tier supports a request without a subject_box: say where in the picture the part |
| IMAGE-008 | size and aspect together are refused with 400 | Image §2 | ➖ skip: no operation takes both size and aspect |
| IMAGE-009 | Descriptors match the profile table: required inputs and outputs, of the right kinds | Image §3, §5 | ➖ skip: the engine offers no Image operations |
| IMAGE-010 | An output the operation doesn't offer is refused with 422 unsupported_parameter | Image §1.2 | ➖ skip: every operation offers every output in the vocabulary |
| IMAGE-011 | enhance_prompt returns enhanced data with prompt and applied, for a target model the target operation offers | Image §3.1 | ➖ skip: the engine doesn't offer the Image profile |
| IMAGE-012 | With prompt_enhance off the text goes as typed: no prompt_rewritten unless prompt_enhance_ignored says why | Image §1.9 | ➖ skip: no operation the suite can drive declares prompt_enhance |
| IMAGE-013 | An ic adapter's required slots are counted: too few references or images is 400 | Image §1.10 | ➖ skip: no operation the suite can drive offers an ic adapter on generate or edit |
| IMAGE-014 | decompose returns exactly layer_count layers, each an RGBA PNG the input's size; effective.layer_count is the count | Image §3.2 | ➖ skip: the engine doesn't offer the Image profile |
| IMAGE-015 | decompose refuses a layer_count above its maximum (422), outputs without layers (400) and an un-offered composite (422) | Image §3.2, Base §6 rule 4 | ➖ skip: the engine doesn't offer the Image profile |
| IMAGE-016 | decompose's layers, composited back to front, approximate the input: the error is reported, never failed | Image §3.2 | ➖ skip: the engine doesn't offer the Image profile |
| AUDIO-001 | Descriptors match the profile table: required inputs and outputs of the right kinds, only vocabulary parameters | Audio §3, §6 | ➖ skip: the engine offers no Audio operations |
| AUDIO-002 | Offers' supports keys have the profile's types, offer limits are the profile's fields, and streaming offers state their format | Audio §4 | ➖ skip: the engine offers no Audio operations |
| AUDIO-003 | Audio outputs report sample_rate, channels and duration_s, and the file agrees | Audio §1.1, Base §10.1 | ➖ skip: the engine offers no Audio operations |
| AUDIO-004 | Every MUST input format is accepted: WAV at 16 and 24 bits and in float, and FLAC | Audio §1.1 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-005 | speak: a voice, a voice_ref and neither each route to an offer that supports them; voice with voice_ref is 400 | Audio §3.2, Base §6.4, §6.5 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-006 | Labels: an emotion the named model doesn't list is 422; an alias is resolved by the engine | Audio §2.1, Base §6.4 rule 3 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-007 | Cues: one the model can't perform is removed with cue_unsupported; [pause 1s] is about a second of silence | Audio §2.2 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-008 | design_voice returns count samples with a seed and the sample text; the same seed reproduces; a sample clones | Audio §3.1 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-009 | edit_speech: an edit an offer lists runs; one it doesn't is 422; one missing its fields is 400; keeps_length keeps it | Audio §3.3 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-010 | generate: count sounds, each duration_s long to the frame, each seeded; the same seed reproduces; an unseeded request reports one | Audio §3.4 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-011 | compose: one song with its facts, duration and seed; the same seed reproduces; malformed edits and scores are 400; no named_only offer by default | Audio §3.5 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-012 | compose extend: the song is before_s + the source + after_s long, to the frame | Audio §3.5 | ➖ skip: no compose offer lists extend |
| AUDIO-013 | compose: a score, reference or edit sent to an offer without the key is 422 unsupported_parameter | Audio §3.5, §4.1 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-014 | Output format: output.sample_rate is honoured; an un-offered media type is 422; a seed above 2³²−1 is 422 | Audio §1.2, §1.8 | ➖ skip: the engine offers no Audio operations |
| AUDIO-015 | separate: each offer's stems run, one output per stem named by it, with its facts and the mixture's length | Audio §3.6 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-016 | separate: an unlisted stem and an unlisted pick kind are 422; the speaker stem without a pick, or a pick without it, is 400 | Audio §3.6, Base §6.4 rule 3 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-017 | separate: a mixture longer than the offer's max_duration_s is 422 out_of_limits | Audio §1.7, §3.6, §4.2 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-018 | edit_speech: a cue placement, removing every cue and target_duration_s each need their key; a fitted take is that long | Audio §3.3, §4.1 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-019 | separate by description: a described sound returns the target and the residual, each the mixture's length; effective.describe says what ran | Audio §3.6 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-020 | separate: describe needs described_target (422); target without describe, and describe beside a labelled stem, are 400; a described-only offer without describe is refused | Audio §3.6, Base §6.4 rule 3 | ➖ skip: the engine doesn't offer the Audio profile |
| AUDIO-021 | separate spans: they run and effective.spans echoes them; they need supports.spans (422) and describe (400); a backwards or overlapping span is 400; one past the mixture is out_of_limits | Audio §3.6, §4.1 | ➖ skip: the engine doesn't offer the Audio profile |
| VIDEO-001 | Descriptors match the profile table: required inputs and outputs of the right kinds, only vocabulary parameters | Video §3, §6 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-002 | Offers' supports keys have the profile's types, offer limits are the profile's fields, and offers with sound state its format | Video §4 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-003 | Video outputs report width, height, fps, frames and duration_s, the file agrees, and audio facts appear exactly with a track | Video §1.3, §1.7, Base §10.1 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-004 | Every MUST input format is accepted: MP4 with H.264 and with HEVC, each with AAC | Video §1.1 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-005 | generate: frames on the offer's grid, effective duration_s, fps, size and frames as made; size with aspect is 400; an off-grid size snaps | Video §1.3, §1.4, §2 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-006 | generate: fixed frames route to offers that support them; a named offer that doesn't is 422; keyframes without a time each is 400 | Video §3.1, §4.1 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-007 | audio: false gives a silent clip; audio: true to an offer without sound is 422 | Video §1.7, §4.1 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-008 | soundtrack: the output's track lasts as long as the clip; a named offer without soundtrack is 422 | Video §3.1 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-009 | extend: the source plus the added frames on the grid, the source's frames kept; before_s to an offer without extend_before is 422 | Video §1.8, §3.2 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-010 | retake: the source's frame count, frames outside the span kept; end_s before start_s is 400; an unlisted retake is 422 | Video §1.8, §3.3 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-011 | upscale: exactly size × scale, the same frames and fps, audio kept; no content is 400; an unlisted content is 422 | Video §1.7, §3.4 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-012 | interpolate: (N − 1) × factor + 1 frames at fps × factor, source frames kept, audio kept; factor with fps is 400 | Video §1.7, §3.5 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-013 | Disclosure: a generated clip says AI-generated in its comment item; upscale and interpolate keep an input's marking | Video §1.9, Base §10.2 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-014 | Previews from an offer with supports.previews are images with at_s inside the clip | Video §1.14, Base §11 | ➖ skip: the engine doesn't offer the Video profile |
| VIDEO-015 | seed is reported; the same seed reproduces where the offer is deterministic; an output media type not offered is 422 | Video §1.2, §1.13 | ➖ skip: the engine doesn't offer the Video profile |
| MESH-001 | Descriptors match the profile table: required inputs and outputs of the right kinds, only vocabulary parameters | Mesh §3, §6 | ✅ pass |
| MESH-002 | Offers' supports keys have the profile's types and their limits are the profile's fields; a part offer lists parts | Mesh §4 | ✅ pass |
| MESH-003 | Mesh outputs are GLB by the conventions, report vertices, faces and bounds, the file agrees, and flat results are warned | Mesh §1.1, §1.2, §1.6, §1.8, Base §10.1 | ✅ pass: hairdeck: 4076 vertices, 9910 faces, 280 px texture, 28 joints |
| MESH-004 | Placement: centered at the origin, grounded at Y = 0, the longest extent size_m | Mesh §1.4 | ➖ skip: the engine offers none of mesh.generate |
| MESH-005 | Every mesh output comes with a preview: a square PNG of at least 512 px with transparent pixels | Mesh §1.7 | ✅ pass |
| MESH-006 | generate: faces within max_faces; the offer's gates and limits refuse; texture_size with vertex colours is 400; effective reports | Mesh §2, §3.1, §4 | ➖ skip: the engine offers none of mesh.generate |
| MESH-007 | generate: background removal is gated; a cut-out image is used as it is and reported as alpha | Mesh §1.10, §3.1 | ➖ skip: the engine offers none of mesh.generate |
| MESH-008 | on_flat takes warn and fail; a result refused for flatness fails input_invalid with reason degenerate_result | Mesh §1.8 | ➖ skip: the engine offers none of mesh.generate |
| MESH-009 | Disclosure and licences: a generated mesh or part says ai_generated; an offer's attribution is in asset.copyright | Mesh §1.11, §1.12, Base §10.2 | ✅ pass: hairdeck: "Built with DINOv3" |
| MESH-010 | seed is reported; the same seed reproduces the same mesh where the offer is deterministic | Mesh §1.14 | ✅ pass: mesh.generate_part / hairdeck: the same seed gave identical files |
| MESH-011 | rig: geometry kept; one skin with joints and weights on every primitive; weights sum to 1; templates named; gates refuse | Mesh §3.2, §4.1 | ➖ skip: the engine offers none of mesh.rig |
| MESH-012 | rig input: a GLB with an embedded texture is accepted; bytes that aren't a GLB are input_invalid | Mesh §1.1, §3.2 | ➖ skip: the engine offers none of mesh.rig |
| MESH-013 | generate_part leaves the result on the body: inside the body's bounds grown by half its height, reaching above its head bone, never warned as flat | Mesh §3.3, §1.4, §1.8 | ✅ pass: hairdeck: y 1.38 to 1.61 m |
| MESH-014 | generate_part: one skin, joints reported; the root joint is the body's head bone, by name and place; weights on every primitive | Mesh §3.3 | ✅ pass: hairdeck: 47 joints under J_Bip_C_Head |
| MESH-015 | generate_part physics: VRMC_springBone with physics true, none with false; physics true to an offer without it is 422 | Mesh §3.3, §4.1 | ✅ pass: hairdeck: springs on and off |
| MESH-016 | generate_part textures: none gives no texture, no COLOR_0 and no texture_size; an unlisted texture is 422; effective reports part, physics, texture, background | Mesh §1.5, §3.3, §4.1 | ✅ pass: hairdeck: untextured; hairdeck refused string("vertex_colors") |
| MESH-017 | subject_box: outside the image or without area is 400; to an offer that takes none, or missing where one is required, 422; effective echoes it | Mesh §2, §3.3, §4.1 | ✅ pass: hairdeck: box required, echoed, five bad boxes 400 |
| MESH-018 | generate_part inputs: no body is 400; a body that isn't a GLB is input_invalid; an unlisted part is 422; an opaque picture runs or is refused by background_removal | Mesh §1.10, §3.3, §4.1 | ✅ pass: hairdeck cut out an opaque picture |
| BASE-090 | Pairing: the token is handed out once, and unpairing revokes it | §5 | ➖ skip: open mode |
