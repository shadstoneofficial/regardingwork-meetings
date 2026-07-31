# Changelog

## Unreleased

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
