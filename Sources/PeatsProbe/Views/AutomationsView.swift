import SwiftUI

struct AutomationsView: View {
    @Environment(\.peats) private var theme
    @Bindable var model: AppModel
    let scanner: BluetoothScanner

    var body: some View {
        let link = scanner.link
        VStack(spacing: 16) {
            usageCard()
            rulesCard(link)
            historyCard(link)
        }
    }

    // MARK: - Usage

    private func usageCard() -> some View {
        let week = model.usageWeek
        let peak = max(week.map { $0.day.normal + $0.day.anc + $0.day.transparency }.max() ?? 0, 0.001)
        let total = week.reduce(0.0) { $0 + $1.day.normal + $1.day.anc + $1.day.transparency }

        return PeatsCard(padding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Listening this week", systemImage: "chart.line.uptrend.xyaxis") {
                    MonoCaption(total > 0 ? String(format: "%.1f h measured", total) : "nothing measured yet")
                }

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, entry in
                        VStack(spacing: 12) {
                            VStack(spacing: 3) {
                                bar(entry.day.transparency, peak: peak, color: theme.blue)
                                bar(entry.day.anc, peak: peak, color: theme.ok)
                                bar(entry.day.normal, peak: peak, color: theme.amber)
                            }
                            .frame(maxWidth: 34, maxHeight: .infinity, alignment: .bottom)

                            Text(entry.label)
                                .font(PeatsFont.mono(11, .regular))
                                .foregroundStyle(theme.cardFG2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 200)

                HStack(spacing: 20) {
                    legend("Noise cancelling", theme.ok)
                    legend("Transparency", theme.blue)
                    legend("Normal", theme.amber)
                    Spacer(minLength: 8)
                    SoftButton(title: "Clear") { model.clearUsage() }
                }
                .padding(.top, 20)

                Text("Measured on this Mac only, from the modes PeatsProbe actually verified while it was running and connected. It is not a device-side statistic and the earbuds are never asked for one.")
                    .font(PeatsFont.body(13))
                    .foregroundStyle(theme.cardFG2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
    }

    private func bar(_ hours: Double, peak: Double, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color)
            .frame(height: hours <= 0 ? 0 : max(4, 150 * hours / peak))
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            Text(title)
                .font(PeatsFont.body(12))
                .foregroundStyle(theme.cardFG2)
        }
    }

    // MARK: - Rules

    private func rulesCard(_ link: DeviceLink) -> some View {
        PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Rules") {
                    SoftButton(title: "New rule") { model.showsRuleSheet = true }
                }

                if model.rules.isEmpty {
                    Text("No rules yet. A rule watches for an app launching on this Mac and then sends one already-verified setting change to the earbuds — nothing runs unless PeatsProbe is open and the link is up.")
                        .font(PeatsFont.body(15))
                        .foregroundStyle(theme.cardFG2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.rules) { rule in
                            InsetRow(
                                title: "\(rule.appName) launches → \(rule.action.title)",
                                subtitle: rule.bundleIdentifier,
                                systemImage: "bolt"
                            ) {
                                HStack(spacing: 10) {
                                    PeatsSwitch(isOn: rule.isEnabled) { model.toggleRule(rule) }
                                    Button {
                                        model.deleteRule(rule)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundStyle(theme.cardFG2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if !link.canControl && !model.rules.isEmpty {
                    UnverifiedNotice(text: "Rules are idle while the earbuds are disconnected.")
                        .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - History

    private func historyCard(_ link: DeviceLink) -> some View {
        let history = link.address.map { scanner.recentHistory(for: $0, limit: 8) } ?? []
        return PeatsCard {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: "Verified changes") {
                    MonoCaption("\(history.count) recent")
                }
                if history.isEmpty {
                    Text("Every setting change the earbuds confirmed by a read-back is listed here.")
                        .font(PeatsFont.body(15))
                        .foregroundStyle(theme.cardFG2)
                } else {
                    VStack(spacing: 8) {
                        ForEach(history) { entry in
                            InsetRow(
                                title: "\(entry.setting): \(entry.value)",
                                subtitle: entry.date.formatted(date: .abbreviated, time: .shortened)
                            ) {
                                StatusBadge(text: "Verified", tint: theme.ok)
                            }
                        }
                    }
                }
            }
        }
    }
}
