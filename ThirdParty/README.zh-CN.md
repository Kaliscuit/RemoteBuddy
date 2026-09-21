# 第三方组件与致谢

**简体中文** · [English](README.md) · [返回项目 README](../README.md)

RemoteBuddy 源码版权归 2026 Kaliscuit 所有，按 **GPL-3.0-only** 发布，见 [LICENSE](../LICENSE)。
提供的图标作为项目资源一并收录。本项目是独立实现，不是 vRemoter 的分支，也不分发其应用或驱动。
协议研究参考了公开的 [vRemoter 项目](https://github.com/vincentkinghsu/vRemoter)，
没有将其应用、自定义驱动或仓库文件直接放入此项目。

本页为中文组件说明；上游许可证保留原文，不以翻译替换其授权文本。

## BlackHole 2ch 0.7.1

- 作者：Existential Audio Inc. 及贡献者。
- [官方项目](https://github.com/ExistentialAudio/BlackHole)、[官方安装器](https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg)、[对应源码](https://github.com/ExistentialAudio/BlackHole/tree/v0.7.1)。
- 源码许可为 GPL-3.0；完整上游声明见 [BlackHole-LICENSE.txt](BlackHole-LICENSE.txt)。
  官方编译产物、安装器和品牌另有权利保留声明。
- 未作修改。公开包附对应源码，并在安装时直接从 Existential Audio 官网取得安装器。
  `Local-Offline` 和 `Personal-Complete` 包缓存官方安装器，仅供本人设备使用，不公开上传。
  各版本都按固定 SHA-256 清单校验；项目不据此假定获得了二进制分发许可。
- [BlackHole 集成说明](https://github.com/ExistentialAudio/BlackHole#can-i-integrate-blackhole-into-my-app)要求 GPL-3.0 或单独授权。

## Python 3.13.15

- 作者：Python Software Foundation 及贡献者。
- [官方版本页面](https://www.python.org/downloads/release/python-31315/)。
- 许可证：PSF License Version 2 及附带声明，见 [Python-LICENSE.txt](Python-LICENSE.txt)。
- 发布包保留未修改的官方 universal2 macOS 安装器及对应 `Python-3.13.15.tar.xz` 源码，
  安装器中的其他第三方声明也保持原样。
- 辅助服务只使用标准库，以 `-I -S -B` 启动，禁用用户包和 site 启动加载。

## Apple PacketLogger：不进入公开分发包

Apple 的 Additional Tools for Xcode 是专有软件。
[Apple Xcode and Apple SDKs Agreement](https://www.apple.com/legal/sla/docs/xcode.pdf) 第 2.7 条限制再分发。
本仓库和公开安装包不包含 PacketLogger 或 Apple 的磁盘映像。公开版使用者需要从
[Apple Developer](https://developer.apple.com/download/all/?q=Additional%20Tools) 按其条款取得软件，
再向安装器提供本地应用路径。安装器校验 Apple 签名，复制未修改的整个应用。

已验证版本：Additional Tools for Xcode 26.5 中的 PacketLogger 26.0.0，最低 macOS 14。
其他版本可能改变命令行接口或系统要求。

`--personal-complete` 仅将维护者现有的原版 Apple 签名应用放入本人授权 Mac 迁移与开发测试包。
此包为私用，排除在 Git 之外，不得上传或作为公开下载。
这不授予第三方再分发权，也不会将 Apple 软件重新按 RemoteBuddy 的 GPL 授权。
