import SwiftUI

@main
struct BambuBarApp: App {
    @StateObject private var model = PrinterModel()

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Label(model.menuTitle, systemImage: model.symbol)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var model: PrinterModel
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.stateText).font(.headline)
                Spacer()
                Text(model.connection).font(.caption).foregroundStyle(.secondary)
            }
            if !model.job.isEmpty { Text(model.job).font(.subheadline).lineLimit(1) }
            if model.gcodeState == "RUNNING" || model.gcodeState == "PAUSE" || model.gcodeState == "PREPARE" {
                ProgressView(value: Double(model.percent), total: 100)
                HStack {
                    Text("\(model.percent)%")
                    Spacer()
                    Text("Layer \(model.layer)/\(model.totalLayers)")
                    Spacer()
                    Text("noch \(model.remainingText)")
                }.font(.caption)
            }
            Divider()
            HStack {
                Label("\(Int(model.nozzle))° / \(Int(model.nozzleTarget))°", systemImage: "thermometer.medium")
                Spacer()
                Label("Bett \(Int(model.bed))° / \(Int(model.bedTarget))°", systemImage: "square.fill")
            }.font(.caption)
            Divider()
            if showSettings {
                TextField("IP-Adresse", text: model.$host)
                TextField("Seriennummer", text: model.$serial)
                SecureField("Access Code", text: model.$accessCode)
                Button("Verbinden") { model.connect(); showSettings = false }
            }
            HStack {
                Button(showSettings ? "Schließen" : "Einstellungen") { showSettings.toggle() }
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
