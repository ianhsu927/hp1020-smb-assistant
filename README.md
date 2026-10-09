# HP1020 SMB Assistant

Apple 芯片 Mac 通过 Windows SMB 共享使用 HP LaserJet 1020 的图形配置工具。界面使用 SwiftUI + AppKit，打印数据转换使用 ARM64 foo2zjs 和 Ghostscript，不依赖 Rosetta。

**实验版：已验证应用启动和 PDF → ZjStream 转换，尚未验证 macOS 27 上真实的 Windows SMB / HP 1020 打印。不能保证安装后可用。**

## 功能

- 填写 Windows IP / 主机名与打印机共享名。
- 检查 SMB TCP 445 连接，显示安装及队列状态。
- 下载固定版本的 ARM64 驱动，核对固定 SHA-256 后请求系统管理员授权。
- 创建独立的 `HP1020_SMB` 打印队列并提交 PDF 测试页。
- 通过系统打印队列处理 Windows 认证，应用不收集或保存密码。
- 确认并授权后删除已安装驱动和 `HP1020_SMB` 队列，删除前检查其他队列的驱动引用。

## 构建

需要 macOS、Xcode Command Line Tools，目标为 Apple Silicon / macOS 13 或更高版本。

```sh
xcode-select --install
./scripts/build.sh
```

构建结果：`dist/HP1020 SMB 助手.app` 和 `dist/HP1020-SMB-Assistant.zip`。

程序仅使用本地临时签名，没有 Apple Developer ID 签名或公证。首次打开可能需要通过 macOS 的正常安全批准流程；无需关闭 SIP 或全局安全保护。

卸载安全检查的测试使用临时目录和模拟打印命令，不修改系统打印机或驱动：

```sh
python3 -m unittest discover -s tests -v
```

## 使用

1. 在 Windows 上确认 HP 1020 能打印测试页，并开启打印机共享。
2. 保持 Windows 和打印机在线。打印机开机后的固件初始化由 Windows 环境负责，应用不上传固件。
3. 打开助手，填写 Windows IPv4 地址或主机名、打印机共享名。
4. 点击“检查连接”。此功能只检查端口，不检查共享名或登录权限。
5. 点击“安装并添加打印机”，下载完成后通过系统弹窗授权。
6. 点击“打印测试页”。若任务需要认证，在系统打印队列输入 Windows 用户名和密码。
7. 从其他应用按 ⌘P，选择 `HP1020_SMB`。

提交成功不等于打印成功。请检查实际纸张输出及队列错误。

## 安装行为

驱动安装至 `/Library/Printers/hp-legacy-mac`。PPD 使用该目录中的绝对过滤器路径，不写入 `/usr/libexec/cups/filter`，不修改 USB 后端权限。

如果发现同名队列或该驱动目录已存在，安装会停止，避免覆盖已有配置。安装失败时尝试删除本次新建的队列和驱动目录。

驱动来自社区项目 [ardabeh/hp-legacy-mac](https://github.com/ardabeh/hp-legacy-mac)，不是 HP 官方软件。安装时下载 v1.0.0 ARM64 资源（约 20 MB）：

```text
https://github.com/ardabeh/hp-legacy-mac/releases/download/v1.0.0/hp-legacy-mac-bundle-arm64.tar.gz
SHA-256: 60c133b5a53fcce4a4364e1da53d8815cf6b14549e4eba2e88f567fdb6ee950b
```

校验值用于确认资源与开发时核对的版本一致，并非独立的软件安全审计。仓库和应用不包含驱动二进制。

## 当前限制

- 仅 HP LaserJet 1020，固定 A4、黑白打印；不实现高级打印选项。
- 尚未验证 CUPS 沙盒中的转换程序执行、真实 SMB 认证和打印机输出。
- 不支持 Intel Mac；不支持 IPv6 地址及域账号配置界面。
- 下载期间无取消按钮，网络操作最长等待 180 秒。
- Windows 必须能自行驱动并初始化打印机。
- 开源驱动作者也将 1020 支持列为实验性。

## 移除

在助手中点击“删除已安装驱动”，确认后通过系统管理员授权。无需填写 Windows 地址或共享名。

此操作删除 `HP1020_SMB` 队列（包括未完成的打印任务）和 `/Library/Printers/hp-legacy-mac` 驱动目录。如果其他打印队列的 PPD 仍引用该目录、同名队列使用了其他驱动，或无法确认安装结构，卸载会停止并显示原因。

已在系统设置中删除队列后，也可以用此按钮移除剩余驱动。删除后可再次安装。

## 源码与许可

- `Sources/Main.swift`：原生界面、输入校验、下载与管理员安装流程。
- `Resources/install.sh`：SMB 队列和 HP 1020 转换过滤器配置。
- `Resources/uninstall.sh`：卸载前检查、移除打印队列与驱动文件。
- `Resources/test.pdf`：测试页。
- `scripts/build.sh`：构建与本地临时签名。

本项目采用 GPL-2.0，安装流程参考 hp-legacy-mac；第三方驱动及 Ghostscript 遵循各自许可证。参见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
