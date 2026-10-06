import Foundation

/// The independently described SoundPEATS packet format used by the RFCOMM
/// transport. This file only builds/parses packets; it never opens Bluetooth
/// channels or sends a command by itself.
struct PeatsPacket {
    let version: UInt8
    let flags: UInt8
    let vendorID: (UInt8, UInt8)
    let opcode: (UInt8, UInt8)
    let payload: [UInt8]

    static let defaultVendorID: (UInt8, UInt8) = (0x00, 0x0A)
    static let equalizerVendorID: (UInt8, UInt8) = (0x00, 0x1D)

    init(
        opcode: (UInt8, UInt8),
        payload: [UInt8] = [],
        vendorID: (UInt8, UInt8) = PeatsPacket.defaultVendorID,
        version: UInt8 = 0x04,
        flags: UInt8 = 0x00
    ) {
        self.version = version
        self.flags = flags
        self.vendorID = vendorID
        self.opcode = opcode
        self.payload = payload
    }

    var data: Data {
        Data([0xFF, version, flags, UInt8(payload.count), vendorID.0, vendorID.1, opcode.0, opcode.1] + payload)
    }

    static func decode(_ data: Data) -> PeatsPacket? {
        let bytes = Array(data)
        guard bytes.count >= 8, bytes[0] == 0xFF, bytes.count == 8 + Int(bytes[3]) else { return nil }
        return PeatsPacket(
            opcode: (bytes[6], bytes[7]),
            payload: Array(bytes.dropFirst(8)),
            vendorID: (bytes[4], bytes[5]),
            version: bytes[1],
            flags: bytes[2]
        )
    }
}

/// Read operations are idempotent and may be retried after a transport timeout.
enum PeatsReadCommand: CaseIterable, Identifiable {
    case leftBattery, rightBattery, caseBattery, firmware
    case noiseControl, noiseControlStrength, transparencyLevel
    case gameMode, multipoint, touchLock, ldac, leAudio
    case promptVolume, voicePackage, touchMapping, classicConnection

    var id: String { label }

    var label: String {
        switch self {
        case .leftBattery: "Left battery"
        case .rightBattery: "Right battery"
        case .caseBattery: "Case battery"
        case .firmware: "Firmware version"
        case .noiseControl: "Noise-control mode"
        case .noiseControlStrength: "Noise-control strength"
        case .transparencyLevel: "Transparency level"
        case .gameMode: "Game mode"
        case .multipoint: "Multipoint"
        case .touchLock: "Touch lock"
        case .ldac: "LDAC"
        case .leAudio: "LE Audio"
        case .promptVolume: "Prompt volume"
        case .voicePackage: "Voice package"
        case .touchMapping: "Touch mapping"
        case .classicConnection: "Classic Bluetooth status"
        }
    }

    var requestOpcode: (UInt8, UInt8) {
        switch self {
        case .leftBattery: (0x03, 0x06)
        case .rightBattery: (0x03, 0x07)
        case .caseBattery: (0x03, 0x23)
        case .firmware: (0x03, 0x09)
        case .noiseControl: (0x03, 0x10)
        case .noiseControlStrength: (0x03, 0x24)
        case .transparencyLevel: (0x03, 0x4C)
        case .gameMode: (0x03, 0x0E)
        case .multipoint: (0x03, 0x14)
        case .touchLock: (0x03, 0x12)
        case .ldac: (0x03, 0x38)
        case .leAudio: (0x03, 0x35)
        case .promptVolume: (0x03, 0x19)
        case .voicePackage: (0x03, 0x21)
        case .touchMapping: (0x03, 0xAA)
        case .classicConnection: (0x03, 0x17)
        }
    }

    var expectedReplyOpcode: (UInt8, UInt8) { (0x83, requestOpcode.1) }
    var packet: PeatsPacket { PeatsPacket(opcode: requestOpcode) }
}

enum PeatsNoiseControlMode: UInt8, CaseIterable, Codable {
    case normal = 0x00
    case noiseCancelling = 0x01
    case transparency = 0x02
    case adaptive = 0x03
    case weakNoiseReduction = 0x04
}

enum PeatsReadValue: Equatable {
    case percentage(Int)
    case firmware(String)
    case noiseControl(PeatsNoiseControlMode)
    case toggle(PeatsToggle)
    case unsignedByte(UInt8)
    case raw([UInt8])

    var displayValue: String {
        switch self {
        case .percentage(let value): "\(value)%"
        case .firmware(let value): value
        case .noiseControl(let value):
            switch value {
            case .normal: "Normal"
            case .noiseCancelling: "Noise Cancelling"
            case .transparency: "Transparency"
            case .adaptive: "Adaptive Noise Cancelling"
            case .weakNoiseReduction: "Weak Noise Reduction"
            }
        case .toggle(let value): value.displayValue
        case .unsignedByte(let value): "\(value)"
        case .raw(let bytes): bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

enum PeatsToggle: UInt8, Equatable, Codable {
    case off = 0x00
    case on = 0x01

    var displayValue: String {
        self == .on ? "On" : "Off"
    }
}

/// Setting operations are intentionally packet builders only. A future control
/// service must ask for an explicit user action, write once, then read back;
/// it must never retry a write automatically.
enum PeatsWriteCommand {
    case noiseControl(PeatsNoiseControlMode)
    case noiseControlStrength(UInt8)
    case transparencyLevel(UInt8)
    case gameMode(PeatsToggle)
    case multipoint(PeatsToggle)
    case touchLock(PeatsToggle)
    case ldac(PeatsToggle)
    case leAudio(PeatsToggle)
    case promptVolume(UInt8)
    case voicePackage(UInt8)
    case findLeft, findRight

    var label: String {
        switch self {
        case .noiseControl(let mode): "Set noise control to \(PeatsReadValue.noiseControl(mode).displayValue)"
        case .noiseControlStrength: "Set noise-control strength"
        case .transparencyLevel: "Set transparency level"
        case .gameMode: "Set game mode"
        case .multipoint: "Set multipoint"
        case .touchLock: "Set touch lock"
        case .ldac: "Set LDAC"
        case .leAudio: "Set LE Audio"
        case .promptVolume: "Set prompt volume"
        case .voicePackage: "Set voice package"
        case .findLeft: "Find left earbud"
        case .findRight: "Find right earbud"
        }
    }

    /// The Q3 command family acknowledges a write through the matching 0x83
    /// response opcode. A caller must still read back the setting afterwards.
    var expectedReplyOpcode: (UInt8, UInt8) { (0x83, packet.opcode.1) }

    var packet: PeatsPacket {
        switch self {
        case .noiseControl(let mode): PeatsPacket(opcode: (0x03, 0x11), payload: [mode.rawValue])
        case .noiseControlStrength(let level): PeatsPacket(opcode: (0x03, 0x25), payload: [level])
        case .transparencyLevel(let level): PeatsPacket(opcode: (0x03, 0x4D), payload: [level])
        case .gameMode(let value): PeatsPacket(opcode: (0x03, 0x0F), payload: [value.rawValue])
        case .multipoint(let value): PeatsPacket(opcode: (0x03, 0x15), payload: [value.rawValue])
        case .touchLock(let value): PeatsPacket(opcode: (0x03, 0x13), payload: [value.rawValue])
        case .ldac(let value): PeatsPacket(opcode: (0x03, 0x39), payload: [value.rawValue])
        case .leAudio(let value): PeatsPacket(opcode: (0x03, 0x34), payload: [value.rawValue])
        case .promptVolume(let volume): PeatsPacket(opcode: (0x03, 0x20), payload: [volume])
        case .voicePackage(let package): PeatsPacket(opcode: (0x03, 0x22), payload: [package])
        case .findLeft: PeatsPacket(opcode: (0x03, 0x3A), payload: [0x01])
        case .findRight: PeatsPacket(opcode: (0x03, 0x3B), payload: [0x01])
        }
    }
}

struct PeatsEqualizerBand: Equatable {
    var frequencyHz: UInt16
    var gainDB: Double
    var q: Double

    /// Q3 support needs a controlled hardware test before this packet is used.
    func packet(totalBands: UInt8, index: UInt8, masterGainDB: Double = 0) -> PeatsPacket {
        let values = [masterGainDB * 60, Double(frequencyHz) * 3, gainDB * 60, q * 4096]
            .map { Int16($0.rounded()).bigEndian }
        let encodedValues = values.flatMap { value in [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)] }
        return PeatsPacket(
            opcode: (0x0E, 0x02),
            payload: [totalBands, index] + encodedValues,
            vendorID: PeatsPacket.equalizerVendorID
        )
    }
}
