# 本地依赖缓存

**简体中文** · [English](README.md) · [返回项目 README](../README.md)

运行 `Scripts/fetch-dependencies.sh` 下载固定版本、未修改的 BlackHole 2ch 与 Python 官方安装器及对应源码。
官方 URL、版本和 SHA-256 位于 `Installer/dependencies.tsv`。下载文件不提交到 Git。

`Scripts/package-release.sh` 在公开包中包含 Python 安装器及源码、BlackHole 源码；
BlackHole 二进制安装器由目标电脑安装时从官网下载。自用 `Local-Offline` 和 `Personal-Complete`
包会包含这个已缓存的安装器。

Apple PacketLogger 不由此下载脚本获取。公开版用户从
[Apple Developer](https://developer.apple.com/download/all/?q=Additional%20Tools) 获取 Additional Tools for Xcode，
然后向 `Install.command` 提供 `PacketLogger.app`。

制作本人的完整迁移测试包时，用 `--personal-complete /path/to/PacketLogger.app` 显式提供现有副本。
它只进入私有包的 `PrivateDependencies/`，不进入源码。不要向仓库或公开下载上传 Apple 应用、DMG 或个人完整包。
