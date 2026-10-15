import Foundation
import AppKit
import SwiftUI

struct AMSUnit: Identifiable {
    let id: String
    /// Display level: higher = more humid (the printer's own scale is the other way around).
    var wetness: Int { level == 0 ? 0 : 6 - level }
    var level = 0        // humidity level as reported by the printer: 5 = driest, 1 = wettest
    var percent: Int?    // raw humidity in %, only reported by newer AMS models
}

final class PrinterModel: ObservableObject {
    @AppStorage("host") var host = ""
    @AppStorage("serial") var serial = ""
    @AppStorage("accessCode") var accessCode = ""

    /// Accumulated time spent in RUNNING state while this app was open (the printer does not report lifetime hours via MQTT).
    @AppStorage("totalPrintSeconds") var totalPrintSeconds = 0.0
    @Published var ams: [AMSUnit] = []

    @Published var connection = ConnectionStatus.notConfigured
    /// "system", "de" or "en"
    @Published var language: String = UserDefaults.standard.string(forKey: "language") ?? "system" {
        didSet { if !isPreview { UserDefaults.standard.set(language, forKey: "language") } }
    }

    /// Where the status is shown. At least one of the two is always on, otherwise the app could not be reached.
    @Published var showMenuBar: Bool = UserDefaults.standard.object(forKey: "showMenuBar") == nil ? true : UserDefaults.standard.bool(forKey: "showMenuBar") {
        didSet {
            guard showMenuBar != oldValue else { return }
            UserDefaults.standard.set(showMenuBar, forKey: "showMenuBar")
            if !showMenuBar && !showWindow { showWindow = true }
            applyPresentation()
        }
    }
    @Published var showWindow: Bool = UserDefaults.standard.bool(forKey: "showWindow") {
        didSet {
            guard showWindow != oldValue else { return }
            UserDefaults.standard.set(showWindow, forKey: "showWindow")
            if !showWindow && !showMenuBar { showMenuBar = true }
            applyPresentation()
        }
    }

    /// Without a menu bar item the app gets a Dock icon, so it can still be quit and reopened.
    func applyPresentation() {
        guard !isPreview else { return }
        let policy: NSApplication.ActivationPolicy = showMenuBar ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        FloatingWindow.set(visible: showWindow, model: self)
    }

    /// Preview models (used for the README screenshot) never connect and never touch stored settings.
    private let isPreview: Bool
    var previewPrintSeconds: Double?
    @Published var gcodeState = ""
    @Published var percent = 0
    @Published var remainingMin = 0
    @Published var nozzle = 0.0
    @Published var nozzleTarget = 0.0
    @Published var bed = 0.0
    @Published var bedTarget = 0.0
    @Published var job = ""
    @Published var layer = 0
    @Published var totalLayers = 0

    private let mqtt = MQTTClient()

    init(preview: Bool = false) {
        isPreview = preview
        if preview { return }
        mqtt.onStatus = { [weak self] s in DispatchQueue.main.async { self?.connection = s } }
        mqtt.onMessage = { [weak self] _, data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let p = obj["print"] as? [String: Any] else { return }
            DispatchQueue.main.async { self?.apply(p) }
        }
        if !host.isEmpty { connect() }
        DispatchQueue.main.async { self.applyPresentation() }
        var last = Date()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            if self.gcodeState == "RUNNING" { self.totalPrintSeconds += now.timeIntervalSince(last) }
            last = now
        }
    }

    func connect() {
        guard !host.isEmpty, !serial.isEmpty, !accessCode.isEmpty else { connection = .notConfigured; return }
        let req = #"{"pushing":{"sequence_id":"0","command":"pushall"}}"#
        mqtt.start(host: host, user: "bblp", pass: accessCode,
                   subscribe: "device/\(serial)/report",
                   requestTopic: "device/\(serial)/request", requestPayload: Data(req.utf8))
    }

    /// The printer sends partial updates – only overwrite keys that are present.
    private func apply(_ p: [String: Any]) {
        if let v = p["gcode_state"] as? String { gcodeState = v }
        if let v = p["mc_percent"] as? Int { percent = v }
        if let v = p["mc_remaining_time"] as? Int { remainingMin = v }
        if let v = p["nozzle_temper"] as? Double { nozzle = v }
        if let v = p["nozzle_target_temper"] as? Double { nozzleTarget = v }
        if let v = p["bed_temper"] as? Double { bed = v }
        if let v = p["bed_target_temper"] as? Double { bedTarget = v }
        if let v = p["subtask_name"] as? String { job = v }
        if let v = p["layer_num"] as? Int { layer = v }
        if let v = p["total_layer_num"] as? Int { totalLayers = v }
        if let units = (p["ams"] as? [String: Any])?["ams"] as? [[String: Any]] {
            for u in units {
                guard let id = u["id"] as? String else { continue }
                var unit = ams.first { $0.id == id } ?? AMSUnit(id: id)
                if let h = u["humidity"] as? String, let n = Int(h) { unit.level = n }
                if let r = u["humidity_raw"] as? String, let n = Int(r) { unit.percent = n }
                if let i = ams.firstIndex(where: { $0.id == id }) { ams[i] = unit } else { ams.append(unit) }
            }
            ams.sort { $0.id < $1.id }
        }
    }

    var isGerman: Bool {
        switch language {
        case "de": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.hasPrefix("de") ?? false
        }
    }

    func tr(_ de: String, _ en: String) -> String { isGerman ? de : en }

    var connectionText: String {
        switch connection {
        case .notConfigured: return tr("Nicht konfiguriert", "Not configured")
        case .connecting: return tr("Verbinde …", "Connecting…")
        case .connected: return tr("Verbunden", "Connected")
        case .denied: return tr("Login abgelehnt – Access Code prüfen", "Login rejected – check access code")
        case .disconnected: return tr("Verbindung getrennt", "Disconnected")
        case .waiting: return tr("Warte auf Netzwerk", "Waiting for network")
        case .failed(let msg): return tr("Fehler: ", "Error: ") + msg
        }
    }

    var stateText: String {
        switch gcodeState {
        case "RUNNING": return tr("Druckt", "Printing")
        case "PREPARE": return tr("Bereitet vor", "Preparing")
        case "PAUSE": return tr("Pausiert", "Paused")
        case "FINISH": return tr("Fertig", "Finished")
        case "FAILED": return tr("Fehlgeschlagen", "Failed")
        case "IDLE": return tr("Bereit", "Idle")
        case "": return "–"
        default: return gcodeState
        }
    }

    var symbol: String {
        switch gcodeState {
        case "RUNNING", "PREPARE": return "printer.fill"
        case "PAUSE": return "pause.circle"
        case "FINISH": return "checkmark.circle"
        case "FAILED": return "exclamationmark.triangle"
        default: return "printer"
        }
    }

    var remainingText: String {
        remainingMin >= 60 ? "\(remainingMin / 60)h \(remainingMin % 60)m" : "\(remainingMin)m"
    }

    var totalPrintText: String {
        let t = previewPrintSeconds ?? totalPrintSeconds
        let h = Int(t) / 3600, m = Int(t) % 3600 / 60
        return "\(h)h \(m)m"
    }

    var menuTitle: String {
        switch gcodeState {
        case "RUNNING": return "\(percent)% · \(remainingText)"
        case "PAUSE": return tr("Pause", "Paused")
        case "FINISH": return tr("Fertig", "Done")
        case "FAILED": return tr("Fehler", "Failed")
        default: return ""
        }
    }
}
