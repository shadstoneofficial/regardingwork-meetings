# Interrupted-session recovery

CAF is streamed so audio already written is generally more recoverable than a
container that requires a finalization pass. This does not guarantee every
abruptly interrupted file is readable.

At session start, the app atomically writes `recording.json` with a session ID,
owner PID, expected tracks, start time, first-buffer times, and recent health.
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
session, or deletes original audio. A recovered transcript can be one-sided and
contains health warnings.

If recording stopped cleanly but transcription was interrupted, `meta.json`
and the CAF files remain. Because `transcript.json` is the completion marker,
the app queues that session again after relaunch and transcribes it from the
beginning. It does not resume from a partial timestamp. Closing the MacBook lid
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
