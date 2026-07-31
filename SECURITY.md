# Security

## Supported security posture

RegardingWork Meetings is a local macOS utility. Its security boundary is the
signed app, the current macOS user account, the recording root, and locally
cached transcription models. Session data is created with user-only POSIX
permissions. Atomic metadata/transcript writes prevent partial completion
markers.

## Important trust boundaries

- The global system-audio tap is intentionally broad.
- FluidAudio and downloaded Parakeet model artifacts are third-party inputs.
- An explicitly configured `on_stop` executable is trusted code with the
  current user's permissions.
- Anyone who can read the macOS user account or its backups may read meetings.

The app does not parse transcript or metadata text as commands. `on_stop`
rejects shell strings and uses direct executable/argv invocation. Keep hook
executables absolute, locally controlled, and non-writable by untrusted users.

## Secrets and signing

Never commit certificates, `.p12` exports, private keys, app-specific passwords,
API keys, keychain files, environment files, notarization responses containing
sensitive context, recordings, transcripts, or models. Signing uses a local
Developer ID identity and a `notarytool` keychain profile. Repository scripts
contain names only, never secret values.

## Reporting

Report vulnerabilities privately to the repository owner. Do not attach real
meeting audio or transcripts to issues. Provide synthetic reproduction data and
redacted logs; session logs should not contain transcript text.

## Known limitations

- POSIX modes do not protect data from the logged-in user, administrators,
  malware, backups, or separately configured folder synchronization.
- A process crash can leave recoverable but incomplete audio.
- Track health detects missing buffers and recent signal, not semantic audio
  correctness.
- Source-track labels are not identity verification or remote-speaker
  diarization.
- Ad-hoc builds do not provide the stable trust of Developer ID notarization.
