import SwiftUI

// MARK: - Card

/// The rounded card that every panel in the design sits on.
struct PeatsCard<Content: View>: View {
    @Environment(\.peats) private var theme
    var padding: CGFloat = 24
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .foregroundStyle(theme.cardFG)
    }
}

/// Card title row: a label on the left, a mono caption or control on the right.
struct CardHeader<Trailing: View>: View {
    @Environment(\.peats) private var theme
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(PeatsFont.body(13, .bold))
            }
            .foregroundStyle(theme.cardFG2)

            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 20)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title: title, systemImage: systemImage, trailing: { EmptyView() })
    }
}

/// The uppercase mono caption used on the right of most card headers.
struct MonoCaption: View {
    @Environment(\.peats) private var theme
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(PeatsFont.mono(11, .regular))
            .tracking(0.45)
            .foregroundStyle(theme.cardFG2)
            .lineLimit(1)
    }
}

// MARK: - Badges

struct StatusBadge: View {
    @Environment(\.peats) private var theme
    let text: String
    var tint: Color?
    var showsDot = false
    var onCard2 = false

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle()
                    .fill(tint ?? theme.cardFG2)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .font(PeatsFont.mono(11, .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(onCard2 ? theme.card2 : theme.card3, in: Capsule())
        .foregroundStyle(tint ?? theme.cardFG2)
        .fixedSize()
    }
}

// MARK: - Buttons

struct SoftButton: View {
    @Environment(\.peats) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PeatsFont.body(14, .bold))
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(prominent ? theme.cardSolid : theme.card2, in: Capsule())
                .foregroundStyle(prominent ? theme.cardSolidFG : theme.cardFG)
                .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(.plain)
    }
}

struct AccentButton: View {
    @Environment(\.peats) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PeatsFont.body(14, .bold))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(theme.blue, in: Capsule())
                .foregroundStyle(.white)
                .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(.plain)
    }
}

/// The segmented pill group used for listening modes.
struct PillPicker<Value: Hashable>: View {
    @Environment(\.peats) private var theme
    let options: [(value: Value, label: String)]
    let selection: Value?
    var isEnabled = true
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                Button { onSelect(option.value) } label: {
                    Text(option.label)
                        .font(PeatsFont.body(14, .bold))
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(
                            selection == option.value ? theme.cardSolid : Color.clear,
                            in: Capsule()
                        )
                        .foregroundStyle(selection == option.value ? theme.cardSolidFG : theme.cardFG2)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(3)
        .background(theme.card2, in: Capsule())
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.18), value: selection)
    }
}

struct ChipButton: View {
    @Environment(\.peats) private var theme
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PeatsFont.body(13, .bold))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(isActive ? theme.cardSolid : theme.card2, in: Capsule())
                .foregroundStyle(isActive ? theme.cardSolidFG : theme.cardFG2)
        }
        .buttonStyle(.plain)
    }
}

/// The pill switch from the design, driven by an explicit action rather than a
/// binding so a device write is never triggered by a state restore.
struct PeatsSwitch: View {
    @Environment(\.peats) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let isOn: Bool
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? theme.ok : theme.card3)
                    .frame(width: 46, height: 28)
                Group {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 22, height: 22)
                    } else {
                        Circle()
                            .fill(isOn ? Color.white : theme.cardFG)
                            .frame(width: 22, height: 22)
                    }
                }
                .padding(.horizontal, 3)
            }
            .frame(width: 46, height: 28)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isOn)
    }
}

// MARK: - Rows

/// The `card-2` inset row that carries a title, subtitle, and a trailing control.
struct InsetRow<Trailing: View>: View {
    @Environment(\.peats) private var theme
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(theme.card3, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PeatsFont.body(14, .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(PeatsFont.body(12))
                        .foregroundStyle(theme.cardFG2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .foregroundStyle(theme.cardFG)
    }
}

struct KeyCap: View {
    @Environment(\.peats) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(PeatsFont.mono(11, .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.card3, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(theme.cardFG2)
    }
}

// MARK: - Numbers and meters

/// The oversized tabular figure used for the hero readouts.
struct BigNumber: View {
    let text: String
    var size: CGFloat = 52
    var suffix: String?
    @Environment(\.peats) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(text)
                .font(PeatsFont.display(size, .heavy))
                .tracking(size * -0.04)
                .monospacedDigit()
            if let suffix {
                Text(suffix)
                    .font(PeatsFont.display(size * 0.46, .heavy))
                    .foregroundStyle(theme.cardFG2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// The 284°-sweep battery ring, matching the arc geometry in the design file.
struct BatteryRing: View {
    @Environment(\.peats) private var theme
    let percentage: Int?
    let caption: String

    private var fraction: Double { Double(percentage ?? 0) / 100 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 284.0 / 360.0)
                    .stroke(theme.card2, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(128))
                Circle()
                    .trim(from: 0, to: (284.0 / 360.0) * fraction)
                    .stroke(percentage == nil ? theme.card2 : theme.ok, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(128))
                    .animation(.easeOut(duration: 0.3), value: fraction)

                Circle()
                    .fill(theme.card2)
                    .overlay {
                        Image(systemName: "airpods.gen3")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(theme.cardFG2)
                    }
                    .padding(24)
            }
            .frame(width: 152, height: 152)

            Text("\(caption) \(percentage.map { "\($0)%" } ?? "—")")
                .font(PeatsFont.mono(11, .semibold))
                .foregroundStyle(theme.cardFG2)
        }
    }
}

/// The gaussian orb row that visualises cancellation strength.
struct OrbRow: View {
    @Environment(\.peats) private var theme
    let value: Int
    var count = 9
    var tint: Color?
    var isLive = true

    var body: some View {
        let active = Int((Double(value) / 100 * Double(count - 1)).rounded())
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                let distance = Double(index - active)
                let size = 16 + 44 * exp(-(distance * distance) / 3.4)
                Circle()
                    .fill(index <= active && isLive ? (tint ?? theme.ok) : theme.card2)
                    .frame(width: size, height: size)
                    .overlay {
                        if index == active && isLive {
                            Circle()
                                .stroke((tint ?? theme.ok).opacity(0.16), lineWidth: 12)
                        }
                    }
            }
        }
        .frame(height: 96)
        .animation(.easeOut(duration: 0.22), value: value)
    }
}

/// The card slider. It reports only on release so a drag never becomes a
/// stream of device writes.
struct PeatsSlider: View {
    @Environment(\.peats) private var theme
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var onCommit: (() -> Void)?

    var body: some View {
        Slider(value: $value, in: range) { editing in
            if !editing { onCommit?() }
        }
        .tint(theme.ok)
        .controlSize(.small)
    }
}

// MARK: - Layout helpers

/// Two- and three-up card grids that collapse the way the design's media
/// queries do.
struct CardGrid<Content: View>: View {
    let columns: Int
    var minWidth: CGFloat = 320
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { content }
                .frame(minWidth: minWidth * CGFloat(columns))
            if columns == 3 {
                Grid(horizontalSpacing: 16, verticalSpacing: 16) { GridRow { content } }
            }
            VStack(spacing: 16) { content }
        }
    }
}

/// The transient status pill from the design, anchored bottom-centre.
struct ToastView: View {
    @Environment(\.peats) private var theme
    let text: String

    var body: some View {
        Text(text)
            .font(PeatsFont.body(14, .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(theme.cardSolid, in: Capsule())
            .foregroundStyle(theme.cardSolidFG)
            .shadow(color: theme.shadow, radius: 18, y: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Marks a control whose behaviour is not yet proven on the connected
/// firmware, so the interface never implies a working feature.
struct UnverifiedNotice: View {
    @Environment(\.peats) private var theme
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.amber)
                .padding(.top, 2)
            Text(text)
                .font(PeatsFont.body(12))
                .foregroundStyle(theme.cardFG2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
