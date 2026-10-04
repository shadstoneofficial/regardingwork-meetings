# Microphone reliability

RegardingWork Meetings records the macOS default input as the `mic.caf`
(`me`) track. A meeting application may use a separately selected microphone,
so the other participant hearing the local user does not prove Meetings is
receiving the same device.

## Verified zero-filled-buffer incident

An incident from 2026-09-14 produced a structurally valid 21:02.9 mono AAC/CAF
file containing 60,619,200 decoded samples, all exactly zero. System audio was
active and Parakeet completed normally. The final metadata correctly classified
the microphone as silent, but the prior health display and transient
notification were not prominent enough to prevent a lost local side.

This evidence proves a microphone capture/routing failure, not a transcription
failure. It does not by itself identify whether macOS, an audio route change,
or the input engine produced the zero-filled buffers because that build did not
record the microphone device identity.

No transcript text or conversation content is included in this incident note.

## Safety behavior

Current hardening distinguishes exact digital zeros from ordinary quiet:

1. At recording start, the menu bar displays **CHECK MIC** until a real
   microphone sample is observed.
2. The current macOS default input name appears in Welcome & Setup and in the
   live recording-health line.
3. If every microphone sample remains exactly zero for two seconds, the app
   preserves that attempt as `mic.zero-filled.caf`, rebuilds the raw microphone
   input graph once, and continues the session in `mic.caf`.
4. The automatic recovery is recorded in the in-progress manifest and final
   metadata.
5. If a call app reconfigures the input engine during a recording, the app
   debounces the change, reattaches raw capture to the same open CAF, pads the
   short restart gap to preserve the shared timeline, and records the restart
   count. Existing microphone audio is not replaced.
6. If zero-filled buffers continue, the menu bar retains **MIC!**, the menu
   reports `digital silence`, and a visible notification explains the failure.
7. If the macOS default input changes during recording, the menu reports the
   old and new device names and instructs the user to start a new recording.

The app does not repeatedly restart the input engine because a recovery loop
could create additional gaps or discard diagnostic evidence. It never treats
exact zeros as healthy audio.

## Immediate response during a call

If the menu displays **MIC!** or `mic digital silence`:

1. Leave the call application running.
2. Stop the current Meetings recording; this preserves everything already
   written, including system audio and diagnostic microphone evidence.
3. Confirm **System Settings → Sound → Input** and the call application name the
   same intended microphone.
4. Start a new Meetings recording and speak until **CHECK MIC** clears and the
   menu reports `mic ✓`.

Quitting and reopening Meetings while it is idle normally does not quit or end
the separate call application. Quitting Meetings while it is recording stops
and finalizes that Meetings session, so a new recording is required afterward.

## Manual verification matrix

Use disposable synthetic calls; never make a real meeting the first test.

- Built-in Mac microphone, with continuous speech for at least 20 seconds.
- USB microphone selected as both macOS default and call-app input.
- AirPods selected as both macOS default and call-app input.
- Call app deliberately set to a different input than macOS; confirm the
  displayed Meetings device makes the mismatch obvious.
- Connect or disconnect a device during recording; confirm `route changed` and
  **MIC!** remain visible.
- Feed zero-filled buffers in a controlled development test; confirm exactly
  one recovery attempt and preservation of `mic.zero-filled.caf`.
- Confirm successful recovery produces audible `mic.caf`, correct start offset,
  and microphone recovery fields in `meta.json`.
- Confirm persistent zero input never displays `mic ✓`.

Real-device route changes and the automatic AVAudioEngine recovery must be
manually validated on supported Macs. Unit tests cover health classification,
single-attempt policy, and route-change reporting, but cannot prove hardware or
macOS permission behavior.

## Upstream comparison

Reviewed `digimata/quill` again on 2026-09-15. Its default branch has no commits
after the commit from which this fork diverged, so there is no merged upstream
microphone fix to pull. Relevant work remains open:

- [PR #2](https://github.com/digimata/quill/pull/2) observes
  `AVAudioEngineConfigurationChange` and reattaches a microphone tap after a
  call app changes the input configuration. This branch adapts that recovery
  concept to the hardened recorder and keeps its file-preservation behavior.
- [PR #6](https://github.com/digimata/quill/pull/6) reports tracks that stop
  growing. RegardingWork Meetings instead evaluates live buffer and signal
  timestamps every second and exposes each track's state in the menu.
- [PR #18](https://github.com/digimata/quill/pull/18) proposes locks around
  recorder state. The fork already protects callback/main-thread recorder
  state with `OSAllocatedUnfairLock`.
- [Issue #11](https://github.com/digimata/quill/issues/11) requests visible
  track failures, and [issue #8](https://github.com/digimata/quill/issues/8)
  requests interrupted-session recovery. Both remain open upstream; the fork
  already implements the corresponding health and manifest/recovery flows.

The upstream configuration-change report involved a microphone file that
stopped growing. The verified RegardingWork incident produced a full-duration
file containing only exact zeros. These are related AVAudioEngine reliability
risks but not identical evidence, which is why both detectors are retained.
