# Beyond Performance 1.1.1

Adjust performance settings and record frame-rate samples in Drive Beyond Horizons. Press **F10** to open the menu.

Performance gains vary. This mod does not guarantee 60 FPS, and driving stutter remains. See MEASUREMENTS.md for the recorded results.

## Install

Close the game. In Beyond Mod Manager, choose **Add ZIP**, select the standalone ZIP and install. Future updates appear in BMM.

For manual installation with UE4SS already installed, copy the package's `BeyondPerformance` folder into `DriveBeyondHorizons/Binaries/Win64/ue4ss/Mods`. Keep your existing `settings.ini` and benchmark files when updating.

Without UE4SS, extract the standalone ZIP and run the included Install.ps1 as described in INSTALLATION.txt. The standalone installer adds missing loader files. The mod-only ZIP requires UE4SS. No other gameplay mod is required.

## Controls and options

Use **Up/Down** to select, **Enter** to change an option and **Esc/F10** to close.

| Option | Default | Effect |
|---|---|---|
| Optimize vehicle attachments | On | Reduces repeated work for vehicle attachments. Unavailable on unsupported game versions. |
| Disable mouse smoothing | On | Turns off mouse smoothing. |
| Reduce render-ahead | Off | May reduce input delay, but can lower FPS or cause stutter. Leave off when troubleshooting low FPS. |
| Disable engine frame-rate smoothing | Off | Removes automatic frame-rate smoothing. May increase power use or stutter. FPS caps and VSync still apply. |
| Reduce rendered pixels | Off | Lowers render resolution for a softer image and less GPU load. Requires DLSS and dynamic resolution to be off. |
| Disable dynamic shadows | Off | Removes dynamic shadows. With Beyond Apocalypse installed, use its Extreme Performance Mode. |
| Disable volumetric cloud and fog rendering | Off | Removes volumetric clouds and fog. With Beyond Apocalypse installed, use its Extreme Performance Mode. |
| Limit frame rate to 60 FPS | Off | Caps FPS at 60, or keeps your lower cap. Does not raise FPS in slow scenes. |

Check the status line if a setting is unavailable. DEFERRED means another setting or mod controls that option.

Turning an option off restores its previous value unless the game or another mod has since changed it. **Restore Beyond Performance defaults** returns to the defaults listed above; it does not turn every option off.

## Record a comparison

Choose **Record a performance sample**. The menu closes, waits three seconds and records about 30 seconds. Results are saved as `benchmark-*.csv` and `benchmark-*.txt` in the mod folder.

Use the same view or route and graphics settings. Change one option at a time and repeat both settings. A crash or world change may leave a partial recording. Results measure game frame times, not mouse-to-screen delay.

## Remove

Close the game and uninstall through BMM if it manages the mod. For a script installation, run Uninstall.ps1 as described in INSTALLATION.txt. It moves the mod, settings and captures into BeyondPerformance-backups. Shared UE4SS files remain installed.

## Source

Tested against Steam build 26437602 with UE4SS 3.0.1 Beta. Build the native helper with build-native.ps1, run tests/run.py, and package with tools/package.py. Development details and measurements remain in the source and MEASUREMENTS.md.
