# Pilot guide

## Supported environment

- macOS 15 or later
- Apple Silicon recommended and the primary pilot target
- Intel Macs may build for macOS 15 but transcription performance and model
  compatibility require explicit pilot validation
- Default input device plus Mac system playback

No real meeting should be the first recording.

## Welcome and setup

The app opens a visible **Welcome & Setup** window on first launch. Use it to:

- request or repair microphone permission;
- open Screen & System Audio Recording settings;
- prepare the local Parakeet model before an important meeting;
- review the global-capture and consent disclosure;
- open the local recordings folder; and
- start a short test recording.

Closing setup leaves the **RW** icon in the menu bar. Reopen setup from that
menu or by opening the app again. If automatic setup display was disabled, the
menu command remains available.

## Install an unsigned development build

```sh
git switch agent/regardingwork-meetings-hardening
swift test
scripts/build-app.sh
open "dist/RegardingWork Meetings.app"
```

The default build is ad-hoc signed. If testing a truly unsigned build is
necessary, use `SKIP_CODESIGN=1 scripts/build-app.sh`; macOS permission identity
will be less stable. Do not distribute either build as a production release.

## Prepare the model

Choose **Prepare Model (~600 MB)** in Welcome & Setup while online, or run
`regardingwork-meetings doctor` and record a short synthetic session. Confirm a
later test transcribes with networking disabled. Do not wait for an important
meeting to discover a missing model.

## Permissions

On first recording, approve:

- System Settings → Privacy & Security → Microphone
- System Settings → Privacy & Security → Screen & System Audio Recording

Confirm the permission entry names RegardingWork Meetings for the app bundle.
After replacing signatures or moving between terminal and app builds, reset and
repeat permissions if macOS associates them with a different identity.

## Headphone test

1. Connect headphones and select the intended microphone.
2. Play a consented synthetic remote-voice clip.
3. Start recording and speak alternating phrases.
4. Confirm the menu reaches `mic ✓ · system ✓`.
5. Stop and verify `mic.caf`, `system.caf`, `meta.json`, `transcript.md`, and
   `transcript.json`.
6. Confirm `me` contains local speech and `them` contains playback.
7. Confirm timestamps are ordered and audio remains local.

## Speaker and echo test

1. Disconnect headphones and play the same clip through speakers.
2. Test with `mic_voice_processing` false, then true.
3. Confirm voice processing does not create a silent mic, unexpected route
   failure, or unacceptable playback ducking.
4. Confirm duplicate warnings appear and only very strong microphone echo is
   hidden from Markdown.
5. Confirm every hidden segment remains in JSON and both CAF files remain.

Headphones are the preferred production setup.

## Recording-health checks

During a synthetic recording:

- stay silent and confirm the menu says `silent`, not healthy;
- speak/play audio and confirm each corresponding track becomes active;
- change the default mic or connect a call app and watch for stalled/failed
  status;
- verify notifications are visible and the menu-bar record symbol remains red;
- confirm unrelated Mac playback is present in `system.caf`.

## Transcript verification

Compare several timestamps against both CAF tracks. Verify source attribution,
warning text, ordering, Markdown rendering, canonical JSON preservation, and
that `transcribe.log` contains no transcript text. Parakeet v2 is English-only;
non-English quality is unsupported in this pilot.

While transcription is active, confirm the menu-bar icon is blue and the menu
says **transcribing locally…**. A red record icon takes precedence if another
recording starts. A transcription failure uses an orange warning icon.

For a disposable session, simulate or observe a transcription failure and
choose **Retry unfinished transcriptions**. Confirm the failed session returns
to the blue queue, later completed sessions are not transcribed again, and the
original CAF files remain unchanged.

Closing the MacBook lid normally suspends processing and allows it to continue
after wake. Quitting, restarting, losing power, or shutting down interrupts the
current transcription. On the next launch, a session with `meta.json` but no
`transcript.json` is queued again from the beginning; original CAF audio is
preserved. Wait for transcription to finish before shutdown when practical.

## Interrupted-session recovery

Use a disposable synthetic session. Force-quit the process while recording,
relaunch, and confirm:

- the already-written CAF files remain;
- the menu reports recovery;
- `meta.json` has `recovered: true`;
- `recording.recovered.json` is preserved;
- only readable tracks are queued;
- missing/unreadable tracks are warned, not fabricated or deleted.

Do not claim crash recovery is verified until this manual test succeeds on the
target Mac.

## Developer ID signing/notarization handoff

No credentials are committed. On the trusted signing Mac:

```sh
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile "<profile>"
SIGNING_IDENTITY="Developer ID Application: …" \
NOTARY_PROFILE="<profile>" \
APP_VERSION="0.1.0" \
scripts/sign-and-notarize.sh
```

The script builds, signs with hardened runtime, verifies, submits with bounded
polling, fetches failure logs, staples, assesses Gatekeeper, creates and
notarizes the DMG, verifies it, and writes SHA-256. Expected artifact:
`dist/RegardingWork-Meetings-0.1.0.dmg`. Do not publish until both app and DMG
verification pass. This repository does not publish automatically.

## Uninstall and rollback

```sh
"/Applications/RegardingWork Meetings.app/Contents/MacOS/regardingwork-meetings" \
  install --uninstall
```

Then quit the app and move it to Trash. Roll back by installing a previously
verified signed build; do not reuse incompatible config without review.

Recordings are intentionally not removed by uninstall. To remove local data,
move `~/RegardingWork Meetings`,
the former `~/RegardingWork/Meetings` folder if it exists, and
`~/Library/Application Support/RegardingWork Meetings` to Trash, review them,
then empty Trash. Remove backups and synced copies separately. FluidAudio model
caches are external to the app and must be located/reviewed before deletion.
