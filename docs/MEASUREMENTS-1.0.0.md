# Beyond Performance: investigation and validation

**Measured result reproduced in two clean combined-mod sessions:** disabling the engine's adaptive frame-rate smoothing increased pooled gameplay-delta FPS from **34.58 to 71.22**, then from **57.98 to 84.16** after a full restart. p95 frame time improved from **45.48 to 32.05 ms** and **31.28 to 23.50 ms**, respectively. In each session both enabled passes beat both disabled passes. These results apply to stationary offscreen tests with the explicit FPS cap set to **0/unlimited**; the baseline adaptive smoothing limit was still active. They are not universal FPS guarantees. Standalone gameplay validation also passed.

**The normal-cap tests did not establish a gain:** at the player's approximately 60.0448 FPS cap, pixel-budget pooled FPS changed **43.90 → 42.44** and smoothing-disable pooled FPS changed **46.20 → 43.99**. The capped smoothing run also contains camera movement during its enabled phases, limiting causal interpretation. The installed preferences and package retain the conservative default **frame-smoothing disable off**; no FPS gain is claimed for the existing normal-cap setup.

The clean attachment comparison showed no FPS gain. The first explicit-cap-zero pixel-budget comparison had substantial baseline drift, so its pooled improvement is inconclusive. An experimental background-video control performed worse and was excluded from the release. No physical mouse-latency improvement has been measured. Development date: **November 7, 2026**.

## Test setup recorded so far

| Item | Recorded setup |
|---|---|
| Game | Main Steam copy of Drive Beyond Horizons; build 26437602, depot manifest 5330885290026193573; Unreal Engine 5.2 |
| Loader | UE4SS 3.0.1 Beta #0, Git 8f7b2ca3; exact package fingerprints are in the manifest |
| CPU | Intel Core i5-13420H, 8 cores / 12 logical processors |
| GPU | NVIDIA GeForce RTX 3050 Laptop GPU; Intel UHD also present; NVIDIA driver 32.0.16.2101 |
| Memory | Approximately 16 GB system RAM; WMI reported approximately 4 GiB NVIDIA VRAM |
| Combined setup | Installed Beyond Apocalypse, Beyond Tuning 1.2.7, Beyond Detours, MixTape Maker, local developer menu, and Beyond Performance; a development dispatcher was present |
| Launch and actual viewport | Command launched main shipping executable with a 1280×720 request, offscreen at `-WinX=-20000 -WinY=-20000`, unattended; the measured viewport was **1536×864** |
| Explicit timing controls | First comparisons: `t.MaxFPS=0`; later normal-cap comparisons: `t.MaxFPS≈60.0448`; `r.VSync=0`, `t.IdleWhenNotForeground=0` throughout |
| Clean process and view | PID 29548; stationary camera approximately `(99520.980, -13883.688, 29228.771)`; rotation `(0,0,0)`; camera verified unchanged at each pass boundary |
| Second clean session view | A later fresh combined-mod process; stationary camera approximately `(100094.094, -13863.514, 29228.771)` with rotation `(0,0,0)`, unchanged within its four passes |
| Render scale | `r.ScreenPercentage=50`, except pixel-budget enabled passes at 37.5; actual viewport dimensions remained unchanged |
| Engine timing flags | Baseline `GameEngine.bSmoothFrameRate=true`, despite `t.MaxFPS=0`; `bUseFixedFrameRate=false` |
| Instrumentation | Clean process did not run the broad attachment hook probe; capture callbacks shared the same local-player tick path; no stack suspension overlapped the clean comparisons |

The offscreen launch is an important limitation. Its presentation and GPU behavior may differ from visible foreground gameplay, particularly on a laptop. Setting `t.IdleWhenNotForeground=0` does not prove equivalence to normal foreground presentation. The actual viewport is reported above rather than inferred from command-line resolution. Power/thermal policy was not experimentally controlled, and no portable route or save/seed identity was recorded for external reproduction.

The current command-only workflow uses the main Steam copy with the installed mod set. No result below establishes performance on a separate lower-end PC, a visible foreground session, or a remote multiplayer client.

## Clean comparisons

Each comparison changed one feature in **off → on → on → off** order, recorded the camera and relevant controls at every boundary, and completed with preference restoration. Initial clean attachment, pixel-budget, and frame-smoothing passes captured approximately **30 seconds after five seconds settling**. The second-session smoothing passes captured approximately **22 seconds after eight seconds settling**, 30 seconds total per phase. Normal-cap pixel passes and the rejected video experiment used approximately **20 seconds after five seconds settling**; normal-cap smoothing passes used **15 seconds after five seconds settling**. The normal-cap smoothing setup log records camera movement, described below; all other reported setup logs contain identical camera values at their eight recorded boundaries. Those boundary checks do not continuously track movement between samples. Absolute FPS should not be compared across different feature experiments or pooled across different game processes.

Average FPS is frame count divided by summed game-provided frame delta. Median is the arithmetic median; p95/p99 use nearest rank. The 1% low is 1000 divided by the mean duration of the slowest ceil(1% of frames). The independent callback-interval columns remain in raw CSVs. These are local gameplay timing samples, not display-present traces.

| Feature being enabled | Pooled FPS off → on | Median ms off → on | p95 ms off → on | p99 ms off → on | 1% low FPS off → on | Interpretation |
|---|---:|---:|---:|---:|---:|---|
| Disable engine frame-rate smoothing, session 1 | **34.58 → 71.22** | **25.41 → 10.48** | **45.48 → 32.05** | **56.18 → 42.27** | **13.54 → 17.18** | Benefit with explicit cap set to 0; baseline adaptive limit active |
| Disable engine frame-rate smoothing, session 2 | **57.98 → 84.16** | **15.04 → 10.13** | **31.28 → 23.50** | **43.34 → 38.47** | **19.11 → 19.82** | Improvement reproduced after a full combined-mod restart |
| Remove duplicate attachment lookups | 35.47 → 34.35 | 24.44 → 24.65 | 43.99 → 46.94 | 54.17 → 57.85 | 15.45 → 14.26 | No measured gameplay FPS or consistency gain |
| Reduce rendered pixels, scale 50 → 37.5 | 47.13 → 55.00 | 19.72 → 16.01 | 39.91 → 34.65 | 51.23 → 45.30 | 16.58 → 18.66 | Inconclusive because the disabled baseline drifted substantially |
| Reduce rendered pixels, normal cap ≈60.0448 | 43.90 → 42.44 | 17.37 → 19.97 | 40.88 → 40.33 | 51.09 → 51.80 | 14.87 → 15.00 | No throughput gain; tail changes mixed |
| Disable engine frame-rate smoothing, normal cap ≈60.0448 | 46.20 → 43.99 | 16.65 → 16.68 | 38.32 → 40.82 | 50.31 → 52.30 | 14.91 → 14.19 | No established gain; camera moved in enabled phases |
| Experimental hidden-menu video pause | 70.05 → 64.64 | 10.54 → 10.93 | 31.63 → 34.63 | 43.50 → 44.50 | 14.11 → 16.10 | Lower throughput; candidate excluded from release |

| Experiment | Pass 1 off FPS | Pass 2 on FPS | Pass 3 on FPS | Pass 4 off FPS |
|---|---:|---:|---:|---:|
| Engine frame-rate smoothing disabled, session 1 | 35.23 | 68.28 | 74.16 | 33.94 |
| Engine frame-rate smoothing disabled, session 2 | 57.09 | 82.50 | 85.82 | 58.87 |
| Attachment lookup optimization | 36.49 | 34.01 | 34.69 | 34.45 |
| Rendered-pixel reduction | 56.29 | 54.08 | 55.93 | 37.97 |
| Rendered-pixel reduction, normal cap ≈60.0448 | 44.62 | 43.49 | 41.40 | 43.19 |
| Engine frame-rate smoothing disabled, normal cap ≈60.0448 | 42.69 | 44.09 | 43.89 | 49.69 |
| Rejected video pause | 71.69 | 64.90 | 64.39 | 68.40 |

### Engine frame-rate smoothing: the verified limiter

The game retained `bSmoothFrameRate=true` while the explicit FPS cap was zero. A separate clean-process stack sample found the game thread repeatedly sleeping/yielding in `UEngine::UpdateTimeAndHandleMaxTickRate`. Changing only the smoothing flag gave the reversible result above, supporting an engine pacing limit as a significant cause of low throughput in this setup.

Across approximately 60 seconds per state, the smoothing test recorded **2,077 off frames and 4,281 on frames**. Frames over 33.3 ms fell from **463 to 185**; frames over 50 ms fell from **47 to 14**. Tail improvement was not absolute: maximum observed frame time rose from **167.91 to 181.82 ms**, so occasional long stalls remained. Callback-interval average FPS independently agreed at **34.58 versus 71.31**.

The second clean process recorded **2,553 off frames and 3,705 on frames** over approximately 44 seconds per state. Frames over 33.3 ms fell from **97 to 63**. Longer hitches did not all improve: frames over 50 ms increased from **9 to 13**, and maximum frame time increased from **85.38 to 102.64 ms**. Callback-interval average FPS agreed at **57.90 versus 84.13**. This reproduction supports the pacing-limit finding, while different baseline speeds across sessions show why a single fixed gain percentage would be misleading.

Both positive-result tests deliberately set the explicit cap to `t.MaxFPS=0`, with VSync off and fixed frame rate disabled; “unlimited” refers only to the explicit cap, because baseline engine smoothing still imposed an adaptive limit. A normal positive FPS cap can determine the limit instead. The later positive-cap test below did not establish an improvement. Disabling smoothing is an optional, default-off control. It can increase CPU/GPU power demand and does not remove work from every slow frame. Visible foreground and controlled battery/AC comparisons remain outside this validation.

### Normal-cap checks: no established performance gain

The normal-cap pixel comparison retained **`t.MaxFPS≈60.0448` and `bSmoothFrameRate=true`**, with a fixed camera, and changed screen percentage **50 → 37.5**. Across approximately 40 seconds per state, off captured **1,758 frames at 43.90 FPS** and on captured **1,701 frames at 42.44 FPS**. p95 improved slightly, while median/p99 and frames over 33.3 ms or 50 ms worsened slightly. This does not establish a useful gain for that setup, despite the real reduction in nominal rendering pixels.

The normal-cap smoothing comparison retained the same positive cap and 50% scale. Across approximately 30 seconds per state it recorded **1,388 off frames at 46.20 FPS** versus **1,321 on frames at 43.99 FPS**; p95/p99 and 1% low worsened. However, the setup log shows the camera moved during enabled phases 2 and 3, from approximately `(100094,-13864)` at zero rotation to `(100202,-13475)` with yaw −100.5°, then another pose. It is therefore a confounded comparison, not a fixed-view estimate of a negative causal effect. It provides no support for an improvement at the normal cap, and the camera evidence is retained rather than discarded.

The release and installed preferences leave **Disable engine frame-rate smoothing off**. A player using an unlimited explicit cap can test the option against their own matched scene; neither this option nor pixel reduction is presented as a measured FPS improvement under the existing normal-cap configuration.

### Pixel budget and the rejected media candidate

Lowering screen percentage from 50 to 37.5 reduces nominal scene pixels to 56.25% of the previous count. It changes actual rendering workload, not just object visibility. However, the first test's two disabled passes differed from **56.29 to 37.97 FPS**, while both enabled passes were around 55 FPS. That drift prevents attributing its pooled difference to this feature. The later normal-cap test also showed no throughput gain. Pixel reduction remains a selectable quality/performance tradeoff without a measured gain claim here. The release refuses to take screen-percentage ownership while DLSS or dynamic resolution is active, and yields/restores its own value if DLSS becomes active later.

The Bink path in stack samples motivated a background-menu video experiment. The pause flag changed, but `GetTime` stayed **0.000 seconds** in both paused and resumed states. `IsPlaying=true` alone did not prove decoder advancement. Its clean A/B result lowered pooled FPS, and the timeline test failed its advancement check. The experiment was therefore rejected; no menu-video control or media mutation belongs to the final release.

## Attachment system: what was verified

A **5.006-second instrumented count window** produced these counts:

| Function | Completed callbacks observed |
|---|---:|
| `AttachableComponent.ReceiveTick` | 45,056 |
| `ItemBaseMaster.CheckIsAttached` | 29,845 |
| `CarItemEquipableActor.Get Vehicle` | 17,654 |
| Native vehicle `UpdateTickAttached` | 21 |

The same investigation found 313 live `AttachableComponent` objects with ticking enabled, 115 live equipable actors with 27 ticking, and 330 `AttachActorOn` components with none ticking. These are counts in one scene, **not CPU timings**. The probe added overhead and cannot supply an uninstrumented FPS baseline.

Several initial suspicions were rejected or narrowed:

- `CheckIsAttached` reads attachment metadata and checks validity; a frequent count does not prove an expensive search.
- The idle attachment component path is not empty: it validates/casts its owner, clears a flag, and enables actor collision. Other branches handle held state, transform interpolation, and item state. Blanket tick disabling or interval increases could break gameplay.
- The current `CarItemEquipableActor.Get Vehicle` function does contain redundant pure work. Its 705-byte Blueprint body repeats two owner queries and a recursive parent vehicle query whose result already exists earlier in the same call, with no intervening state-changing operation.

Beyond Performance skips those duplicate statements and retains the calculated local values. It does not cache across frames, remove components, change collisions, reduce ticks, or alter RPC/save code. The guard validates the complete normalized function/control-flow signature and reflected operands. Unsupported code is left unchanged; restoration checks ownership before writing back.

This verifies unnecessary work in the current build. It does not establish which game update introduced it, nor that attachments dominate total frame time in every scene.

### Exploratory attachment results — excluded from headline claims

The original four-pass stationary comparison used **off → on → on → off**, with approximately 30 seconds captured per pass after settling. The pooled engine-delta results were:

| Setting | Frames | Average FPS | Median frame time | p95 frame time |
|---|---:|---:|---:|---:|
| Lookup optimization off | 1,714 | 28.57 | 31.68 ms | 65.63 ms |
| Lookup optimization on | 1,719 | 28.59 | 30.27 ms | 69.37 ms |

Even before rejecting the session as a final baseline, the average-FPS difference was negligible and tail metrics were mixed. These figures do **not** demonstrate an FPS or consistency improvement.

A separate repeated-lookup microbenchmark on 115 real actors executed 11,500 queries per pass. Off passes took **138 and 166 ms**; on passes took **128 and 142 ms**. Each pass includes Lua marshalling, and the timings vary. This is evidence about that artificial repeated-query workload, not representative gameplay FPS; it is not a headline result and should be rerun after a clean restart if reported as a final comparison.

## Extreme performance mode and grass

The installed Beyond Apocalypse mode was inspected directly. It already reduces LOD/render settings and pauses cloud Niagara simulation; it does more than hide grass. Its foliage discovery uses a bounded initial pass and object/change events, rather than repeatedly scanning every mesh.

For non-colliding placed/PCG ground cover, the foliage feature calls `SetVisibility(false)`. That suppresses visual rendering but does not itself stop PCG generation, component registration, collision bookkeeping, or unrelated world work. The first inventory found **1,296 `SLLandscapePCG` actors and 1,296 PCG components**. A later detailed inventory covered **1,305 actors across eight foliage layers** and reported **zero enabled actor ticks and zero enabled PCG-component ticks** in every layer. All eight also reported `generated=0`; that is an inspected state/count, not a timed measure of all generator work. The snapshots contain different object counts and must not be presented as one identical inventory.

This narrows the suspicion: the inspected scene did not have an enabled per-frame PCG/landscape-actor tick to eliminate. It does not exclude asynchronous generation, registration, rendering, or other event-driven work. The testers' “grass disappears without higher FPS” report remains plausible, but its precise cause has not been isolated in a clean grass-only comparison. Engine pacing and busy game-thread work are verified alternative limits in this scene. Beyond Performance does not disable PCG or world generation wholesale: those systems also produce rock/cactus scenery and collision. It avoids duplicating the legacy mode's shadow/cloud ownership, which could cause repeated setting writes and incorrect restoration.

No measured grass-related FPS improvement is claimed by this build.

## CPU/GPU workload investigation

Normal read-only process access and the local matching game PDB exposed engine timing globals. `SecondsPerCycle` and `SecondsPerCycle64` both read **1×10⁻⁷ seconds**, matching Windows' **10 MHz** performance counter. The external collector recorded sampled game/render/GPU durations, frame-counter increments, process CPU/memory, and process-specific Windows GPU engine counters.

These engine values are asynchronous workload observations and may include waits or delayed GPU results. Sampled GPU milliseconds are not equivalent to GPU utilization. Sampled timing percentiles must not be presented as per-frame p95 or 1% lows. PresentMon's ETW collection was unavailable with normal permissions in this environment; no elevation was used.

A separate **12.004-second clean-process stack sample** captured 241 snapshots each from six busy threads, **1,446 snapshots total**, with zero capture errors. It briefly suspended each target thread to copy its context and stack, resumed it immediately, and unwound the copied data afterward. The maximum observed suspension was **5.972 ms**; total summed suspension was **506.688 ms**. This intentionally perturbed scheduling, ran outside clean A/B capture windows, and is not an FPS benchmark. The earlier sample from the broadly instrumented process is excluded from current attribution.

| Thread/path | Observation |
|---|---|
| Game thread, TID 22824 | 78.62% of one logical CPU over the sample; 41/241 leaf samples inside UE4SS and 128/241 inside the game |
| Game thread wait | 43/241 samples in `UEngine::UpdateTimeAndHandleMaxTickRate` sleep/yield paths |
| Rendering thread, TID 5792 | 55.97% of one logical CPU; 101/241 samples in render-thread waits |
| Rendering media path | Bink draw/texture-upload functions appeared in 23/241 stacks; the later media experiment failed to show benefit |
| Sound setup | Five identical game-thread stacks followed `SpawnSoundAttached` → `UAudioComponent::PlayInternal` → `GetComponentsByInterface`; this is a recurring path, not a verified unnecessary operation |
| Audio worker | A busy worker used 35.41% of one logical CPU; ladder and one-pole audio filters appeared in 83/241 leaf samples. Audio/gameplay throttling was not justified |

The busy game thread and often-waiting render thread argue against labeling this scene “GPU limited” solely from the GPU timing global. UE4SS appeared somewhere in **184/241** game-thread stacks, including detour frames underneath ordinary game work. That inclusive count is **not 76% CPU cost attributable to UE4SS**. Wall-time stack proportions also contain waits; only the separate thread CPU counters measure CPU consumption. UE4SS and NVIDIA lacked matching private symbols, so their labels were nearest exports; reliable attribution there is to the module/RVA, not a particular exported function name.

### Diagnostic-hook confound

The available loader reference source shows that unregistering a Blueprint hook marks its callback index as removed but retains its function-lookup entry. The global Blueprint dispatch path still builds the function's outer-name vector and searches the registry before it checks whether callbacks are removed. The broad attachment probe registered many function paths earlier in the process.

The exact binary implementation has not been exhaustively matched against that reference source, but the source behavior and loader-heavy stacks were sufficient to reject the original process as a clean final baseline. Initial `attachments-abba` and `pixels-abba` captures remain exploratory only; one original pixel test also overlapped stack sampling. All comparisons in the clean-results table instead used a restarted process without that broad probe. No attempt was made to patch another mod or remove another mod's callbacks.

## Mouse response

The engine's mouse-smoothing setting was observed enabled. Beyond Performance can disable it and clear the local player's smoothing history while retaining sensitivity and bindings. Runtime checks confirmed that the flag changes and restores.

The optional render-ahead control sets `r.OneFrameThreadLag=0`; it is off by default because it may trade throughput for responsiveness. No physical mouse-to-display or click-to-photon measurement has been performed. Neither control is presented as a measured millisecond latency reduction.

## Functional validation completed

| Area | Result and scope |
|---|---|
| Native lookup guard | Native build completed; all 18 native guard/restoration checks passed, including rejection of mismatches and preservation of foreign changes |
| Deterministic Lua checks | Final Lua suite and syntax checks passed; includes engine-smoothing snapshot/restore, external-owner yield, invalid-engine guard, defaults, preserving explicit cap/VSync/fixed-frame controls, and DLSS pixel-budget ownership guards |
| Live lookup equivalence | Vehicle results matched for 115 live equipable actors; recorded tick and collision states stayed unchanged |
| Native interaction | One Lada door-window item completed detach and native primary-action reattachment with the feature off and on; original item and preference restored |
| Render/input options | Off/on/restore operations completed for mouse smoothing, render-ahead, pixel budget, shadows, clouds, and frame cap; clean ABBA also verified the engine frame-rate smoothing flag changed and restored. Overlapping legacy-mode settings can defer rather than mutate |
| F10 menu | Live UMG content created; Enter toggled/restored an option; all rows navigated/wrapped; input state restored; competing cursor overlay refused |
| Menu layout rendering | UMG rendered to textures at synthetic 1280×720 and 1536×864 geometry, both pages; these are not physical monitor screenshots or proof of every display/DPI combination |
| Installer | Ten fixture checks passed on Windows PowerShell 5.1 and PowerShell 7; final installer rerun also passed all ten. Coverage includes spaced paths, upgrades, settings/capture retention, other-mod/loader/mod-list preservation, corruption refusal, missing/mismatched runtime handling, uninstall backup, and running-game refusal |
| Standalone cold start | Main Steam executable started through the normal loader with Beyond Performance as the sole gameplay mod; startup log confirmed that configuration. The temporary loader-directory override was restored byte-for-byte to its original settings file |
| Standalone gameplay and menu | Vehicle results, tick states and collision states matched for 51 live equipable actors. All eight performance options and menu navigation/toggle/restoration/competing-overlay checks passed |
| Standalone native interaction | One Lada boot completed native detach and primary-action reattachment with attachment optimization both off and on; original item and preference restored |
| Built-in recorder | Standalone 30-second recording completed with 1,627 frames and wrote CSV plus metadata/statistics. Its 54.2 FPS and p95 29.0 ms validate recording functionality only; this was not an A/B comparison |
| Preference persistence | Nondefault `raw_mouse=false` survived a full process restart and the separate standalone test; the default `true` preference was restored afterward |
| Final combined-mod restart | Normal combined installation restarted successfully; equivalence/tick/collision checks passed for 54 live equipable actors, all eight options and menu checks passed |
| World-transition cleanup | A native transition to the main menu without saving closed the open F10 menu, finalized an active 100-frame partial recorder capture, restored the native attachment function, and restored the original engine-smoothing flag. Enabled preferences survived cleanup, then conservative defaults were restored for delivery |

The standalone run used the main Steam executable with a temporary separate mod directory containing Beyond Performance, rather than removing or editing sibling mods. Its native helper, gameplay options, F10 menu, interactions, and recorder worked without the other gameplay mods. Test dispatch code was present for automation and is excluded from the release. Restoring the normal loader configuration and repeating combined-mod validation confirmed the return path. The world-transition test exercised unload cleanup; its partial recorder output is functional evidence, not a performance comparison or a save/reload test. These checks support runtime independence; full remote host/client interaction, reconnect, save integrity across restarts, long-distance driving, and broader hardware coverage remain untested.

The standalone recorder used the normal positive cap `t.MaxFPS≈60.0448`, 50% render scale, and a 1536×864 viewport, with the optional frame-smoothing-disable feature off. Its **54.2 FPS** should not be compared to the explicit-cap-zero A/B values above: the launch configuration and scene differed, and no matched feature-off recording was taken.

## Coverage limits

Performance comparisons are complete within the scope and limitations above. This release has not established the following:

1. Visible foreground performance with controlled power policy, repeatable driving-route performance, save/reload integrity, remote multiplayer host/client and reconnect behavior, or performance on additional lower-end hardware. Local interaction tests do not supply that coverage.
2. A numerical physical input-to-display latency improvement. FPS, engine timing globals, and an input-setting flag do not measure it.

Beyond Performance has a verified redundant-work fix, tested local controls and standalone operation, and a measured frame-smoothing improvement reproduced in two specified clean sessions. Other features must be judged by their individual results and limitations rather than attributed that gain.

## Evidence index

Primary records are `attachments-clean-abba`, `pixels-clean-abba`, `pixels-capped-clean-abba`, `smoothing-clean-abba`, `smoothing-second-clean-abba`, `smoothing-capped-clean-abba`, and `menu-video-clean-abba`, each with CSV, setup, completion, and derived summary files. The “clean” filename describes the process/instrumentation designation; the camera-motion confound in capped smoothing is explicitly documented above. Periodic workload captures use the corresponding `*-clean-workload` prefix. `cpu-stack-clean-profile.json` and `cpu-stack-clean-report.txt` provide separate intrusive attribution, not benchmark timing. `detail-probe.txt` contains the later foliage-layer inventory. Functional records include `attachment-interaction-test.txt`, `runtime-validation.txt`, `standalone-cold-start.log`, `standalone-runtime-validation.txt`, `standalone-attachment-interaction-test.txt`, `persistence-test.txt`, `combined-final-runtime-validation.txt`, `final-travel-check.txt`, menu rendering logs/PNGs, and installer fixture `results.json` files. Final native/Lua/installer logs record successful checks. `benchmark-20261107-175819.csv` and `.txt` are the standalone recorder check, not a feature comparison.

The release evidence index distinguishes raw observations, derived metrics, synthetic menu renders, and rejected experiments. Earlier confounded captures and full game assets/binaries/PDBs are excluded. Diagnostic call counts and the old repeated-lookup microbenchmark above describe development investigation only and do not establish a final FPS effect.
