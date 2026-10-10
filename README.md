# RegardingWork Meetings

RegardingWork Meetings is an open-source, fully local macOS meeting recorder and
transcriber in the RegardingWork Voice product family. A deliberate menu-bar
action captures the default microphone and all Mac system audio as separate
CAF tracks, then runs Parakeet transcription on-device. Audio and transcripts
stay on the Mac.

This application is separate from RegardingWork Dictate.

## Requirements

- macOS 15 or later
- Apple Silicon recommended for transcription performance
- Microphone and Screen & System Audio Recording permissions
- Network access only for the one-time FluidAudio/Parakeet model download

## Development build

For a signed release, open the downloaded DMG and drag
**RegardingWork Meetings.app** onto the **Applications** shortcut shown beside
it. Quit an older copy first and choose **Replace** when upgrading. Recordings
are stored separately and are not removed by replacing the application.

```sh
swift build -c release
swift test
scripts/build-app.sh
open "dist/RegardingWork Meetings.app"
```

The app bundle is ad-hoc signed for development by default. It uses
`com.regardingwork.meetings`; a Developer ID build must use the signing handoff
in [PILOT.md](PILOT.md). No release workflow publishes artifacts.

## Use

1. Launch the app. **Welcome & Setup** opens with microphone, system-audio,
   model, storage, privacy, and consent guidance.
2. Request microphone access and prepare the local Parakeet model. macOS asks
   for Screen & System Audio Recording access when the first recording starts.
3. Choose **Start Test Recording** in setup or **Start recording** from the
   **RW** menu-bar icon.
4. Confirm the menu shows `mic ✓ · system ✓` while someone speaks on each
   source. `silent`, `digital silence`, `route changed`, `stalled`, or `failed`
   is a real warning.
5. Choose **Stop recording**. The menu-bar icon becomes a blue processing
   symbol while Parakeet transcribes locally in a serial queue.
6. Open `~/RegardingWork Meetings/<yyyy.MM.dd-HHmm>/`.

If transcription shows the orange needs-attention state, choose **Retry
unfinished transcriptions** from the menu. The app re-scans both current and
legacy recording roots and queues sessions with `meta.json` but no completed
`transcript.json`. Existing completed transcripts and original CAF audio are
left unchanged.

Since 0.1.4, failed/missing/unreadable tracks remain unfinished and retryable;
successful track output is checkpointed. A completed transcript means inference
finished for the captured sources, **not** that recording was complete.
The 0.1.5 beta candidate labels known capture failures/gaps prominently in the
menu, notification, Markdown and JSON (`capture_incomplete`). Retrying cannot
restore audio that was never recorded.

The 0.1.5 candidate also shows **SYS!** for a stalled/failed/restarting system
track, **CHECK SYS** for startup/quiet, and **SYS GAP** after an interruption,
even if new audio resumes. It can rebuild a stalled tap up to three times while
the visible recording is active, preserving earlier audio in separate CAFs.
Ordinary quiet does not trigger recovery. See
[SYSTEM_AUDIO_RELIABILITY.md](SYSTEM_AUDIO_RELIABILITY.md) for limitations and
the required real-Mac test matrix. Use **About RegardingWork Meetings…** or the
version line in the menu to check the exact app version/build.

At recording start, **CHECK MIC** remains beside the red recording symbol until
the input produces a nonzero sample. That alone does not prove speech capture.
The menu names the current macOS default microphone. This is the selected
route, not proof of audible speech; inspect the separate health indication.
**MIC!** means digital silence, a stalled/failed input,
or a route change needs immediate attention. See
[MICROPHONE_RELIABILITY.md](MICROPHONE_RELIABILITY.md).

Closing Welcome & Setup leaves the **RW** recorder icon available in the menu bar. Reopen
the window at any time by opening the app again or choosing
**Welcome & Setup…** from the menu. Its **Show this window when…opens**
checkbox controls whether it appears automatically on future launches.

Each completed session can contain:

| File | Purpose |
|---|---|
| `mic.caf` | Local microphone; transcript source label `me` |
| `system.caf` | Everything the Mac played; source label `them` |
| `system.recovery-NNN.caf` | Preserved system capture after a safe tap restart; included at its original offset |
| `meta.json` | Timing, source attribution, recovery, and final track health |
| `mic.zero-filled.caf` | Preserved diagnostic evidence after automatic zero-input recovery |
| `transcript.json` | Canonical transcript, including preserved echo candidates |
| `transcript.md` | Readable transcript with visible warnings |
| `transcribe.log` | Progress and errors; never transcript text |

While recording, `recording.json` is updated atomically. A clean stop writes
`meta.json` and removes it. After interruption, recovery preserves readable
tracks, writes explicit recovered metadata, and retains the sidecar as
`recording.recovered.json`. See [RECOVERY.md](RECOVERY.md).

## Attribution is not diarization

`me` means the microphone track and `them` means the system-audio track. This
is two-track source attribution, not identification or diarization of multiple
remote speakers.

Speaker playback can bleed into the microphone. Headphones are the preferred
setup. Heuristically matched duplicates are hidden only from Markdown; the
canonical JSON marks and retains them, and original audio is never removed.
Weaker matches stay visible with warnings. This text/timing heuristic can hide
a legitimate repeated response, so consult JSON/audio when speech seems missing.

Optional Apple voice processing can reduce speaker echo:

```json
{
  "mic_voice_processing": true
}
```

It is off by default because it can duck playback, alter microphone audio, or
fail on some routes. The app falls back to raw mic capture if the initial
voice-processing signal is digitally silent.

## Configuration

Optional configuration lives at:

`~/.config/regardingwork-meetings/config.json`

```json
{
  "recordings_dir": "~/RegardingWork Meetings",
  "transcription": {"enabled": true, "engine": "parakeet"},
  "mic_voice_processing": false,
  "on_stop": ["/absolute/path/to/trusted-hook", "--local-only"]
}
```

Recording-root precedence is `--out`, then configuration, then
`~/RegardingWork Meetings`. Builds that used the former
`~/RegardingWork/Meetings` default are not moved or deleted; the app still
discovers unfinished sessions there and retries their transcription after
relaunch. `on_stop` is disabled unless an argv array is
explicitly configured. It is executed directly, without a shell, and receives
the session directory as its final argument. Treat it as an advanced,
trusted-user feature.

## CLI

```sh
regardingwork-meetings
regardingwork-meetings run --out <directory>
regardingwork-meetings doctor
regardingwork-meetings install --launch-at-login
regardingwork-meetings install --uninstall
```

The login agent identifier is `com.regardingwork.meetings`. Launching at login
does not start a recording; recording always requires the visible menu action.

## Local architecture

- `AVAudioEngine` captures and downmixes the default microphone.
- A Core Audio global process tap captures all Mac playback.
- CAF/AAC files stream to disk. Interrupted files are preserved, but unfinalized
  AAC may be undecodable; see [RECOVERY.md](RECOVERY.md).
- FluidAudio runs Parakeet TDT 0.6B v2/Core ML locally.
- Track timestamps are offset, merged, and deterministically ordered.
- No analytics, telemetry, SSO, sync, summarization, cloud transcription, or
  external AI processing exists.

Parakeet v2 is English-only. Multilingual Parakeet or Whisper remains a future
option; neither is silently substituted or shipped here.

See [IMPROVEMENTS_AND_UPSTREAM.md](IMPROVEMENTS_AND_UPSTREAM.md) for the
2026-10-03 reliability review, current upstream status, and proposed next-beta
and contribution work. Those proposals are not shipped fixes.

## Privacy and operations

Global system capture includes notifications, music, browser tabs, and unrelated
applications. Use Focus mode and close unrelated media. Recording other people
may require notice or consent. Read [PRIVACY.md](PRIVACY.md),
[RECORDING_AND_CONSENT.md](RECORDING_AND_CONSENT.md), and [PILOT.md](PILOT.md)
before a real meeting.

## Upstream and license

The complete upstream Git history and original MIT license are preserved.
RegardingWork Meetings is derived from
[digimata/quill](https://github.com/digimata/quill). See
[UPSTREAM.md](UPSTREAM.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md),
and the unchanged [LICENSE](LICENSE).
