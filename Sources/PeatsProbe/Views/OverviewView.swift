import SwiftUI

struct OverviewView: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    var body: some View {
        let link = scanner.link
        VStack(spacing: 16) {
            heroCard(link)

            CardGrid(columns: 2) {
                listeningModeCard(link)
                quickActionsCard(link)
            }

            LinkStatusStrip(scanner: scanner, link: link)
        }
        .onChange(of: link.status?.noiseControl) { _, newValue in
            if let newValue { model.noteObservedMode(newValue) }
        }
    }

    // MARK: - Hero

    private func heroCard(_ link: DeviceLink) -> some View {
        let status = link.status
        let average: Int? = {
            let values = [status?.leftBattery, status?.rightBattery].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / values.count
        }()

        return PeatsCard(padding: 32) {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(link.name)
                        .font(PeatsFont.display(32, .bold))
                        .tracking(-0.96)
                        .multilineTextAlignment(.center)
                    Text(link.connectionText)
                        .font(PeatsFont.body(15, .bold))
                        .foregroundStyle(link.isConnected ? theme.ok : theme.cardFG2)
                    Text(heroMeta(link))
                        .font(PeatsFont.mono(11, .regular))
                        .tracking(0.44)
                        .foregroundStyle(theme.cardFG2)
                }

                HStack(alignment: .center, spacing: 24) {
                    BatteryRing(percentage: status?.leftBattery, caption: "LEFT")
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        BigNumber(text: average.map { "\($0)%" } ?? "—", size: 56)
                        Label("battery", systemImage: "battery.100")
                            .font(PeatsFont.body(14, .semibold))
                            .foregroundStyle(theme.cardFG2)
                        Text("CASE \(status?.caseBattery.map { "\($0)%" } ?? "—")")
                            .font(PeatsFont.mono(11, .regular))
                            .tracking(0.55)
                            .foregroundStyle(theme.cardFG2)
                            .padding(.top, 8)
                    }
                    .fixedSize()

                    BatteryRing(percentage: status?.rightBattery, caption: "RIGHT")
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 840)

                HStack(spacing: 8) {
                    SoftButton(title: "Switch to Transparency") {
                        guard let address = link.address else { return }
                        scanner.setNoiseControl(.transparency, for: address)
                        model.show("Sending one Transparency change…")
                    }
                    .disabled(!link.canControl || isBusy(link))

                    SoftButton(title: gameButtonTitle(status)) {
                        guard let address = link.address else { return }
                        let next: PeatsToggle = status?.gameMode == .on ? .off : .on
                        scanner.setGameMode(next, for: address)
                        model.show("Sending one Game Mode change…")
                    }
                    .disabled(!link.canControl || isBusy(link))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func heroMeta(_ link: DeviceLink) -> String {
        guard let firmware = link.status?.firmware else { return "FIRMWARE NOT READ YET" }
        return "FIRMWARE \(firmware)"
    }

    private func gameButtonTitle(_ status: BluetoothScanner.CoreDeviceStatus?) -> String {
        switch status?.gameMode {
        case .on: "Disable Game Mode"
        case .off: "Enable Game Mode"
        case nil: "Read Game Mode"
        }
    }

    private func isBusy(_ link: DeviceLink) -> Bool {
        guard let address = link.address else { return false }
        return scanner.isANCControlInProgress(at: address)
            || scanner.isGameModeControlInProgress(at: address)
            || scanner.diagnosticsRunning
    }

    // MARK: - Listening mode

    private func listeningModeCard(_ link: DeviceLink) -> some View {
        let mode = link.status?.noiseControl
        return PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Listening mode", systemImage: "waveform") {
                    MonoCaption(mode.map { PeatsReadValue.noiseControl($0).displayValue } ?? "not read")
                }

                VStack(spacing: 2) {
                    Text(mode.map { PeatsReadValue.noiseControl($0).displayValue } ?? "—")
                        .font(PeatsFont.display(30, .heavy))
                        .tracking(-0.9)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("Verified on the earbuds")
                        .font(PeatsFont.body(15))
                        .foregroundStyle(theme.cardFG2)
                }
                .frame(maxWidth: .infinity)

                OrbRow(
                    value: orbValue(for: mode),
                    tint: mode == .transparency ? theme.blue : theme.ok,
                    isLive: mode != nil && mode != .normal
                )
                .frame(maxWidth: .infinity)

                PillPicker(
                    options: [
                        (PeatsNoiseControlMode.normal, "Normal"),
                        (.noiseCancelling, "ANC"),
                        (.transparency, "Transparency")
                    ],
                    selection: mode,
                    isEnabled: link.canControl && !isBusy(link)
                ) { value in
                    guard let address = link.address else { return }
                    scanner.setNoiseControl(value, for: address)
                    model.show("Sending one \(PeatsReadValue.noiseControl(value).displayValue) change…")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func orbValue(for mode: PeatsNoiseControlMode?) -> Int {
        switch mode {
        case .noiseCancelling, .adaptive: 100
        case .weakNoiseReduction: 55
        case .transparency: 70
        case .normal: 0
        case nil: 0
        }
    }

    // MARK: - Quick actions

    private func quickActionsCard(_ link: DeviceLink) -> some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Quick actions", systemImage: "bolt.fill") {
                    MonoCaption("verified only")
                }
                VStack(spacing: 8) {
                    actionRow(
                        "Noise Cancelling",
                        "One explicit mode write, then a live read-back",
                        "waveform",
                        "⇧⌘2",
                        enabled: link.canControl && !isBusy(link)
                    ) {
                        guard let address = link.address else { return }
                        scanner.setNoiseControl(.noiseCancelling, for: address)
                    }

                    actionRow(
                        "Toggle Touch Lock",
                        touchLockSubtitle(link),
                        "hand.raised",
                        "⇧⌘T",
                        enabled: link.canControl && !isBusy(link)
                    ) {
                        guard let address = link.address else { return }
                        let next: PeatsToggle = link.status?.touchLock == .on ? .off : .on
                        scanner.setTouchLock(next, for: address)
                    }

                    actionRow(
                        "Refresh live status",
                        "Battery, firmware, and current mode in one session",
                        "arrow.clockwise",
                        "⇧⌘R",
                        enabled: link.canControl && !isBusy(link)
                    ) {
                        guard let address = link.address else { return }
                        scanner.refreshCoreDeviceStatus(for: address)
                    }

                    actionRow(
                        "Protocol diagnostics",
                        "Frame log, passive listen, and opcode discovery",
                        "chevron.left.forwardslash.chevron.right",
                        "Dev",
                        enabled: true
                    ) {
                        model.section = .developer
                    }
                }
            }
        }
    }

    private func touchLockSubtitle(_ link: DeviceLink) -> String {
        switch link.status?.touchLock {
        case .on: "Currently on"
        case .off: "Currently off"
        case nil: "Not read yet"
        }
    }

    private func actionRow(
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ key: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            InsetRow(title: title, subtitle: subtitle, systemImage: symbol) {
                KeyCap(text: key)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}
