import AppKit
import Foundation
import IOBluetooth
import WebKit

struct PairedDevice: Equatable {
    let name: String
    let address: String
}

enum BridgeState: Equatable {
    case stopped
    case starting
    case waitingForCard
    case waitingForReader
    case connected(String)
    case error(String)

    var title: String {
        switch self {
        case .stopped:
            return "準備完了"
        case .starting:
            return "起動中"
        case .waitingForCard:
            return "カード待ち"
        case .waitingForReader:
            return "Mac 側待ち"
        case .connected:
            return "接続中"
        case .error:
            return "エラー"
        }
    }

    var detail: String {
        switch self {
        case .stopped:
            return "Start Bridge を押すと、Mac と Android の待受を始めます。"
        case .starting:
            return "Bluetooth bridge helper を起動しています。数秒待ってください。"
        case .waitingForCard:
            return "スマホは見えています。MyNumber Reader を開いてカードを背面に当ててください。"
        case .waitingForReader:
            return "Mac 側でマイナポータルまたは e-Tax のカード読取画面を開いてください。"
        case .connected(let name):
            return "\(name) と接続できています。処理が終わるまでカードを動かさないでください。"
        case .error(let message):
            return message
        }
    }

    var badgeText: String {
        switch self {
        case .stopped:
            return "READY"
        case .starting:
            return "BOOTING"
        case .waitingForCard, .waitingForReader:
            return "WAITING"
        case .connected:
            return "LIVE"
        case .error:
            return "ERROR"
        }
    }

    var badgeColorHex: String {
        switch self {
        case .stopped:
            return "#2f8159"
        case .starting:
            return "#276ca8"
        case .waitingForCard, .waitingForReader:
            return "#a76b1f"
        case .connected:
            return "#18799c"
        case .error:
            return "#b03d36"
        }
    }
}

struct SetupSnapshot {
    let bridgeState: BridgeState
    let helperBundled: Bool
    let driverInstalled: Bool
    let mynaPortalInstalled: Bool
    let pairedDevices: [PairedDevice]
    let selectedDevice: PairedDevice?
    let bridgeRunning: Bool
    let lastLogLine: String

    var headline: String {
        if !driverInstalled {
            return "Step 1 から始めてください"
        }
        if pairedDevices.isEmpty {
            return "まず Android を Bluetooth でペアリングしてください"
        }
        if selectedDevice == nil {
            return "使う Android を選んでください"
        }
        return bridgeState.title
    }

    var detail: String {
        if !driverInstalled {
            return "この Mac に smart card driver がまだ入っていません。"
        }
        if pairedDevices.isEmpty {
            return "Bluetooth Settings から Pixel とこの Mac を 1 回だけペアリングします。"
        }
        if selectedDevice == nil {
            return "一覧から使うスマホを 1 台選んでください。"
        }
        return bridgeState.detail
    }

    var nextAction: String {
        if !driverInstalled {
            return "Install Driver を押して、終わったら Refresh"
        }
        if pairedDevices.isEmpty {
            return "Bluetooth Settings を開いて Pixel をペアリング"
        }
        if selectedDevice == nil {
            return "使うスマホを選ぶ"
        }
        switch bridgeState {
        case .stopped:
            return "Start Bridge を押す"
        case .starting:
            return "数秒待つ"
        case .waitingForCard:
            return "スマホで MyNumber Reader を開いてカードを当てる"
        case .waitingForReader:
            return "Mac 側でカード読取画面を開く"
        case .connected:
            return "カードを動かさずに待つ"
        case .error:
            return "Latest Log を確認する"
        }
    }
}

struct DevicePayload: Codable {
    let name: String
    let address: String
    let selected: Bool
}

struct SnapshotPayload: Codable {
    let headline: String
    let detail: String
    let nextAction: String
    let badgeText: String
    let badgeColor: String
    let bridgeTitle: String
    let lastLogLine: String
    let bridgeRunning: Bool
    let driverInstalled: Bool
    let helperBundled: Bool
    let mynaPortalInstalled: Bool
    let devices: [DevicePayload]
}

final class BridgeWebViewController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {
    private let webView: WKWebView
    private var isPageReady = false
    private var pendingPayload: SnapshotPayload?

    var onPrimaryAction: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onOpenBluetoothSettings: (() -> Void)?
    var onOpenDriverInstaller: (() -> Void)?
    var onOpenHelperLog: (() -> Void)?
    var onOpenMynaPortal: (() -> Void)?
    var onSelectDevice: ((String?) -> Void)?

    init() {
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MyNumber Bridge"
        window.minSize = NSSize(width: 860, height: 680)
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        contentController.add(self, name: "bridge")
        webView.navigationDelegate = self
        setupWindow()
        loadUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(snapshot: SetupSnapshot) {
        let payload = SnapshotPayload(
            headline: snapshot.headline,
            detail: snapshot.detail,
            nextAction: snapshot.nextAction,
            badgeText: snapshot.bridgeState.badgeText,
            badgeColor: snapshot.bridgeState.badgeColorHex,
            bridgeTitle: snapshot.bridgeState.title,
            lastLogLine: snapshot.lastLogLine,
            bridgeRunning: snapshot.bridgeRunning,
            driverInstalled: snapshot.driverInstalled,
            helperBundled: snapshot.helperBundled,
            mynaPortalInstalled: snapshot.mynaPortalInstalled,
            devices: snapshot.pairedDevices.map {
                DevicePayload(
                    name: $0.name,
                    address: $0.address,
                    selected: $0 == snapshot.selectedDevice
                )
            }
        )

        pendingPayload = payload
        renderIfReady()
    }

    private func setupWindow() {
        guard let contentView = window?.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.93, green: 0.92, blue: 0.88, alpha: 1.0).cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func loadUI() {
        guard let uiURL = Bundle.main.resourceURL?.appendingPathComponent("ui/index.html") else {
            return
        }
        webView.loadFileURL(uiURL, allowingReadAccessTo: uiURL.deletingLastPathComponent())
    }

    private func renderIfReady() {
        guard isPageReady, let payload = pendingPayload else {
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        webView.evaluateJavaScript("window.renderApp(\(json));", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        renderIfReady()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "bridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch action {
        case "primary":
            onPrimaryAction?()
        case "refresh":
            onRefresh?()
        case "openBluetooth":
            onOpenBluetoothSettings?()
        case "installDriver":
            onOpenDriverInstaller?()
        case "openLog":
            onOpenHelperLog?()
        case "openPortal":
            onOpenMynaPortal?()
        case "selectDevice":
            onSelectDevice?(body["address"] as? String)
        default:
            break
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let selectedDeviceDefaultsKey = "SelectedBluetoothDeviceAddress"

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    private var windowController: BridgeWebViewController?
    private var bridgeProcess: Process?
    private var bridgePipe: Pipe?
    private var bridgeState: BridgeState = .stopped
    private var lastLogLine = "No activity yet"
    private var isStoppingBridge = false

    private lazy var helperLogURL: URL = {
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/mynumber-bridge", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("bridge-gui.log", isDirectory: false)
    }()

    private var helperURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("rfcomm-vpcd-client", isDirectory: false)
    }

    private var bundledDriverURL: URL {
        URL(fileURLWithPath: "/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureDefaultSelection()

        let controller = BridgeWebViewController()
        controller.onPrimaryAction = { [weak self] in
            guard let self else { return }
            if self.bridgeProcess == nil {
                self.startBridge()
            } else {
                self.stopBridge()
            }
        }
        controller.onRefresh = { [weak self] in
            self?.refreshDevices()
        }
        controller.onOpenBluetoothSettings = { [weak self] in
            self?.openBluetoothSettings()
        }
        controller.onOpenDriverInstaller = { [weak self] in
            self?.runDriverInstaller()
        }
        controller.onOpenHelperLog = { [weak self] in
            self?.openHelperLog()
        }
        controller.onOpenMynaPortal = { [weak self] in
            self?.openMynaPortal()
        }
        controller.onSelectDevice = { [weak self] address in
            self?.selectedDeviceAddress = address
            self?.refreshWindow()
        }

        windowController = controller
        refreshWindow()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopBridge()
    }

    private func startBridge() {
        guard bridgeProcess == nil else {
            return
        }
        guard let selectedDeviceAddress else {
            bridgeState = .error("スマホが未選択です。Step 2 で 1 台選んでください。")
            refreshWindow()
            return
        }
        guard fileManager.isExecutableFile(atPath: helperURL.path) else {
            bridgeState = .error("Bundled helper が見つかりません。app を rebuild してください。")
            refreshWindow()
            return
        }

        isStoppingBridge = false
        bridgeState = .starting
        refreshWindow()

        let process = Process()
        let pipe = Pipe()
        process.executableURL = helperURL
        process.arguments = ["--device-address", selectedDeviceAddress]
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            self?.handleProcessOutput(text)
        }

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                self.bridgePipe?.fileHandleForReading.readabilityHandler = nil
                self.bridgePipe = nil
                self.bridgeProcess = nil
                if self.isStoppingBridge {
                    self.bridgeState = .stopped
                } else if process.terminationStatus != 0 {
                    self.bridgeState = .error("Bridge exited with status \(process.terminationStatus).")
                } else {
                    self.bridgeState = .stopped
                }
                self.refreshWindow()
            }
        }

        do {
            try process.run()
            bridgeProcess = process
            bridgePipe = pipe
            appendLogLine("Bridge process started for \(selectedDeviceAddress)")
        } catch {
            bridgeState = .error("Bridge を開始できませんでした: \(error.localizedDescription)")
        }

        refreshWindow()
    }

    private func stopBridge() {
        isStoppingBridge = true
        bridgePipe?.fileHandleForReading.readabilityHandler = nil
        if let bridgeProcess, bridgeProcess.isRunning {
            bridgeProcess.terminate()
        }
        bridgeProcess = nil
        bridgePipe = nil
        bridgeState = .stopped
        refreshWindow()
    }

    private func refreshDevices() {
        ensureDefaultSelection()
        refreshWindow()
    }

    private func openBluetoothSettings() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings"),
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        ].compactMap { $0 }

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }
    }

    private func openHelperLog() {
        if !fileManager.fileExists(atPath: helperLogURL.path) {
            try? Data().write(to: helperLogURL)
        }
        NSWorkspace.shared.open(helperLogURL)
    }

    private func runDriverInstaller() {
        let scriptPath = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/install_vpcd_macos.sh")
            .path

        let command = "bash '\(scriptPath.replacingOccurrences(of: "'", with: "'\\''"))'"
        let appleScriptSource = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: appleScriptSource)?.executeAndReturnError(&error)
        if error != nil {
            bridgeState = .error("Terminal を開けませんでした。")
            refreshWindow()
        }
    }

    private func openMynaPortal() {
        let appURL = URL(fileURLWithPath: "/Applications/MynaPortalApp.app")
        if fileManager.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private var selectedDeviceAddress: String? {
        get {
            let value = defaults.string(forKey: selectedDeviceDefaultsKey)
            return value?.isEmpty == false ? value : nil
        }
        set {
            defaults.set(newValue, forKey: selectedDeviceDefaultsKey)
        }
    }

    private func pairedDevices() -> [PairedDevice] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
        return devices
            .map { device in
                let name = device.nameOrAddress ?? "Unknown Device"
                let address = normalizeBluetoothAddress(device.addressString ?? "")
                return PairedDevice(name: name, address: address)
            }
            .filter { !$0.address.isEmpty }
            .sorted {
                if $0.name == $1.name {
                    return $0.address < $1.address
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func preferredAutoSelectableDevices(from devices: [PairedDevice]) -> [PairedDevice] {
        devices.filter {
            let lowercased = $0.name.lowercased()
            return lowercased.contains("pixel") || lowercased.contains("android")
        }
    }

    private func ensureDefaultSelection() {
        let devices = pairedDevices()
        if let selectedDeviceAddress,
           devices.contains(where: { $0.address == selectedDeviceAddress }) {
            return
        }

        let preferred = preferredAutoSelectableDevices(from: devices)
        if preferred.count == 1 {
            selectedDeviceAddress = preferred[0].address
            return
        }
        if devices.count == 1 {
            selectedDeviceAddress = devices[0].address
        } else {
            selectedDeviceAddress = nil
        }
    }

    private func refreshWindow() {
        let devices = pairedDevices()
        let selected = devices.first(where: { $0.address == selectedDeviceAddress })
        let snapshot = SetupSnapshot(
            bridgeState: bridgeState,
            helperBundled: fileManager.isExecutableFile(atPath: helperURL.path),
            driverInstalled: fileManager.fileExists(atPath: bundledDriverURL.path),
            mynaPortalInstalled: fileManager.fileExists(atPath: "/Applications/MynaPortalApp.app"),
            pairedDevices: devices,
            selectedDevice: selected,
            bridgeRunning: bridgeProcess != nil,
            lastLogLine: lastLogLine
        )
        windowController?.update(snapshot: snapshot)
    }

    private func handleProcessOutput(_ text: String) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return
        }

        DispatchQueue.main.async {
            for line in lines {
                self.appendLogLine(line)
                self.lastLogLine = self.trimmed(line)
                self.updateBridgeState(from: line)
            }
            self.refreshWindow()
        }
    }

    private func updateBridgeState(from line: String) {
        if let deviceName = extractDeviceName(from: line) {
            bridgeState = .connected(deviceName)
            return
        }
        if line.contains("Bluetooth bridge is active") {
            bridgeState = .connected(selectedDeviceDescription ?? "Android phone")
            return
        }
        if line.contains("Service ") && line.contains("not currently advertised") {
            bridgeState = .waitingForCard
            return
        }
        if line.contains("Waiting for VPCD") {
            bridgeState = .waitingForReader
            return
        }
        if line.contains("Bluetooth client disconnected") {
            bridgeState = .waitingForCard
            return
        }
        if line.contains("Failed to open Bluetooth connection")
            || line.contains("Could not determine which paired Android device")
            || line.contains("Multiple paired Android-like devices matched")
            || line.contains("Bundled helper is missing") {
            bridgeState = .error(trimmed(line))
        }
    }

    private func extractDeviceName(from line: String) -> String? {
        guard let range = line.range(of: "Connected to "),
              let tailRange = line.range(of: " over RFCOMM channel") else {
            return nil
        }
        let name = String(line[range.upperBound..<tailRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private var selectedDeviceDescription: String? {
        pairedDevices().first(where: { $0.address == selectedDeviceAddress })?.name
    }

    private func normalizeBluetoothAddress(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    private func trimmed(_ line: String) -> String {
        let sanitized = line.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "No activity yet" : sanitized
    }

    private func appendLogLine(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(timestamp)] \(line)\n"
        let data = Data(text.utf8)
        if fileManager.fileExists(atPath: helperLogURL.path),
           let handle = try? FileHandle(forWritingTo: helperLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: helperLogURL)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
