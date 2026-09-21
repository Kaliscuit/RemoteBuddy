# 单字节 HID 报告兼容方案

**简体中文** · [English](PROTOCOL.md) · [返回 README](../README.md)

已测试的 Google Chromecast Voice Remote：VID `0x18D1`、PID `0x9450`，
蓝牙型号标识 **ABBEY**，Firmware / Software **22.2 / 22.2**。
它在 Report 1 中声明两个 Consumer 数组槽位，但单按和松开时发送单字节载荷。
macOS IOHID / CoreHID 能收到双键报告，却丢弃这些不足长度的报告。
HCI 捕获中存在完整的按下和松开事件，说明丢失位于蓝牙接收之后、普通 HID 投递之前。
这也解释了更换电池或修改映射为什么没有解决单按漏键。

辅助服务通过私有 FIFO 读取 Apple PacketLogger 的实时流，利用配置中的遥控器地址，
从设备元数据和 LE 连接事件中识别连接句柄，再重组 ACL / L2CAP 分片。
只有指定 ATT 报告句柄（已验证为 `0x0046`）的通知或指示，以及含一到两个有效按键字节的报告会被转发。

服务通过权限为 0600 的 Unix socket 仅向选定用户发送过滤后的按键数据，并校验连接方 UID。
应用校验服务端为 root，拒绝过期事件；断开连接和超时保护会释放按住的键。
因此 PacketLogger 是运行时依赖，不只是调试日志工具；不需要用户打开它的图形窗口。
辅助服务不会保存原始抓包文件，但兼容描述文件可能令 macOS 自身保存蓝牙原始日志。

麦克风使用独立的公开 ATVV BLE 服务，经标准 IMA ADPCM 解码后送往 BlackHole。
语音可用并不能证明按键投递正常。仓库不包含真实设备地址、原始录音或私人抓包，测试使用合成数据。
