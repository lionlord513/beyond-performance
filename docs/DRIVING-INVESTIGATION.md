# Foreground driving investigation — November 7, 2026

## Reproduced failure

The normal-entry 60-second driving capture recorded **24.27 FPS**, **93.54 ms p95**, **138.23 ms p99**, **210.50 ms maximum**, **313 frames over 50 ms**, and **59 frames over 100 ms**. The car reached **137.46 km/h**. Every external workload sample was foreground. This demonstrates the reported problem; it does not demonstrate near-constant 60 FPS.

The test used the main Steam build 26437602, DirectX 11, the installed Beyond Apocalypse, Beyond Tuning, Beyond Detours and MixTape Maker mods, and Beyond Performance 1.0.0 with its QA dispatcher. The PC has an i5-13420H, 16 GB RAM and RTX 3050 Laptop GPU with approximately 4 GB dedicated memory. Chrome was closed. Discord remained open at the user's request. Apocalypse extreme mode was active. Beyond Performance's low-latency, frame-smoothing-disable and pixel-budget settings were enabled; rendered scale was 37.5%, explicit cap approximately 59.59 FPS. The user spawned/entered the RotorGT7 through normal gameplay and drove it. No scripted pawn, seat, camera, velocity or input manipulation was used in this successful run.

The run included a separate 12-second diagnostic stack sample about 21–33 seconds into driving. Its 726 thread snapshots briefly suspended each thread before copying its context: maximum single suspension 2.20 ms, total across threads 119.46 ms. It is therefore diagnostic evidence, **not a clean before/after benchmark**. The native frame trace contains every observed hitch, without outlier removal. Engine player deltas are not display-present timestamps.

## What the profile supports

- The main thread used 63.79% of one logical core during the stack window. Of 121 snapshots, 29 contained a render-command fence wait and 15 contained world tick-group/task-completion waits. These are wall-time observations, not percentages of CPU cost.
- Rendering, Blueprint work, attachment traversal, native foliage maintenance and Chaos vehicle/collision work were all observed. Physics is present but has not been isolated as the dominant cause. No physics, collision, attachment tick, replication or save throttling is justified by these data.
- The rendering thread used 33.07% of a core and was often waiting. GPU timing globals contain synchronization and delayed results; they are not pure GPU execution measurements. Windows' sampled busiest game GPU engine had a median 23.27% utilization. Neither observation alone proves a GPU bottleneck.
- System available memory stayed approximately 2.35–2.46 GiB. Median game dedicated GPU allocation was 3,715.8 MiB; shared allocation was about 88.1 MiB. These are allocations, not proof of VRAM paging.
- The 35–50 second section was particularly bad: five-second bins measured 19.04, 16.95 and 14.49 FPS. Average process reads in those bins were only about 1.1–1.6 MiB/s and system paging had subsided. Streaming reads or low free RAM cannot explain the entire failure. Some other intervals did contain read bursts; process reads include cached/device I/O and system paging includes other apps.
- A reliable recurring three-second cause was not established. Several sibling mods have periodic work, but their interval alone does not establish causality. Their code and preferences were not patched.

## World and foliage investigation

The game already exposes budgeted native generation: foliage calculations/updates were limited to two, terrain mesh publishing to 1.5 ms, item work to 0.35 ms and roadside spawning to 1 ms. Those are existing game settings, not improvements supplied by this mod. Native foliage maintenance still appeared in CPU samples even though the inspected PCG component/actor ticks were disabled. Hiding grass therefore does not imply elimination of all generation/registration work.

Collision-bearing terrain, cactus/rock foliage and streamed gameplay objects share these systems. Disabling them wholesale, delaying collision readiness or making collidable scenery invisible would violate gameplay preservation. No measured grass-only improvement was established. Details of the original attachment and grass investigation remain in MEASUREMENTS-1.0.0.md.

## Excluded experiments and crash

Earlier background render-ahead tests suggested a benefit from normal pipeline overlap, but they were not foreground proof. A mixed-focus repetition also included a newly spawned car. An isolated car-spawn comparison fell from 51.57 to 43.73 FPS, but was background, lacked reversal, and changed the scene; it cannot identify physics cost.

A subsequent direct-seating QA experiment crashed with `AItemSaverState::FindAuthorityWatcher: No valid controlled Pawn found` in ItemSaverState.cpp line 432. This was an assertion, not an out-of-memory report. The QA code had bypassed normal seat entry and may have left controller/pawn ownership inconsistent. The experiment was rejected and is excluded from the mod and release. A nearby Beyond Detours log line does not establish that mod caused the crash. The successful run above used a fresh process and normal user entry.

The first six-phase rendering comparison also contained camera/player movement and only 66% foreground coverage. Its pooled timing differences are excluded from causal performance claims. Actual native flags confirmed that the RHI command enabled a dedicated rendering-command thread, whereas querying it as a numeric console variable did not report its state.

## Evidence identifiers

`native-entry-drive.csv`, `native-entry-drive-context.txt`, the corresponding external workload/meta/summary files, `native-entry-drive-stacks-report.txt`, `native-entry-drive-stacks-waits.txt`, and `native-entry-drive-hitches.json` contain the successful driving investigation. `pipeline-abc-cba` is the excluded moving/mixed-focus experiment. Full game binaries, PDBs, saves, crash dumps and personal application details are not redistributed.
