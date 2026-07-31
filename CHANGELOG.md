# Changelog

## Unreleased

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
