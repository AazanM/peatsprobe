import SwiftUI

struct AudioEQView: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    @State private var presetName = ""
    @State private var showsNamePrompt = false

    var body: some View {
        let link = scanner.link
        VStack(spacing: 16) {
            eqCard(link)

            CardGrid(columns: 2) {
                codecCard(link)
                libraryCard()
            }

            LinkStatusStrip(scanner: scanner, link: link)
        }
    }

    // MARK: - Equaliser

    private func eqCard(_ link: DeviceLink) -> some View {
        let supported = link.address.map { scanner.supportLevel(.equaliser, for: $0) } ?? .unknown
        return PeatsCard(padding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Parametric EQ", systemImage: "slider.horizontal.3") {
                    MonoCaption("\(model.selectedPreset?.name ?? "Custom") · ±6 dB")
                }

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(AppModel.eqBands.enumerated()), id: \.offset) { index, label in
                        bandColumn(index: index, label: label)
                    }
                }
                .frame(height: 210)

                HStack(spacing: 8) {
                    ForEach(model.allPresets) { preset in
                        ChipButton(title: preset.name, isActive: model.selectedPresetID == preset.id) {
                            model.selectPreset(preset)
                        }
                        .contextMenu {
                            if !preset.isBuiltIn {
                                Button("Delete preset", role: .destructive) { model.deletePreset(preset) }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    SoftButton(title: "Save on this Mac") { showsNamePrompt = true }
                }
                .padding(.top, 24)

                UnverifiedNotice(text: eqNotice(supported))
                    .padding(.top, 16)
            }
        }
        .alert("Name this preset", isPresented: $showsNamePrompt) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                model.saveWorkingPreset(named: name)
                presetName = ""
            }
            Button("Cancel", role: .cancel) { presetName = "" }
        }
    }

    private func eqNotice(_ support: BluetoothScanner.SupportLevel) -> String {
        support == .verified
            ? "The equaliser opcode is verified on this firmware."
            : "Curves are stored on this Mac only. The Q3 Pro equaliser opcode has not been proven on this firmware, so PeatsProbe will not write a band that may be interpreted as something else. Confirm the opcode in Developer → opcode discovery first."
    }

    private func bandColumn(index: Int, label: String) -> some View {
        let gain = model.workingGains.indices.contains(index) ? model.workingGains[index] : 0
        let fraction = (gain + 6) / 12
        return VStack(spacing: 12) {
            GeometryReader { proxy in
                let height = proxy.size.height
                ZStack(alignment: .bottom) {
                    Capsule().fill(theme.card2)
                    Capsule()
                        .fill(theme.ok)
                        .frame(height: max(6, height * fraction))
                    Circle()
                        .fill(theme.cardSolid)
                        .frame(width: 13, height: 13)
                        .offset(y: -(height * fraction) + 6.5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let ratio = 1 - min(max(drag.location.y / height, 0), 1)
                            setGain(index, to: (ratio * 12 - 6).rounded())
                        }
                )
            }
            .frame(width: 11)

            Text(label)
                .font(PeatsFont.mono(10, .regular))
                .foregroundStyle(theme.cardFG2)
        }
        .frame(maxWidth: .infinity)
    }

    private func setGain(_ index: Int, to value: Double) {
        guard model.workingGains.indices.contains(index) else { return }
        guard model.workingGains[index] != value else { return }
        model.workingGains[index] = value
    }

    // MARK: - Codec

    private func codecCard(_ link: DeviceLink) -> some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Codec & transport") {
                    MonoCaption("as reported")
                }
                VStack(spacing: 8) {
                    ToggleSettingRow(
                        title: "LDAC",
                        subtitle: ldacSubtitle(link),
                        supportKey: .ldac,
                        isOn: link.status?.ldac == .on,
                        link: link,
                        model: model,
                        scanner: scanner,
                        isBusy: link.address.map { scanner.isLDACControlInProgress(at: $0) } ?? false,
                        read: { address in scanner.readCommands([.ldac], for: address) },
                        write: { address, value in scanner.setLDAC(value, for: address) }
                    )

                    ToggleSettingRow(
                        title: "LE Audio / LC3",
                        subtitle: leAudioSubtitle(link),
                        supportKey: .leAudio,
                        isOn: link.status?.leAudio == .on,
                        link: link,
                        model: model,
                        scanner: scanner,
                        isBusy: link.address.map { scanner.isLEAudioControlInProgress(at: $0) } ?? false,
                        read: { address in scanner.readCommands([.leAudio], for: address) },
                        write: { address, value in scanner.setLEAudio(value, for: address) }
                    )
                }

                Text("macOS negotiates the active codec itself; PeatsProbe cannot read which one is in use over RFCOMM. The rows above reflect only what the earbuds report about their own codec switches.")
                    .font(PeatsFont.body(13))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
    }

    private func ldacSubtitle(_ link: DeviceLink) -> String {
        link.status?.ldac.map { "Device reports \($0.displayValue)" } ?? "No value returned yet"
    }

    private func leAudioSubtitle(_ link: DeviceLink) -> String {
        link.status?.leAudio.map { "Device reports \($0.displayValue)" } ?? "No value returned yet"
    }

    // MARK: - Library

    private func libraryCard() -> some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Preset library") {
                    MonoCaption("\(model.allPresets.count) presets")
                }
                VStack(spacing: 8) {
                    ForEach(model.allPresets) { preset in
                        InsetRow(
                            title: preset.name,
                            subtitle: preset.gains.map { String(format: "%+.0f", $0) }.joined(separator: " ")
                        ) {
                            StatusBadge(
                                text: preset.isBuiltIn ? "Built in" : "Yours",
                                tint: preset.isBuiltIn ? theme.cardFG2 : theme.blue
                            )
                        }
                        .onTapGesture { model.selectPreset(preset) }
                    }
                }
            }
        }
    }
}

/// A boolean device setting rendered as the design's switch row, with an
/// explicit read control and a support badge.
struct ToggleSettingRow: View {
    @Environment(\.peats) private var theme
    let title: String
    let subtitle: String
    let supportKey: BluetoothScanner.SupportKey
    let isOn: Bool
    let link: DeviceLink
    @Bindable var model: AppModel
    let scanner: BluetoothScanner
    let isBusy: Bool
    let read: (String) -> Void
    let write: (String, PeatsToggle) -> Void

    private var support: BluetoothScanner.SupportLevel {
        link.address.map { scanner.supportLevel(supportKey, for: $0) } ?? .unknown
    }

    var body: some View {
        InsetRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                if support == .verified {
                    PeatsSwitch(isOn: isOn, isBusy: isBusy) {
                        guard let address = link.address else { return }
                        write(address, isOn ? .off : .on)
                        model.show("Sending one \(title) change…")
                    }
                    .disabled(!link.canControl || isBusy || scanner.diagnosticsRunning)
                } else {
                    SoftButton(title: "Read") {
                        guard let address = link.address else { return }
                        read(address)
                        model.show("Reading \(title.lowercased())…")
                    }
                    .disabled(!link.canControl || scanner.diagnosticsRunning)
                    StatusBadge(
                        text: support == .unsupported ? "Unsupported" : "Unproven",
                        tint: support == .unsupported ? theme.red : theme.amber
                    )
                }
            }
        }
    }
}
