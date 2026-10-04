# Upstream

RegardingWork Meetings preserves the complete Git history and unchanged MIT
license of the project cloned from:

`https://github.com/digimata/quill.git`

As checked on 2026-10-03, that URL redirects to
[humanitas-labs/quill](https://github.com/humanitas-labs/quill). The configured
remote remains unchanged. The original Andrew Jones MIT license in this
repository must not be replaced by upstream's newer copyright notice.

Remotes:

```text
origin   https://github.com/shadstoneofficial/regardingwork-meetings.git
upstream https://github.com/digimata/quill.git
```

Quill and Digimata names are retained only for original licensing, attribution,
the upstream remote, and migration history. Runtime identities and paths use
RegardingWork Meetings.

## Reviewed upstream context

Reviewed initially on 2026-07-31, refreshed on 2026-09-15, and checked again on
2026-10-03. The earlier snapshots are historical. Source code is authoritative.
Upstream `master` now ends at `aad60f98e680720dd24a30115580f226ae36c12c`, has
reorganized native macOS code under `macos/`, and includes
[route-recovery commit `8c46659`](https://github.com/humanitas-labs/quill/commit/8c46659a2a67638ccbf36e1d4d1e0036c81976f4).

That implementation preserves numbered capture segments, records interruptions,
uses bounded recovery retries and a monotonic timeline, and keeps watchdog/menu
timers running in common run-loop modes. Physical route validation remains
tracked in [issue #64](https://github.com/humanitas-labs/quill/issues/64).

Relevant current work:

- [PR #71](https://github.com/humanitas-labs/quill/pull/71), open: crash manifests,
  interrupted-segment recovery, and JSON written last as the completion marker.
  It also proposes PCM instead of AAC because the author found unfinalized AAC
  unreadable. Our narrower synthetic writer check reproduced that risk; this
  is not a test of an actual Meetings app crash or permission behavior.
- [PR #72](https://github.com/humanitas-labs/quill/pull/72), open: imported audio
  transcription, including Voice Memos. This is a future feature reference.
- [Issue #56](https://github.com/humanitas-labs/quill/issues/56): playback echo
  filtering; preserve legitimate repetitions and original audio.
- [Issue #57](https://github.com/humanitas-labs/quill/issues/57): settings and
  private paths/logs; coordinate focused storage-hardening contributions.
- [Issues #59](https://github.com/humanitas-labs/quill/issues/59),
  [#60](https://github.com/humanitas-labs/quill/issues/60), and
  [#61](https://github.com/humanitas-labs/quill/issues/61): permission identity,
  permanent startup failures, and app-bundle/signing work.
- Multilingual Parakeet, Whisper, per-app capture, and diarization remain
  separate upstream planning topics, not additions to this local product.

Older PRs #2, #6, #7, #12, and #18 are closed, not pending merged fixes. The
existing RegardingWork microphone work adapted historical PR #2's
configuration-change observer and same-file recovery concept; upstream's newer
segmented design is different and needs a selective integration review.

No cloud transcription PR was adopted, and no upstream PR was merged wholesale.
See [IMPROVEMENTS_AND_UPSTREAM.md](IMPROVEMENTS_AND_UPSTREAM.md) for local gaps,
verification limits, contribution candidates, and an approval-gated PR plan.

On 2026-10-03, the manual-retry feature was adapted to upstream master and
submitted as [draft PR #73](https://github.com/humanitas-labs/quill/pull/73)
from the separate `shadstoneofficial/quill` contribution fork. The release
build, 39 tests (7 new), CLI help, and formatting/diff checks passed locally.
Actual capture, menu interaction, and Parakeet inference were not manually
tested. The PR remains a draft, not an upstream merge or a new product build.

## Migration from an upstream development install

No data or configuration is moved automatically. That avoids overwriting,
merging, or deleting existing recordings without an explicit user choice.

- The old `~/.config/quill/config.json` is not read. Review it manually and
  create `~/.config/regardingwork-meetings/config.json`.
- The old `~/Recordings` folder is not renamed or deleted. Copy selected
  sessions into `~/RegardingWork Meetings` only after backing them up.
- Remove an old `com.digimata.quill` LaunchAgent separately before enabling
  `com.regardingwork.meetings`; never run both against the same recording root.
- Permission grants for an upstream binary do not transfer to the
  `com.regardingwork.meetings` app identity.

## Updating

```sh
git fetch upstream
git log --oneline --left-right HEAD...upstream/master
```

Review upstream changes; do not rebase away original history or overwrite
RegardingWork-specific behavior. Preserve the original `LICENSE` and update
this file when incorporating upstream work.
