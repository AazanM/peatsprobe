import SwiftUI

struct ConnectivityView: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    var body: some View {
        let link = scanner.link
        VStack(spacing: 16) {
            if !link.canControl { NeedsDeviceCard(link: link, scanner: scanner) }

            multipointCard(link)

            CardGrid(columns: 2) {
                linkCard(link)
                macBehaviourCard()
            }

            LinkStatusStrip(scanner: scanner, link: link)
        }
    }

    // MARK: - Multipoint

    private func multipointCard(_ link: DeviceLink) -> some View {
        let value = link.status?.multipoint
        let busy = link.address.map { scanner.isMultipointControlInProgress(at: $0) } ?? false
        return PeatsCard(padding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Multipoint", systemImage: "point.3.connected.trianglepath.dotted") {
                    StatusBadge(
                        text: value.map { $0 == .on ? "On" : "Off" } ?? "Not read",
                        tint: value == .on ? theme.ok : theme.cardFG2,
                        showsDot: true,
                        onCard2: true
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(value.map { $0 == .on ? "Two hosts" : "One host" } ?? "—")
                            .font(PeatsFont.display(32, .heavy))
                            .tracking(-1.3)
                        Text("Toggling multipoint makes the Q3 Pro tear the link down and reconnect. PeatsProbe sends the write once, waits for the earbuds to come back, and then performs a single live read-back. If they do not return in time the session times out and releases cleanly instead of hanging.")
                            .font(PeatsFont.body(15))
                            .foregroundStyle(theme.cardFG2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if value == nil {
                        SoftButton(title: "Read multipoint") {
                            guard let address = link.address else { return }
                            scanner.readCommands([.multipoint], for: address)
                        }
                        .disabled(!link.canControl || busy)
                    } else {
                        PeatsSwitch(isOn: value == .on, isBusy: busy) {
                            guard let address = link.address else { return }
                            scanner.setMultipoint(value == .on ? .off : .on, for: address)
                            model.show("Sending one Multipoint change — expect a reconnect")
                        }
                        .disabled(!link.canControl || busy || scanner.diagnosticsRunning)
                    }
                }

                if busy {
                    UnverifiedNotice(text: "Multipoint write in flight. The earbuds usually drop and re-announce; leave them in range and do not send another command until this clears.")
                        .padding(.top, 20)
                }
            }
        }
    }

    // MARK: - Link facts

    private func linkCard(_ link: DeviceLink) -> some View {
        let services = link.address.map { scanner.services(for: $0) } ?? []
        return PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Control link") {
                    MonoCaption("RFCOMM")
                }
                VStack(spacing: 8) {
                    InsetRow(title: "Address", subtitle: link.address ?? "—") { EmptyView() }
                    InsetRow(title: "Firmware", subtitle: link.status?.firmware ?? "Not read yet") { EmptyView() }
                    InsetRow(
                        title: "SDP services",
                        subtitle: services.isEmpty
                            ? "Run a service discovery to list them"
                            : services.map { service in
                                service.rfcommChannel.map { "\(service.name) · ch \($0)" } ?? service.name
                            }.joined(separator: ", ")
                    ) { EmptyView() }
                }

                HStack(spacing: 8) {
                    SoftButton(title: "Discover services") {
                        guard let address = link.address else { return }
                        scanner.discoverServices(for: address)
                    }
                    .disabled(!link.hasDevice)

                    SoftButton(title: "Refresh status") {
                        guard let address = link.address else { return }
                        scanner.refreshCoreDeviceStatus(for: address)
                    }
                    .disabled(!link.canControl)
                }
                .padding(.top, 16)

                if let status = link.address.flatMap({ scanner.statusForServiceDiscovery(at: $0) }) {
                    Text(status)
                        .font(PeatsFont.body(13))
                        .foregroundStyle(theme.cardFG2)
                        .padding(.top, 12)
                }
            }
        }
    }

    // MARK: - Mac-side behaviour

    private func macBehaviourCard() -> some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "This Mac") {
                    MonoCaption("local")
                }
                VStack(spacing: 8) {
                    InsetRow(
                        title: "Low-battery notification",
                        subtitle: "Warn at 15% on either earbud"
                    ) {
                        PeatsSwitch(isOn: scanner.lowBatteryNotificationsEnabled) {
                            scanner.setLowBatteryNotificationsEnabled(!scanner.lowBatteryNotificationsEnabled)
                        }
                    }

                    InsetRow(
                        title: "Menu-bar controls",
                        subtitle: "Battery, ANC, Game Mode, and Touch Lock from the menu bar"
                    ) {
                        StatusBadge(text: "Always on", tint: theme.ok)
                    }
                }

                Text("Auto-reconnect and audio stealing are handled by macOS Bluetooth itself, not by the earbud protocol, so PeatsProbe does not present switches it cannot honour.")
                    .font(PeatsFont.body(13))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
    }
}
