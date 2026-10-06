import Foundation

enum FeatureReadiness: String {
    case validated = "Validated on Q3 Pro"
    case readProbe = "Ready for read-only Q3 Pro probe"
    case controlledWrite = "Needs one controlled Q3 Pro write test"
    case localFeature = "Mac app feature"
    case deviceDependent = "Available if Q3 Pro exposes it"
}

struct PlannedFeature: Identifiable {
    let id: String
    let area: String
    let name: String
    let readiness: FeatureReadiness
    let notes: String
}

enum FeatureManifest {
    static let all: [PlannedFeature] = [
        .init(id: "connect", area: "Connection", name: "Paired-device discovery and reconnect", readiness: .validated, notes: "Uses the Q3 Pro's Bluetooth Classic RFCOMM service."),
        .init(id: "leftBattery", area: "Connection", name: "Left-earbud battery", readiness: .validated, notes: "Read-only protocol request proven on this Q3 Pro."),
        .init(id: "rightBattery", area: "Connection", name: "Right-earbud battery", readiness: .readProbe, notes: "Same battery command family as the validated left-side read."),
        .init(id: "caseBattery", area: "Connection", name: "Charging-case battery", readiness: .readProbe, notes: "Shown only if the Q3 Pro returns a value."),
        .init(id: "firmware", area: "Connection", name: "Firmware and device details", readiness: .readProbe, notes: "Used to build a per-firmware compatibility profile."),
        .init(id: "menuBar", area: "Mac integration", name: "Menu-bar battery and quick controls", readiness: .localFeature, notes: "Uses the saved device state and Mac notifications."),
        .init(id: "notifications", area: "Mac integration", name: "Low-battery notifications", readiness: .localFeature, notes: "Configurable thresholds per earbud and case."),
        .init(id: "shortcuts", area: "Mac integration", name: "Keyboard shortcuts", readiness: .localFeature, notes: "For switching already validated modes."),
        .init(id: "ancRead", area: "Noise control", name: "Current Normal / ANC / Transparency mode", readiness: .readProbe, notes: "The read is safe; write is separately gated."),
        .init(id: "ancWrite", area: "Noise control", name: "Normal / ANC / Transparency switching", readiness: .controlledWrite, notes: "One deliberate mode change, confirmed by a read-back."),
        .init(id: "ancStrength", area: "Noise control", name: "ANC strength and scene modes", readiness: .controlledWrite, notes: "Read the raw device level, make one explicit adjustment, then read it back live."),
        .init(id: "transparency", area: "Noise control", name: "Transparency level", readiness: .controlledWrite, notes: "Read the raw device level, make one explicit adjustment, then read it back live."),
        .init(id: "eq", area: "Audio", name: "Custom parametric EQ and saved presets", readiness: .controlledWrite, notes: "Requires Q3-specific EQ version and audible confirmation."),
        .init(id: "profiles", area: "Audio", name: "Device profiles and community EQ imports", readiness: .localFeature, notes: "Local preset library; importing never changes earbuds until Apply is confirmed."),
        .init(id: "ldac", area: "Audio", name: "LDAC status and toggle", readiness: .controlledWrite, notes: "One explicit toggle followed by a live read-back; support is connection-dependent."),
        .init(id: "spatial", area: "Audio", name: "Spatial or panoramic audio", readiness: .deviceDependent, notes: "Only included if the Q3 Pro answers the relevant feature probe."),
        .init(id: "game", area: "Controls", name: "Game mode", readiness: .controlledWrite, notes: "One explicit, reversible write followed by a live read-back; no automatic retries."),
        .init(id: "touchLock", area: "Controls", name: "Touch lock", readiness: .controlledWrite, notes: "One explicit toggle write followed by a live read-back; no automatic retries."),
        .init(id: "touchMap", area: "Controls", name: "Touch-control mapping", readiness: .readProbe, notes: "Read mapping first; editing needs a dedicated validation pass."),
        .init(id: "find", area: "Controls", name: "Find left or right earbud", readiness: .controlledWrite, notes: "An audible action with a visible stop/confirmation flow."),
        .init(id: "voice", area: "Controls", name: "Prompt volume and voice package", readiness: .controlledWrite, notes: "Prompt volume is read before the explicit one-step write, then read back live; voice package remains untested."),
        .init(id: "multipoint", area: "Connectivity", name: "Multipoint status and toggle", readiness: .controlledWrite, notes: "One explicit toggle write followed by a live read-back; enabling can reconfigure the control link."),
        .init(id: "leAudio", area: "Connectivity", name: "LE Audio status and toggle", readiness: .controlledWrite, notes: "One explicit toggle followed by a live read-back; support is device-dependent."),
        .init(id: "automation", area: "Automation", name: "Per-app sound profiles", readiness: .localFeature, notes: "App-launch rules can select a pre-approved, validated profile."),
        .init(id: "autoMode", area: "Automation", name: "Contextual ANC and game-mode rules", readiness: .localFeature, notes: "Examples: meeting, media, or game launch rules; requires explicit user consent."),
        .init(id: "diagnostics", area: "Developer", name: "Protocol log and compatibility report", readiness: .localFeature, notes: "Records only app-originated packet metadata and Q3 probe responses."),
    ]
}
