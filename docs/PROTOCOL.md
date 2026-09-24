# Short HID report compatibility

**English** · [简体中文](PROTOCOL.zh-CN.md) · [Project README](../README.en.md)

The tested Chromecast Voice Remote (VID 0x18D1, PID 0x9450, model ABBEY,
firmware 22.2) declares two Consumer array slots for Report 1 but sends one-byte
payloads for single presses and releases. macOS IOHID/CoreHID passed dual-key
reports while discarding these short reports. HCI capture contained both press
and release edges, locating the loss after Bluetooth receipt and before normal
HID delivery. This is why changing mappings or batteries did not fix single taps.

The helper reads Apple's live PacketLogger stream through a private FIFO. It
identifies connection handles from device metadata/LE connection events using the
configured remote address. It reassembles ACL/L2CAP fragments and admits only ATT
notifications/indications for the configured report handle (tested: 0x0046), with
one or two valid remote key bytes. It sends only filtered reports to the selected
user over a mode-0600 Unix socket, validating peer UID. The app validates root
peer identity and rejects stale events. Disconnects and a watchdog release keys.

The `zhuhai_jieli` / `hid_mouse` / 0.0.1 variant sends a two-byte little-endian
Consumer Usage on handle `0x002b`. With `report_format: "consumer16"`, the helper
normalizes the 14 observed buttons and release reports to the existing IDs.
Unknown usages, incorrect lengths, and other devices/attributes are rejected.
`indexed` remains the default for older configurations; payload formats are not guessed.

This variant also delays the voice release notification: even a tap with no audio
has about 1.3 seconds between AUDIO_START and AUDIO_STOP. The app reads the
manufacturer (0x2A29), model (0x2A24), and firmware (0x2A26) from Device Information.
`RemoteCompatibilityProfile` enables the workaround only when all three match
`zhuhai_jieli` / `hid_mouse` / `0.0.1`. It promotes a press to a hold after 550 ms of
decoded audio, including silence, instead of counting the delayed notification.
A short press opens a continuous stream after release. A subsequent physical
press stops it even when the firmware reuses the current stream ID.

Other manufacturers, models, firmware versions, or incomplete device information
keep the standard elapsed-time gesture detection. Matching ignores case and
surrounding string padding but does not use prefixes or the Bluetooth display
name. Identity is cleared when connecting to a device. This automatic voice
profile handles voice timing independently of the selected button protocol.
Remote Settings reads connected HID metadata through IOKit, including
`DeviceAddress`, `PhysicalDeviceUniqueID`, manufacturer, model, firmware, and
VID/PID. The physical UUID selects the matching CoreBluetooth peripheral, never
the first device with the same name. Verified VID/PID plus ABBEY / 22.2 selects
`0x46` / `indexed`; the full Jieli identity plus VID/PID selects `0x2b` /
`consumer16`. Unknown identities require verified manual settings.

Helper protocol v2 accepts one bounded device-selection JSON message from its
configured peer UID. It validates a strict field allowlist, address, format,
handle, optional peripheral UUID, and detection flag. It cannot change UID/GID,
socket or executable paths. The root-owned config is atomically replaced, then
the client reads it back and restarts both input paths. Capture restarts with
fresh connection metadata. Malformed requests and failed writes preserve the
old file. Older helpers are detected before sending a configuration request.

A remote-initiated voice stop ends the local gesture without sending another
MIC_CLOSE. Stop acknowledgements reset local state without further commands,
preventing a feedback loop on firmware that acknowledges every close.

Microphone data takes the independent public ATVV BLE service path, with standard
IMA ADPCM decoding and BlackHole audio output. A working voice path alone does not
prove button delivery. No raw recordings, live device addresses or private capture
artifacts are included in this repository; tests use synthetic fixtures.
