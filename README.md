# RemoteBuddy

<img src="Resources/Artwork/AppIcon-source.png" width="128" alt="RemoteBuddy 应用图标：橙色背景上的白色遥控器">

**简体中文** · [English](README.en.md)

把 Google Chromecast Voice Remote 变成 Mac 的语音输入与可自定义按键遥控器。
界面支持中文和英文，自动跟随 macOS 首选语言。

<img src="docs/images/status-icon-preview.png" width="360" alt="状态栏图标在浅色、深色和收音状态下的展示">

状态栏图标：浅色模式、深色模式、收音中（红色）。

- 遥控器麦克风通过 ATVV 蓝牙服务传输语音，解码后送入 BlackHole 2ch。
- 按键可映射为快捷键、系统音量、打开应用或网址，保存后立即生效。
- 语音键短按切换收音、按住说话；普通按键没有独立长按设置。
- 支持登录自启、按键松开保护；修复已测试遥控器在 macOS 上的单按漏键问题。

## 已验证的遥控器

| 项目 | 已验证信息 |
| --- | --- |
| 产品 | **Google Chromecast Voice Remote**（Chromecast with Google TV 配套语音遥控器） |
| 蓝牙设备名称 | `Chromecast Remote` |
| 蓝牙设备信息中的型号标识 | **ABBEY** |
| Firmware / Software | **22.2 / 22.2** |
| USB/HID Vendor ID / Product ID | `0x18D1` / `0x9450` |
| 按键 ATT 报告句柄 | `0x0046` |
| 已完成实机验证的平台 | Apple Silicon，macOS 26.5.2 |

ABBEY 是从设备信息读取的型号标识，不是所有 Google TV 遥控器的统称。
Google TV Streamer Voice Remote、第三方替代遥控器和其他固件版本尚未验证。
应用已构建为 Intel / Apple Silicon 通用程序，但尚未在 Intel 或所有旧系统完成硬件验证。
[Google 官方遥控器介绍](https://support.google.com/chromecast/answer/10116742?hl=zh-Hans)。

## PacketLogger 为什么必需

**PacketLogger 是当前按键兼容方案的运行依赖，不只是用于记录诊断日志。**
已测试遥控器的单字节 HID 报告会被 macOS 的正常 HID 通道丢弃；
辅助服务借助 PacketLogger 的实时 HCI 数据取得完整的按下和松开事件。
不需要手动打开 PacketLogger 的图形窗口，安装后的辅助服务会按需启动捕获。
语音使用独立的 BLE / ATVV 通道，不依赖 PacketLogger。

按键路径：`遥控器 → PacketLogger → 本机辅助服务 → RemoteBuddy → Mac 按键事件`。

## 在新电脑安装

公开版安装包位于项目的 [Releases](https://github.com/Kaliscuit/RemoteBuddy/releases)。
GitHub 的源码 ZIP 不含已构建应用，需要先按下文构建。

| 安装包 | BlackHole 2ch | Python 运行时 | PacketLogger |
| --- | --- | --- | --- |
| `Public`：用于公开发布 | 安装时从官网自动下载并校验 | 已包含 | 使用者从 Apple 官方获取 |
| `Personal-Complete`：供本人其他 Mac 迁移测试 | 已包含 | 已包含 | 已包含本人的原版副本，安装器自动识别 |

另有 `Local-Offline` 依赖缓存包，其中没有 PacketLogger；它不是个人完整包。
个人包不用于公开分发。新电脑无需 Homebrew、Xcode 或预装 Python。

**公开版用户按以下步骤操作：**

1. 在 Mac 蓝牙设置中配对遥控器，并在“系统信息 → 蓝牙”中记录它的地址。
2. 登录 [Apple Developer 下载页](https://developer.apple.com/download/all/?q=Additional%20Tools)，
   下载兼容当前 macOS 的 **Additional Tools for Xcode**，打开 `.dmg`，找到并复制 `PacketLogger.app`。
   不需要安装完整 Xcode。已验证版本为 Additional Tools for Xcode 26.5 内的 PacketLogger 26.0.0。
3. 解压 RemoteBuddy 发布包，运行 **Install.command**，填写 PacketLogger 的路径和遥控器地址，
   核对安装计划后输入本机管理员密码。
4. 在系统设置中安装 **RemoteBuddy Bluetooth Compatibility** 描述文件，重启 Mac，
   允许 RemoteBuddy 使用蓝牙和辅助功能。
5. 在语音输入或录音应用中选择 **BlackHole 2ch** 为麦克风，再实际测试方向键和语音。

**个人完整包用户**直接从第 3 步运行安装器；PacketLogger 路径会自动识别，仍需完成配对、
遥控器地址、管理员授权、描述文件和系统权限设置。

应用部署目标为 macOS 13；PacketLogger 可能要求更新系统，安装器会检查。
当前个人包中的 PacketLogger 最低要求 macOS 14。新电脑的完整实装仍需在目标机器验证。

详细步骤、检查与停用见 [中文安装指南](docs/INSTALL.zh-CN.md)。
`Check.command` 执行只读检查；`Uninstall.command` 停用自启、辅助服务和捕获配置。
当前应用是本地签名构建，尚未经过 Developer ID 公证，首次运行可能需要在系统设置允许打开。

## 初始映射

| 遥控器按键 | Mac 操作 |
| --- | --- |
| 方向环 / 确定 | 方向键 / Return |
| 返回 / 电源 / 信号源 | Delete（删除左侧字符）/ Esc / Control+C |
| YouTube / Netflix | Page Up / Page Down |
| Home | Command+Space |
| 音量、静音 | 系统音量 |
| 语音短按 / 按住 | Fn+Space 切换 / 保持 Fn |

通过菜单栏 **按键设置…** 修改映射。设置窗口打开时，遥控器只用于选择待配置按键，
暂停执行映射和语音输出。所有普通按键按住约 0.34 秒后都会连发，不按物理按键或映射类型过滤：
包括删除、翻页、组合快捷键、音量、静音、播放/暂停、打开应用和网址。禁用动作仍不执行。
连发目标间隔为 65 毫秒，各键独立计时；松开即停止。按住超过两秒会强制释放，松开再按可继续。
语音键保持短按切换收音、按住说话的行为。

## 源码与构建

```sh
git clone git@github.com:Kaliscuit/RemoteBuddy.git
cd RemoteBuddy
./Scripts/test.sh
./Scripts/build-app.sh
./Scripts/fetch-dependencies.sh
./Scripts/package-release.sh
```

开发需要带 macOS 26 SDK 的 Xcode（用于 CoreHID 诊断）和 Python 3（用于测试）。
输出位于 `dist/`。依赖下载、个人配置、编译缓存、抓包和私人完整包均不提交到 Git。

文档均提供中英文对照入口：

- [安装](docs/INSTALL.zh-CN.md) · [Installation](docs/INSTALL.en.md)
- [开发与发布](docs/DEVELOPMENT.zh-CN.md) · [Development](docs/DEVELOPMENT.md)
- [按键兼容原理](docs/PROTOCOL.zh-CN.md) · [Protocol](docs/PROTOCOL.md)
- [第三方组件](ThirdParty/README.zh-CN.md) · [Third-party notices](ThirdParty/README.md)

## 数据与兼容性

辅助服务以 root 运行，验证本地连接用户并按指定遥控器地址、ATT 句柄过滤通知。
原始捕获通过内存 FIFO 处理，不由辅助服务保存为抓包文件或上传网络。
**兼容描述文件会启用 macOS 自身的蓝牙原始日志，可能包含其他蓝牙设备的信息。**
退出应用停止实时捕获；要关闭系统捕获配置，请运行停用工具或在系统设置移除描述文件。

旧内部名称 `local.codex.RemoteMic` / `RemoteMic` 保留以兼容已有权限和映射。
用户名、UID 和遥控器地址在安装时生成；每台 Mac 的服务目前支持一个指定用户、一只遥控器。

许可证：**GPL-3.0-only**。见 [LICENSE](LICENSE) 和 [第三方说明](ThirdParty/README.zh-CN.md)。
