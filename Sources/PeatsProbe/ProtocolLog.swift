import Foundation

/// One RFCOMM frame, or one transport note, recorded exactly as it crossed the
/// link. Nothing here is synthesised: every `tx` entry is a packet this app
/// actually wrote, and every `rx` entry is bytes the earbuds actually sent.
struct ProtocolLogEntry: Identifiable, Equatable, Sendable {
    enum Direction: String, Sendable {
        case tx = "TX"
        case rx = "RX"
        case note = "··"
    }

    let id: UUID
    let date: Date
    let direction: Direction
    let bytes: [UInt8]
    let message: String

    init(direction: Direction, bytes: [UInt8] = [], message: String) {
        self.id = UUID()
        self.date = Date()
        self.direction = direction
        self.bytes = bytes
        self.message = message
    }

    var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var timestamp: String {
        ProtocolLogEntry.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

/// A bounded, in-memory frame log. It holds only packet metadata that this Mac
/// sent or received; it never writes captured bytes to disk.
@MainActor
@Observable
final class ProtocolLog {
    private(set) var entries: [ProtocolLogEntry] = []
    var isPaused = false

    private let limit = 600

    func append(_ entry: ProtocolLogEntry) {
        guard !isPaused else { return }
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    func note(_ message: String) {
        append(ProtocolLogEntry(direction: .note, message: message))
    }

    func clear() {
        entries.removeAll()
    }

    var recent: [ProtocolLogEntry] {
        Array(entries.suffix(200).reversed())
    }

    func exportText() -> String {
        entries
            .map { "\($0.timestamp)  \($0.direction.rawValue)  \($0.hex.isEmpty ? "—" : $0.hex)  \($0.message)" }
            .joined(separator: "\n")
    }
}

/// Human-readable decoding for an arbitrary frame, used by the developer views
/// so an unknown opcode still reads as something useful rather than raw hex.
enum PeatsFrameDescriber {
    static func describe(_ packet: PeatsPacket) -> String {
        let opcode = String(format: "%02X %02X", packet.opcode.0, packet.opcode.1)
        if let known = knownName(for: packet.opcode) {
            return "\(opcode)  \(known)\(payloadSuffix(packet.payload))"
        }
        return "\(opcode)  unknown opcode\(payloadSuffix(packet.payload))"
    }

    private static func payloadSuffix(_ payload: [UInt8]) -> String {
        guard !payload.isEmpty else { return "  (no payload)" }
        let hex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        if payload.count == 1 {
            return "  payload \(hex) (\(payload[0]))"
        }
        let ascii = String(bytes: payload.filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .utf8) ?? ""
        return ascii.count >= 3 ? "  payload \(hex) “\(ascii)”" : "  payload \(hex)"
    }

    private static func knownName(for opcode: (UInt8, UInt8)) -> String? {
        let request = (opcode.0 & 0x7F, opcode.1)
        let isReply = opcode.0 & 0x80 != 0
        guard let command = PeatsReadCommand.allCases.first(where: {
            $0.requestOpcode.0 == request.0 && $0.requestOpcode.1 == request.1
        }) else {
            return writeName(for: request).map { isReply ? "\($0) reply" : $0 }
        }
        return isReply ? "\(command.label) reply" : "\(command.label) request"
    }

    private static func writeName(for opcode: (UInt8, UInt8)) -> String? {
        switch (opcode.0, opcode.1) {
        case (0x03, 0x11): "set noise-control mode"
        case (0x03, 0x25): "set noise-control strength"
        case (0x03, 0x4D): "set transparency level"
        case (0x03, 0x0F): "set game mode"
        case (0x03, 0x15): "set multipoint"
        case (0x03, 0x13): "set touch lock"
        case (0x03, 0x39): "set LDAC"
        case (0x03, 0x34): "set LE Audio"
        case (0x03, 0x20): "set prompt volume"
        case (0x03, 0x22): "set voice package"
        case (0x03, 0x3A): "find left earbud"
        case (0x03, 0x3B): "find right earbud"
        case (0x0E, 0x02): "set equaliser band"
        default: nil
        }
    }
}
