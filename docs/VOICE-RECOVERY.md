# Voice stability fixes in 1.2.4

[简体中文](VOICE-RECOVERY.zh-CN.md) · [Installation](INSTALL.en.md)

This update addresses missing initial words, silent microphone input after opening Sound settings, and toggle recording that cannot be stopped. Recovery is internal; no menu action is added.

- Audio is buffered from the initial press. Playback begins 400 ms after sending the input method shortcut, preserving the prefix across the short-press microphone reopen. This fixed delay does not prove that every input method is ready.
- Buffered audio drains before the recording shortcut is released. If playback stalls, the shortcut is still released after a maximum two-second wait.
- Engine configuration notifications rebuild output on a dedicated queue and bind it to BlackHole again. A 500 ms health check detects stopped engines, changed output devices and queued audio without render progress. Recovery preserves the queue and retries failures with backoff.
- Delayed microphone opens and hold detection use cancellable session generations. Three seconds without audio packets resets the microphone and shortcuts. Quiet packets keep a session alive. A fresh press can recover from a missed previous release.
- A toggle-stop press immediately requests microphone closure without waiting for release. If no stop acknowledgement arrives within two seconds, the app resets and resends close even if audio continues. Keep-alive pauses while waiting for closure.
- Dispatch timers maintain keep-alive. Disconnects, write failures, remote timeouts and application exit clean up recording state.

Tests cover prefix/tail preservation, repeated taps, open/press races, stale tasks, remote stops, silent packets, missing release recovery and decoder sync isolation. A separate BlackHole check verified recovery after configuration notifications and a stopped engine without notifications.

Tests use synthetic data and simulated transport events. The user's remote and WeChat input method on the other Mac still require validation. Upgrade the app in `~/Applications`, confirm BlackHole 2ch is selected in the input method, then test initial words, Sound settings changes and repeated start/stop taps.

For remaining issues, export the recent numeric diagnostics (no recorded audio):

```sh
/usr/bin/log show --last 10m --style compact --info --predicate 'subsystem == "local.codex.RemoteMic" AND category == "audio"' > "$HOME/Desktop/RemoteBuddy-voice-diagnostics.txt"
```
