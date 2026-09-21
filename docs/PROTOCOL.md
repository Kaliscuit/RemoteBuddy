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

Microphone data takes the independent public ATVV BLE service path, with standard
IMA ADPCM decoding and BlackHole audio output. A working voice path alone does not
prove button delivery. No raw recordings, live device addresses or private capture
artifacts are included in this repository; tests use synthetic fixtures.
