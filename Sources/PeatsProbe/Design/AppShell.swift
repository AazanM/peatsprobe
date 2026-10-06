import SwiftUI

/// The rounded two-column window from the design: a device sidebar on the left
/// and a titled content column on the right.
struct AppShell: View {
    @Environment(\.colorScheme) private var systemScheme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    private var theme: PeatsTheme { model.theme(for: systemScheme) }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.board.ignoresSafeArea()

            HStack(spacing: 0) {
                Sidebar(model: model, scanner: scanner)
                    .frame(width: 248)

                Divider().overlay(theme.shellLine)

                VStack(spacing: 0) {
                    header
                    Divider().overlay(theme.shellLine)
                    content
                }
            }
            .background(theme.shell)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: theme.shadow, radius: 18, y: 14)
            .padding(16)

            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 40)
            }
        }
        .environment(\.peats, theme)
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .preferredColorScheme(model.resolvedColorScheme)
        .sheet(isPresented: $model.showsDeviceSheet) {
            DeviceSheet(model: model, scanner: scanner)
                .environment(\.peats, theme)
        }
        .sheet(isPresented: $model.showsRuleSheet) {
            NewRuleSheet(model: model)
                .environment(\.peats, theme)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(model.section.title)
                .font(PeatsFont.display(21, .bold))
                .tracking(-0.42)
                .foregroundStyle(theme.shellFG)

            Spacer(minLength: 8)

            circleButton(theme.isDark ? "moon.fill" : "sun.max") {
                model.toggleAppearance(currentlyDark: theme.isDark)
            }
            circleButton("magnifyingglass") { model.showsDeviceSheet = true }
            circleButton("ellipsis") {
                model.show("Menu bar: battery · ANC · Game Mode · refresh")
            }

            AccentButton(title: scanner.diagnosticsRunning ? "Busy…" : "Refresh") {
                guard let device = scanner.preferredPairedDevice else {
                    model.show("No paired SOUNDPEATS device found")
                    return
                }
                guard device.isConnected else {
                    model.show("\(device.name) is disconnected")
                    return
                }
                scanner.refreshCoreDeviceStatus(for: device.address)
                model.show("Reading live status from \(device.name)")
            }
            .disabled(scanner.diagnosticsRunning)
        }
        .padding(.leading, 32)
        .padding(.trailing, 24)
        .frame(height: 68)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(theme.shellFG2)
                .overlay(Circle().stroke(theme.shellLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                switch model.section {
                case .overview: OverviewView(model: model, scanner: scanner)
                case .noise: NoiseControlView(model: model, scanner: scanner)
                case .audio: AudioEQView(model: model, scanner: scanner)
                case .controls: ControlsView(model: model, scanner: scanner)
                case .connectivity: ConnectivityView(model: model, scanner: scanner)
                case .automations: AutomationsView(model: model, scanner: scanner)
                case .developer: DeveloperView(model: model, scanner: scanner)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.2), value: model.section)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 24))
                    .frame(width: 38, height: 38)
                    .background(theme.cardSolid, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(theme.cardSolidFG)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SOUNDPEATS")
                        .font(PeatsFont.display(15, .bold))
                        .tracking(-0.22)
                    Text(deviceModelName)
                        .font(PeatsFont.body(12))
                        .foregroundStyle(theme.shellFG2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 20)

            Text("DEVICE")
                .font(PeatsFont.mono(10, .semibold))
                .tracking(1.1)
                .foregroundStyle(theme.shellFG2)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            VStack(spacing: 2) {
                ForEach(AppModel.Section.allCases) { section in
                    navItem(section)
                }
            }

            Spacer(minLength: 16)

            deviceCard
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.shell)
    }

    private var deviceModelName: String {
        scanner.preferredPairedDevice?.name ?? "No device paired"
    }

    private func navItem(_ section: AppModel.Section) -> some View {
        let isActive = model.section == section
        return Button { model.section = section } label: {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 17)
                Text(section.title)
                    .font(PeatsFont.body(14, isActive ? .bold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                isActive ? theme.shellFG : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .foregroundStyle(isActive ? theme.shell : theme.shellFG2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var deviceCard: some View {
        let device = scanner.preferredPairedDevice
        let status = device.flatMap { scanner.coreStatus(for: $0.address) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(device?.isConnected == true ? theme.ok : theme.cardFG2)
                    .frame(width: 8, height: 8)
                Text(device?.name ?? "Not paired")
                    .font(PeatsFont.body(14, .bold))
                    .lineLimit(1)
            }
            Text(status?.firmware.map { "FW \($0)" } ?? "Firmware unknown")
                .font(PeatsFont.mono(11, .regular))
                .foregroundStyle(theme.cardFG2)
                .padding(.top, 3)
                .padding(.bottom, 12)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 5) {
                batteryPip("L", status?.leftBattery)
                batteryPip("R", status?.rightBattery)
                batteryPip("C", status?.caseBattery)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(theme.cardFG)
    }

    private func batteryPip(_ label: String, _ value: Int?) -> some View {
        Text("\(label) \(value.map(String.init) ?? "—")")
            .font(PeatsFont.mono(10, .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(theme.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Sheets

private struct DeviceSheet: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Paired devices")
                .font(PeatsFont.display(21, .bold))
                .tracking(-0.5)
            Text("macOS's own pairing list. PeatsProbe never pairs or unpairs anything; it only talks to a device this Mac is already paired with.")
                .font(PeatsFont.body(14))
                .foregroundStyle(theme.cardFG2)
                .fixedSize(horizontal: false, vertical: true)

            if scanner.pairedDevices.isEmpty {
                Text("No paired Bluetooth devices found.")
                    .font(PeatsFont.body(14))
                    .foregroundStyle(theme.cardFG2)
            } else {
                VStack(spacing: 8) {
                    ForEach(scanner.pairedDevices) { device in
                        InsetRow(
                            title: device.name,
                            subtitle: device.address
                        ) {
                            StatusBadge(
                                text: device.isConnected ? "Connected" : "Offline",
                                tint: device.isConnected ? theme.ok : theme.cardFG2
                            )
                        }
                    }
                }
            }

            HStack {
                SoftButton(title: "Refresh list") { scanner.refreshPairedDevices() }
                Spacer()
                SoftButton(title: "Done", prominent: true) { model.showsDeviceSheet = false }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.card)
        .foregroundStyle(theme.cardFG)
    }
}

private struct NewRuleSheet: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    @State private var bundleID = ""
    @State private var action: AppModel.AutomationRule.Action = .ancTransparency

    var body: some View {
        let apps = model.runningApplications()
        VStack(alignment: .leading, spacing: 20) {
            Text("New rule")
                .font(PeatsFont.display(21, .bold))
                .tracking(-0.5)
            Text("When the chosen app launches on this Mac, PeatsProbe sends one verified setting change to the earbuds. Rules only fire while PeatsProbe is running and the link is up.")
                .font(PeatsFont.body(14))
                .foregroundStyle(theme.cardFG2)
                .fixedSize(horizontal: false, vertical: true)

            InsetRow(title: "When this app launches") {
                Picker("", selection: $bundleID) {
                    Text("Choose…").tag("")
                    ForEach(apps, id: \.bundleID) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            InsetRow(title: "Apply") {
                Picker("", selection: $action) {
                    ForEach(AppModel.AutomationRule.Action.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            HStack {
                Spacer()
                SoftButton(title: "Cancel") { model.showsRuleSheet = false }
                SoftButton(title: "Create rule", prominent: true) {
                    guard let app = apps.first(where: { $0.bundleID == bundleID }) else { return }
                    model.addRule(.init(bundleIdentifier: app.bundleID, appName: app.name, action: action))
                    model.showsRuleSheet = false
                }
                .disabled(bundleID.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(theme.card)
        .foregroundStyle(theme.cardFG)
    }
}
