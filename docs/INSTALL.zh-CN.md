# 新电脑安装

**简体中文** · [English](INSTALL.en.md) · [返回 README](../README.md)

## 先确认你拿到的安装包

- **Public**：公开发行版。Python 已包含；BlackHole 安装器从官网自动下载。
  你必须先按下一节从 Apple 获取 PacketLogger。
- **Personal-Complete**：供本人其他 Mac 迁移与开发测试使用。已包含 RemoteBuddy、
  BlackHole 2ch、Python 和本人的原版 PacketLogger。跳过 Apple 下载步骤，安装器自动找到它。
- **Local-Offline**：只缓存 BlackHole / Python 的中间版本，没有 PacketLogger；不要与个人完整包混淆。

两个私用版本都不能作为公开下载。所有版本都需要在新 Mac 配对遥控器、确认管理员授权、
安装描述文件并允许蓝牙和辅助功能。当前完整包内的 PacketLogger 最低要求 macOS 14；
实机验证范围为 Apple Silicon / macOS 26.5.2。

## 为什么必须有 PacketLogger

PacketLogger 提供按键兼容通道需要的实时 HCI 数据，不是可随意删除的诊断日志附件。
没有它，已测试遥控器可能恢复单按漏键和延迟；语音使用独立 BLE 通道。
不需要你打开 PacketLogger 的图形窗口，辅助服务会管理后台捕获。

## 公开版：获取 PacketLogger

1. 打开 [Apple Developer 下载页](https://developer.apple.com/download/all/?q=Additional%20Tools)，按页面要求登录 Apple 账号。
2. 搜索 **Additional Tools for Xcode**，选择适合目标 macOS 的版本。
   已验证的组合是 **Additional Tools for Xcode 26.5 → PacketLogger 26.0.0**。
3. 下载并打开 `.dmg`，在磁盘映像中找到 **PacketLogger.app**。
   不需要下载或安装完整 Xcode，也不要只提取应用内部的命令行可执行文件。
4. 将完整的 `PacketLogger.app` 复制到本地目录，例如自己的 `~/Applications/` 文件夹，保留原始签名和内容。
5. 运行 RemoteBuddy 安装器时提供它的完整路径。交互式输入应为实际绝对路径，
   不要加引号，也不要把 `~` 当成已经展开的个人目录。安装器会检查 Apple 签名、架构和系统要求。

公开包不会镜像 Apple 工具，原因见 [第三方组件说明](../ThirdParty/README.zh-CN.md)。

## 准备

1. Mac 和 Chromecast Voice Remote；先在系统设置 → 蓝牙中完成配对。
   已验证设备是 **Google Chromecast Voice Remote**，蓝牙型号标识 **ABBEY**，Firmware / Software **22.2 / 22.2**，
   VID/PID 为 `0x18D1` / `0x9450`。其他型号和固件尚未验证，见 [README 的设备表](../README.md)。
   需要进入配对状态时，同时按住遥控器的“返回”和“Home”，直到指示灯开始闪动，然后在 Mac 蓝牙设置中连接。
   按钮操作参见 [Google 官方配对说明](https://support.google.com/chromecast/answer/10109990?hl=zh-Hans)。
2. RemoteBuddy 完整发布压缩包。源码 ZIP 不含已构建应用；从源码使用需先构建。
3. **仅 Public / Local-Offline 用户**：从 [Apple Developer](https://developer.apple.com/download/all/?q=Additional%20Tools)
   登录下载适用于当前 macOS 的 Additional Tools for Xcode，取出 `PacketLogger.app`。
   不需要安装完整 Xcode。已验证的是 Additional Tools for Xcode 26.5 中的 PacketLogger 26.0.0。
4. 在“系统信息 → 蓝牙”中找到这只遥控器的地址（六组十六进制字节）。
   配对信息因电脑和设备而异，安装包不预填开发者的地址。

## 安装

1. 解压到可写目录，双击 **Install.command**，终端会显示安装计划。
   当前 RemoteBuddy 为本地签名构建，尚未使用 Developer ID 公证；如果系统阻止打开，
   应先核对下载来源与发布校验和，再按照“隐私与安全性”页面允许运行。
   不需要关闭 SIP、Gatekeeper 或降低启动安全等级。
2. Public / Local-Offline 用户输入 `PacketLogger.app` 的完整路径；Personal-Complete 自动识别内置副本。所有用户都需输入自己的遥控器地址。可直接从 Finder 复制路径，
   输入原始路径，不加引号。安装器会校验 Apple 签名、CPU 架构和最低系统要求。
3. 确认安装计划后，在终端输入本机管理员密码（输入不回显，不要发送给他人）。
   安装器按需安装 BlackHole 2ch 和独立 Python 3.13，然后配置辅助服务、应用和登录自启。
   公开包会先从官网获取并校验 BlackHole；个人完整包已包含所需的三个外部组件。
4. 系统会打开 **RemoteBuddy Bluetooth Compatibility** 描述文件（文件名 `RemoteBuddy-Bluetooth.mobileconfig`）；在系统设置中搜索“描述文件”或“设备管理”并手动安装。
   这是项目生成的未签名配置，开启系统蓝牙 HCI 捕获；macOS 可能记录其他蓝牙设备的原始流量。
5. 重启 Mac。允许 RemoteBuddy 的蓝牙权限，在“隐私与安全性 → 辅助功能”中允许它控制电脑。
6. 在语音输入应用中选择 **BlackHole 2ch** 为麦克风。RemoteBuddy 不是语音识别引擎，
   它只将遥控器音频提供给你使用的识别或录音应用。

也可以在终端显式传参：

```sh
./Install.command "$HOME/Applications/PacketLogger.app" 'AA:BB:CC:DD:EE:FF'
```

地址是示例，必须替换为自己的。默认 ATT 报告句柄为 `0x46`，适用于已验证的固件；
第三个参数可指定经过诊断确认的新句柄。更新固件后若失效，应重新检查协议，不要盲目扫描其他设备。

### 更换遥控器

更新应用和辅助服务后，直接使用菜单栏 **遥控器设置…**（按键设置窗口中也有入口）：

1. 在系统蓝牙设置中配对并连接新遥控器。
2. 点击 **刷新设备**，选择列表中的遥控器；列表会同时显示地址，区分同名设备。
3. 保持 **自动识别兼容参数** 开启，确认显示的厂商、型号、固件和匹配结果。
4. 点击 **保存并连接**，关闭设置窗口后测试按键和语音。无需重新安装或手动重启，个人映射会保留。

列表读取已连接的 Chromecast 遥控器，不替代系统蓝牙配对。自动识别目前支持下列已验证的组合，
不是根据蓝牙名称猜测协议，也不扫描未知句柄。固件更新后请刷新并重新识别。

设备名称相同不代表固件和按键格式相同。原版 ABBEY / 22.2 使用 `0x46` 和
`indexed`；已适配的 `zhuhai_jieli` / `hid_mouse` / 0.0.1 使用 `0x2b` 和
`consumer16`。后者会转换为原有的按键编号，保留个人映射。

使用包含此适配的新安装包时，可为后一种设备指定第四个参数：

```sh
./Install.command "$HOME/Applications/PacketLogger.app" 'AA:BB:CC:DD:EE:FF' 0x2b consumer16
```

也可在设置中手动输入地址，支持冒号或连字符分隔。同型号更换地址时可沿用已确认的参数；
未知型号需关闭自动识别，手动填写已核对的格式和句柄。应用不会为未知设备自动套用旧协议。
如果提示辅助服务版本过旧，请运行新版安装器更新一次辅助服务，仅替换 `.app` 不够。

配置仍保存于 `/Library/Application Support/RemoteMic/hci-config.json`，由辅助服务原子更新，
保持 root 所有和 0644 权限。设备字段包括 `address`、`attribute`、`report_format`、
`peripheral_id`（语音设备标识）和 `auto_detect`。旧配置无需迁移，缺失格式时默认 `indexed`。

语音松键延迟补偿会自动读取厂商、型号和固件，三者全部匹配上述已验证的 Jieli 设备才启用；
其他设备保留原来的手势计时逻辑。详见[协议兼容说明](PROTOCOL.zh-CN.md)。

## 检查

安装成功后，应看到菜单栏遥控器图标、语音“已就绪”和“按键：兼容桥接已连接”。
如果只看到语音就绪，请检查描述文件和辅助服务，不能据此认定按键通道也正常。

运行 **Check.command** 查看依赖、配置和服务状态。自动检查通过并不证明实际按键或语音成功：

- 在文本编辑器中分别测试方向、确定、返回；长按返回应连续删除，松开即停。
- 所有普通按键按住都会重复当前动作，包括组合快捷键、静音、打开应用和网址；不按映射类型过滤。
  每个键独立计时，超过两秒强制释放，松开再按可继续；禁用动作仍不执行。
- 语音键短按切换收音，按住说话、松开结束；接收应用的输入应选择 BlackHole 2ch。
- 打开按键设置时，遥控器应只定位设置行；关闭后恢复执行。
- 如果装有 Karabiner-Elements，让它忽略 Chromecast Remote，避免重复处理；本工具不要求安装 Karabiner。

菜单中的语音就绪与“按键：兼容桥接已连接”分别代表两条链路。
修改系统语言后，重新启动 RemoteBuddy 切换中英文。

## 安装位置与升级

- 应用：当前用户的 `~/Applications/RemoteBuddy.app`。
- 映射：`~/Library/Application Support/RemoteMic/button-mappings.json`。
- 辅助服务、遥控器配置和使用者自己的 PacketLogger：`/Library/Application Support/RemoteMic/`。
- 登录任务：`~/Library/LaunchAgents/local.codex.RemoteMic.plist`。
- 系统服务：`/Library/LaunchDaemons/local.codex.RemoteMic.hci.plist`。
- Python：`/Library/Frameworks/Python.framework/Versions/3.13/`。
- BlackHole：`/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver`。

Python 官方包默认允许管理员组写入。为供 root 辅助服务使用，安装器会将 Python 3.13 框架及其父目录设为 root 所有、禁止其他用户写入，并以 `-I -S` 隔离模式禁用用户包和 site 启动加载。其他 Python 版本不会递归改动；若使用这份 3.13 开发程序，请在虚拟环境中安装依赖。

旧内部名称用于保留权限和映射。升级会备份旧应用和配置，不重置映射，不覆盖已经安装的 Apple 工具。
辅助服务只绑定一个用户与一个遥控器；为另一用户重新安装会改变服务的绑定。

## 停用与移除

双击 **Uninstall.command**，确认后停用登录自启、系统服务并移除本项目的蓝牙捕获描述文件。
应用和个人映射保留，可在确认不再需要后手动移到废纸篓。
BlackHole 与 Python 可能供其他软件使用，停用工具不自动删除它们；如需要，按各自官方文档卸载。

退出 RemoteBuddy 会停止实时读取，但不会自动移除系统捕获配置。停用后的 plist 改名为 `.disabled`，
不会在下次启动时自动加载。安装失败的临时目录会保留以便诊断，请勿把里面的 Apple 应用上传。

## 自用完整包

`Personal-Complete` 包已经包含你自己的原版 PacketLogger，运行 `Install.command` 时会自动使用，无需再手动填写应用路径。遥控器地址、管理员授权、兼容描述文件和系统权限仍需在新电脑配置。这个包仅供本人授权设备迁移与开发测试，不可作为 GitHub 公开下载。

PacketLogger 在当前方案中提供按键所需的实时蓝牙数据，不只是用于诊断日志；语音 BLE 通道独立于它。
