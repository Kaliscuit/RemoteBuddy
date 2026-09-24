# Clean installation

**English** · [简体中文](INSTALL.zh-CN.md) · [Project README](../README.en.md)

## Choose the correct archive

- **Public** includes Python and downloads BlackHole's installer from its official website.
  Obtain PacketLogger from Apple using the instructions below.
- **Personal-Complete**, for the owner's other Macs and migration/development tests,
  includes RemoteBuddy, BlackHole 2ch, Python and the owner's original PacketLogger.
  Skip the Apple download; the installer detects the bundled copy.
- **Local-Offline** only caches BlackHole/Python and has no PacketLogger. It is not
  the personal complete archive.

Neither private variant is for public distribution. Every variant still needs remote
pairing, administrator authorization, the compatibility profile, Bluetooth and
Accessibility permission on the new Mac. The current personal archive's PacketLogger
requires macOS 14+. Hardware validation covers Apple Silicon and macOS 26.5.2.

## Why PacketLogger is required

PacketLogger supplies live HCI data for the button workaround; it is not an optional
logging attachment. Removing it may bring back missed/delayed single presses on the
tested remote. Voice uses an independent BLE path. You do not need to launch the
PacketLogger GUI; the installed helper manages capture in the background.

## Public archive: obtain PacketLogger

1. Open [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Additional%20Tools)
   and sign in to your Apple account as requested.
2. Search for **Additional Tools for Xcode** and choose a version compatible with
   the target macOS. Validated: **Additional Tools for Xcode 26.5 → PacketLogger 26.0.0**.
3. Download and open the `.dmg`, then locate **PacketLogger.app** in the disk image.
   Full Xcode is not required. Do not extract only the executable from inside the app.
4. Copy the entire, unmodified `PacketLogger.app` into a local folder, such as your
   own `~/Applications/`, preserving its original signature and contents.
5. Supply its full path when running the RemoteBuddy installer. At the interactive
   prompt use the actual absolute path, without extra quotes or an unexpanded `~`.
   The installer checks Apple's signature, CPU architecture and minimum macOS.

Public packages do not mirror Apple tools; see [third-party notices](../ThirdParty/README.md).

## Install

1. Pair the Chromecast Voice Remote in macOS Bluetooth settings. The tested device
   is **Google Chromecast Voice Remote**, Bluetooth model identifier **ABBEY**,
   Firmware / Software **22.2 / 22.2**, VID/PID `0x18D1` / `0x9450`.
   Other remotes/firmware are unverified; see the [device table](../README.en.md).
   To enter pairing mode, hold **Back + Home** until the LED pulses, then connect
   in the Mac's Bluetooth settings. See [Google's button instructions](https://support.google.com/chromecast/answer/10109990?hl=en).
2. Extract the complete RemoteBuddy release, not GitHub's source-only ZIP.
3. **Public / Local-Offline users only:** download Additional Tools for Xcode from
   [Apple Developer](https://developer.apple.com/download/all/?q=Additional%20Tools)
   and locate `PacketLogger.app`. A free Apple account/login may be required.
   Full Xcode is not needed on the target Mac. Tested: PacketLogger 26.0.0 from
   Additional Tools for Xcode 26.5. Choose a version compatible with your macOS.
4. Find the remote's Bluetooth address in **System Information → Bluetooth**.
5. Run **Install.command**. Public / Local-Offline users enter the original
   PacketLogger path (without added quotes); Personal-Complete detects it automatically.
   Enter your remote's address, review the plan and confirm. The public
   release fetches BlackHole 2ch from the official website and verifies its hash.
   The local offline variant already caches this download and must not be published.
6. Enter your administrator password in Terminal, never in chat. The installer
   installs BlackHole/Python as needed, the helper and login startup. No Homebrew,
   Xcode or existing Python is required. The dedicated Python runtime is installed
   from the unmodified python.org package and may also install Python's standard tools.
7. Install the opened **RemoteBuddy Bluetooth Compatibility** profile
   (`RemoteBuddy-Bluetooth.mobileconfig`) in System Settings; search for Profiles
   or Device Management if needed. It is unsigned and requests system Bluetooth HCI capture. This may
   cause macOS to retain raw traffic from other Bluetooth devices as well.
8. Restart the Mac. Allow RemoteBuddy's Bluetooth and Accessibility permissions.
   Select **BlackHole 2ch** as the microphone in your recording/dictation app.

RemoteBuddy is locally signed, not Developer ID notarized. Verify the download
and release checksum before allowing it through macOS Privacy & Security if
blocked. Do not disable SIP, Gatekeeper or boot security.

Optional arguments:

```sh
./Install.command "$HOME/Applications/PacketLogger.app" 'AA:BB:CC:DD:EE:FF' 0x46
```

Replace the sample address. The optional third argument is the ATT report handle;
`0x46` is verified for ABBEY 22.2. It may change with firmware.

### Replacing a remote

Identical Bluetooth names do not guarantee identical firmware or report formats.
ABBEY / 22.2 uses `0x46` and `indexed`. The supported `zhuhai_jieli` /
`hid_mouse` / 0.0.1 variant uses `0x2b` and `consumer16`; the helper translates
its Consumer usages to the existing button IDs, preserving personal mappings.
With a release containing this support, select the format using the fourth argument:

```sh
./Install.command "$HOME/Applications/PacketLogger.app" 'AA:BB:CC:DD:EE:FF' 0x2b consumer16
```

For an existing installation, device settings are in
`/Library/Application Support/RemoteMic/hci-config.json`. Back it up, update
`address`, and set `attribute` (`43` in JSON for `0x2b`) and `report_format` to
match the device. Missing `report_format` defaults to `indexed`. Keep the file
root-owned and writable only by root, restart the system helper and RemoteBuddy,
then reconnect the remote. Changing only the address cannot fix a different
report format; diagnose other firmware before selecting its parameters.

The voice release-delay workaround is selected automatically from the remote's
manufacturer, model, and firmware. All three must match the tested Jieli variant;
other devices keep the original gesture timing. See [protocol compatibility](PROTOCOL.md).

## Verify operation

The menu bar should show the remote icon, voice **Ready** and **Buttons:
Compatibility bridge connected**. Voice readiness alone does not verify button
capture; check the profile/helper if the button bridge is still waiting.

**Check.command** performs read-only checks. Service state is not a hardware test:
press each direction, OK and Back in a text editor; holding Back should repeatedly
delete and stop on release. Test voice toggle and hold-to-talk in an app listening
to BlackHole. Every ordinary button repeats its mapping, including shortcuts,
mute, app launches and websites, with independent timers. The two-second forced
release remains; release and press again to continue. Disabled actions do nothing. While Button Settings is open, button
output and microphone forwarding are paused.

If Karabiner is installed, exclude this remote to avoid duplicate handling.
Karabiner is not a dependency. Voice and button bridge status are independent.
Restart RemoteBuddy after changing system/app language.

## Python runtime permissions

The python.org installer normally allows the admin group to write to its framework.
For the root helper, setup makes Python 3.13 and its parent framework directories
root-owned and not writable by other users. Other Python versions are not traversed.
The helper uses `-I -S` to disable user packages and site initialization. Use virtual
environments for your own Python 3.13 dependencies after this change.

## Paths and removal

The app is in `~/Applications/RemoteBuddy.app`. Legacy `RemoteMic` internal paths
preserve upgrade compatibility: mappings live in
`~/Library/Application Support/RemoteMic/button-mappings.json`; the root helper,
config and user's PacketLogger copy live in `/Library/Application Support/RemoteMic/`.
Launch jobs are `local.codex.RemoteMic` (user) and `local.codex.RemoteMic.hci` (system).
One local user and one remote are supported; reinstalling for another user changes
that service binding. Existing app/config are backed up and mappings are preserved.

Run **Uninstall.command** to disable startup/helper and remove the capture profile.
The app and mappings are preserved for manual removal. Shared BlackHole/Python
installations are not deleted; use their official uninstall instructions if needed.
Quitting the app stops live capture but does not remove the system capture profile.
Failed installation stages may contain the user's Apple application; do not upload them.

## Personal complete archive

The private `Personal-Complete` archive includes your original PacketLogger and
the installer detects it automatically. Configure the remote address and confirm
administrator access, the profile and permissions on the new Mac. This archive
is for your own authorized Mac migration/development tests, not public download.

PacketLogger supplies live Bluetooth data required by the current button bridge;
it is not just a diagnostic log viewer. Voice uses an independent BLE path.
