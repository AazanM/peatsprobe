import Foundation
import SwiftUI

/// The one connected SOUNDPEATS device the shell is driving, resolved once per
/// render so no view has to repeat the paired-device lookup.
struct DeviceLink {
    let address: String?
    let name: String
    let isConnected: Bool
    let status: BluetoothScanner.CoreDeviceStatus?

    var hasDevice: Bool { address != nil }

    /// Every device write in this app is gated on this.
    var canControl: Bool { address != nil && isConnected }

    var connectionText: String {
        guard hasDevice else { return "No SOUNDPEATS device paired" }
        return isConnected ? "Connected" : "Disconnected — showing last verified state"
    }
}

extension BluetoothScanner {
    var link: DeviceLink {
        guard let device = preferredPairedDevice else {
            return DeviceLink(address: nil, name: "No device", isConnected: false, status: nil)
        }
        return DeviceLink(
            address: device.address,
            name: device.name,
            isConnected: device.isConnected,
            status: coreStatus(for: device.address)
        )
    }
}

/// Shown wherever a card needs a device but none is connected.
struct NeedsDeviceCard: View {
    @Environment(\.peats) private var theme
    let link: DeviceLink
    let scanner: BluetoothScanner

    var body: some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(link.hasDevice ? "\(link.name) is not connected" : "No SOUNDPEATS device is paired")
                    .font(PeatsFont.display(21, .bold))
                    .tracking(-0.5)
                Text(link.hasDevice
                     ? "Connect the earbuds from the macOS Bluetooth menu, then refresh. Everything below still shows the last state PeatsProbe verified."
                     : "Pair the earbuds in System Settings → Bluetooth first. PeatsProbe only talks to devices this Mac has already paired.")
                    .font(PeatsFont.body(15))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                SoftButton(title: "Refresh paired devices") { scanner.refreshPairedDevices() }
            }
        }
    }
}

/// A one-line live status strip: what the last read or write actually reported.
struct LinkStatusStrip: View {
    @Environment(\.peats) private var theme
    let scanner: BluetoothScanner
    let link: DeviceLink

    var body: some View {
        let control = link.address.flatMap { scanner.statusForControl(at: $0) }
        let read = link.address.flatMap { scanner.statusForReadProbe(at: $0) }
        let message = control ?? read ?? "No RFCOMM activity yet this session."
        return HStack(spacing: 14) {
            Circle()
                .fill(link.isConnected ? theme.ok : theme.cardFG2)
                .frame(width: 8, height: 8)
            Text(message)
                .font(PeatsFont.body(13))
                .foregroundStyle(theme.cardFG2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            StatusBadge(
                text: link.isConnected ? "Link up" : "Link down",
                tint: link.isConnected ? theme.ok : theme.cardFG2,
                showsDot: false,
                onCard2: true
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: Capsule())
        .foregroundStyle(theme.cardFG)
    }
}
