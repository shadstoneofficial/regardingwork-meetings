# System audio reliability — 0.1.5 beta candidate

## Why this change exists

A reviewed 0.1.4 incident had a long microphone recording but system capture
stopped partway through. Private metadata recorded microphone route changes
shortly before a persistent system stall. Transcription successfully processed
the available audio; it could not restore the missing remote speech. This
correlation does not prove which macOS/USB/call-app event caused the tap to stop.
No personal recordings or incident files are included in this repository.

The previous system recorder had no restart path, and the menu-bar warning text
prioritized microphone problems. These deficiencies are addressed together:
preserve data, attempt bounded recovery, and expose partial capture clearly.

## What the candidate does

Only a user-started, visibly active recording may recover. The common-mode
watchdog evaluates successful audio writes, not just callback arrival. A stall
or incompatible buffer can rebuild the global process tap and its private
aggregate device up to three times per session, delayed by 2/4/8 seconds.
Quiet with fresh buffers never triggers this restart. A disk/write failure
halts system capture and remains visible; the microphone continues if healthy.

The old tap stops and its AAC CAF is finalized. New capture has a new, exclusive
filename (`system.recovery-001.caf`, etc.), allowing the format to change without
reopening/truncating an earlier file. Files are mode 0600; session directories
remain 0700. The manifest records each file before capture starts. Stop or quit
clears scheduled recovery; closed recorder callbacks cannot write into a new
file. There is no background/hidden recording or post-stop auto-restart.

The red record symbol remains obvious. Its labels mean:

| Label | Meaning and action |
| --- | --- |
| CHECK SYS | Startup or fresh buffers without recent audible signal. Play/speak on the remote side and check again. |
| SYS! | System capture stalled, failed or is restarting. Open the menu immediately; do not assume full recording. |
| SYS GAP | An interruption occurred. It remains even after recovery; earlier missing audio is not restored. |
| MIC! / CHECK MIC | Independent microphone safety warnings; both sides can have problems at once. |

The menu names the current default microphone separately from its health.
About/the version line identifies the bundle version/build. Metadata records
the app version/source, macOS version, observed default output routes, segment
frame counts/rate and successful-buffer endpoints, and interruption/recovery
events. Default routes are diagnostic context, not proof of what every app used.

All started system segments are transcribed locally and merged at their
original offsets, including gaps. Missing/unreadable started segments stay
unfinished and retryable. Known failed-start attempts with no samples are
preserved with a warning instead of being mistaken for recoverable inference.
Readable audio takes precedence over stale metadata. Legacy sessions work as
before; completed transcripts are never silently rewritten.

Successful inference of available audio is not complete meeting capture.
Known gaps/failures produce a persistent menu warning, a qualified notification,
a prominent Markdown banner and JSON `capture_incomplete: true`. Review this
flag and all warnings before giving a transcript to a summarizer. Ordinary
quiet alone is not treated as proof of lost capture. No summarizer is shipped.

## Limits — do not call this dependable solely because tests pass

- Stalls are detected after 15 seconds without a successful write (5 seconds
  for the first buffer), plus watchdog scheduling and retry delay. Some speech
  can be lost before recovery. The app cannot restore uncaptured audio.
- API start success alone never counts as healthy. Audible signal is required;
  a quiet track cannot prove that routing/permission is correct.
- Buffer timestamps and gap endpoints are approximate wall-clock evidence,
  not sample-accurate reconstruction. Sleep, scheduling and clock changes need
  physical validation. Short dropped intervals can escape stall detection.
- Some macOS permission/device/tap failures will not recover automatically.
  After three attempts, stop/save and start another visible recording when
  practical. App restarts before every meeting are not the intended workflow.
- AAC-in-CAF remains unchanged. A power loss/force quit before finalization can
  leave the active segment undecodable. Completed earlier segments are retained,
  but this is not a guarantee of crash-safe audio. A format change requires a
  separate product decision.
- System capture records all Mac playback, including unrelated apps and
  notifications. Headphones/Focus mode, participant notice and consent still
  matter. The app never uploads these files.
- `me`/`them` are source tracks, not speaker diarization. Echo filtering retains
  canonical JSON/audio but can hide repeated responses in Markdown.

Signal detection respects PCM channel stride, including interleaved stereo,
as specified by [Apple's buffer documentation](https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer/floatchanneldata).

## Verification and acceptance matrix

Automated tests use injected recorders/engines and synthetic files only. They
exercise a stall after 15 minutes, preservation/offsets, fresh-quiet behavior,
three-attempt exhaustion, storage failure, stop during pending recovery,
exclusive file/symlink refusal, manifest-before-capture, segmented transcription
and retry, recovered manifests, version/warnings and interleaved signal checks.
They do not certify real hardware capture or Parakeet recognition.

Required manual tests on each target Apple Silicon Mac/macOS combination:

1. Install the signed candidate from the DMG Applications shortcut. Verify About
   shows **0.1.5 (build 6)** and metadata matches its source commit. Verify both
   permissions and prepare the local model; repeat offline after preparation.
2. Use a consented synthetic call/playback and headphones. Alternate identifiable
   phrases on mic and remote playback. Listen to both tracks and compare timing
   and attribution throughout a **90-minute or longer** session.
3. Switch built-in/USB/Bluetooth inputs and outputs during capture; unplug and
   reconnect USB, connect/disconnect headphones and let a call app reconfigure
   audio. Keep the menu open during some transitions. A route change may not
   stall; when it does, verify SYS!, bounded recovery, new files and sticky
   SYS GAP. Never count missing speech as recovered.
4. Test long ordinary quiet then resumed speech/playback: CHECK SYS, no automatic
   restart, subsequent audible health. Test a real no-buffer failure separately.
5. Stop during a pending retry and during recovery startup. Confirm the macOS
   recording indicator clears and no new buffers/files appear afterward. Quit
   during a pending retry and verify the same. Do not do this on an important call.
6. On disposable copies/staging, test missing/unreadable restarted files and model
   failures: only unfinished work retries; successful inference checkpoints,
   original audio, partial reports and capture-gap warnings remain intact.
7. Compare every system segment's duration/offset against continuous mic audio.
   Confirm inference completion with gaps is **not** presented as a complete
   meeting in notification, menu, Markdown or JSON.
8. Test sleep/wake, force quit and relaunch during a disposable recording. Check
   earlier finalized segments, manifest evidence, recovery offsets, unavailable
   active segments and user-only modes. An undecodable active AAC is a known
   limit, not a passed recovery test.
9. Test speakers with voice processing off/on; verify echo warnings/canonical
   retention and microphone routing. Check logs contain no transcript text.

Record hardware, macOS, exact build/source, durations, route transitions and
outcomes in a private pilot report. Do not commit recordings, meeting transcripts,
model caches, certificates or machine-specific configuration. Keep an independent
consented backup for critical meetings until this matrix passes on the user's Mac.
