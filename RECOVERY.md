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
Current limitations: recovery marks readable tracks as `recovered`, which can
hide earlier silence/failure warnings, and uses relaunch time for session end
and duration. Readability is not proof of complete or audible capture. Consult
the preserved manifest and listen to both tracks; retaining historical health
and deriving the actual capture endpoint are planned fixes, not shipped ones.

If recording stopped cleanly but transcription was interrupted, `meta.json`
and the CAF files remain. Because `transcript.json` is the completion marker,
the app queues that session again after relaunch and transcribes it from the
beginning. It does not resume from a partial timestamp. A current limitation is
that track-level transcription errors can still leave `transcript.json`; that
session is then skipped by retry. See the improvement plan for partial-output
handling. Closing the MacBook lid
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
