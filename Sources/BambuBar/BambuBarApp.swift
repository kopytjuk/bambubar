import SwiftUI

@main
struct BambuBarApp: App {
    @StateObject private var model = PrinterModel()

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--screenshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { renderScreenshot(to: CommandLine.arguments[i + 1]) }
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { model.showMenuBar }, set: { model.showMenuBar = $0 })) {
            ContentView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: bambooMenuBarImage())
                if !model.menuTitle.isEmpty { Text(model.menuTitle) }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Plain SwiftUI bar (also renders in the offscreen README screenshot, unlike the AppKit-backed ProgressView).
struct ProgressBar: View {
    var fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.25))
                Capsule().fill(Color(red: 0.0, green: 0.68, blue: 0.26))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

struct ContentView: View {
    @ObservedObject var model: PrinterModel
    /// Offscreen rendering cannot draw real buttons, so the screenshot uses look-alikes.
    var preview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.stateText).font(.headline)
                Spacer()
                Text(model.connectionText).font(.caption).foregroundStyle(.secondary)
            }
            if !model.job.isEmpty { Text(model.job).font(.subheadline).lineLimit(1) }
            if model.gcodeState == "RUNNING" || model.gcodeState == "PAUSE" || model.gcodeState == "PREPARE" {
                ProgressBar(fraction: Double(model.percent) / 100)
                HStack {
                    Text("\(model.percent)%")
                    Spacer()
                    Text("Layer \(model.layer)/\(model.totalLayers)")
                    Spacer()
                    Text(model.tr("noch \(model.remainingText)", "\(model.remainingText) left"))
                }.font(.caption)
            }
            Divider()
            HStack {
                Label("\(Int(model.nozzle))° / \(Int(model.nozzleTarget))°", systemImage: "thermometer.medium")
                Spacer()
                Label("\(model.tr("Bett", "Bed")) \(Int(model.bed))° / \(Int(model.bedTarget))°", systemImage: "square.fill")
            }.font(.caption)
            if !model.ams.isEmpty {
                Divider()
                ForEach(model.ams) { unit in
                    HStack {
                        Label("AMS \(Int(unit.id).map { $0 + 1 } ?? 0) \(model.tr("Feuchte", "humidity"))", systemImage: "humidity")
                        Spacer()
                        Text(unit.percent.map { "\($0)%" } ?? "\(model.tr("Stufe", "Level")) \(unit.wetness)/5")
                    }.font(.caption)
                }
            }
            Divider()
            HStack {
                Label(model.tr("Druckzeit gesamt", "Total print time"), systemImage: "clock")
                Spacer()
                Text(model.totalPrintText)
            }.font(.caption)
            .help(model.tr("Summe der Druckzeit, die BambuBar seit dem ersten Start beobachtet hat",
                           "Print time BambuBar has observed since it was first started"))
            Divider()
            HStack {
                if preview {
                    fakeButton(model.tr("Einstellungen", "Settings"))
                    Spacer()
                    fakeButton(model.tr("Beenden", "Quit"))
                } else {
                    Button(model.tr("Einstellungen", "Settings")) { SettingsWindow.show(model) }
                    Spacer()
                    Button(model.tr("Beenden", "Quit")) { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func fakeButton(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.4)))
    }
}

/// Settings live in their own window: toggling extra rows inside the menu bar popover resized it
/// and left a rectangular drawing artifact behind.
struct SettingsView: View {
    @ObservedObject var model: PrinterModel
    var close: () -> Void

    var body: some View {
        Form {
            TextField(model.tr("IP-Adresse", "IP address"), text: model.$host)
            TextField(model.tr("Seriennummer", "Serial number"), text: model.$serial)
            SecureField("Access Code", text: model.$accessCode)
            Picker(model.tr("Sprache", "Language"), selection: $model.language) {
                Text(model.tr("System", "System")).tag("system")
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }
            Toggle(model.tr("In der Menüleiste anzeigen", "Show in menu bar"), isOn: $model.showMenuBar)
            Toggle(model.tr("Schwebefenster anzeigen", "Show floating window"), isOn: $model.showWindow)
            HStack {
                Spacer()
                Button("OK") { model.connect(); close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ model: PrinterModel) {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model) { w.close() })
            w.center()
            window = w
        }
        window?.title = model.tr("BambuBar Einstellungen", "BambuBar Settings")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Renders the popover with sample data (no printer needed) – used for the README screenshot.
@MainActor
func renderScreenshot(to path: String) {
    let m = PrinterModel(preview: true)
    m.language = "en"
    m.connection = .connected
    m.gcodeState = "RUNNING"
    m.job = "Benchy_0.2mm_PLA"
    m.percent = 64; m.remainingMin = 83; m.layer = 142; m.totalLayers = 222
    m.nozzle = 219.6; m.nozzleTarget = 220; m.bed = 60; m.bedTarget = 60
    m.ams = [AMSUnit(id: "0", level: 4, percent: 24)]
    m.previewPrintSeconds = 127 * 3600 + 42 * 60
    let view = ContentView(model: m, preview: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
        .padding(20)
    let r = ImageRenderer(content: view)
    r.scale = 2
    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

/// Small always-on-top window with the same content as the menu bar popover.
enum FloatingWindow {
    private static var panel: NSPanel?

    static func set(visible: Bool, model: PrinterModel) {
        if !visible { panel?.close(); return }
        if panel == nil {
            let controller = NSHostingController(rootView: ContentView(model: model))
            controller.sizingOptions = [.preferredContentSize]
            let p = NSPanel(contentViewController: controller)
            p.styleMask = [.titled, .closable, .utilityWindow]
            p.title = "BambuBar"
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if !p.setFrameUsingName("BambuBarFloating") { p.center() }
            p.setFrameAutosaveName("BambuBarFloating")
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { _ in
                model.showWindow = false
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }
}
