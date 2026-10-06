import SwiftUI

@main
struct PeatsProbeApp: App {
    @State private var bluetooth = BluetoothScanner()
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("SOUNDPEATS Control") {
            AppShell(model: model, scanner: bluetooth)
                .frame(minWidth: 1040, minHeight: 720)
                .task { model.startAutomation(with: bluetooth) }
        }
        .windowResizability(.contentMinSize)

        // The original diagnostic surface, kept reachable for raw testing.
        Window("Legacy Diagnostics", id: "legacy-diagnostics") {
            ContentView(scanner: bluetooth)
                .frame(minWidth: 760, minHeight: 550)
        }

        MenuBarExtra {
            Text(bluetooth.menuBarStatusDetail)
                .foregroundStyle(.secondary)

            if let device = bluetooth.preferredPairedDevice,
               let status = bluetooth.coreStatus(for: device.address) {
                Divider()
                LabeledContent("Left", value: status.leftBattery.map { "\($0)%" } ?? "—")
                LabeledContent("Right", value: status.rightBattery.map { "\($0)%" } ?? "—")
                LabeledContent("Case", value: status.caseBattery.map { "\($0)%" } ?? "—")
                LabeledContent("Firmware", value: status.firmware ?? "—")
                LabeledContent("ANC", value: status.noiseControl.map { PeatsReadValue.noiseControl($0).displayValue } ?? "—")
                LabeledContent("Game Mode", value: status.gameMode?.displayValue ?? "—")
                LabeledContent("Multipoint", value: status.multipoint?.displayValue ?? "—")
            }

            Divider()
            Button("Refresh live status") {
                bluetooth.refreshPreferredDeviceStatus()
            }
            .disabled(bluetooth.preferredPairedDevice?.isConnected != true)

            Toggle(
                "Low-battery notifications",
                isOn: Binding(
                    get: { bluetooth.lowBatteryNotificationsEnabled },
                    set: { bluetooth.setLowBatteryNotificationsEnabled($0) }
                )
            )

            if let device = bluetooth.preferredPairedDevice {
                Button("Save current verified snapshot") {
                    bluetooth.saveCurrentProfile(for: device.address)
                }
                .disabled(bluetooth.coreStatus(for: device.address) == nil)

                let profiles = bluetooth.profiles(for: device.address)
                if !profiles.isEmpty {
                    Divider()
                    Text("Saved snapshots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(profiles.prefix(3)) { profile in
                        Text(profile.name)
                    }
                }

                let history = bluetooth.recentHistory(for: device.address, limit: 4)
                if !history.isEmpty {
                    Divider()
                    Text("Recent verified changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(history) { entry in
                        Text("\(entry.setting): \(entry.value)")
                    }
                }
            }
        } label: {
            Label(bluetooth.menuBarStatusLabel, systemImage: "earbuds")
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandMenu("PeatsProbe") {
                Button("Refresh Q3 Pro Status") {
                    bluetooth.refreshPreferredDeviceStatus()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Set ANC: Normal") {
                    bluetooth.setPreferredNoiseControl(.normal)
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])

                Button("Set ANC: Noise Cancelling") {
                    bluetooth.setPreferredNoiseControl(.noiseCancelling)
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Button("Set ANC: Transparency") {
                    bluetooth.setPreferredNoiseControl(.transparency)
                }
                .keyboardShortcut("3", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Game Mode") {
                    bluetooth.togglePreferredGameMode()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Toggle Touch Lock") {
                    bluetooth.togglePreferredTouchLock()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }
}
