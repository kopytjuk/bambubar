import SwiftUI

@main
struct BambuBarApp: App {
    @StateObject private var model = PrinterModel()

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
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

struct ContentView: View {
    @ObservedObject var model: PrinterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.stateText).font(.headline)
                Spacer()
                Text(model.connectionText).font(.caption).foregroundStyle(.secondary)
            }
            if !model.job.isEmpty { Text(model.job).font(.subheadline).lineLimit(1) }
            if model.gcodeState == "RUNNING" || model.gcodeState == "PAUSE" || model.gcodeState == "PREPARE" {
                ProgressView(value: Double(model.percent), total: 100)
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
                Button(model.tr("Einstellungen", "Settings")) { SettingsWindow.show(model) }
                Spacer()
                Button(model.tr("Beenden", "Quit")) { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
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
            HStack {
                Spacer()
                Button(model.tr("Verbinden", "Connect")) { model.connect(); close() }
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
