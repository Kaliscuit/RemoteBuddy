# Local dependency cache

**English** · [简体中文](README.zh-CN.md) · [Project README](../README.en.md)

Run `Scripts/fetch-dependencies.sh` to download pinned, unmodified BlackHole 2ch
and Python installers and their corresponding sources. Official URLs, versions
and SHA-256 checksums live in `Installer/dependencies.tsv`. Downloads are ignored by Git.

`Scripts/package-release.sh` includes Python's installer/source and BlackHole's
source in public archives; BlackHole's binary installer is fetched from its
official website on the target Mac. Private `Local-Offline` and `Personal-Complete`
archives also include that cached installer.

Apple PacketLogger is not fetched by this script. Public users obtain Additional
Tools for Xcode from [Apple Developer](https://developer.apple.com/download/all/?q=Additional%20Tools)
and provide `PacketLogger.app` to `Install.command`.

For the owner's complete migration/development test archive, explicitly provide
an existing copy using `--personal-complete /path/to/PacketLogger.app`. It enters
only the private archive's `PrivateDependencies/`, not the source snapshot. Never
upload Apple's application, DMG or personal complete archive to the repository or public downloads.
