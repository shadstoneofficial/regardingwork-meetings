# Changelog

## 0.1.5 Beta Candidate (build 6) - 2026-10-10

- Detect system stalls/incompatible buffers and attempt at most three safe tap
  rebuilds during an already visible recording. Quiet with live buffers does
  not restart; storage write failures halt instead of looping.
- Finalize and preserve each earlier CAF. New capture uses exclusively reserved
  numbered system files and records them before capture begins. Stop/quit
  cancels pending recovery; callbacks cannot write into a closed/new segment.
- Merge all captured system segments at their original offsets, preserve failed
  attempts, and keep unavailable started segments retryable. Recovery includes
  every registered segment and preserves the original sidecar.
- Display persistent SYS!, CHECK SYS and SYS GAP labels beside the red recording
  indicator. Distinguish successful inference from potentially incomplete
  capture in the menu, notification, Markdown banner and canonical JSON.
- Add About/version menu and app build/source, macOS version, output route
  history, successful-buffer endpoints, frame counts and capture gaps to private
  metadata/manifests. Correct interleaved system-buffer signal detection.
- Add synthetic long-session stall, bounded recovery/cancellation, preservation,
  permissions, segmented inference/retry/recovery and warning/version tests.
- Keep local Parakeet, AAC-in-CAF, original audio, attribution, privacy/consent,
  retention and playback-echo defaults unchanged. Real route/long-meeting,
  permission, inference and abrupt-exit tests remain mandatory before trust.
  This is an unmerged beta candidate, not a stable/reliability guarantee.

## 0.1.4 Beta Candidate (build 5) - 2026-10-04

- Keep failed inference, missing, empty and unreadable audio unfinished and
  retryable instead of creating false completion markers.
- Retain successful per-track output in private checkpoints and reuse it on
  retry. Partial reports are labelled separately; existing final transcripts
  and original audio are never automatically replaced.
- Retain historical health, digital-zero evidence and observed microphone routes
  during recovery. Derive duration from persisted buffers/readable audio, not
  relaunch time; unknown duration is not invented.
- Keep health/timing monitoring active while menus are tracking, and show the
  current default microphone without clearing degraded health on route change.
- Count each committed restart-gap chunk once and invalidate scheduled
  configuration retries on stop.
- Add injected-engine, recovery, continuity and synthetic run-loop regressions.
- Bound notarization requests and poll retries, keep diagnostics private, support
  external build/temp storage and embed the exact source commit in the app.
- Preserve AAC-in-CAF, local Parakeet and existing playback-echo defaults. Abruptly
  interrupted AAC can still be unreadable; real-device/inference/crash testing
  remains mandatory. Published as a prerelease and source merged on 2026-10-10;
  it is not a stable release.

## Unreleased

- Set the next signed development artifact identity to version 0.1.3 (build 4).
- Add the conventional Applications shortcut to signed DMGs and generate a
  portable checksum that does not expose the build machine path.
- Distinguished exact zero-filled microphone buffers from ordinary quiet,
  automatically rebuild the raw microphone input once, and preserve the failed
  attempt for diagnosis.
- Show **CHECK MIC** until microphone liveness is established and retain a
  prominent **MIC!** indicator for digital silence, route changes, stalls, or
  failures.
- Display and persist the selected macOS default microphone identity, detect
  route changes, and document the verified zero-filled-buffer incident and
  hardware test matrix.
- Restart microphone capture after call-app input reconfiguration while
  appending to the same CAF, preserving earlier audio and timestamp alignment.
- Added a menu action to retry all unfinished local transcriptions without
  restarting the app. Completed transcripts and original audio are preserved.
- Added a Welcome & Setup window that appears by default and remains accessible
  from the menu bar or by reopening the running app.
- Replaced the generic waveform menu-bar icon with a distinct monochrome
  **RW** monogram so Meetings is easy to distinguish from Dictate.
- Added blue local-transcription and orange transcription-failure menu-bar
  states; active recording remains the highest-priority red state.
- Changed the default recording root to `~/RegardingWork Meetings`. The former
  `~/RegardingWork/Meetings` default is preserved and scanned for interrupted
  or unfinished sessions without automatic moves or deletion.
- Added microphone permission status/request, System Audio settings guidance,
  on-device model preparation, recordings-folder access, consent/privacy
  guidance, and a Start Test Recording action.
- Keep the setup window available even when startup checks need attention, so a
  denied permission no longer makes the app disappear before showing recovery
  guidance.
- Rebranded the package, target, executable, CLI, menu, permissions, paths,
  LaunchAgent, logs, bundle, packaging, docs, and assets as RegardingWork
  Meetings.
- Added a proper `com.regardingwork.meetings` app bundle and local Developer ID
  signing/notarization tooling without release publication.
- Added user-only modes for recording directories and session artifacts.
- Added visible per-track buffer/signal/failure health and a reliable red
  recording symbol.
- Added atomic in-progress manifests and conservative interrupted-session
  recovery that preserves readable tracks and recovery evidence.
- Added explicit two-track attribution language and conservative playback-echo
  detection. Canonical JSON and original audio retain suppressed Markdown
  segments.
- Replaced shell-string `on_stop` with an opt-in executable/argv array.
- Added configuration, identity, health, manifest, recovery, transcript,
  ordering, duplicate detection, permissions, and hook tests.
- Kept Parakeet local transcription as the only shipped engine. Whisper and
  multilingual alternatives remain future options.
