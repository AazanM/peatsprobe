import SwiftUI

struct ContentView: View {
    let scanner: BluetoothScanner

    private var soundPEATSDevices: [BluetoothScanner.Device] {
        scanner.devices.filter { $0.isSoundPEATS }
    }

    private var otherDevices: [BluetoothScanner.Device] {
        scanner.devices.filter { !$0.isSoundPEATS }
    }

    private var pairedSoundPEATSDevices: [BluetoothScanner.PairedDevice] {
        scanner.pairedDevices.filter { $0.isSoundPEATS }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("PeatsProbe")
                    .font(.title2.bold())
                Text("Safe Bluetooth Classic + BLE discovery for Q3 Pro")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                statusBadge
                Button(scanner.state == .scanning ? "Stop scan" : "Refresh & scan") {
                    scanner.state == .scanning ? scanner.stopScan() : scanner.scan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUnavailable)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var content: some View {
        if isUnavailable {
            ContentUnavailableView(
                "Bluetooth unavailable",
                systemImage: "bluetooth.slash",
                description: Text(scanner.state.label)
            )
        } else if scanner.devices.isEmpty && pairedSoundPEATSDevices.isEmpty {
            ContentUnavailableView(
                "No scan results yet",
                systemImage: "earbuds",
                description: Text("Put the Q3 Pro in its case-open state, keep it near this Mac, then scan. This build only discovers devices; it does not connect or send commands."))
        } else {
            List {
                if !pairedSoundPEATSDevices.isEmpty {
                    Section("Paired SOUNDPEATS devices (Bluetooth Classic)") {
                        ForEach(pairedSoundPEATSDevices) { device in
                            PairedDeviceRow(
                                device: device,
                                services: scanner.services(for: device.address),
                                discoveryStatus: scanner.statusForServiceDiscovery(at: device.address),
                                channelTestStatus: scanner.statusForChannelTest(at: device.address),
                                readProbeStatus: scanner.statusForReadProbe(at: device.address),
                                controlStatus: scanner.statusForControl(at: device.address),
                                coreStatus: scanner.coreStatus(for: device.address),
                                isChangingANC: scanner.isANCControlInProgress(at: device.address),
                                isChangingGameMode: scanner.isGameModeControlInProgress(at: device.address),
                                isChangingMultipoint: scanner.isMultipointControlInProgress(at: device.address),
                                isChangingTouchLock: scanner.isTouchLockControlInProgress(at: device.address),
                                isChangingPromptVolume: scanner.isPromptVolumeControlInProgress(at: device.address),
                                isChangingANCStrength: scanner.isByteControlInProgress(.noiseControlStrength, at: device.address),
                                isChangingTransparencyLevel: scanner.isByteControlInProgress(.transparencyLevel, at: device.address),
                                isChangingVoicePackage: scanner.isByteControlInProgress(.voicePackage, at: device.address),
                                isChangingLDAC: scanner.isLDACControlInProgress(at: device.address),
                                isChangingLEAudio: scanner.isLEAudioControlInProgress(at: device.address),
                                discover: { scanner.discoverServices(for: device.address) },
                                testSPP: { scanner.testRFCOMMOpenClose(for: device.address, channelID: 1) },
                                readLeftBattery: { scanner.readLeftBattery(for: device.address, channelID: 1) },
                                refreshCoreStatus: { scanner.refreshCoreDeviceStatus(for: device.address, channelID: 1) },
                                setNoiseControl: { scanner.setNoiseControl($0, for: device.address, channelID: 1) },
                                setGameMode: { scanner.setGameMode($0, for: device.address, channelID: 1) },
                                setMultipoint: { scanner.setMultipoint($0, for: device.address, channelID: 1) },
                                setTouchLock: { scanner.setTouchLock($0, for: device.address, channelID: 1) },
                                readPromptVolume: { scanner.readPromptVolume(for: device.address, channelID: 1) },
                                setPromptVolume: { scanner.setPromptVolume($0, for: device.address, channelID: 1) },
                                readByteSetting: { scanner.readByteControl($0, for: device.address, channelID: 1) },
                                setByteSetting: { scanner.setByteControl($0, to: $1, for: device.address, channelID: 1) },
                                setLDAC: { scanner.setLDAC($0, for: device.address, channelID: 1) },
                                setLEAudio: { scanner.setLEAudio($0, for: device.address, channelID: 1) }
                            )
                        }
                    }
                }

                if !soundPEATSDevices.isEmpty {
                    Section("SOUNDPEATS candidates") {
                        ForEach(soundPEATSDevices) { device in
                            DeviceRow(device: device, highlighted: true)
                        }
                    }
                }

                if !otherDevices.isEmpty {
                    Section("Other nearby BLE devices") {
                        ForEach(otherDevices) { device in
                            DeviceRow(device: device, highlighted: false)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var statusBadge: some View {
        Label(scanner.state.label, systemImage: scanner.state == .scanning ? "wave.3.right" : "circle.fill")
            .font(.caption)
            .foregroundStyle(scanner.state == .scanning ? .orange : .secondary)
            .symbolEffect(.variableColor.iterative, isActive: scanner.state == .scanning)
    }

    private var isUnavailable: Bool {
        if case .unavailable = scanner.state { return true }
        return false
    }
}

private struct PairedDeviceRow: View {
    let device: BluetoothScanner.PairedDevice
    let services: [BluetoothScanner.ClassicService]
    let discoveryStatus: String?
    let channelTestStatus: String?
    let readProbeStatus: String?
    let controlStatus: String?
    let coreStatus: BluetoothScanner.CoreDeviceStatus?
    let isChangingANC: Bool
    let isChangingGameMode: Bool
    let isChangingMultipoint: Bool
    let isChangingTouchLock: Bool
    let isChangingPromptVolume: Bool
    let isChangingANCStrength: Bool
    let isChangingTransparencyLevel: Bool
    let isChangingVoicePackage: Bool
    let isChangingLDAC: Bool
    let isChangingLEAudio: Bool
    let discover: () -> Void
    let testSPP: () -> Void
    let readLeftBattery: () -> Void
    let refreshCoreStatus: () -> Void
    let setNoiseControl: (PeatsNoiseControlMode) -> Void
    let setGameMode: (PeatsToggle) -> Void
    let setMultipoint: (PeatsToggle) -> Void
    let setTouchLock: (PeatsToggle) -> Void
    let readPromptVolume: () -> Void
    let setPromptVolume: (UInt8) -> Void
    let readByteSetting: (BluetoothScanner.ByteControlSetting) -> Void
    let setByteSetting: (BluetoothScanner.ByteControlSetting, UInt8) -> Void
    let setLDAC: (PeatsToggle) -> Void
    let setLEAudio: (PeatsToggle) -> Void

    private var sppChannel: UInt8? {
        services.first { $0.name.localizedCaseInsensitiveContains("spp") }?.rfcommChannel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "earbuds")
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).fontWeight(.semibold)
                    Text(device.address)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if device.isConnected {
                    Button("Discover services", action: discover)
                        .buttonStyle(.bordered)
                    if sppChannel != nil {
                        Button("Test SPP open/close", action: testSPP)
                            .buttonStyle(.bordered)
                        Button("Read left battery", action: readLeftBattery)
                            .buttonStyle(.bordered)
                        Button("Refresh core status", action: refreshCoreStatus)
                            .buttonStyle(.borderedProminent)
                    }
                }
                Label(device.isConnected ? "Connected" : "Not connected", systemImage: device.isConnected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(device.isConnected ? .green : .secondary)
            }

            if let discoveryStatus {
                Text(discoveryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34)
            }

            if let channelTestStatus {
                Text(channelTestStatus)
                    .font(.caption)
                    .foregroundStyle(channelTestStatus.contains("successfully") ? .green : .secondary)
                    .padding(.leading, 34)
            }

            if let readProbeStatus {
                Text(readProbeStatus)
                    .font(.caption)
                    .foregroundStyle(readProbeStatus.contains("battery") || readProbeStatus.contains("Firmware") ? .green : .secondary)
                    .padding(.leading, 34)
            }

            if device.isConnected && sppChannel != nil {
                CoreStatusView(status: coreStatus)
                    .padding(.leading, 34)

                LegacyNoiseControlView(
                    currentMode: coreStatus?.noiseControl,
                    isChanging: isChangingANC,
                    setMode: setNoiseControl
                )
                .padding(.leading, 34)

                ToggleSettingControlView(
                    title: "Game Mode",
                    currentValue: coreStatus?.gameMode,
                    isChanging: isChangingGameMode,
                    setValue: setGameMode
                )
                .padding(.leading, 34)

                ToggleSettingControlView(
                    title: "Multipoint",
                    currentValue: coreStatus?.multipoint,
                    isChanging: isChangingMultipoint,
                    setValue: setMultipoint
                )
                .padding(.leading, 34)

                ToggleSettingControlView(
                    title: "Touch Lock",
                    currentValue: coreStatus?.touchLock,
                    isChanging: isChangingTouchLock,
                    setValue: setTouchLock
                )
                .padding(.leading, 34)

                PromptVolumeControlView(
                    currentValue: coreStatus?.promptVolume,
                    isChanging: isChangingPromptVolume,
                    readValue: readPromptVolume,
                    setValue: setPromptVolume
                )
                .padding(.leading, 34)

            }

            if let controlStatus {
                Text(controlStatus)
                    .font(.caption)
                    .foregroundStyle(controlStatus.contains("confirmed") || controlStatus.contains("verified") ? .green : .secondary)
                    .padding(.leading, 34)
            }

            ForEach(services) { service in
                HStack {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.secondary)
                    Text(service.name)
                    Spacer()
                    if let channel = service.rfcommChannel {
                        Text("RFCOMM channel \(channel)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tint)
                    }
                }
                .font(.caption)
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ToggleSettingControlView: View {
    let title: String
    let currentValue: PeatsToggle?
    let isChanging: Bool
    let setValue: (PeatsToggle) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            toggleButton(.on, label: "Enable")
            toggleButton(.off, label: "Disable")

            if isChanging {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func toggleButton(_ value: PeatsToggle, label: String) -> some View {
        if currentValue == value {
            Button(label) {}
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(true)
        } else {
            Button(label) {
                setValue(value)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isChanging)
        }
    }
}

private struct PromptVolumeControlView: View {
    let currentValue: UInt8?
    let isChanging: Bool
    let readValue: () -> Void
    let setValue: (UInt8) -> Void

    @State private var stagedValue: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Text("Prompt Volume")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button("Read", action: readValue)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChanging)

            if let currentValue {
                Slider(value: $stagedValue, in: 0...255, step: 1)
                    .frame(width: 120)
                    .disabled(isChanging)

                TextField("Value", value: $stagedValue, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .disabled(isChanging)

                Button("Apply") {
                    setValue(UInt8(clamping: Int(stagedValue.rounded())))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChanging || UInt8(clamping: Int(stagedValue.rounded())) == currentValue)
            } else {
                Text("Read first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isChanging {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
        .onAppear { syncStagedValue() }
        .onChange(of: currentValue) { _, _ in syncStagedValue() }
        .onChange(of: stagedValue) { _, newValue in
            stagedValue = min(255, max(0, newValue.rounded()))
        }
    }

    private func syncStagedValue() {
        if let currentValue { stagedValue = Double(currentValue) }
    }
}

private struct ByteSettingControlView: View {
    let setting: BluetoothScanner.ByteControlSetting
    let currentValue: UInt8?
    let isChanging: Bool
    let readValue: (BluetoothScanner.ByteControlSetting) -> Void
    let setValue: (BluetoothScanner.ByteControlSetting, UInt8) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(setting.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button("Read") { readValue(setting) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChanging)

            if let currentValue {
                Button("−") {
                    if currentValue > 0 { setValue(setting, currentValue - 1) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChanging || currentValue == 0)

                Text("\(currentValue)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 22)

                Button("+") {
                    if currentValue < .max { setValue(setting, currentValue + 1) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChanging || currentValue == .max)
            } else {
                Text("Read first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isChanging {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }
}

private struct LegacyNoiseControlView: View {
    let currentMode: PeatsNoiseControlMode?
    let isChanging: Bool
    let setMode: (PeatsNoiseControlMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Noise control")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            modeButton(.normal)
            modeButton(.noiseCancelling)
            modeButton(.transparency)

            if isChanging {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func modeButton(_ mode: PeatsNoiseControlMode) -> some View {
        if currentMode == mode {
            Button(label(for: mode)) {}
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(true)
        } else {
            Button(label(for: mode)) {
                setMode(mode)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isChanging)
        }
    }

    private func label(for mode: PeatsNoiseControlMode) -> String {
        switch mode {
        case .normal: "Normal"
        case .noiseCancelling: "Noise Cancelling"
        case .transparency: "Transparency"
        case .adaptive, .weakNoiseReduction: "Unsupported"
        }
    }
}

private struct CoreStatusView: View {
    let status: BluetoothScanner.CoreDeviceStatus?

    private var ancValue: String {
        guard let mode = status?.noiseControl else { return "—" }
        return PeatsReadValue.noiseControl(mode).displayValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Core device status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                StatusValue(label: "Left", value: status?.leftBattery.map { "\($0)%" } ?? "—")
                StatusValue(label: "Right", value: status?.rightBattery.map { "\($0)%" } ?? "—")
                StatusValue(label: "Case", value: status?.caseBattery.map { "\($0)%" } ?? "—")
                StatusValue(label: "Firmware", value: status?.firmware ?? "—")
                StatusValue(label: "ANC", value: ancValue)
                StatusValue(label: "Game", value: status?.gameMode?.displayValue ?? "—")
                StatusValue(label: "Multi", value: status?.multipoint?.displayValue ?? "—")
                StatusValue(label: "Lock", value: status?.touchLock?.displayValue ?? "—")
                StatusValue(label: "Prompt", value: status?.promptVolume.map(String.init) ?? "—")
            }
        }
        .font(.caption)
        .padding(.top, 2)
    }
}

private struct StatusValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(value == "—" ? .secondary : .primary)
        }
    }
}

private struct DeviceRow: View {
    let device: BluetoothScanner.Device
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: highlighted ? "earbuds" : "dot.radiowaves.left.and.right")
                .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .fontWeight(highlighted ? .semibold : .regular)
                Text(device.id.uuidString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if !device.advertisedServices.isEmpty {
                    Text("Services: \(device.advertisedServices.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(device.rssi) dBm")
                    .monospacedDigit()
                Text(signalLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var signalLabel: String {
        if device.rssi >= -55 { return "Strong signal" }
        if device.rssi >= -75 { return "Nearby" }
        return "Weak signal"
    }
}

#Preview {
    ContentView(scanner: BluetoothScanner())
        .frame(width: 760, height: 550)
}
