import Foundation
import IOBluetooth

/// Keeps a single RFCOMM session open while it performs a sequence of safe,
/// idempotent state reads. It contains no setting-changing packet path.
final class RFCOMMReadProbe: NSObject, @unchecked Sendable {
    var onFinish: ((String, String) -> Void)?
    var onValue: ((String, PeatsReadCommand, PeatsReadValue) -> Void)?
    var onLog: (@Sendable (ProtocolLogEntry) -> Void)?

    private var address: String?
    private var channel: IOBluetoothRFCOMMChannel?
    private var responseBuffer = Data()
    private var remainingCommands: [PeatsReadCommand] = []
    private var readValues: [(PeatsReadCommand, PeatsReadValue)] = []
    private var activeCommand: PeatsReadCommand?
    private var openTimeout: DispatchWorkItem?
    private var responseTimeout: DispatchWorkItem?
    private var completed = false

    func read(
        _ commands: [PeatsReadCommand],
        from device: IOBluetoothDevice,
        address: String,
        channelID: BluetoothRFCOMMChannelID
    ) {
        guard !commands.isEmpty else { return }
        guard channel == nil else {
            report(address: address, "A state refresh is already running")
            return
        }

        self.address = address
        self.remainingCommands = commands
        self.readValues.removeAll(keepingCapacity: true)
        self.responseBuffer.removeAll(keepingCapacity: true)
        self.completed = false

        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(
            &openedChannel,
            withChannelID: channelID,
            delegate: self
        )
        channel = openedChannel
        guard result == kIOReturnSuccess else {
            finish("Could not start the status-refresh channel (IOKit \(result)).")
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.finish("Status-refresh channel did not open in time.")
        }
        openTimeout?.cancel()
        openTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    @objc func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openTimeout?.cancel()
        openTimeout = nil
        guard !completed else {
            if let rfcommChannel, rfcommChannel.isOpen() { _ = rfcommChannel.close() }
            return
        }
        guard error == kIOReturnSuccess, let rfcommChannel else {
            finish("Status-refresh channel did not open (IOKit \(error)).")
            return
        }
        channel = rfcommChannel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.sendNextRead()
        }
    }

    @objc func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        responseBuffer.append(dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)
        parseResponses()
    }

    @objc func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {}

    private func sendNextRead() {
        guard !completed else { return }
        guard !remainingCommands.isEmpty else {
            let summary = readValues
                .map { "\($0.0.label): \($0.1.displayValue)" }
                .joined(separator: "  ·  ")
            finish(summary.isEmpty ? "No device values were returned." : summary)
            return
        }
        guard let channel else {
            finish("RFCOMM channel closed before the status refresh completed.")
            return
        }

        let command = remainingCommands.removeFirst()
        activeCommand = command
        var request = command.packet.data
        let requestLength = UInt16(request.count)
        let result = request.withUnsafeMutableBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnBadArgument }
            return channel.writeAsync(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                length: requestLength,
                refcon: nil
            )
        }
        guard result == kIOReturnSuccess else {
            finish("Could not send the \(command.label.lowercased()) read (IOKit \(result)).")
            return
        }
        onLog?(ProtocolLogEntry(direction: .tx, bytes: Array(command.packet.data), message: PeatsFrameDescriber.describe(command.packet)))

        reportCurrent("Reading \(command.label.lowercased())…")
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let command = self.activeCommand else { return }
            self.finish("No reply for \(command.label.lowercased()). No setting was changed.")
        }
        responseTimeout?.cancel()
        responseTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: timeout)
    }

    private func parseResponses() {
        while let frameData = nextFrame() {
            guard let packet = PeatsPacket.decode(frameData) else {
                onLog?(ProtocolLogEntry(direction: .rx, bytes: Array(frameData), message: "undecodable frame"))
                continue
            }
            onLog?(ProtocolLogEntry(direction: .rx, bytes: Array(frameData), message: PeatsFrameDescriber.describe(packet)))
            guard let command = activeCommand else { continue }
            guard packet.opcode.0 == command.expectedReplyOpcode.0,
                  packet.opcode.1 == command.expectedReplyOpcode.1 else { continue }

            responseTimeout?.cancel()
            responseTimeout = nil
            let value = decode(packet.payload, for: command)
            readValues.append((command, value))
            onValue?(address ?? "", command, value)
            activeCommand = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.sendNextRead()
            }
            return
        }
    }

    private func decode(_ payload: [UInt8], for command: PeatsReadCommand) -> PeatsReadValue {
        switch command {
        case .leftBattery, .rightBattery, .caseBattery:
            return .percentage(Int(payload.last ?? 0))
        case .firmware:
            let bytes = payload.drop(while: { $0 == 0 })
            return .firmware(String(bytes: bytes, encoding: .utf8) ?? "Unknown")
        case .noiseControl:
            if let mode = PeatsNoiseControlMode(rawValue: payload.last ?? 0xFF) {
                return .noiseControl(mode)
            }
            return .raw(payload)
        case .gameMode, .multipoint, .touchLock, .ldac, .leAudio:
            if let value = PeatsToggle(rawValue: payload.last ?? 0xFF) {
                return .toggle(value)
            }
            return .raw(payload)
        case .noiseControlStrength, .transparencyLevel, .promptVolume, .voicePackage:
            guard let value = payload.last else { return .raw(payload) }
            return .unsignedByte(value)
        default:
            return .raw(payload)
        }
    }

    private func nextFrame() -> Data? {
        guard let start = responseBuffer.firstIndex(of: 0xFF) else {
            responseBuffer.removeAll(keepingCapacity: true)
            return nil
        }
        if start > responseBuffer.startIndex {
            responseBuffer.removeSubrange(responseBuffer.startIndex..<start)
        }
        guard responseBuffer.count >= 8 else { return nil }

        // Data preserves its collection indices after removeFirst/removeSubrange.
        // Use an offset from its current start index rather than the literal index 3.
        let payloadLengthIndex = responseBuffer.index(responseBuffer.startIndex, offsetBy: 3)
        let frameLength = 8 + Int(responseBuffer[payloadLengthIndex])
        guard responseBuffer.count >= frameLength else { return nil }
        let frame = Data(responseBuffer.prefix(frameLength))
        responseBuffer.removeFirst(frameLength)
        return frame
    }

    private func finish(_ message: String) {
        guard !completed else { return }
        completed = true
        openTimeout?.cancel()
        openTimeout = nil
        responseTimeout?.cancel()
        responseTimeout = nil
        if let channel {
            _ = channel.setDelegate(nil)
            if channel.isOpen() { _ = channel.close() }
        }
        channel = nil
        remainingCommands.removeAll()
        readValues.removeAll()
        activeCommand = nil
        guard let address else { return }
        self.address = nil
        report(address: address, message)
    }

    private func reportCurrent(_ message: String) {
        guard let address else { return }
        report(address: address, message)
    }

    private func report(address: String, _ message: String) {
        onFinish?(address, message)
    }
}

/// Sends exactly one explicit setting change and waits for the device's
/// acknowledgement. It never retries a write; the caller performs a separate
/// read-back after the command completes, including after an acknowledgement
/// timeout.
final class RFCOMMWriteProbe: NSObject, @unchecked Sendable {
    var onFinish: ((String, PeatsWriteCommand, String, Bool, Bool) -> Void)?
    var onLog: (@Sendable (ProtocolLogEntry) -> Void)?

    private var address: String?
    private var channel: IOBluetoothRFCOMMChannel?
    private var command: PeatsWriteCommand?
    private var responseBuffer = Data()
    private var openTimeout: DispatchWorkItem?
    private var responseTimeout: DispatchWorkItem?
    private var completed = false
    private var writeWasSent = false

    func write(
        _ command: PeatsWriteCommand,
        to device: IOBluetoothDevice,
        address: String,
        channelID: BluetoothRFCOMMChannelID
    ) {
        guard channel == nil else {
            report(
                address: address,
                command: command,
                "Another setting change is already running.",
                confirmed: false,
                shouldReadBack: false
            )
            return
        }

        self.address = address
        self.command = command
        responseBuffer.removeAll(keepingCapacity: true)
        completed = false
        writeWasSent = false

        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(
            &openedChannel,
            withChannelID: channelID,
            delegate: self
        )
        channel = openedChannel
        guard result == kIOReturnSuccess else {
            finish("Could not start the setting-control channel (IOKit \(result)).", confirmed: false)
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.finish("Setting-control channel did not open in time.", confirmed: false)
        }
        openTimeout?.cancel()
        openTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    @objc func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openTimeout?.cancel()
        openTimeout = nil
        guard !completed else {
            if let rfcommChannel, rfcommChannel.isOpen() { _ = rfcommChannel.close() }
            return
        }
        guard error == kIOReturnSuccess, let rfcommChannel else {
            finish("Setting-control channel did not open (IOKit \(error)).", confirmed: false)
            return
        }
        channel = rfcommChannel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.sendWrite()
        }
    }

    @objc func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        responseBuffer.append(dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)
        parseResponses()
    }

    @objc func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {}

    private func sendWrite() {
        guard !completed, let channel, let command else { return }

        var request = command.packet.data
        let requestLength = UInt16(request.count)
        let result = request.withUnsafeMutableBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnBadArgument }
            return channel.writeAsync(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                length: requestLength,
                refcon: nil
            )
        }
        guard result == kIOReturnSuccess else {
            finish("Could not send \(command.label.lowercased()) (IOKit \(result)).", confirmed: false)
            return
        }
        onLog?(ProtocolLogEntry(direction: .tx, bytes: Array(command.packet.data), message: PeatsFrameDescriber.describe(command.packet)))
        writeWasSent = true

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let command = self.command else { return }
            self.finish("\(command.label) was sent without an acknowledgement. Checking the live setting now…", confirmed: false)
        }
        responseTimeout?.cancel()
        responseTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: timeout)
    }

    private func parseResponses() {
        while let frameData = nextFrame() {
            guard let packet = PeatsPacket.decode(frameData) else {
                onLog?(ProtocolLogEntry(direction: .rx, bytes: Array(frameData), message: "undecodable frame"))
                continue
            }
            onLog?(ProtocolLogEntry(direction: .rx, bytes: Array(frameData), message: PeatsFrameDescriber.describe(packet)))
            guard let command else { continue }
            guard packet.opcode.0 == command.expectedReplyOpcode.0,
                  packet.opcode.1 == command.expectedReplyOpcode.1 else { continue }

            finish("\(command.label) confirmed by the earbud. Reading back the live setting…", confirmed: true)
            return
        }
    }

    private func nextFrame() -> Data? {
        guard let start = responseBuffer.firstIndex(of: 0xFF) else {
            responseBuffer.removeAll(keepingCapacity: true)
            return nil
        }
        if start > responseBuffer.startIndex {
            responseBuffer.removeSubrange(responseBuffer.startIndex..<start)
        }
        guard responseBuffer.count >= 8 else { return nil }

        let payloadLengthIndex = responseBuffer.index(responseBuffer.startIndex, offsetBy: 3)
        let frameLength = 8 + Int(responseBuffer[payloadLengthIndex])
        guard responseBuffer.count >= frameLength else { return nil }
        let frame = Data(responseBuffer.prefix(frameLength))
        responseBuffer.removeFirst(frameLength)
        return frame
    }

    private func finish(_ message: String, confirmed: Bool) {
        guard !completed else { return }
        completed = true
        openTimeout?.cancel()
        openTimeout = nil
        responseTimeout?.cancel()
        responseTimeout = nil
        if let channel {
            _ = channel.setDelegate(nil)
            if channel.isOpen() { _ = channel.close() }
        }
        channel = nil
        guard let completedCommand = command else { return }
        command = nil
        let shouldReadBack = writeWasSent
        writeWasSent = false
        guard let address else { return }
        self.address = nil
        report(address: address, command: completedCommand, message, confirmed: confirmed, shouldReadBack: shouldReadBack)
    }

    private func report(
        address: String,
        command: PeatsWriteCommand,
        _ message: String,
        confirmed: Bool,
        shouldReadBack: Bool
    ) {
        onFinish?(address, command, message, confirmed, shouldReadBack)
    }
}
