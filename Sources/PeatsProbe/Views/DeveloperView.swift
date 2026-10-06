import AppKit
import SwiftUI

/// The workbench that makes a phone unnecessary. Every unproven feature can be
/// worked out here, on this Mac, from the earbuds' own answers:
///
/// * **Passive listen** writes nothing. Press a stem, watch the frame the
///   earbuds push, and you have the opcode and its encoding.
/// * **Single packet** sends exactly one operator-composed frame and shows the
///   reply, so a guess can be tested in isolation.
/// * **Opcode sweep** enumerates a request range and records which opcodes the
///   firmware answers at all.
struct DeveloperView: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    @State private var opcodeHigh = "03"
    @State private var opcodeLow = "10"
    @State private var payloadHex = ""
    @State private var sweepStart = "00"
    @State private var sweepEnd = "3F"
    @State private var listenSeconds: Double = 30
    @State private var showsSweepWarning = false
    /// Every verified read on this firmware is an even opcode and its write is
    /// that number plus one, so an even-only sweep is far less likely to change
    /// a setting — or to knock the earbuds off the link.
    @State private var sweepReadsOnly = true

    var body: some View {
        let link = scanner.link
        VStack(spacing: 16) {
            if !link.canControl { NeedsDeviceCard(link: link, scanner: scanner) }

            discoveryCard(link)
            logCard(link)

            CardGrid(columns: 2) {
                discoveredCard(link)
                supportCard(link)
            }
        }
    }

    // MARK: - Discovery

    private func discoveryCard(_ link: DeviceLink) -> some View {
        PeatsCard(padding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Opcode discovery", systemImage: "scope") {
                    StatusBadge(
                        text: scanner.diagnosticsRunning ? "Running" : "Idle",
                        tint: scanner.diagnosticsRunning ? theme.amber : theme.cardFG2,
                        showsDot: true,
                        onCard2: true
                    )
                }

                Text("These tools replace capturing the vendor's phone app. The earbuds are the source of truth: a passive listen proves what a gesture sends, a single packet tests one guess, and a sweep shows which request opcodes this firmware answers at all.")
                    .font(PeatsFont.body(15))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)

                VStack(spacing: 8) {
                    // Passive listen
                    InsetRow(
                        title: "Passive listen",
                        subtitle: "Opens the channel and writes nothing. Press the stems and watch the log.",
                        systemImage: "ear"
                    ) {
                        HStack(spacing: 10) {
                            Text("\(Int(listenSeconds))s")
                                .font(PeatsFont.mono(12))
                                .foregroundStyle(theme.cardFG2)
                            Stepper("", value: $listenSeconds, in: 10...180, step: 10)
                                .labelsHidden()
                            SoftButton(title: "Listen") {
                                guard let address = link.address else { return }
                                scanner.startPassiveListen(for: address, duration: listenSeconds)
                                model.show("Listening — press an earbud gesture now")
                            }
                            .disabled(!link.canControl || scanner.diagnosticsRunning)
                        }
                    }

                    // Single packet
                    InsetRow(
                        title: "Single packet",
                        subtitle: "Writes one frame exactly once. Opcode and payload are hexadecimal.",
                        systemImage: "paperplane"
                    ) {
                        HStack(spacing: 8) {
                            hexField($opcodeHigh, width: 44, placeholder: "03")
                            hexField($opcodeLow, width: 44, placeholder: "10")
                            hexField($payloadHex, width: 110, placeholder: "payload")
                            SoftButton(title: "Send once") {
                                guard let address = link.address,
                                      let high = UInt8(opcodeHigh, radix: 16),
                                      let low = UInt8(opcodeLow, radix: 16) else {
                                    model.show("Opcode must be two hex bytes")
                                    return
                                }
                                scanner.sendRawPacket(
                                    opcode: (high, low),
                                    payload: parseHex(payloadHex),
                                    for: address
                                )
                            }
                            .disabled(!link.canControl || scanner.diagnosticsRunning)
                        }
                    }

                    // Sweep
                    InsetRow(
                        title: "Opcode sweep",
                        subtitle: "Sends every request in the range once, with an empty payload.",
                        systemImage: "list.number"
                    ) {
                        HStack(spacing: 8) {
                            hexField($sweepStart, width: 44, placeholder: "00")
                            Text("→").foregroundStyle(theme.cardFG2)
                            hexField($sweepEnd, width: 44, placeholder: "3F")
                            SoftButton(title: "Sweep") { showsSweepWarning = true }
                                .disabled(!link.canControl || scanner.diagnosticsRunning)
                        }
                    }

                    InsetRow(
                        title: "Reads only (even opcodes)",
                        subtitle: "Every verified read here is even and its write is that number + 1. Leave this on unless you mean to send writes.",
                        systemImage: "shield.lefthalf.filled"
                    ) {
                        PeatsSwitch(isOn: sweepReadsOnly) { sweepReadsOnly.toggle() }
                    }
                }

                if scanner.diagnosticsRunning {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(link.address.flatMap { scanner.statusForDiagnostics(at: $0) } ?? "Running…")
                            .font(PeatsFont.body(13))
                            .foregroundStyle(theme.cardFG2)
                        Spacer()
                        SoftButton(title: "Stop") { scanner.cancelDiagnostics() }
                    }
                    .padding(.top, 16)
                } else if let status = link.address.flatMap({ scanner.statusForDiagnostics(at: $0) }) {
                    Text(status)
                        .font(PeatsFont.body(13))
                        .foregroundStyle(theme.cardFG2)
                        .padding(.top, 16)
                }

                if let address = link.address, !(scanner.suspectOpcodes[address] ?? []).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.amber)
                            Text("Dropped the link").font(PeatsFont.display(14, .semibold))
                                .foregroundStyle(theme.cardFG)
                            Spacer()
                            SoftButton(title: "Clear") { scanner.clearSuspectOpcodes(for: address) }
                        }
                        Text("These opcodes were the last thing written before the earbuds closed the channel. Future sweeps skip them.")
                            .font(PeatsFont.body(12))
                            .foregroundStyle(theme.cardFG2)
                        Text((scanner.suspectOpcodes[address] ?? []).joined(separator: "   "))
                            .font(PeatsFont.mono(12))
                            .foregroundStyle(theme.amber)
                        if let resume = scanner.sweepResumePoint[address] {
                            SoftButton(title: "Resume sweep from \(String(format: "%02X", resume))") {
                                sweepStart = String(format: "%02X", resume)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card2))
                    .padding(.top, 16)
                }

                UnverifiedNotice(text: "A sweep range can contain setting-changing opcodes: on this protocol a write usually sits one number above its matching read. Sweep a narrow range you are willing to have side effects in, and keep the earbuds somewhere you can hear them.")
                    .padding(.top, 16)
            }
        }
        .alert("Send \(sweepCount) packets?", isPresented: $showsSweepWarning) {
            Button("Start sweep") {
                guard let address = link.address,
                      let start = UInt8(sweepStart, radix: 16),
                      let end = UInt8(sweepEnd, radix: 16),
                      start <= end else {
                    model.show("Sweep range must be two hex bytes, low first")
                    return
                }
                scanner.startOpcodeSweep(range: start...end, evenOnly: sweepReadsOnly, for: address)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(sweepReadsOnly
                 ? "Each even opcode in 03 \(sweepStart.uppercased())–\(sweepEnd.uppercased()) is sent once with an empty payload. Odd opcodes are skipped because they are usually the writes."
                 : "Each opcode in 03 \(sweepStart.uppercased())–\(sweepEnd.uppercased()) is sent once with an empty payload. Odd ones are usually writes and may change a setting rather than read one.")
        }
    }

    private var sweepCount: Int {
        guard let start = UInt8(sweepStart, radix: 16), let end = UInt8(sweepEnd, radix: 16), start <= end else { return 0 }
        return stride(from: Int(start), through: Int(end), by: 1)
            .filter { !sweepReadsOnly || $0 % 2 == 0 }
            .count
    }

    private func hexField(_ text: Binding<String>, width: CGFloat, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(PeatsFont.mono(12))
            .frame(width: width)
    }

    private func parseHex(_ input: String) -> [UInt8] {
        input
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { UInt8($0, radix: 16) }
    }

    // MARK: - Log

    private func logCard(_ link: DeviceLink) -> some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Protocol log") {
                    HStack(spacing: 12) {
                        MonoCaption("\(scanner.protocolLog.entries.count) frames")
                        SoftButton(title: scanner.protocolLog.isPaused ? "Resume" : "Pause") {
                            scanner.protocolLog.isPaused.toggle()
                        }
                        SoftButton(title: "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(scanner.protocolLog.exportText(), forType: .string)
                            model.show("Log copied to the clipboard")
                        }
                        SoftButton(title: "Clear") { scanner.protocolLog.clear() }
                    }
                }

                if scanner.protocolLog.entries.isEmpty {
                    Text("Nothing captured yet. Every frame this app sends or receives — from a status refresh, a setting write, or a discovery run — appears here as it happens.")
                        .font(PeatsFont.body(15))
                        .foregroundStyle(theme.cardFG2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(scanner.protocolLog.recent) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(entry.timestamp)
                                        .foregroundStyle(theme.cardFG2)
                                    Text(entry.direction.rawValue)
                                        .foregroundStyle(directionColor(entry.direction))
                                        .frame(width: 22, alignment: .leading)
                                    Text(entry.hex.isEmpty ? "—" : entry.hex)
                                        .foregroundStyle(theme.cardFG2)
                                        .frame(width: 190, alignment: .leading)
                                    Text(entry.message)
                                        .foregroundStyle(theme.cardFG)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .font(PeatsFont.mono(11, .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .frame(height: 260)
                    .background(theme.card2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private func directionColor(_ direction: ProtocolLogEntry.Direction) -> Color {
        switch direction {
        case .tx: theme.blue
        case .rx: theme.ok
        case .note: theme.cardFG2
        }
    }

    // MARK: - Discovered opcodes

    private func discoveredCard(_ link: DeviceLink) -> some View {
        let found = link.address.map { scanner.discoveredOpcodes[$0] ?? [] } ?? []
        return PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Answered opcodes") {
                    HStack(spacing: 12) {
                        MonoCaption("\(found.count) found")
                        if !found.isEmpty {
                            SoftButton(title: "Clear") {
                                guard let address = link.address else { return }
                                scanner.clearDiscoveredOpcodes(for: address)
                            }
                        }
                    }
                }

                if found.isEmpty {
                    Text("Opcodes this Q3 Pro actually replied to will collect here, with the payload it returned. That list — not a guess from another model — is what a new feature should be built on.")
                        .font(PeatsFont.body(15))
                        .foregroundStyle(theme.cardFG2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 8) {
                        ForEach(found) { entry in
                            InsetRow(
                                title: entry.hex,
                                subtitle: entry.describedAs
                            ) {
                                StatusBadge(text: "req \(entry.requestHex)", tint: theme.cardFG2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Support matrix

    private func supportCard(_ link: DeviceLink) -> some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Feature support on this firmware") {
                    MonoCaption(link.status?.firmware ?? "unknown fw")
                }
                VStack(spacing: 6) {
                    ForEach(BluetoothScanner.SupportKey.allCases, id: \.self) { key in
                        let level = link.address.map { scanner.supportLevel(key, for: $0) } ?? .unknown
                        HStack(spacing: 12) {
                            Text(key.title)
                                .font(PeatsFont.body(13, .semibold))
                            Spacer(minLength: 8)
                            StatusBadge(text: label(level), tint: tint(level), onCard2: true)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .top) {
                            if key != BluetoothScanner.SupportKey.allCases.first {
                                Rectangle().fill(theme.cardLine).frame(height: 1)
                            }
                        }
                    }
                }

                Text("Verified means the earbuds returned a value for it on this Mac. Nothing here is inferred from the model name.")
                    .font(PeatsFont.body(13))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
    }

    private func label(_ level: BluetoothScanner.SupportLevel) -> String {
        switch level {
        case .verified: "Verified"
        case .unsupported: "Unsupported"
        case .unknown: "Unproven"
        }
    }

    private func tint(_ level: BluetoothScanner.SupportLevel) -> Color {
        switch level {
        case .verified: theme.ok
        case .unsupported: theme.red
        case .unknown: theme.amber
        }
    }
}
