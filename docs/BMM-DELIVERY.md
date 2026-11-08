# Beyond Mod Manager and release delivery

Beyond Performance uses its own public release feed at `lionlord513/beyond-performance`. It has no dependency or required load order involving another gameplay mod. UE4SS is its only declared dependency.

With the game closed, choose **Add mod ZIP** in Beyond Mod Manager and select `BeyondPerformance-VERSION-standalone.zip`. Review the preview and install. BMM supplies the bundled loader only when needed, retains existing loader files, and records Beyond Performance's version and archive digest. A pre-existing manual installation must be reviewed and adopted through BMM before the manager owns it. Use one installation method for later updates and removal; do not mix the separate PowerShell uninstaller with a manager-owned installation.

After the first import, BMM's update check uses the mod's own feed. The manager reads GitHub releases anonymously, validates the release tag and `bmm-mod.json`, then verifies the selected ZIP's size and SHA-256 against both release metadata and `SHA256SUMS.txt`. Matching installed versions and hashes do not repeatedly prompt for updates. The current manager's built-in catalog is unchanged; the initial entry is added by importing the ZIP.

Both package variants contain one `BeyondPerformance/bmm.json`. The update asset is the standalone ZIP so a fresh install can obtain the tested shared loader; existing loader files remain untouched. The mod-only ZIP can also be imported when UE4SS is already installed. Preferences, backups, captures and state are retained during manager updates. Benchmark files created after installation are unowned user files, so they are also retained on removal.

## Reproduce the release checks

Use Python 3 with `lupa`, Zig, PowerShell and the shipped Beyond Mod Manager 1.0.8 executable. The actual loader bundle must match the fingerprints in `tools/package.py`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/Build-Release.ps1 -Python python -Zig zig -Manager 'C:\Tools\Beyond Mod Manager.exe' -Output 'C:\Releases\BeyondPerformance-1.1.0'
```

The build runs Lua 5.4 checks, native ownership tests, installer fixtures, and integration tests against the actual manager assembly. The manager tests write only disposable fixture directories and never run the game or the manager UI. They cover fresh install, update, native helper installation, version/feed identity, enable/disable, uninstall/reinstall, settings/capture retention, sibling file protection and rejection of conflicting release hashes. Results are saved in `work/bmm-results.txt`; the release directory receives `validation.json` binding the successful checks to the final artifact hashes.

Runtime gameplay and frame-time measurements are a separate release requirement. These fixture tests cannot establish FPS improvements, multiplayer behavior or native game compatibility.

## Publish the reviewed version

Keep this project in its own Git repository on a committed, clean `main` branch. Set the same version in runtime code and `bmm.json`, build and validate the final artifacts, then inspect the release plan:

```powershell
python tools/publish_release.py --artifacts 'C:\Releases\BeyondPerformance-1.1.0'
```

The default command has no remote side effects. After final review, add `--publish --manager 'C:\Tools\Beyond Mod Manager.exe'`. It uses existing GitHub authentication without displaying credentials, creates the public repository only if absent, pushes the clean source, and stages a draft release. Every uploaded artifact must return a matching server digest and size before publication. Existing releases are never overwritten. Finally, the actual BMM updater performs anonymous discovery, verified download and fixture installation of the published ZIP.

The release contains the standalone ZIP, mod-only ZIP, source ZIP, `bmm-mod.json`, and archive-level `SHA256SUMS.txt`. Package-internal `SHA256SUMS.txt` files cover extracted files; the release-level file covers the downloadable archives. No account credential, personal settings, save, game executable or other gameplay mod belongs in any artifact.
