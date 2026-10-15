import Foundation
import Network

enum ConnectionStatus {
    case notConfigured, connecting, connected, denied, disconnected
    case waiting(String)
    case failed(String)
}

/// Minimal MQTT 3.1.1 client (QoS 0, TLS with self-signed cert) – just enough for Bambu Lab's local broker.
final class MQTTClient {
    var onMessage: ((String, Data) -> Void)?
    var onStatus: ((ConnectionStatus) -> Void)?

    private let queue = DispatchQueue(label: "mqtt")
    private var conn: NWConnection?
    private var buffer = Data()
    private var pingTimer: DispatchSourceTimer?
    private var generation = 0

    private var host = "", user = "", pass = "", clientId = ""
    private var subscribeTopic = "", requestTopic = "", requestPayload = Data()
    private var wanted = false

    func start(host: String, user: String, pass: String, subscribe: String, requestTopic: String, requestPayload: Data) {
        queue.async {
            self.host = host; self.user = user; self.pass = pass
            self.subscribeTopic = subscribe; self.requestTopic = requestTopic; self.requestPayload = requestPayload
            self.clientId = "bambubar-\(UUID().uuidString.prefix(8))"
            self.wanted = true
            self.connect()
        }
    }

    func stop() {
        queue.async {
            self.wanted = false
            self.generation += 1
            self.pingTimer?.cancel()
            self.conn?.cancel()
            self.conn = nil
        }
    }

    // MARK: connection

    private func connect() {
        generation += 1
        let gen = generation
        pingTimer?.cancel()
        conn?.cancel()
        buffer.removeAll()

        let tls = NWProtocolTLS.Options()
        // The printer uses a self-signed certificate.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, done in done(true) }, queue)
        let params = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let c = NWConnection(host: NWEndpoint.Host(host), port: 8883, using: params)
        conn = c
        onStatus?(.connecting)

        c.stateUpdateHandler = { [weak self] state in
            guard let self, gen == self.generation else { return }
            switch state {
            case .ready:
                self.send(self.connectPacket())
                self.receive(gen)
            case .failed(let e):
                self.onStatus?(.failed(e.localizedDescription))
                self.scheduleReconnect(gen)
            case .waiting(let e):
                self.onStatus?(.waiting(e.localizedDescription))
            default: break
            }
        }
        c.start(queue: queue)
    }

    private func scheduleReconnect(_ gen: Int) {
        guard wanted, gen == generation else { return }
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.wanted, gen == self.generation else { return }
            self.connect()
        }
    }

    private func receive(_ gen: Int) {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self, gen == self.generation else { return }
            if let data { self.buffer.append(data); self.parse() }
            if err != nil || done {
                self.onStatus?(.disconnected)
                self.scheduleReconnect(gen)
            } else {
                self.receive(gen)
            }
        }
    }

    // MARK: packets

    private func parse() {
        while buffer.count >= 2 {
            var mult = 1, rem = 0, idx = 1
            var complete = false
            while idx < buffer.count && idx <= 4 {
                let b = Int(buffer[buffer.startIndex + idx]); idx += 1
                rem += (b & 0x7F) * mult; mult *= 128
                if b & 0x80 == 0 { complete = true; break }
            }
            guard complete, buffer.count >= idx + rem else { return }
            let first = buffer[buffer.startIndex]
            let body = Data(buffer.subdata(in: (buffer.startIndex + idx)..<(buffer.startIndex + idx + rem)))
            buffer = Data(buffer.dropFirst(idx + rem))
            handle(first, body)
        }
    }

    private func handle(_ first: UInt8, _ body: Data) {
        switch first >> 4 {
        case 2: // CONNACK
            if body.count >= 2, body[1] == 0 {
                onStatus?(.connected)
                send(subscribePacket())
                requestFullState()
                startPing()
            } else {
                onStatus?(.denied)
                wanted = false
                conn?.cancel()
            }
        case 3: // PUBLISH
            guard body.count >= 2 else { return }
            let tl = Int(body[0]) << 8 | Int(body[1])
            guard body.count >= 2 + tl else { return }
            let topic = String(decoding: body[2..<(2 + tl)], as: UTF8.self)
            let qos = Int(first >> 1) & 3
            let off = 2 + tl + (qos > 0 ? 2 : 0)
            if body.count >= off { onMessage?(topic, Data(body[off...])) }
        default: break
        }
    }

    func requestFullState() {
        queue.async { self.send(self.publishPacket(self.requestTopic, self.requestPayload)) }
    }

    private func startPing() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in self?.send(Data([0xC0, 0x00])) }
        t.resume()
        pingTimer = t
    }

    private func send(_ d: Data) { conn?.send(content: d, completion: .contentProcessed { _ in }) }

    private func str(_ s: String) -> Data {
        let u = Data(s.utf8)
        return Data([UInt8(u.count >> 8), UInt8(u.count & 0xFF)]) + u
    }

    private func packet(_ header: UInt8, _ body: Data) -> Data {
        var out = Data([header]); var n = body.count
        repeat { var b = UInt8(n % 128); n /= 128; if n > 0 { b |= 0x80 }; out.append(b) } while n > 0
        return out + body
    }

    private func connectPacket() -> Data {
        packet(0x10, str("MQTT") + Data([0x04, 0xC2, 0x00, 0x3C]) + str(clientId) + str(user) + str(pass))
    }
    private func subscribePacket() -> Data { packet(0x82, Data([0x00, 0x01]) + str(subscribeTopic) + Data([0x00])) }
    private func publishPacket(_ topic: String, _ payload: Data) -> Data { packet(0x30, str(topic) + payload) }
}
