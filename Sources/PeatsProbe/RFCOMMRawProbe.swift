import Foundation
import IOBluetooth

/// Reverse-engineering transport for the Q3 Pro control link, used so a feature
/// can be discovered on this Mac instead of by capturing an Android phone's
/// traffic.
///
/// Three modes, in increasing order of intrusiveness:
///
/// 1. `listen` — opens the channel and writes nothing at all. Every frame the
///    earbuds push (for example after a stem press) is decoded and logged.
/// 2. `send` — writes exactly one operator-supplied packet, then records every
///    frame that arrives in the reply window. It never retries.
/// 3. `sweep` — walks a caller-supplied list of request packets one at a time,
///    recording which ones the firmware answers. Each packet is still sent once.
final class RFCOMMRawProbe: NSObject, @unchecked Sendable {
    struct Reply: Sendable {
        let request: PeatsPacket?
        let packet: PeatsPacket
        let bytes: [UInt8]
    }

    var onLog: (@Sendable (ProtocolLogEntry) -> Void)?
    var onReply: (@Sendable (String, Reply) -> Void)?
    var onStatus: (@Sendable (String, String) -> Void)?
    var onFinish: (@Sendable (String, String) -> Void)?
    /// Called when the link dies mid-run. `suspect` is the last packet this Mac
    /// wrote before the channel went away — the prime candidate for whatever
    /// knocked the earbuds off — and `resumeAt` is the next opcode that was
    /// never reached, so a sweep can be continued past the culprit.
    var onLinkDropped: (@Sendable (String, PeatsPacket?, PeatsPacket?) -> Void)?

    private var address: String?
    private var channel: IOBluetoothRFCOMMChannel?
    private var responseBuffer = Data()
    private var queue: [PeatsPacket] = []
    private var activeRequest: PeatsPacket?
    private var lastSent: PeatsPacket?
    private var answered = 0
    private var received = 0
    private var openTimeout: DispatchWorkItem?
    private var stepTimeout: DispatchWorkItem?
    private var listenTimeout: DispatchWorkItem?
    private var completed = false
    private var isListening = false
    private var stepInterval: TimeInterval = 0.8

    var isRunning: Bool { channel != nil && !completed }

    /// Opens the control channel read-only and logs whatever the earbuds send.
    /// No packet is written, so this cannot change a setting.
    func listen(
        from device: IOBluetoothDevice,
        address: String,
        channelID: BluetoothRFCOMMChannelID,
        duration: TimeInterval
    ) {
        guard start(device: device, address: address, channelID: channelID, requests: []) else { return }
        isListening = true
        let stop = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish("Listen window ended. \(self.received) frame\(self.received == 1 ? "" : "s") captured; nothing was written.")
        }
        listenTimeout?.cancel()
        listenTimeout = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: stop)
    }

    /// Writes one operator-supplied packet exactly once and records the replies.
    func send(
        _ packet: PeatsPacket,
        to device: IOBluetoothDevice,
        address: String,
        channelID: BluetoothRFCOMMChannelID,
        replyWindow: TimeInterval = 1.6
    ) {
        stepInterval = replyWindow
        _ = start(device: device, address: address, channelID: channelID, requests: [packet])
    }

    /// Walks a list of request packets, one send each, recording which answer.
    func sweep(
        _ packets: [PeatsPacket],
        to device: IOBluetoothDevice,
        address: String,
        channelID: BluetoothRFCOMMChannelID,
        replyWindow: TimeInterval = 0.55
    ) {
        stepInterval = replyWindow
        _ = start(device: device, address: address, channelID: channelID, requests: packets)
    }

    func cancel() {
        finish("Stopped by the operator.")
    }

    private func start(
        device: IOBluetoothDevice,
        address: String,
        channelID: BluetoothRFCOMMChannelID,
        requests: [PeatsPacket]
    ) -> Bool {
        guard channel == nil else {
            onStatus?(address, "A diagnostics session is already running.")
            return false
        }

        self.address = address
        queue = requests
        activeRequest = nil
        lastSent = nil
        answered = 0
        received = 0
        completed = false
        isListening = false
        responseBuffer.removeAll(keepingCapacity: true)

        var openedChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&openedChannel, withChannelID: channelID, delegate: self)
        channel = openedChannel
        guard result == kIOReturnSuccess else {
            finish("Could not open the diagnostics channel (IOKit \(result)).")
            return false
        }

        log(.note, [], "Opening RFCOMM channel \(channelID) for diagnostics")
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish("Diagnostics channel did not open in time.")
        }
        openTimeout?.cancel()
        openTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        return true
    }

    @objc func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openTimeout?.cancel()
        openTimeout = nil
        guard !completed else {
            if let rfcommChannel, rfcommChannel.isOpen() { _ = rfcommChannel.close() }
            return
        }
        guard error == kIOReturnSuccess, let rfcommChannel else {
            finish("Diagnostics channel did not open (IOKit \(error)).")
            return
        }
        channel = rfcommChannel
        log(.note, [], "Channel open")
        if isListening {
            status("Listening. Press the earbud stems now — every frame they push is logged.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendNext()
        }
    }

    @objc func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        responseBuffer.append(dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength)
        drainFrames()
    }

    @objc func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard !completed else { return }
        reportDrop()
        finish(dropMessage())
    }

    private func sendNext() {
        guard !completed else { return }
        guard !queue.isEmpty else {
            finish("Finished. \(answered) of the sent packet\(answered == 1 ? "" : "s") were answered; \(received) frame\(received == 1 ? "" : "s") captured.")
            return
        }
        guard let channel else {
            reportDrop()
            finish(dropMessage())
            return
        }

        let packet = queue.removeFirst()
        activeRequest = packet
        var request = packet.data
        let length = UInt16(request.count)
        let result = request.withUnsafeMutableBytes { bytes -> IOReturn in
            guard let baseAddress = bytes.baseAddress else { return kIOReturnBadArgument }
            return channel.writeAsync(baseAddress.assumingMemoryBound(to: UInt8.self), length: length, refcon: nil)
        }
        guard result == kIOReturnSuccess else {
            reportDrop()
            finish(dropMessage("Could not write the diagnostics packet (IOKit \(result))."))
            return
        }

        lastSent = packet
        log(.tx, Array(packet.data), PeatsFrameDescriber.describe(packet))
        status("Sent \(String(format: "%02X %02X", packet.opcode.0, packet.opcode.1)) · \(queue.count) remaining")

        let step = DispatchWorkItem { [weak self] in
            self?.activeRequest = nil
            self?.sendNext()
        }
        stepTimeout?.cancel()
        stepTimeout = step
        DispatchQueue.main.asyncAfter(deadline: .now() + stepInterval, execute: step)
    }

    private func drainFrames() {
        while let frame = nextFrame() {
            received += 1
            guard let packet = PeatsPacket.decode(frame) else {
                log(.rx, Array(frame), "undecodable frame")
                continue
            }
            log(.rx, Array(frame), PeatsFrameDescriber.describe(packet))
            if activeRequest != nil { answered += 1 }
            if let address {
                onReply?(address, Reply(request: activeRequest, packet: packet, bytes: Array(frame)))
            }
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

    /// The last packet written before the link went away, and the first one the
    /// run never got to. Both are worth surfacing: the sweep that dropped the
    /// earbuds is only useful if we know where it stopped.
    private func reportDrop() {
        guard let address, !completed else { return }
        onLinkDropped?(address, lastSent, queue.first)
    }

    private func dropMessage(_ prefix: String? = nil) -> String {
        var parts: [String] = [prefix ?? "The earbuds dropped the diagnostics channel."]
        if let lastSent {
            parts.append("Last packet written was \(String(format: "%02X %02X", lastSent.opcode.0, lastSent.opcode.1)) — treat it as the suspect.")
        }
        if let next = queue.first {
            parts.append("Never reached \(String(format: "%02X %02X", next.opcode.0, next.opcode.1)) onward.")
        }
        return parts.joined(separator: " ")
    }

    private func finish(_ message: String) {
        guard !completed else { return }
        completed = true
        openTimeout?.cancel(); openTimeout = nil
        stepTimeout?.cancel(); stepTimeout = nil
        listenTimeout?.cancel(); listenTimeout = nil
        if let channel {
            _ = channel.setDelegate(nil)
            if channel.isOpen() { _ = channel.close() }
        }
        channel = nil
        queue.removeAll()
        activeRequest = nil
        lastSent = nil
        isListening = false
        log(.note, [], message)
        guard let address else { return }
        self.address = nil
        onFinish?(address, message)
    }

    private func status(_ message: String) {
        guard let address else { return }
        onStatus?(address, message)
    }

    private func log(_ direction: ProtocolLogEntry.Direction, _ bytes: [UInt8], _ message: String) {
        onLog?(ProtocolLogEntry(direction: direction, bytes: bytes, message: message))
    }
}
