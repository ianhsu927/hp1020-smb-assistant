import SwiftUI
import AppKit

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleQuote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\"" }
func command(_ path: String, _ args: [String]) throws -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    if p.terminationStatus != 0 { throw NSError(domain: "HP1020", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "操作失败（\(p.terminationStatus)）" : output]) }
    return output
}

@MainActor final class Model: ObservableObject {
    @Published var host = ""
    @Published var share = ""
    @Published var auth = true
    @Published var busy = false
    @Published var status = "请先在 Windows 上确认打印机能正常打印。"
    @Published var log = "此工具面向 Apple 芯片 Mac。1020 / macOS 27 / SMB 尚待实际打印验证。"
    let queue = "HP1020_SMB"
    func inputs() throws -> (String, String) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = share.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty, h.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]*$", options: .regularExpression) != nil, !s.isEmpty, !s.contains("/"), !s.contains("\\"), !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw NSError(domain: "HP1020", code: 1, userInfo: [NSLocalizedDescriptionKey: "请填写有效的 Windows IPv4 地址或主机名，以及不含斜杠的打印机共享名。"])
        }
        return (h, s)
    }
    func task(_ label: String, _ work: @escaping () throws -> String) {
        guard !busy else { return }; busy = true; status = label
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<String, Error> = Result { try work() }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let text): self.status = "操作完成"; self.log = text
                case .failure(let error): self.status = "操作未完成"; self.log = error.localizedDescription
                }
            }
        }
    }
    func check() {
        do { let (h, _) = try inputs(); task("检查 SMB 端口…") {
            _ = try command("/usr/bin/nc", ["-z", "-G", "5", "-w", "5", h, "445"])
            return "Windows 的 SMB 端口可连接。\n这只验证网络连通，不验证共享名、登录权限或打印能力。"
        } } catch { log = error.localizedDescription }
    }
    func install() {
        do {
            let (h, s) = try inputs()
            var chars = CharacterSet.urlPathAllowed; chars.remove(charactersIn: "/%?#:@\\")
            let uri = "smb://" + h + "/" + (s.addingPercentEncoding(withAllowedCharacters: chars) ?? "")
            let needsAuth = auth ? "yes" : "no"
            guard let resources = Bundle.main.resourceURL else { return }
            task("下载驱动并检查完整性，随后会请求管理员授权…") {
                let fm = FileManager.default
                let temp = fm.temporaryDirectory.appendingPathComponent("HP1020-" + UUID().uuidString)
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: temp) }
                let archive = temp.appendingPathComponent("driver.tar.gz")
                _ = try command("/usr/bin/curl", ["--fail", "--location", "--silent", "--show-error", "--connect-timeout", "20", "--max-time", "180", "--proto", "=https", "--proto-redir", "=https", "https://github.com/ardabeh/hp-legacy-mac/releases/download/v1.0.0/hp-legacy-mac-bundle-arm64.tar.gz", "-o", archive.path])
                let sum = try command("/usr/bin/shasum", ["-a", "256", archive.path])
                guard sum.hasPrefix("60c133b5a53fcce4a4364e1da53d8815cf6b14549e4eba2e88f567fdb6ee950b ") else { throw NSError(domain: "HP1020", code: 2, userInfo: [NSLocalizedDescriptionKey: "驱动资源校验失败，未安装。"] ) }
                _ = try command("/usr/bin/tar", ["-xzf", archive.path, "-C", temp.path])
                let script = resources.appendingPathComponent("install.sh").path
                let cmd = ["/bin/sh", script, temp.appendingPathComponent("bundle").path, uri, needsAuth].map(shellQuote).joined(separator: " ")
                let output = try command("/usr/bin/osascript", ["-e", "do shell script " + appleQuote(cmd) + " with administrator privileges"])
                return output + "\n请打印测试页。若任务要求认证，打开打印队列输入 Windows 用户名和密码。"
            }
        } catch { log = error.localizedDescription }
    }
    func test() {
        guard let pdf = Bundle.main.url(forResource: "test", withExtension: "pdf") else { return }
        task("提交一页测试…") {
            let result = try command("/usr/bin/lp", ["-d", "HP1020_SMB", pdf.path])
            return result + "\n任务已提交，不等于已打印成功。请检查纸张输出；若未打印，打开系统打印队列查看认证或错误信息。"
        }
    }
    func diagnose() { task("读取打印队列…") {
        let p = try command("/usr/bin/lpstat", ["-p", "HP1020_SMB", "-l"])
        let jobs = try command("/usr/bin/lpstat", ["-o", "HP1020_SMB"])
        return p + "\n" + jobs
    } }
}

struct ContentView: View {
    @StateObject var m = Model()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "printer.fill").font(.system(size: 35)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("HP 1020 · SMB 打印助手").font(.title2.bold())
                    Text("Apple 芯片原生驱动 · 通过 Windows 共享打印").foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Windows 地址") { TextField("例如 192.168.1.100", text: $m.host).textFieldStyle(.roundedBorder).frame(width: 320) }
                    LabeledContent("打印机共享名") { TextField("例如 HP1020", text: $m.share).textFieldStyle(.roundedBorder).frame(width: 320) }
                    Toggle("Windows 共享需要用户名和密码", isOn: $m.auth)
                    Text("当前版本：A4、黑白打印。密码在系统打印队列中输入。\n将新建 HP1020_SMB 队列，不修改你的其他打印机。").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            HStack {
                Button("检查连接", action: m.check)
                Button("安装并添加打印机", action: m.install).buttonStyle(.borderedProminent)
                Button("打印测试页", action: m.test)
                Button("查看队列状态", action: m.diagnose)
            }.disabled(m.busy)
            HStack { if m.busy { ProgressView().controlSize(.small) }; Text(m.status).font(.callout) }
            ScrollView { Text(m.log).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("打开打印机设置") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Print-Scan-Settings.extension")!) }
                Spacer()
                Link("开源驱动与许可", destination: URL(string: "https://github.com/ardabeh/hp-legacy-mac")!)
            }
            Text("社区实验方案：尚未验证 macOS 27 的实际打印；Windows 必须在线并已初始化打印机。安装会请求系统管理员授权。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 680, height: 550)
    }
}
@main struct PrinterApp: App {
    var body: some Scene { WindowGroup { ContentView() }.windowResizability(.contentSize) }
}
