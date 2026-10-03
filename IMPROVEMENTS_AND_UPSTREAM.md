# Reliability improvements and upstream contribution plan

Reviewed: 2026-10-03. This is a source review and implementation proposal, not
a statement that the improvements below have shipped. The first focused
upstream contribution, manual transcription retry, is now submitted as
[draft PR #73](https://github.com/humanitas-labs/quill/pull/73). It is not merged
or a new RegardingWork build.

## Recommendation

Make the next RegardingWork Meetings beta a reliability-and-visibility release:
preserve captured audio, retain evidence of interruptions, make partial
transcription retryable, and let the user inspect both tracks while recording.
Keep all capture and transcription local. Do not change retention, consent,
model, or recording format without an explicit product decision.

Contribute small, independently tested fixes back to upstream. Do not submit
RegardingWork's whole rebranding branch or duplicate another contributor's PR.

## Review baseline

| Item | Verified snapshot |
| --- | --- |
| RegardingWork repository | `shadstoneofficial/regardingwork-meetings` |
| Application reviewed | `v0.1.3`, commit `8d134d9142c995c33634a9e6b523ac4c7b981ec0` |
| Public stable release | `v0.1.2`; `v0.1.3` is a prerelease |
| Existing microphone work | [RegardingWork PR #4](https://github.com/shadstoneofficial/regardingwork-meetings/pull/4), open draft |
| Original upstream | `digimata/quill`, now redirects to `humanitas-labs/quill` |
| Current upstream base | `master`, `aad60f98e680720dd24a30115580f226ae36c12c` |
| Route-recovery implementation | [Upstream commit `8c46659`](https://github.com/humanitas-labs/quill/commit/8c46659a2a67638ccbf36e1d4d1e0036c81976f4) |
| First submitted contribution | [Upstream draft PR #73](https://github.com/humanitas-labs/quill/pull/73), manual retry |

GitHub confirms that RegardingWork's repository is an independent repository
(`fork: false`), not a GitHub-network fork. For an upstream PR, use a separate
GitHub fork and branches based on upstream's current `master`. Do not repoint
RegardingWork's `origin`. The existing upstream remote still redirects and was
not changed.

Source code was treated as authoritative. Upstream PR bodies describe their
authors' verification, not tests independently performed by RegardingWork.

## What upstream already has

Current upstream reorganizes native macOS code under `macos/`. Its route
recovery implementation restarts either failed track into a new numbered
segment, preserves previous segments, and records interruptions and final
capture status. Both the watchdog and menu ticker use common run-loop modes.
Its v2 metadata reader also accepts older v1 sessions.

This is relevant to our timestamp-padding problem and lack of durable gap
history. Adapt the mechanism selectively; a wholesale merge would not preserve
all RegardingWork behavior. Keep our branded paths, original license,
permissions, crash manifest, device diagnostics, and explicit source attribution.

Upstream still requests physical-device validation in
[issue #64](https://github.com/humanitas-labs/quill/issues/64). Passing its unit
tests is not proof that all real microphone/output routes recover correctly.

### Open upstream work to coordinate with

| Work | State at review | Our response |
| --- | --- | --- |
| [PR #71](https://github.com/humanitas-labs/quill/pull/71): interrupted-session recovery and completion-marker order | Open, not merged | Review rather than submit a competing crash-recovery PR |
| [PR #72](https://github.com/humanitas-labs/quill/pull/72): imported audio transcription | Open, not merged | Useful future reference; importing audio is not part of the next reliability fix |
| [#56](https://github.com/humanitas-labs/quill/issues/56): playback echo filtering | Open | Share conservative preservation/test concepts only after addressing our false-positive case |
| [#57](https://github.com/humanitas-labs/quill/issues/57): settings and private paths/logs | Open | Coordinate owner-only storage and hook compatibility; do not port our brand/path migration |
| [#59](https://github.com/humanitas-labs/quill/issues/59): terminal system-capture silence | Open | Keep signed app permission identity; do not claim permission alone proves capture |
| [#60](https://github.com/humanitas-labs/quill/issues/60): permanent startup failure/relaunch loop | Open | Our visible setup is useful prior work, but upstream proposes a different lifecycle solution |
| [#61](https://github.com/humanitas-labs/quill/issues/61): signed app/DMG | Open | Offer packaging experience, not certificates, credentials, or RegardingWork identity |
| [#64](https://github.com/humanitas-labs/quill/issues/64): hardware route matrix | Open | Use synthetic, consented test calls and report only tests actually run |

Older PRs, including #2, #6, #7, #12, and #18, are now closed, not merged PRs
waiting for us to pull. Relevant work was consolidated or replaced. The
July/September snapshots in earlier documentation are historical, not current
status.

## Important new finding: AAC crash recovery

PR #71's author reports that an open AAC-in-CAF recording could not be decoded
after a forced exit, and proposes 16-bit PCM recording instead. Their estimated
storage cost is approximately 1 GB/hour for typical microphone/system rates.
This is an unmerged proposal, not our current recording format.

We independently ran a narrower synthetic writer check on macOS 26.6.2,
Apple Silicon, Swift 6.3.3. It generated a three-second mono 48 kHz tone with
AVAudioFile, using the same AAC settings as our microphone writer. Abrupt cases
used `_exit(0)` while the file remained open, bypassing file-object finalization.

| Synthetic file | Decode result using `afconvert` |
| --- | --- |
| AAC CAF, abruptly exited | Failed: `ExtAudioFileRead failed (-66567)` |
| AAC CAF, cleanly closed control | Decoded: 3 seconds, 144,000 samples |
| 16-bit PCM CAF, abruptly exited | Decoded: 3 seconds, 144,000 samples |

This supports the risk; it is not a force-quit test of the actual app, a power
loss test, or a real microphone/system recording. No meeting files were used.
CAF alone does not guarantee that an unfinalized compressed recording is
readable. A manifest cannot recover audio the decoder cannot read.

Before selecting a solution, approve and test either a recoverable PCM capture
format or another preservation design. Compare disk usage, long-session disk
pressure, clean-stop compatibility, and abrupt-exit decode behavior. Do not
silently transcode/delete original sessions or introduce automatic retention.

## RegardingWork findings and acceptance criteria

### 1. Partial/failed transcription is incorrectly marked complete — high priority

In `TranscriptionCoordinator.swift`, track-level errors are caught and skipped,
but `transcript.json` is still written. Its presence makes the session ineligible
for retry. Even a compute error is described as unreadable audio.

A synthetic engine compiled with the unchanged coordinator reproduced:

- both tracks failing: zero segments, two warnings, "transcript ready", no retry;
- microphone failing/system succeeding: one-sided completed output, no retry.

Required result: distinguish successful empty/silent input, missing/unreadable
input, transient inference failure, partial output, and complete output. Keep
successful work available, but permit retry of failed tracks/segments. Show
partial status in the menu and transcript. Do not overwrite an older successful
transcript silently. Add injected-engine tests for these cases and for a later
meeting succeeding after an earlier failure.

Upstream's current coordinator also skips track/segment errors and writes the
completion marker. Neither its current master nor the reviewed PR #71 patch
fixes this policy. A shared fix is a future contribution, not an existing local
fix ready to export.

### 2. Recovery erases known failure status — high priority

Our recovery code replaces a readable track's prior health with `recovered`.
Readability is not evidence of useful audio. A synthetic one-second zero-filled
CAF previously marked `digital_silence` became `recovered`, with no transcript
warning. Relaunch the next day also produced a duration of 86,400 seconds.

Required result: retain interruption/zero-input history; report incomplete
capture even when some files are readable. Derive recovered capture endpoints
from durable evidence/audio duration, not the relaunch time. Distinguish
recovery time from recording end time and do not label today's input device as
the historical ending device. Preserve the original manifest.

### 3. Repeated restart padding can distort alignment — high priority

`MicRecorder.padGapWithSilence()` measures from `lastBufferAt` on every restart
attempt. Padding does not advance that endpoint. Repeated failed attempts can
append overlapping gap durations more than once.

Required result: use one monotonic session timeline, numbered recovery
segments, bounded retries, and persisted gap boundaries. Verify sample-rate
changes, repeated failures, and stopping during retry with fake recorders.
Prior audio must remain unchanged. Preserve v1 session read compatibility.

### 4. Health status can stop refreshing during menu inspection

Our ticker is scheduled in the default run-loop mode. A synthetic event-tracking
check observed zero default-timer callbacks versus five common-mode callbacks.

Required result: keep health, elapsed time, and manifest updates running in
common modes or another suitable monitoring mechanism. Test with the menu
held open. Upstream already addresses this; bring its idea into RegardingWork,
not back to upstream as a duplicate contribution.

### 5. Echo suppression can hide a real reply

Our detector classified a non-overlapping, repeated four-word response as echo
because of its 1.5-second tolerance. Canonical JSON retained it, but Markdown
hid it. Text similarity is not calibrated acoustic confidence.

Required result: strengthen the evidence needed to suppress speech, test
genuine repetitions/backchannels, and provide a readable way to reveal all
echo candidates. Preserve JSON and original audio. Seek approval before a
material change to transcript filtering defaults.

### 6. The live microphone name is a startup snapshot

`RecordingSession.microphoneDeviceName` returns `deviceAtStart`. A route-change
warning exists, but the main recording label can retain the old name.

Required result: distinguish requested/default input, actual current capture
device, and historical devices. Display live identity and meters while the menu
is open; record route changes without pretending a name alone proves speech
was captured.

## Contribution candidates from work already done here

| Candidate | Local prior work | Upstream disposition |
| --- | --- | --- |
| Manual retry without restarting the app | Actor re-scan, current-session exclusion, menu action, discovery tests | Submitted as [draft PR #73](https://github.com/humanitas-labs/quill/pull/73); does not solve the partial-completion loophole on its own |
| User-only recording/transcript/metadata/log permissions | `SecureStorage`, private session artifacts, permission tests | Strong separate contribution; coordinate with #57 and PR #71; preserve upstream paths and avoid unrelated directory permission changes |
| Microphone identity and persistent capture warnings | Device name/UID, local metadata, visible warning text | Useful independent contribution after correcting live-device labeling; adapt to upstream's v2 segments |
| Direct argv `on_stop` execution | Argument-array validation, no shell, argument tests | Requires agreement about migration from upstream's documented shell strings; do not silently break existing hooks |
| JSON completion marker written last | Local ordered writes and regression test | Already in PR #71; credit that work instead of a duplicate PR |
| Crash manifests | Local conservative discovery and evidence retention | Already under active development in PR #71; our current AAC and failure-history limitations prevent an unchanged port |
| Echo preservation/source-attribution guidance | Original JSON/audio retained, explicit `me`/`them` meaning | Offer docs and safer tests for #56; do not export our detector unchanged |
| App bundle/setup/visible processing states | Local bundle/DMG/setup UI and recording/transcription states | Follow-up discussion around #61/#63; neutral branding, no signing material |

The upstream hook is explicitly configured trusted-user code; its shell-string
support is not by itself proof of a transcript-injection vulnerability. A safer
argv contribution should be described accurately as hardening and a
compatibility decision.

## Next beta scope

1. Fix transcription outcome/retry semantics with deterministic injected-engine
   tests.
2. Adapt segmented capture recovery and durable interruption history while
   preserving manifests, privacy, and older sessions.
3. Resolve the recording-format decision with synthetic and actual-app
   abrupt-exit tests before promising recoverability.
4. Keep monitoring live while the menu is open; display actual input identity,
   level meters, and persistent degraded status.
5. Add a small history/details interface: open audio, open transcript, inspect
   capture completeness, retry an eligible session, and export redacted
   diagnostics. Never include meeting content in general logs.
6. Distinguish normal quiet from stopped transport/exact-zero capture so
   warnings remain meaningful. Add verify/repair-model guidance.

Do not add cloud processing, automatic recording, synchronization, diarization,
summarization, new model defaults, or automatic deletion as part of this scope.

## Safe upstream PR workflow

1. Obtain approval to open specific public draft PRs. Approval was received
   for the first manual-retry contribution, and draft PR #73 was submitted.
   Keep later contributions focused; do not treat this as merge/release approval.
2. Recheck current upstream master, open PRs, contributor instructions, and the
   chosen account. The read-only account check currently identifies
   `shadstoneofficial`.
3. Use an isolated checkout of a GitHub-network fork of `humanitas-labs/quill`.
   Keep product app-code changes separate and never modify RegardingWork Dictate.
4. Start each `codex/` contribution branch from upstream master. Port only the
   relevant behavior and tests. Do not cherry-pick branding-heavy commits.
5. Retain upstream's current copyright/license; retain our original Andrew
   Jones MIT license unchanged. Any imported upstream work needs appropriate
   notices without replacing the original license.
6. Use synthetic fixtures. Never submit audio, transcript text, device UIDs,
   usernames, local paths, private session metadata, models, or signing secrets.
7. Run upstream's release build, tests, help smoke tests, format/diff checks,
   and applicable synthetic regressions. State physical tests not performed.
8. Push only the explicit contribution branch, open a draft PR against upstream
   master, link related work without claiming someone else's issue is solved,
   and attach the PR to this task. Do not merge or publish a release.

## Verification record and remaining manual checks

RegardingWork's release build, 22 automated tests, CLI help smoke tests, and
temporary app/bundle identifier checks passed during the preceding app review.
Its release build, 22 tests, CLI help, and temporary unsigned development bundle
checks were repeated successfully when documenting the submission. Bundle and
embedded identifiers remain `com.regardingwork.meetings`; no product app code
changed. The synthetic coordinator, recovery, echo, and timer checks exposed
the gaps above. The synthetic codec check was run during the upstream review.

### Submitted contribution: manual retry

- PR: [humanitas-labs/quill #73](https://github.com/humanitas-labs/quill/pull/73),
  **feat(macos): retry unfinished transcriptions from menu**; open draft.
- Contribution fork: `shadstoneofficial/quill`, verified GitHub-network fork of
  `humanitas-labs/quill`. RegardingWork's origin/upstream remotes are unchanged.
- Branch: `codex/manual-transcription-retry`; commit
  `8d94aef08480e2e5b0a343a655fd5e5420019908`, based on upstream master
  `aad60f98e680720dd24a30115580f226ae36c12c`.
- Scope: shared launch/manual discovery, actor in-flight/queued deduplication,
  completed-file preservation, disabled/nothing-to-retry feedback, immediate
  queued-count updates, and clearing a resolved last-failure status. Upstream
  config, model, recording format, hook behavior, dependencies, and license are
  unchanged. No RegardingWork runtime branding was ported.
- Verification: upstream release build, 39 tests (7 new), five additional runs
  of the 7 retry tests, four CLI help smoke tests, strict formatting lint, and
  diff checks passed. Tests use fake engines and synthetic metadata/placeholders,
  not actual audio, models, user hooks, or notifications. Existing FluidAudio
  resource and upstream XCTest actor-isolation warnings remain.
- Host storage: internal disk pressure interrupted verification. Only the new
  contribution checkout/cache was relocated to external storage, its original
  copy retained, and generated compiler artifacts rebuilt. Final tests used
  external temporary/cache paths with `--cache-path` and `--manifest-cache local`.
  No user recordings or application data were removed or uploaded.
- Limits: not force re-transcription; sessions already containing
  `transcript.json`, including wrongly marked partial output, remain ineligible.
  Missing audio and recordings without `meta.json` are not repaired. There is a
  small pending-discovery extraction overlap with PR #71, explicitly disclosed
  for a later rebase. No upstream CI checks were listed at submission; local
  checks are not a claim of passing GitHub CI or maintainer acceptance.

Real menu interaction, microphone/system capture, Parakeet inference,
sleep/wake, and actual-app crash recovery were not manually tested for this PR.

Before a dependable new build, manually test built-in/USB/AirPods inputs,
call-app reconfiguration, input/output changes, unavailable recovery devices,
stop-during-retry, speaker/headphone attribution, sleep/wake, actual-app
force-quit/relaunch, permissions on a clean Mac, disk pressure, and consecutive
long meetings while prior transcriptions run. Compare decoded audio durations,
both source tracks, and transcript timestamps. Do not use a real important
meeting as the first test.

Current state: first focused upstream contribution submitted as a draft, with
the remaining product improvements and contribution candidates documented.
No RegardingWork application changes, merge, release, or new signed build were
made. Remaining work needs implementation and the physical checks above.
