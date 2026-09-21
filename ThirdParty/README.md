# Third-party software and attribution

**English** · [简体中文](README.zh-CN.md) · [Project README](../README.en.md)

RemoteBuddy source is copyright (c) 2026 Kaliscuit, distributed under
**GPL-3.0-only**; see the repository `LICENSE`. The supplied artwork is included
as part of the project. Upstream licenses are retained in their original language;
the Chinese notices do not replace the license texts. This is an independent implementation, not a fork or a
redistribution of vRemoter. Protocol discovery was informed by the public
[vRemoter project](https://github.com/vincentkinghsu/vRemoter); no upstream app,
custom driver or repository contents are included.

## BlackHole 2ch 0.7.1

- Author: Existential Audio Inc. and contributors.
- Official project: https://github.com/ExistentialAudio/BlackHole
- Installer: https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg
- Corresponding source: https://github.com/ExistentialAudio/BlackHole/tree/v0.7.1
- Source license: GPL-3.0; full upstream notice in `BlackHole-LICENSE.txt`.
  The upstream notice reserves rights in official binaries, installers and branding.
- No modifications. The **public release** includes the source archive and fetches
  the official installer directly from Existential Audio during installation.
  The `--local-offline` and `--personal-complete` packages include the downloaded installer solely for the
  maintainer’s own Mac setup; do not upload that package. All variants verify
  the same pinned SHA-256 manifest. No distribution permission is presumed.
- BlackHole's integration guidance calls for GPL-3.0 or a separate license:
  https://github.com/ExistentialAudio/BlackHole#can-i-integrate-blackhole-into-my-app

## Python 3.13.15

- Author: Python Software Foundation and contributors.
- Official release: https://www.python.org/downloads/release/python-31315/
- License: PSF License Version 2 and bundled notices; see `Python-LICENSE.txt`.
- No modifications. The release contains the original universal2 macOS
  installer and corresponding `Python-3.13.15.tar.xz` source archive. The
  installer's own additional third-party notices remain intact.
- The helper uses only the standard library and isolated mode with site loading disabled (`-I -S -B`).

## Apple PacketLogger — excluded from public distribution

Apple's Additional Tools for Xcode is proprietary. Section 2.7 of Apple's
[Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf)
restricts redistribution. This repository and generated public release do not
contain PacketLogger or Apple's disk image. Users must obtain the application
from https://developer.apple.com/download/all/?q=Additional%20Tools under Apple's
terms, then point the installer at their local copy. The installer checks Apple's
signature and copies the original, unmodified application locally.

Tested capture tool: PacketLogger 26.0.0 from Additional Tools for Xcode 26.5.
Different versions may change the CLI or minimum macOS requirement.

The optional `--personal-complete` archive copies the maintainer's existing,
unmodified Apple-signed app for their own authorized Mac migration/development
tests. It is explicitly private, excluded from Git and must not be uploaded or
published. This does not grant redistribution rights or relicense Apple software.
