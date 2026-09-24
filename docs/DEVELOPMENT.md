# Development and release

**English** · [简体中文](DEVELOPMENT.zh-CN.md) · [Project README](../README.en.md)

## Layout

- `Sources/RemoteBuddy/`: `App`, `Audio`, `Bluetooth`, `Input`, `Settings`, `Support`, `Diagnostics`.
- `Helpers/hci_helper.py`: root-side streaming PacketLogger parser and restricted Unix socket service.
- `Installer/`: portable setup, config generation, pinned dependencies, read-only checks and disable scripts.
- `Scripts/`: tests, universal app build, icon regeneration, dependency fetch and release packaging.
- `Resources/`: supplied artwork, icon variants, localization and minimal capture profile.
- `Tests/`: Swift behavior/localization tests, synthetic Python stream and installer tests.
- `ThirdParty/`: upstream notices and licenses.

No capture files, personal settings, real device addresses, certificates or Apple
binaries belong in Git. Diagnostics are opt-in; the old experimental-read menu
is absent. Historical scratch scripts and duplicate Python decoders were omitted.

## Build requirements

Xcode with macOS 26 SDK (the opt-in CoreHID probe requires the SDK), macOS 13+
application deployment target, Python 3 for tests. `Scripts/build-app.sh` builds
arm64 + x86_64. The installed app needs only macOS frameworks and the packaged
runtime for the helper; Xcode and Python build tooling are not target requirements.

Run `Scripts/test.sh`, `Scripts/build-app.sh`, then
`Scripts/fetch-dependencies.sh`. Set `SIGNING_IDENTITY` for a Developer ID build;
by default the application is ad-hoc signed for local use. An open-source
release is not automatically notarized. A maintainer must separately sign,
notarize and staple before describing a release as notarized.

`Scripts/build-app.sh --regenerate-icons` recreates icons from the supplied PNGs.
Normal builds use checked-in generated icons and need no image-generation service.

## Release contents

`Scripts/package-release.sh` creates the public ZIP in `dist/`. It includes the
app, installer, Python installer and source, BlackHole source, full RemoteBuddy
source and licenses. BlackHole's official **binary installer is not mirrored**:
the installer fetches it from Existential Audio. The SHA-256 values are pinned.
Apple PacketLogger is always excluded and is supplied by the end user.

`Scripts/package-release.sh --local-offline` additionally includes the cached
BlackHole binary installer, for the maintainer's own Macs. Never upload this
Local-Offline archive to GitHub, Releases or another distribution channel.
It still requires the user's separately obtained PacketLogger.

For your own authorized Mac migration/development tests only, use
`Scripts/package-release.sh --personal-complete /path/to/PacketLogger.app`.
This produces a **Personal-Complete** archive containing the unmodified Apple
application in `PrivateDependencies/`; the installer detects it automatically.
This private directory is never included in the source snapshot and is ignored
by Git. Do not publish this archive. Public mode never includes the Apple tool.

Update dependency versions, download URLs and checksums together. Verify upstream
licenses and notarized package signatures on every upgrade. Do not trust a changed
hash simply because the download succeeds. Corresponding source archives and
license notices accompany runtime packages. CI tests and builds but does not
publish releases or acquire Apple tools automatically.

The release source snapshot is an explicit allowlist, not a recursive copy of
the working directory. Apple software, `.git`, caches, captures and local config
must not enter any public artifact. PacketLogger is a runtime dependency of the
current button compatibility bridge, not merely a debugging log viewer. Voice
uses a separate BLE path. Removing this dependency requires another validated
source of complete button reports. Verify `Scripts/audit-source.sh` before commit.

## Compatibility notes

Internal `local.codex.RemoteMic` IDs and the `RemoteMic` config directory are kept
to preserve existing installations. User home/UID/GID/remote address are generated
at install time. The user-side client reads the remote identity from the root-owned
helper config. It never learns a remote identity from arbitrary socket messages.
Protocol v2 permits the configured user to update only validated device-selection
fields. The app reads back the root-owned file before switching both button and
voice connections. User mappings and privileged service paths are not editable
through that operation. Test format validation, atomic-write failure, peer
ownership, old helpers, and same-name device selection when changing this path.

PacketLogger records begin with cached metadata timestamps as well as live packets.
Do not calibrate live events from the first record. The FIFO is live-only; IPC
includes current receive timestamps and stale input is rejected by the client.
Helper traffic must stay in memory. The OS profile separately enables macOS raw
Bluetooth logging, disclosed in the install guide.

Synthetic tests cover parsing, mapping and config portability. Building both CPU
architectures does not replace testing a new Mac, OS version or remote firmware.
