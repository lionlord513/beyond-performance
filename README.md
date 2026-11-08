# Beyond Performance 1.1.0

Beyond Performance is a standalone performance utility for **Drive Beyond Horizons**. It removes verified duplicate attachment lookups, provides local rendering and mouse-response controls, and records frame-time samples for comparison.

**The near-constant 60 FPS target has not been achieved.** A foreground, fixed-view comparison of normal render-ahead versus the enabled reduced-render-ahead option measured **44.46 → 49.96 FPS**, with p95 **46.23 → 36.19 ms**. Individual passes varied substantially; this short result is not a guaranteed gain. Leave **Reduce render-ahead** off when troubleshooting low FPS. Disabling mouse smoothing is a separate control.

A fully foreground diagnostic drive reached 137 km/h but averaged only 24.27 FPS. A later drive with normal render-ahead averaged 42.78 FPS but used a different car/route, reached only 53 km/h, and had mixed foreground coverage; it is not a before/after comparison. Severe hitches remain. An extra rendering-command thread worsened a clean comparison and was rejected. See [MEASUREMENTS.md](MEASUREMENTS.md).

Version 1.1.0 adds its own Beyond Mod Manager update feed, crash-resilient frame recording, and dynamic-resolution ownership protection. The guarded attachment optimization remains; no attachment FPS gain is claimed.

The target inspected during development is Steam build **26437602**, Unreal Engine **5.2**, with the tested UE4SS **3.0.1 Beta #0 / Git 8f7b2ca3** loader. The attachment feature checks the actual loaded function and its reflected operands before applying; an unsupported signature leaves the game function unchanged.

## Install through Beyond Mod Manager

Close the game, choose **Add mod ZIP**, select `BeyondPerformance-1.1.0-standalone.zip`, and install. After import, the manager checks this mod's own [GitHub releases](https://github.com/lionlord513/beyond-performance/releases) for updates and verifies downloaded sizes and SHA-256 hashes. Its only declared dependency is the shared UE4SS loader. Existing settings and captures are retained. A manual installation must be adopted/replaced through the manager before it owns updates; review the import preview. See [manager delivery details](docs/BMM-DELIVERY.md).

## Alternative PowerShell installation

1. Close Drive Beyond Horizons and extract the entire package into a new folder.
2. Open PowerShell in that folder and run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   ```

   The default game folder is `C:\Program Files (x86)\Steam\steamapps\common\Drive Beyond Horizons`. For another library, specify its actual game folder:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Drive Beyond Horizons'
   ```

3. Start the game, load gameplay, and press **F10**.

Use the **standalone** package when UE4SS is missing. It supplies the tested shared loader where files are absent. Use the **mod-only** package with an existing compatible UE4SS installation. Neither requires Beyond Apocalypse, Beyond Tuning, Beyond Detours, MixTape Maker, or any other gameplay mod.

The installer preserves existing loader files, UE4SS settings, `mods.txt`, other mods, and saves. It installs this mod through its own `enabled.txt`. An existing `BeyondPerformance : 0` entry is respected and must be enabled manually if you want the mod to run. Custom UE4SS mod-directory configurations require the manual procedure in [INSTALLATION.txt](INSTALLATION.txt).

## F10 controls

Use **Up/Down** to select a row, **Enter** to change it, and **Esc/F10** to close. The menu has two pages and advances as you move through the rows. It is keyboard operated. It refuses to take input from an existing game menu, chat, or cursor overlay.

| Option | Default | Behavior |
|---|---|---|
| Remove duplicate attachment lookups | On | Reuses values already calculated inside the same native Blueprint function call. Attachment ticks, interaction timing, physics, and replication continue normally. |
| Disable mouse smoothing | On | Turns off the engine smoothing filter and clears its history. Sensitivity and action bindings remain unchanged. This is not a measured latency guarantee. |
| Reduce render-ahead (can lower FPS) | Off | Sets `r.OneFrameThreadLag` to zero. It can reduce queued work but may also lower FPS; compare both settings. |
| Disable engine frame-rate smoothing | Off | Removes the engine's adaptive FPS ceiling through `GameEngine.bSmoothFrameRate`. Explicit FPS caps, VSync, and fixed-frame settings remain unchanged. May increase power use or make frame pacing less even. |
| Reduce rendered pixels | Off | Uses 75% of the current render scale in each dimension, with a lower limit of 25%. The scene becomes softer; menu resolution stays unchanged. DLSS and dynamic resolution must be off; the option yields if DLSS or dynamic resolution takes control later. |
| Disable dynamic shadows | Off | Disables shadow rendering. Defers to Beyond Apocalypse when that mod's performance component is installed. |
| Disable volumetric cloud and fog rendering | Off | Disables those volumetric rendering passes without changing the game clock or weather state. Defers to Beyond Apocalypse when its performance component is installed. |
| Limit frame rate to 60 FPS | Off | Caps at 60 FPS, retaining a lower existing cap. It cannot make a scene that runs below 60 FPS faster. |

The status line reports whether a feature applied, deferred to another setting owner, or was unavailable. Shadow/cloud rows display **DEFERRED** when Apocalypse owns those controls. An enabled preference expresses the requested setting; check the status when a compatibility guard prevents its application.

Settings are stored in `ue4ss\Mods\BeyondPerformance\settings.ini`. Turning an option off restores its previous transient value when Beyond Performance still owns that value. If the game or another mod changes it, Beyond Performance yields instead of repeatedly forcing its own setting. Changes are not written into the game's graphics/input configuration.

**Restore Beyond Performance defaults** enables duplicate-lookup removal and disables mouse smoothing. Every other option is off, including **Disable engine frame-rate smoothing**, which restores the game's prior smoothing flag when still owned. Available defaults are applied and saved; unavailable features are reported. This is not an “all features off” button.

## Record a comparison

Choose **Record a performance sample**. The menu closes, waits three seconds, and records approximately 30 seconds of local player frames. Results are saved beside `settings.ini` as `benchmark-*.csv` and `benchmark-*.txt`.

Use the same save, camera or route, weather/time, graphics settings, resolution, and warmed-up scene. Change one option at a time. Repeat **off → on → on → off** and compare all runs; do not select only the fastest result. Keep the menu closed during capture. Start a fresh game process after broad development instrumentation before making a final comparison.

The capture includes game-provided frame delta and callback intervals, average FPS, median/p95/p99 frame time, a defined 1% low, and hitch counts. It is a local gameplay timing sample, not a display-present trace or mouse-to-screen latency measurement. Capture metadata explains the definitions and limitations. The CSV is checkpointed every two seconds. A crash retains completed checkpoints with a sidecar marked incomplete; at most the pending buffer may be lost. World changes finalize partial results. Reports also count frames over 100 ms and record ending settings.

## Independence and compatibility

All runtime code and the native helper are inside `BeyondPerformance`. No sibling mod is imported, executed, patched, or required. The attachment optimization changes only verified in-memory instructions in the game's pure vehicle-lookup function; it does not edit game assets on disk or reduce attachment tick frequency. Unsupported or conflicting instructions are left alone.

The shadow/cloud controls detect the presence of Beyond Apocalypse's performance component and defer for the entire combined installation, including extreme-mode transitions. Beyond Performance does not toggle that mod or alter its preferences. Its own remaining controls continue to operate independently.

Live combined-mod checks matched vehicle results for 115 equipable actors with tick/collision state unchanged, and completed native detach/reattach with lookup optimization off and on. A separate normal-loader start with Beyond Performance as the only gameplay mod passed equivalent checks for 51 actors, a Lada boot detach/reattach cycle, all eight options, F10 navigation/restoration, and the built-in recorder. A final combined-mod restart passed 54-actor and menu checks. A nondefault preference survived a full restart. Transitioning to the main menu closed the utility menu, finalized a partial sample, and restored attachment and engine-smoothing changes. Second-pass driving observations are documented separately. Full remote host/client, long-duration driving, and save-integrity validation remain untested; these checks are not a general multiplayer certification.

## Upgrade or remove

Run the new installer with the game closed. It retains `settings.ini`, benchmark captures, and this mod's data, and backs up the previous Beyond Performance folder under `DriveBeyondHorizons\Binaries\Win64\BeyondPerformance-backups`.

To remove the active mod:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -GamePath 'YOUR GAME FOLDER'
```

Uninstall moves only Beyond Performance into its backup directory, retaining preferences and captures. The shared loader and other mods remain installed. Restarting the game without Beyond Performance removes its transient changes. Do not replace native files or hot-reload this mod while the game is running.

## Build from source

The runtime Lua files are shipped as source. The native helper requires a Windows x64 build; development used Zig **0.14.1**. Packaging requires Python **3.11 or newer** and its standard library. The Lua tests additionally require the `lupa` Lua 5.4 binding; `--lupa-path` accepts an existing installation.

From the source directory:

```powershell
pwsh -NoProfile -File .\build-native.ps1 -Zig 'C:\Tools\zig\zig.exe'
python .\tests\run.py
python .\tools\test_install.py
python .\tools\package.py --output .\build --source-zip
```

The installer tests use disposable fixture folders and do not launch the game. The packager checks the tested runtime fingerprints and omits personal settings, captures, state, symbols, and intermediate build files. Add `--mod-only` for a package without loader binaries, or `--stage-only` to inspect the package before creating a ZIP. `--runtime-source` selects the tested game's `Binaries\Win64` directory. Use a new output directory if a staging folder already exists.

The package includes `package-manifest.json`, `SHA256SUMS.txt`, installation scripts, and the runtime source/license notice. UE4SS's MIT license accompanies the standalone loader. No game executable, PDB, game content, or other gameplay mod is redistributed.

## Source inventory

Runtime Lua modules are under `mod/BeyondPerformance/Scripts/`.

| File or group | Purpose |
|---|---|
| `main.lua` | Startup, local-controller selection, preferences, and map/shutdown cleanup. |
| `render.lua` | Mouse, render-budget, and engine frame-rate smoothing controls with owned-value restoration. |
| `attachments.lua`, `attachment_symbols.lua` | Reflected function checks and the native helper's lifetime. |
| `ui.lua`, `settings.lua` | F10 utility menu and validated persistent preferences. |
| `benchmark.lua` | Temporary local frame capture, statistics, and CSV/metadata export. |
| `native/attachments.c`, `native/attachment_guard.h` | Guarded in-memory duplicate-lookup optimization. |
| `tests/run.py`, `tests/run.lua`, `native/test_attachments.c` | Reproducible Lua checks and native guard tests. |
| `tools/` | Installer, removal, packaging, and disposable installation tests. |
