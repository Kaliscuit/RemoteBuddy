# 开发与发布

**简体中文** · [English](DEVELOPMENT.md) · [返回 README](../README.md)

## 目录

- `Sources/RemoteBuddy/`：`App`、`Audio`、`Bluetooth`、`Input`、`Settings`、`Support`、`Diagnostics`。
- `Helpers/hci_helper.py`：以 root 运行的流式 PacketLogger 解析器和受限 Unix socket 服务。
- `Installer/`：安装、配置生成、锁定版本的依赖清单、只读检查与停用脚本。
- `Scripts/`：测试、通用应用构建、图标生成、依赖下载和打包工具。
- `Resources/`：应用及状态栏图标、中英文界面资源、精简蓝牙兼容描述文件。
- `Tests/`：Swift 行为和翻译测试；Python 合成数据解析和安装配置测试。
- `ThirdParty/`：第三方说明及上游许可证原文。

抓包、个人设置、真实设备地址、签名证书和 Apple 二进制不应提交到 Git。
诊断功能只在明确启用时使用；正式界面不提供旧的实验读取菜单。
历史临时脚本和重复的 Python 解码器已从源码目录移除。

## 构建

开发需要带 macOS 26 SDK 的 Xcode，以及用于测试的 Python 3。
应用部署目标为 macOS 13；CoreHID 诊断需要新 SDK。
`Scripts/build-app.sh` 构建 arm64 + x86_64 通用程序。
使用发布包的新电脑不需要安装 Xcode、Homebrew 或开发用 Python。

依次运行：

```sh
./Scripts/test.sh
./Scripts/build-app.sh
./Scripts/fetch-dependencies.sh
```

设置 `SIGNING_IDENTITY` 可以使用 Developer ID 签名；默认仅作本地 ad-hoc 签名。
源码开源不会自动完成应用公证。对外声称已公证之前，维护者必须完成签名、公证和 stapling。
描述文件当前未签名，由用户在系统设置中手动安装；应用签名不能替代描述文件和权限确认。

`Scripts/build-app.sh --regenerate-icons` 可从提供的 PNG 重新生成图标。
正常构建使用仓库内已有图标，不需要图像生成服务。

## 三种安装包

| 命令参数 | 内容与用途 |
| --- | --- |
| 无参数 | `Public`：公开发布。包含应用、安装器、Python 安装包与源码、BlackHole 源码、RemoteBuddy 源码和许可证；安装时从官网获取 BlackHole 安装器，用户另行提供 PacketLogger。 |
| `--local-offline` | `Local-Offline`：另含已缓存的 BlackHole 安装器，供本人设备使用；仍不包含 PacketLogger，不用于公开分发。 |
| `--personal-complete /path/to/PacketLogger.app` | `Personal-Complete`：再加入本人的原版 PacketLogger，供本人授权 Mac 迁移与开发测试。安装器自动识别，不可上传 GitHub 或作为公开下载。 |

示例：

```sh
./Scripts/package-release.sh
./Scripts/package-release.sh --personal-complete '/path/to/PacketLogger.app'
```

个人包的 Apple 应用位于 `PrivateDependencies/`，不会进入 `Source/` 快照，并被 Git 忽略。
公开模式不会包含 Apple 工具。所有版本与 SHA-256 固定在 `Installer/dependencies.tsv`。

升级依赖时同时更新版本、官方 URL、校验和、许可证和对应源码，并检查官方安装包签名和公证。
不能仅因为下载成功就接受新的校验和。CI 执行测试和构建，不自动发布，也不自动获取 Apple 工具。

发布源码按明确的目录清单复制，不递归打包整个工作区。提交前执行 `Scripts/audit-source.sh`，
确认 Apple 软件、`.git`、缓存、抓包和个人配置不会进入公开产物。

## 为什么保留 PacketLogger

PacketLogger 是当前按键兼容通道的运行依赖，不只是日志查看器。
它向辅助服务提供未被 macOS HID 解析丢弃的按键通知；语音使用独立的 BLE 通道。
删除此依赖需要另一个已验证能完整接收按键报告的来源，目前尚未提供这种替代方案。

## 兼容性和数据边界

内部 `local.codex.RemoteMic` 标识及 `RemoteMic` 设置目录保留以兼容已有安装。
用户目录、UID、GID 和遥控器地址在安装时生成。应用从 root 所有的配置文件读取预期设备地址，
不会信任任意 socket 消息提供的新设备身份。
协议 v2 允许配置用户更新经过验证的设备选择字段，应用回读 root 配置后才同步切换按键和语音。
该操作不能修改个人映射或系统服务路径。修改此流程时，应检查格式验证、原子写入失败、
连接方身份、旧版辅助服务兼容，以及同名设备选择。

PacketLogger 的起始记录同时可能含缓存的元数据时间和实时包时间。
不要用第一条记录去统一校准所有实时事件。FIFO 只读取实时数据；IPC 带当前接收时间，应用拒绝过期输入。
辅助服务的原始流量只在内存处理；系统描述文件另外启用 macOS 自身的蓝牙日志，安装说明已披露。

自动测试验证解析、映射和安装配置。成功编译两种架构不等于已在其他 Mac、系统或固件上完成实机测试。
已验证的遥控器信息见 [README](../README.md)。
