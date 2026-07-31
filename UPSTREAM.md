# Upstream

RegardingWork Meetings preserves the complete Git history and unchanged MIT
license of the project cloned from:

`https://github.com/digimata/quill.git`

Remotes:

```text
origin   https://github.com/shadstoneofficial/regardingwork-meetings.git
upstream https://github.com/digimata/quill.git
```

Quill and Digimata names are retained only for original licensing, attribution,
the upstream remote, and migration history. Runtime identities and paths use
RegardingWork Meetings.

## Reviewed upstream context

Reviewed on 2026-07-31, with source code treated as authoritative:

- Issues #14 and #19: duplicated system playback in the microphone transcript
  and incorrect-looking `me`/`them` attribution.
- Issue #11 and PR #6: invisible track failures and a file-growth watchdog.
- Issue #8: interrupted sessions with readable CAF files but no `meta.json`.
- PR #2: mic capture stopping after call-app input reconfiguration.
- PR #7: write Markdown before JSON so JSON remains the completion marker.
- PR #18: recorder shared-state races and invalid menu SVG markup.
- Issue #23: broad global capture and a proposed future per-app selector.
- Issues #5 and #13 plus PRs #4 and #9: multilingual Parakeet and Whisper
  requests. These are documented as future options and are not added here.
- PR #12: `.app`/DMG Developer ID signing and notarization direction.
- PR #20 and issue #22: true remote-speaker diarization/naming proposals; these
  are outside this product's two-track attribution scope.

No cloud transcription PR was adopted. No upstream PR was merged wholesale;
the local implementation follows this repository's privacy and preservation
guardrails.

## Updating

```sh
git fetch upstream
git log --oneline --left-right HEAD...upstream/master
```

Review upstream changes; do not rebase away original history or overwrite
RegardingWork-specific behavior. Preserve the original `LICENSE` and update
this file when incorporating upstream work.
