# Privacy

RegardingWork Meetings is local-first by design. It records two local audio
files and runs transcription on this Mac. It does not upload audio,
transcripts, metadata, or logs; it has no analytics, telemetry, SSO,
synchronization, summarization, cloud transcription, or external AI processing.

## What is captured

- The default microphone captures the user and nearby room sound.
- The global system-audio tap captures everything the Mac plays: every meeting
  participant, notification, browser tab, music player, and unrelated app.
- macOS displays its system recording indicator while capture is active.
- The menu-bar icon becomes an explicit red recording symbol and the menu shows
  elapsed time plus each track's health.

The application cannot guarantee that unrelated audio is absent. Use Focus,
close unrelated media, and run the pilot checks before important meetings.

## Storage and permissions

The default root is `~/RegardingWork/Meetings`. Session directories are mode
`0700`; audio, transcripts, metadata, manifests, and session logs are mode
`0600`. LaunchAgent logs live under
`~/Library/Application Support/RegardingWork Meetings/Logs` with user-only
permissions. Transcript text is never written to general application logs.

The Parakeet model is managed locally by FluidAudio/Core ML. A network
connection is needed for its initial download; transcription after preparation
is on-device.

## Retention and deletion

There is no automatic retention, upload, cleanup, or deletion. Recordings remain
until the user removes them. Finder Trash is recoverable until emptied.
Permanent deletion means deleting the session or recordings root and emptying
Trash; backups, snapshots, copied exports, and synced folders must be handled
separately. The app never assumes it can erase those copies.

Recovery preserves evidence rather than deleting it. Original CAF files and the
recovered manifest remain available for inspection and retranscription.

## Optional hook

`on_stop` is disabled by default. If explicitly configured, it executes a
trusted local executable with fixed argv values plus the session directory.
No shell is used. The app never executes commands from transcript text,
recording metadata, filenames inside metadata, or model output. A hook can
still copy or disclose data, so only trusted users should enable it.
