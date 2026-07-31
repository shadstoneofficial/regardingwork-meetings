# Repository instructions

## Identity and scope

This repository is RegardingWork Meetings, part of RegardingWork Voice. It is
separate from RegardingWork Dictate. Never modify a Dictate repository as part
of work here.

Runtime identity:

- executable: `regardingwork-meetings`
- Swift target: `RegardingWorkMeetings`
- bundle and LaunchAgent: `com.regardingwork.meetings`
- recordings: `~/RegardingWork/Meetings`

Quill and Digimata names may appear only in original licensing, upstream
attribution, upstream remote documentation, or migration history. Never rewrite
the root MIT license or upstream Git history.

## Product guardrails

- Keep recording and transcription local by default.
- Do not add cloud transcription, Railway, analytics, telemetry, SSO, sync,
  summarization, or external AI processing.
- Keep Parakeet as the shipped engine unless an approved product decision says
  otherwise. Whisper is a documented future option.
- Preserve original audio and prefer data recovery over cleanup.
- Never hide track failures or claim health without recent buffers and signal.
- `me`/`them` are source tracks, not speaker identity or true diarization.
- Do not silently discard duplicate speech; preserve it in canonical JSON and
  original audio, with visible warnings.
- Recording must always have visible menu and macOS indicators.
- Do not change retention, consent, or transcription behavior materially
  without product approval.

## Security and data

- Create session directories with mode `0700` and files with `0600`.
- Never log transcript text.
- Keep `on_stop` disabled unless explicitly configured. Use direct argv
  execution; never a shell and never command data from metadata/transcripts.
- Never commit recordings, transcripts, models, credentials, certificates,
  signing secrets, machine configuration, or generated release artifacts.

## Verification

Before handoff run:

```sh
swift build -c release
swift test
.build/release/regardingwork-meetings --help
.build/release/regardingwork-meetings doctor --help
scripts/build-app.sh
```

Inspect `dist/RegardingWork Meetings.app/Contents/Info.plist`, the embedded
binary plist, bundle identifier, executable name, and stale functional names.
Do not claim microphone, system audio, real meetings, crash recovery, or
transcription is verified unless manually tested with the required macOS
permissions.

Use focused branches and reviewable commits. Do not publish a release or merge
the default branch without explicit approval.
