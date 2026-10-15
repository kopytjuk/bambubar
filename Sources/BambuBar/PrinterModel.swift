import Foundation
import SwiftUI

struct AMSUnit: Identifiable {
    let id: String
    var level = 0        // humidity level 1-5 as reported by the printer
    var percent: Int?    // raw humidity in %, only reported by newer AMS models
}

final class PrinterModel: ObservableObject {
    @AppStorage("host") var host = ""
    @AppStorage("serial") var serial = ""
    @AppStorage("accessCode") var accessCode = ""

    /// Accumulated time spent in RUNNING state while this app was open (the printer does not report lifetime hours via MQTT).
    @AppStorage("totalPrintSeconds") var totalPrintSeconds = 0.0
    @Published var ams: [AMSUnit] = []

    @Published var connection = "Nicht konfiguriert"
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

    init() {
        mqtt.onStatus = { [weak self] s in DispatchQueue.main.async { self?.connection = s } }
        mqtt.onMessage = { [weak self] _, data in
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let p = obj["print"] as? [String: Any] else { return }
            DispatchQueue.main.async { self?.apply(p) }
        }
        if !host.isEmpty { connect() }
        var last = Date()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            if self.gcodeState == "RUNNING" { self.totalPrintSeconds += now.timeIntervalSince(last) }
            last = now
        }
    }

    func connect() {
        guard !host.isEmpty, !serial.isEmpty, !accessCode.isEmpty else { connection = "Nicht konfiguriert"; return }
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

    var stateText: String {
        switch gcodeState {
        case "RUNNING": return "Druckt"
        case "PREPARE": return "Bereitet vor"
        case "PAUSE": return "Pausiert"
        case "FINISH": return "Fertig"
        case "FAILED": return "Fehlgeschlagen"
        case "IDLE": return "Bereit"
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
        let h = Int(totalPrintSeconds) / 3600, m = Int(totalPrintSeconds) % 3600 / 60
        return "\(h)h \(m)m"
    }

    var menuTitle: String {
        gcodeState == "RUNNING" ? "\(percent)% · \(remainingText)" : ""
    }
}
