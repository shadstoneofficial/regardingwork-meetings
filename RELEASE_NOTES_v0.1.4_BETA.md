# RegardingWork Meetings 0.1.4 Beta Candidate

Focused local recording/transcription reliability improvements:

- Failed transcription tracks remain retryable; successful track output is
  retained privately and partial reports no longer look complete.
- Recovery retains original evidence, historical track warnings and capture
  timing instead of using the next launch's time or microphone.
- Current default microphone identity and route history are recorded, health
  monitoring continues during menu tracking, and restart padding is not repeated.

This is an unmerged pilot candidate. No stable release or default-branch merge
is implied. Local Parakeet, AAC-in-CAF, source-track attribution and playback-echo
defaults are unchanged. Abruptly interrupted AAC may still be unreadable.
Original audio and older completed transcripts are preserved.

Automated synthetic tests do not prove physical audio capture, real Parakeet
inference, sleep/wake or actual-app crash recovery. Complete PILOT.md using
disposable synthetic sessions before relying on the candidate in a meeting.
Signed-artifact source SHA, Apple IDs and hashes belong in the verification
report after packaging, not an unverified release announcement.
