import SwiftUI

struct NoiseControlView: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    @State private var strength: Double = 50
    @State private var transparency: Double = 50

    var body: some View {
        let link = scanner.link
        VStack(spacing: 16) {
            if !link.canControl { NeedsDeviceCard(link: link, scanner: scanner) }

            modeCard(link)

            CardGrid(columns: 2) {
                strengthCard(link)
                transparencyCard(link)
            }

            LinkStatusStrip(scanner: scanner, link: link)
        }
        .onAppear { syncFromDevice(link) }
        .onChange(of: link.status?.noiseControlStrength) { _, _ in syncFromDevice(scanner.link) }
        .onChange(of: link.status?.transparencyLevel) { _, _ in syncFromDevice(scanner.link) }
    }

    private func syncFromDevice(_ link: DeviceLink) {
        if let value = link.status?.noiseControlStrength { strength = Double(value) }
        if let value = link.status?.transparencyLevel { transparency = Double(value) }
    }

    private func isBusy(_ link: DeviceLink) -> Bool {
        guard let address = link.address else { return false }
        return scanner.isANCControlInProgress(at: address)
            || scanner.isByteControlInProgress(.noiseControlStrength, at: address)
            || scanner.isByteControlInProgress(.transparencyLevel, at: address)
            || scanner.diagnosticsRunning
    }

    // MARK: - Mode

    private func modeCard(_ link: DeviceLink) -> some View {
        let mode = link.status?.noiseControl
        return PeatsCard(padding: 28) {
            VStack(spacing: 0) {
                CardHeader(title: "Noise control", systemImage: "waveform") {
                    StatusBadge(
                        text: mode == nil ? "Not read" : "Verified",
                        tint: mode == nil ? theme.cardFG2 : theme.ok,
                        showsDot: true,
                        onCard2: true
                    )
                }

                VStack(spacing: 2) {
                    Text(mode.map { PeatsReadValue.noiseControl($0).displayValue } ?? "—")
                        .font(PeatsFont.display(40, .heavy))
                        .tracking(-1.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Live mode on the earbuds")
                        .font(PeatsFont.body(15))
                        .foregroundStyle(theme.cardFG2)
                }

                OrbRow(
                    value: mode == .transparency ? 70 : (mode == .normal ? 0 : 100),
                    tint: mode == .transparency ? theme.blue : theme.ok,
                    isLive: mode != nil && mode != .normal
                )
                .padding(.vertical, 12)

                PillPicker(
                    options: [
                        (PeatsNoiseControlMode.normal, "Normal"),
                        (.noiseCancelling, "Noise Cancelling"),
                        (.transparency, "Transparency")
                    ],
                    selection: mode,
                    isEnabled: link.canControl && !isBusy(link)
                ) { value in
                    guard let address = link.address else { return }
                    scanner.setNoiseControl(value, for: address)
                    model.show("Sending one \(PeatsReadValue.noiseControl(value).displayValue) change…")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Strength

    private func strengthCard(_ link: DeviceLink) -> some View {
        ByteSettingCard(
            title: "ANC strength",
            caption: "0–255 raw",
            explanation: "The raw cancellation level the firmware reports. PeatsProbe reads the live value first and only writes what you apply.",
            setting: .noiseControlStrength,
            supportKey: .noiseControlStrength,
            value: $strength,
            deviceValue: link.status?.noiseControlStrength,
            link: link,
            model: model,
            scanner: scanner
        )
    }

    private func transparencyCard(_ link: DeviceLink) -> some View {
        ByteSettingCard(
            title: "Transparency level",
            caption: "0–255 raw",
            explanation: "How much of the outside world passes through while Transparency is on.",
            setting: .transparencyLevel,
            supportKey: .transparencyLevel,
            value: $transparency,
            deviceValue: link.status?.transparencyLevel,
            link: link,
            model: model,
            scanner: scanner
        )
    }
}

/// A byte-valued device setting: read the live value, then apply exactly one
/// explicit write. Until the earbuds have actually answered the read, the
/// slider stays locked so the app cannot imply a control that does nothing.
struct ByteSettingCard: View {
    @Environment(\.peats) private var theme
    let title: String
    let caption: String
    let explanation: String
    let setting: BluetoothScanner.ByteControlSetting
    let supportKey: BluetoothScanner.SupportKey
    @Binding var value: Double
    let deviceValue: UInt8?
    let link: DeviceLink
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    private var support: BluetoothScanner.SupportLevel {
        link.address.map { scanner.supportLevel(supportKey, for: $0) } ?? .unknown
    }

    private var isBusy: Bool {
        guard let address = link.address else { return false }
        return scanner.isByteControlInProgress(setting, at: address) || scanner.diagnosticsRunning
    }

    var body: some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: title) {
                    StatusBadge(text: supportText, tint: supportTint, showsDot: true, onCard2: true)
                }

                BigNumber(text: deviceValue.map(String.init) ?? "—", size: 40)

                Text(explanation)
                    .font(PeatsFont.body(15))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                if support == .verified {
                    PeatsSlider(value: $value, range: 0...255)
                        .padding(.top, 16)
                    HStack {
                        MonoCaption("target \(Int(value))")
                        Spacer()
                        SoftButton(title: "Apply once") {
                            guard let address = link.address else { return }
                            scanner.setByteControl(setting, to: UInt8(value.rounded()), for: address)
                            model.show("Sending one \(title) write…")
                        }
                        .disabled(!link.canControl || isBusy)
                    }
                    .padding(.top, 12)
                } else {
                    UnverifiedNotice(text: unverifiedText)
                        .padding(.top, 16)
                }

                HStack(spacing: 8) {
                    SoftButton(title: "Read from device") {
                        guard let address = link.address else { return }
                        scanner.readByteControl(setting, for: address)
                        model.show("Reading \(title.lowercased())…")
                    }
                    .disabled(!link.canControl || isBusy)

                    if support != .unknown {
                        SoftButton(title: "Reset support") {
                            guard let address = link.address else { return }
                            scanner.resetSupport(supportKey, for: address)
                        }
                    } else {
                        SoftButton(title: "Mark unsupported") {
                            guard let address = link.address else { return }
                            scanner.markUnsupported(supportKey, for: address)
                            model.show("\(title) marked unsupported on this firmware")
                        }
                        .disabled(!link.hasDevice)
                    }
                    Spacer()
                    MonoCaption(caption)
                }
                .padding(.top, 16)
            }
        }
    }

    private var supportText: String {
        switch support {
        case .verified: "Verified"
        case .unsupported: "Unsupported"
        case .unknown: "Unproven"
        }
    }

    private var supportTint: Color {
        switch support {
        case .verified: theme.ok
        case .unsupported: theme.red
        case .unknown: theme.amber
        }
    }

    private var unverifiedText: String {
        support == .unsupported
            ? "This firmware never returned a value for \(title.lowercased()). The write is disabled so the app does not send a command that does nothing. Use Developer → opcode discovery to find the real opcode."
            : "The earbuds have not returned a value for \(title.lowercased()) yet. Read it first — the slider unlocks only once a real value comes back, so no unproven write is ever sent."
    }
}
