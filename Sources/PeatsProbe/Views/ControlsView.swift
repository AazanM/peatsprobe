import SwiftUI

struct ControlsView: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    @State private var promptVolume: Double = 0

    var body: some View {
        let link = scanner.link
        VStack(spacing: 16) {
            if !link.canControl { NeedsDeviceCard(link: link, scanner: scanner) }

            touchMappingCard(link)

            CardGrid(columns: 3, minWidth: 260) {
                gameModeCard(link)
                touchLockCard(link)
                promptCard(link)
            }

            LinkStatusStrip(scanner: scanner, link: link)
        }
        .onAppear {
            if let value = link.status?.promptVolume { promptVolume = Double(value) }
        }
        .onChange(of: link.status?.promptVolume) { _, newValue in
            if let newValue { promptVolume = Double(newValue) }
        }
    }

    private func isBusy(_ link: DeviceLink) -> Bool {
        guard let address = link.address else { return false }
        return scanner.isGameModeControlInProgress(at: address)
            || scanner.isTouchLockControlInProgress(at: address)
            || scanner.isPromptVolumeControlInProgress(at: address)
            || scanner.diagnosticsRunning
    }

    // MARK: - Touch mapping

    private func touchMappingCard(_ link: DeviceLink) -> some View {
        let support = link.address.map { scanner.supportLevel(.touchMapping, for: $0) } ?? .unknown
        return PeatsCard(padding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Touch mapping", systemImage: "hand.tap") {
                    StatusBadge(
                        text: support == .verified ? "Verified" : "Unproven",
                        tint: support == .verified ? theme.ok : theme.amber,
                        showsDot: true,
                        onCard2: true
                    )
                }

                Text("The Q3 Pro has not returned a touch-mapping table to this Mac yet, so PeatsProbe shows no editable gesture list. The reliable way to work the mapping out without the vendor's phone app is to open a passive listen session and press each stem gesture — the earbuds announce what they did, and those frames appear in the Developer log.")
                    .font(PeatsFont.body(15))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SoftButton(title: "Read mapping once") {
                        guard let address = link.address else { return }
                        scanner.readCommands([.touchMapping], for: address)
                        model.show("Requesting the touch-mapping table…")
                    }
                    .disabled(!link.canControl || isBusy(link))

                    SoftButton(title: "Open passive listen") { model.section = .developer }
                }
                .padding(.top, 20)
            }
        }
    }

    // MARK: - Game mode

    private func gameModeCard(_ link: DeviceLink) -> some View {
        let value = link.status?.gameMode
        let busy = link.address.map { scanner.isGameModeControlInProgress(at: $0) } ?? false
        return PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Game Mode") {
                    if value == nil {
                        StatusBadge(text: "Not read", tint: theme.cardFG2)
                    } else {
                        PeatsSwitch(isOn: value == .on, isBusy: busy) {
                            guard let address = link.address else { return }
                            scanner.setGameMode(value == .on ? .off : .on, for: address)
                            model.show("Sending one Game Mode change…")
                        }
                        .disabled(!link.canControl || isBusy(link))
                    }
                }

                Text(value.map { $0 == .on ? "On" : "Off" } ?? "—")
                    .font(PeatsFont.display(40, .heavy))
                    .tracking(-1.6)

                Text("Low-latency mode, verified by a live read-back after every write. Confirm the effect by comparing audio-to-video sync before and after.")
                    .font(PeatsFont.body(15))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                SoftButton(title: "Read Game Mode") {
                    guard let address = link.address else { return }
                    scanner.readCommands([.gameMode], for: address)
                }
                .disabled(!link.canControl || isBusy(link))
                .padding(.top, 16)
            }
        }
    }

    // MARK: - Touch lock

    private func touchLockCard(_ link: DeviceLink) -> some View {
        let value = link.status?.touchLock
        let busy = link.address.map { scanner.isTouchLockControlInProgress(at: $0) } ?? false
        return PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Touch lock") {
                    if value == nil {
                        StatusBadge(text: "Not read", tint: theme.cardFG2)
                    } else {
                        PeatsSwitch(isOn: value == .on, isBusy: busy) {
                            guard let address = link.address else { return }
                            scanner.setTouchLock(value == .on ? .off : .on, for: address)
                            model.show("Sending one Touch Lock change…")
                        }
                        .disabled(!link.canControl || isBusy(link))
                    }
                }

                Text("Ignore every stem gesture so a collar cannot skip a track. The menu-bar controls keep working.")
                    .font(PeatsFont.body(15))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    findRow("Find left", left: true, link: link)
                    findRow("Find right", left: false, link: link)
                }
                .padding(.top, 20)
            }
        }
    }

    private func findRow(_ title: String, left: Bool, link: DeviceLink) -> some View {
        Button {
            guard let address = link.address else { return }
            scanner.findEarbud(left: left, for: address)
            model.show("Sent one \(title.lowercased()) command — listen for a chime")
        } label: {
            InsetRow(title: title) {
                StatusBadge(text: "Unproven", tint: theme.amber)
            }
        }
        .buttonStyle(.plain)
        .disabled(!link.canControl || isBusy(link))
        .opacity(link.canControl ? 1 : 0.5)
    }

    // MARK: - Prompt volume

    private func promptCard(_ link: DeviceLink) -> some View {
        let deviceValue = link.status?.promptVolume
        let busy = link.address.map { scanner.isPromptVolumeControlInProgress(at: $0) } ?? false
        return PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Prompt volume") {
                    MonoCaption("0–255 raw")
                }

                BigNumber(text: deviceValue.map(String.init) ?? "—", size: 40)

                PeatsSlider(value: $promptVolume, range: 0...255)
                    .padding(.top, 16)
                    .disabled(deviceValue == nil)

                HStack(spacing: 8) {
                    Text("Target")
                        .font(PeatsFont.body(13))
                        .foregroundStyle(theme.cardFG2)
                    TextField("", value: $promptVolume, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                        .disabled(deviceValue == nil)
                    Spacer(minLength: 0)
                    SoftButton(title: "Apply") {
                        guard let address = link.address else { return }
                        let clamped = min(max(promptVolume.rounded(), 0), 255)
                        scanner.setPromptVolume(UInt8(clamped), for: address)
                        model.show("Sending one prompt-volume write…")
                    }
                    .disabled(!link.canControl || busy || deviceValue == nil)
                }
                .padding(.top, 12)

                SoftButton(title: "Read current value") {
                    guard let address = link.address else { return }
                    scanner.readPromptVolume(for: address)
                }
                .disabled(!link.canControl || isBusy(link))
                .padding(.top, 12)

                if deviceValue == nil {
                    UnverifiedNotice(text: "Read the live value first. The slider stays locked until the earbuds return a number, so the app never guesses the scale.")
                        .padding(.top, 16)
                }
            }
        }
    }
}
