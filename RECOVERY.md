# Interrupted-session recovery

CAF is streamed so audio already written is generally more recoverable than a
container that requires a finalization pass. This does not guarantee every
abruptly interrupted file is readable.

At session start, the app atomically writes `recording.json` with a session ID,
owner PID, expected tracks, start time, first-buffer times, and recent health.
On clean stop it writes `meta.json` first and then removes the in-progress
manifest.

At relaunch, the app scans the recordings root:

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

For manual inspection:

```sh
find ~/RegardingWork/Meetings -name 'recording*.json' -o -name 'meta.json'
afinfo "/path/to/session/mic.caf"
afinfo "/path/to/session/system.caf"
```

Copy a session before experimenting. Do not rename unknown files into the queue
or edit metadata to execute anything; metadata and transcript text are never
command sources.
