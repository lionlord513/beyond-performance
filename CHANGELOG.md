# Changelog

## 1.1.0

- Added an independent Beyond Mod Manager release feed, package metadata and checksums; no dependency or load-order requirement involving another gameplay mod.
- Made the frame recorder checkpoint its CSV every two seconds. Interrupted captures retain their completed frames and remain explicitly marked partial. Added frames over 100 ms and ending settings to the report.
- Clarified that reducing render-ahead can worsen throughput and stutter. It remains optional and off by default.
- Fixed pixel-budget ownership when dynamic resolution activates after the option: restore only the still-owned scale and yield, matching existing DLSS protection.
- Added foreground driving investigation, including native car entry and a measured 137 km/h run. See MEASUREMENTS.md for results and limitations.

## 1.0.0

- Added guarded removal of duplicate within-call attachment lookups, local mouse/render controls, persistent settings, F10 utility menu, frame recorder and standalone installer.
- Initial tests demonstrated an offscreen unlimited-cap smoothing effect, but did not establish improvement at the normal cap. Historical measurements are retained in docs/MEASUREMENTS-1.0.0.md.
