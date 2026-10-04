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

1. At recording start, the menu bar displays **CHECK MIC** until a
   nonzero microphone sample is observed; this alone does not prove speech.
2. Welcome & Setup shows the current macOS default input. The recording-health
   line in v0.1.4 shows the current macOS default microphone, not a startup-only
   snapshot. Observed routes and health changes are retained privately, with
   the initial capture device recorded separately.
3. If every microphone sample remains exactly zero for two seconds, the app
   preserves that attempt as `mic.zero-filled.caf`, rebuilds the raw microphone
   input graph once, and continues the session in `mic.caf`.
4. The automatic recovery is recorded in the in-progress manifest and final
   metadata.
5. If a call app reconfigures the input engine during a recording, the app
   debounces the change, reattaches raw capture to the same open CAF, pads the
   short restart gap to preserve the shared timeline, and records the restart
   count. Existing microphone audio is not replaced.
   Version 0.1.4 counts committed padding once across repeated failed restarts
   and invalidates scheduled configuration retries on stop.
6. If zero-filled buffers continue, the menu bar retains **MIC!**, the menu
   reports `digital silence`, and a visible notification explains the failure.
7. If the macOS default input changes during recording, the menu reports the
   old and new device names and instructs the user to start a new recording.

Digital-zero repair is limited to one attempt; configuration restart failures
can retry until stopped. The app never treats
exact zeros as healthy audio.

Version 0.1.4 uses common run-loop modes for health/timing checks while a menu
is tracking. A synthetic run-loop test verifies registration; actual menu-open
recording still requires pilot testing.

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

Checked again on 2026-10-03. `digimata/quill` now redirects to
`humanitas-labs/quill`, and its current `master` includes
[segmented route recovery](https://github.com/humanitas-labs/quill/commit/8c46659a2a67638ccbf36e1d4d1e0036c81976f4).
The September observation that upstream had no newer commits is no longer
current.

Upstream restarts failed capture into numbered files, retains prior segments,
records interruption history, and runs its watchdog in common run-loop modes.
The physical-device validation matrix remains open in
[issue #64](https://github.com/humanitas-labs/quill/issues/64). Historical PRs
#2, #6, and #18 are closed; they should not be described as still-open fixes.

RegardingWork's existing same-file restart/padding and exact-zero recovery are
different. Version 0.1.4 addresses repeated-gap accounting, durable health
history and current default-device display without changing the recording
format. Physical recovery still needs testing. A displayed device name or nonzero
sample is not proof that the intended speaker was recorded. See
[IMPROVEMENTS_AND_UPSTREAM.md](IMPROVEMENTS_AND_UPSTREAM.md) for the reviewed
gaps, test evidence, and proposed integration/contribution boundaries.

The upstream configuration-change report involved a microphone file that
stopped growing. The verified RegardingWork incident produced a full-duration
file containing only exact zeros. These are related AVAudioEngine reliability
risks but not identical evidence, which is why both detectors are retained.
