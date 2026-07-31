# RegardingWork Meetings

RegardingWork Meetings is a private, fully local macOS meeting recorder and
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
   waveform menu-bar icon.
4. Confirm the menu shows `mic ✓ · system ✓` while someone speaks on each
   source. `silent`, `stalled`, or `failed` is a real warning.
5. Choose **Stop recording**. Parakeet transcribes locally in a serial queue.
6. Open `~/RegardingWork/Meetings/<yyyy.MM.dd-HHmm>/`.

Closing Welcome & Setup leaves the recorder available in the menu bar. Reopen
the window at any time by opening the app again or choosing
**Welcome & Setup…** from the menu. Its **Show this window when…opens**
checkbox controls whether it appears automatically on future launches.

Each completed session can contain:

| File | Purpose |
|---|---|
| `mic.caf` | Local microphone; transcript source label `me` |
| `system.caf` | Everything the Mac played; source label `them` |
| `meta.json` | Timing, source attribution, recovery, and final track health |
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
setup. High-confidence overlapping duplicates are hidden only from Markdown;
the canonical JSON marks and retains them, and original audio is never removed.
Weaker matches stay visible with warnings.

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
  "recordings_dir": "~/RegardingWork/Meetings",
  "transcription": {"enabled": true, "engine": "parakeet"},
  "mic_voice_processing": false,
  "on_stop": ["/absolute/path/to/trusted-hook", "--local-only"]
}
```

Recording-root precedence is `--out`, then configuration, then
`~/RegardingWork/Meetings`. `on_stop` is disabled unless an argv array is
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
- CAF/AAC files stream to disk and preserve already-written audio on abrupt exit.
- FluidAudio runs Parakeet TDT 0.6B v2/Core ML locally.
- Track timestamps are offset, merged, and deterministically ordered.
- No analytics, telemetry, SSO, sync, summarization, cloud transcription, or
  external AI processing exists.

Parakeet v2 is English-only. Multilingual Parakeet or Whisper remains a future
option; neither is silently substituted or shipped here.

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
