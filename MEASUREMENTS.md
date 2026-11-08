# Beyond Performance 1.1.0 — second-pass measurements

**Near-constant 60 FPS was not achieved.** The release corrects the tested machine's reduced-render-ahead preference, improves recorder reliability and setting ownership, and adds independent manager updates. It does not claim to eliminate streaming, directional or physics hitches.

## Repeatable foreground comparisons

Main Steam build 26437602, UE 5.2, DX11; i5-13420H, 16 GB RAM, RTX 3050 Laptop 4 GB. Installed Apocalypse, Tuning, Detours and MixTape Maker remained present and unchanged. Chrome was closed; Discord remained open by request. Apocalypse extreme mode was active. Render scale 37.5%, explicit cap approximately 59.59 FPS, VSync off, frame-rate smoothing disabled. Comparisons used the same loaded world, stationary player and camera within each experiment. All external samples were foreground.

Each run used four 12-second phases in A–B–B–A order, excluding the first two seconds of each phase as settling. Remaining hitches were retained. Samples are local player game deltas; FPS is sample count divided by summed deltas, percentiles are nearest rank. These are not display-present or physical mouse-latency measurements. Read-only workload sampling ran concurrently; no stack suspension, build or broad hook probe overlapped these comparisons.

| Experiment | A pooled FPS / p95 | B pooled FPS / p95 | Decision |
|---|---:|---:|---|
| Extra rendering-command thread: A off, B on; normal render-ahead in both | 56.47 / 23.80 ms | 48.63 / 34.46 ms | Rejected; original thread state restored; no such option shipped |
| Render-ahead: A reduced overlap (`r.OneFrameThreadLag=0`), B normal overlap (`=1`) | 44.46 / 46.23 ms | 49.96 / 36.19 ms | Saved reduced-render-ahead off on the tested installation; still optional/off by default |

Individual phases must be considered: the thread experiment measured **58.79, 45.55, 51.70, 54.15 FPS**. The render-ahead experiment measured **38.61, 54.31, 45.60, 50.28 FPS**. The latter has overlapping phase results and substantial drift; its pooled +12.4% is a short-run observation, not a robust general gain estimate. Frames over 50 ms fell from 39 to 7 in equal approximately 20-second measured windows, but this also needs longer replication. No new uniform 60 FPS claim follows.

The first experiment's camera remained fixed throughout. In the second, slight mouse movement occurred during the initial excluded settling period; every measured frame had identical player position and sampled camera yaw/pitch. The two experiments used different view angles and must not be pooled together. Native read-only flags confirmed the separate RHI thread changed only in its intended phases; a console-variable query cannot verify that console command.

## Driving and remaining failures

| Capture | FPS | p95 / p99 | >100 ms | Maximum speed | Limits |
|---|---:|---:|---:|---:|---|
| Rotor GT7, reduced render-ahead | 24.27 | 93.54 / 138.23 ms | 59 | 137.46 km/h | 100% foreground; diagnostic stack sampling overlapped part of run |
| Kaiju G54, normal render-ahead | 42.78 | 38.20 / 56.79 ms | 5 | 53.24 km/h | Different car/route; external 65-second window 81.25% foreground; no stack sampling |

Each player trace lasts approximately 60 seconds. The later trace's maximum hitch was **332.46 ms**, and its controller pawn stayed valid. It is not a matched speed/physics comparison, and cannot establish a mod FPS gain or smooth high-speed driving. The user reported the later car was slower. Subsequent stopped-car checks found normal global/custom time dilation (1.0), handbrake off and an idle engine. No throttle, gear, seat, power or physics changes were made by this test. Idle torque readings cannot diagnose the earlier acceleration complaint; its cause remains unresolved.

The profile identified render-fence waits, world tick/task waits, Blueprint work, native foliage maintenance and Chaos physics. Bad periods persisted after disk reads/paging subsided. No single periodic three-second cause or physics-only explanation was established. See [driving investigation](docs/DRIVING-INVESTIGATION.md) for attribution, existing streaming budgets and rejected experiments, including the earlier invalid-pawn QA crash. That direct-seating fixture was discarded and is not included in the mod.

## What changed and what was validated

- The tested installation now retains normal render-ahead while retaining disabled mouse smoothing. New installations already default reduced-render-ahead off. The F10 wording makes its FPS tradeoff explicit; upgrades retain user preferences.
- The frame recorder checkpoints every two seconds, preserves partial crash data, counts >100 ms frames and records final settings. Lua tests verify data exists before finalization, a 2.1-second hitch survives, cleanup occurs and ending preferences are reported.
- Pixel budget now yields when dynamic resolution becomes active after application. Tests verify restoration of only still-owned scale, rejection while dynamic resolution is active and preservation of externally changed scale. Existing DLSS behavior is retained. No FPS increase is claimed for this compatibility fix.
- Independent BMM metadata, release digest/size checks, package building and tests use the actual shipped BMM 1.0.8 assembly. `validation.json` binds release artifact hashes to the native, Lua, installer and BMM checks. The public release is additionally checked through anonymous BMM discovery/download/fixture installation.
- The attachment algorithm, native guard, F10 layout/input behavior and gameplay-sensitive systems are unchanged from 1.0.0. Historical standalone/combined menu, attachment interaction, persistence and world-transition checks remain in [the original validation report](docs/MEASUREMENTS-1.0.0.md). No other mod is patched or required. Full remote multiplayer, reconnect and long-term save integrity remain untested.

## Evidence

`evidence/` contains the two foreground comparison CSV/setup/completion/analysis records and the two driving traces/context summaries. Raw frame hitches are retained. Mixed-focus/moving experiments are documented as exclusions. Game binaries, symbols, saves, other mods, credentials and full crash dumps are not redistributed. The historical offscreen unlimited-cap smoothing result is documented separately and does not substitute for foreground driving proof.
