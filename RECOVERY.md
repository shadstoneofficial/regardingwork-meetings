# Interrupted-session recovery

The current app streams AAC audio into CAF files. Files already written are
preserved after interruption, but an AAC CAF that was not finalized can be
undecodable. A synthetic writer check reproduced this; it was not a crash test
of the actual app. A manifest cannot restore audio that the decoder cannot
read. See [IMPROVEMENTS_AND_UPSTREAM.md](IMPROVEMENTS_AND_UPSTREAM.md) for the
evidence and recording-format decision still needed before promising reliable
abrupt-exit recovery. Do not delete interrupted files just because recovery
failed.

At session start, the app atomically writes `recording.json` with a session ID,
owner PID, expected tracks, start time, first-buffer times, and recent health.
Version 0.1.4 also records persisted last-buffer timestamps, observed health
changes and microphone route history as private session evidence.
On clean stop it writes `meta.json` first and then removes the in-progress
manifest.

At relaunch, the app scans the current recordings root. When the new default
`~/RegardingWork Meetings` is active, it also scans the former
`~/RegardingWork/Meetings` default without moving or deleting it:

1. A manifest whose owner PID still appears active is deferred.
2. Malformed manifests are preserved and reported.
3. Each expected track is checked for readable audio frames.
4. If at least one track is readable, recovered `meta.json` is written without
   overwriting existing metadata.
5. The original sidecar is preserved as `recording.recovered.json`.
6. Recovery is visible in the menu and notification, and the session joins the
   normal local transcription queue.
7. If no track is readable, the folder is left untouched for manual inspection.

Recovery never fabricates a missing source, overwrites an existing completed
session, or deletes original audio. A recovered transcript can be one-sided.
Version 0.1.4 retains historical failure/silence states and original sidecar
bytes. Capture end is derived from persisted buffer times and readable audio
duration, not relaunch or today's microphone. Older manifests without endpoint
evidence can have an explicitly noted zero/unknown duration. Readability is not
proof of complete or audible capture. Consult the original manifest and listen
to both tracks. Unavailable sources remain in metadata for later retry; no
missing audio is fabricated.

If recording stopped cleanly but transcription was interrupted, `meta.json`
and the CAF files remain. Because `transcript.json` is the completion marker,
the app queues that session again after relaunch. Version 0.1.4 keeps successful
tracks in user-only `transcription-state.json` and retries unfinished tracks.
Incomplete reports are `transcript.partial.md` / `.json`; only all successfully
processed sources create final `transcript.json`. A readable track with no
recognized speech is distinct from an empty/unreadable file. Later meetings
continue through the queue after a failure. Resume is at track granularity,
not a timestamp within a failed track. Older final transcripts, including ones
with incomplete warnings from earlier versions, remain untouched and require
manual inspection on a copied session; this beta does not silently redo them.
Closing the MacBook lid
normally suspends the running process and allows work to continue after wake,
but waiting for completion before shutdown is safest.

Choose **Retry unfinished transcriptions** from the menu to perform the same
safe scan without restarting the app. This can be used after a temporary model
or Core ML failure while later meetings continue through the serial queue.

For manual inspection:

```sh
find "$HOME/RegardingWork Meetings" -name 'recording*.json' -o -name 'meta.json'
find "$HOME/RegardingWork/Meetings" -name 'recording*.json' -o -name 'meta.json'
afinfo "/path/to/session/mic.caf"
afinfo "/path/to/session/system.caf"
```

Copy a session before experimenting. Do not rename unknown files into the queue
or edit metadata to execute anything; metadata and transcript text are never
command sources.
