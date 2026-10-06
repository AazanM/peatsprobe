import AppKit
import Foundation
import SwiftUI

/// Everything the redesigned shell needs that lives on this Mac rather than on
/// the earbuds: which section is showing, the appearance, the local EQ library,
/// app-launch rules, and locally measured listening time.
///
/// Nothing in here pretends to be device state. Values that belong to the
/// earbuds come from `BluetoothScanner` only.
@MainActor
@Observable
final class AppModel {
    enum Section: String, CaseIterable, Identifiable {
        case overview, noise, audio, controls, connectivity, automations, developer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .noise: "Noise Control"
            case .audio: "Audio & EQ"
            case .controls: "Controls"
            case .connectivity: "Connectivity"
            case .automations: "Automations"
            case .developer: "Developer"
            }
        }

        var symbol: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .noise: "waveform"
            case .audio: "slider.horizontal.3"
            case .controls: "hand.tap"
            case .connectivity: "wifi"
            case .automations: "bolt"
            case .developer: "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    enum Appearance: String, CaseIterable {
        case light, dark, system
    }

    struct EQPreset: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var name: String
        var gains: [Double]
        var isBuiltIn: Bool = false
    }

    struct AutomationRule: Identifiable, Codable, Equatable {
        enum Action: String, Codable, CaseIterable {
            case ancNormal, ancNoiseCancelling, ancTransparency, gameModeOn, gameModeOff

            var title: String {
                switch self {
                case .ancNormal: "Normal"
                case .ancNoiseCancelling: "Noise Cancelling"
                case .ancTransparency: "Transparency"
                case .gameModeOn: "Game Mode on"
                case .gameModeOff: "Game Mode off"
                }
            }
        }

        var id: UUID = UUID()
        var bundleIdentifier: String
        var appName: String
        var action: Action
        var isEnabled: Bool = true
    }

    struct UsageDay: Codable, Equatable {
        var normal: Double = 0
        var anc: Double = 0
        var transparency: Double = 0
    }

    static let eqBands = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let builtInPresets: [EQPreset] = [
        .init(name: "Balanced", gains: [3, 2, 1, 0, -1, 0, 1, 2, 3, 2], isBuiltIn: true),
        .init(name: "Bass Boost", gains: [6, 6, 5, 2, 0, -1, -1, 0, 1, 1], isBuiltIn: true),
        .init(name: "Vocal", gains: [-2, -1, 0, 2, 5, 6, 4, 2, 0, -1], isBuiltIn: true),
        .init(name: "Studio Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], isBuiltIn: true),
        .init(name: "Podcast", gains: [-4, -3, 0, 3, 5, 5, 3, 1, -1, -3], isBuiltIn: true)
    ]

    var section: Section = .overview {
        didSet { UserDefaults.standard.set(section.rawValue, forKey: Keys.section) }
    }

    var appearance: Appearance = .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var toast: String?
    var showsDeviceSheet = false
    var showsRuleSheet = false

    private(set) var customPresets: [EQPreset] = []
    var selectedPresetID: UUID?
    var workingGains: [Double] = AppModel.builtInPresets[0].gains

    private(set) var rules: [AutomationRule] = []
    private(set) var usage: [String: UsageDay] = [:]

    private var toastTask: Task<Void, Never>?
    private var usageAnchor: (mode: PeatsNoiseControlMode, date: Date)?
    private var launchObserver: NSObjectProtocol?
    private weak var scanner: BluetoothScanner?

    private enum Keys {
        static let section = "peatsProbe.ui.section"
        static let appearance = "peatsProbe.ui.appearance"
        static let presets = "peatsProbe.ui.presets"
        static let rules = "peatsProbe.ui.rules"
        static let usage = "peatsProbe.ui.usage"
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.section),
           let value = Section(rawValue: raw) {
            section = value
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.appearance),
           let value = Appearance(rawValue: raw) {
            appearance = value
        }
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: Keys.presets),
           let presets = try? decoder.decode([EQPreset].self, from: data) {
            customPresets = presets
        }
        if let data = UserDefaults.standard.data(forKey: Keys.rules),
           let saved = try? decoder.decode([AutomationRule].self, from: data) {
            rules = saved
        }
        if let data = UserDefaults.standard.data(forKey: Keys.usage),
           let saved = try? decoder.decode([String: UsageDay].self, from: data) {
            usage = saved
        }
        selectedPresetID = AppModel.builtInPresets.first?.id
    }

    func theme(for colorScheme: ColorScheme) -> PeatsTheme {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: colorScheme == .dark ? .dark : .light
        }
    }

    var resolvedColorScheme: ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    func toggleAppearance(currentlyDark: Bool) {
        appearance = currentlyDark ? .light : .dark
        show(currentlyDark ? "Light appearance" : "Dark appearance")
    }

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - EQ library

    var allPresets: [EQPreset] { AppModel.builtInPresets + customPresets }

    var selectedPreset: EQPreset? {
        allPresets.first { $0.id == selectedPresetID }
    }

    func selectPreset(_ preset: EQPreset) {
        selectedPresetID = preset.id
        workingGains = preset.gains
    }

    func saveWorkingPreset(named name: String) {
        let preset = EQPreset(name: name, gains: workingGains)
        customPresets.append(preset)
        selectedPresetID = preset.id
        persistPresets()
        show("Saved “\(name)” to this Mac")
    }

    func deletePreset(_ preset: EQPreset) {
        customPresets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id { selectedPresetID = AppModel.builtInPresets.first?.id }
        persistPresets()
    }

    private func persistPresets() {
        UserDefaults.standard.set(try? JSONEncoder().encode(customPresets), forKey: Keys.presets)
    }

    // MARK: - Automation rules

    /// Rules are driven by real app-launch notifications from this Mac and only
    /// ever apply a setting that has already been verified on the earbuds.
    func startAutomation(with scanner: BluetoothScanner) {
        self.scanner = scanner
        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.handleLaunch(bundleID: bundleID, name: app.localizedName ?? bundleID) }
        }
    }

    private func handleLaunch(bundleID: String, name: String) {
        guard let scanner,
              let device = scanner.preferredPairedDevice,
              device.isConnected,
              let rule = rules.first(where: { $0.isEnabled && $0.bundleIdentifier == bundleID }) else { return }
        apply(rule.action, on: scanner, address: device.address)
        show("\(name) launched → \(rule.action.title)")
    }

    private func apply(_ action: AutomationRule.Action, on scanner: BluetoothScanner, address: String) {
        switch action {
        case .ancNormal: scanner.setNoiseControl(.normal, for: address)
        case .ancNoiseCancelling: scanner.setNoiseControl(.noiseCancelling, for: address)
        case .ancTransparency: scanner.setNoiseControl(.transparency, for: address)
        case .gameModeOn: scanner.setGameMode(.on, for: address)
        case .gameModeOff: scanner.setGameMode(.off, for: address)
        }
    }

    func addRule(_ rule: AutomationRule) {
        rules.append(rule)
        persistRules()
        show("Rule created")
    }

    func toggleRule(_ rule: AutomationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled.toggle()
        persistRules()
    }

    func deleteRule(_ rule: AutomationRule) {
        rules.removeAll { $0.id == rule.id }
        persistRules()
    }

    private func persistRules() {
        UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: Keys.rules)
    }

    /// Applications the operator can pick from: whatever is running right now.
    func runningApplications() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return (bundleID, name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Locally measured listening time

    /// Attributes elapsed time to the mode the earbuds were verified to be in.
    /// It only counts while PeatsProbe is running and the link is up, which the
    /// Automations view states plainly.
    func noteObservedMode(_ mode: PeatsNoiseControlMode) {
        let now = Date()
        defer { usageAnchor = (mode, now) }
        guard let anchor = usageAnchor else { return }
        let elapsed = now.timeIntervalSince(anchor.date) / 3600
        // A gap longer than 30 minutes means the app was idle, not listening.
        guard elapsed > 0, elapsed < 0.5 else { return }
        let key = AppModel.dayKey(for: anchor.date)
        var day = usage[key] ?? UsageDay()
        switch anchor.mode {
        case .normal: day.normal += elapsed
        case .noiseCancelling, .adaptive, .weakNoiseReduction: day.anc += elapsed
        case .transparency: day.transparency += elapsed
        }
        usage[key] = day
        pruneUsage()
        UserDefaults.standard.set(try? JSONEncoder().encode(usage), forKey: Keys.usage)
    }

    func clearUsage() {
        usage.removeAll()
        usageAnchor = nil
        UserDefaults.standard.removeObject(forKey: Keys.usage)
    }

    private func pruneUsage() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let cutoffKey = AppModel.dayKey(for: cutoff)
        usage = usage.filter { $0.key >= cutoffKey }
    }

    /// The last seven days, oldest first, for the usage chart.
    var usageWeek: [(label: String, day: UsageDay)] {
        let calendar = Calendar.current
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let weekday = calendar.component(.weekday, from: date) - 1
            return (symbols[weekday], usage[AppModel.dayKey(for: date)] ?? UsageDay())
        }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
