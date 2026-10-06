@preconcurrency import CoreBluetooth
import Foundation
import IOBluetooth
import UserNotifications

@MainActor
@Observable
final class BluetoothScanner: NSObject {
    struct VerifiedSettingHistoryEntry: Identifiable, Codable, Equatable {
        let id: UUID
        let address: String
        let setting: String
        let value: String
        let date: Date
    }

    struct SavedProfile: Identifiable, Codable, Equatable {
        let id: UUID
        let address: String
        let name: String
        let date: Date
        let status: CoreDeviceStatus
    }

    enum ByteControlSetting: CaseIterable, Hashable {
        case noiseControlStrength
        case transparencyLevel
        case promptVolume
        case voicePackage

        var title: String {
            switch self {
            case .noiseControlStrength: "ANC Strength"
            case .transparencyLevel: "Transparency Level"
            case .promptVolume: "Prompt Volume"
            case .voicePackage: "Voice Package"
            }
        }

        var readCommand: PeatsReadCommand {
            switch self {
            case .noiseControlStrength: .noiseControlStrength
            case .transparencyLevel: .transparencyLevel
            case .promptVolume: .promptVolume
            case .voicePackage: .voicePackage
            }
        }

        func writeCommand(_ value: UInt8) -> PeatsWriteCommand {
            switch self {
            case .noiseControlStrength: .noiseControlStrength(value)
            case .transparencyLevel: .transparencyLevel(value)
            case .promptVolume: .promptVolume(value)
            case .voicePackage: .voicePackage(value)
            }
        }
    }

    struct DiscoveredOpcode: Identifiable, Equatable, Codable {
        var id: String { hex }
        let hex: String
        let requestHex: String
        let payload: [UInt8]
        let describedAs: String
        let date: Date
    }

    /// A feature is only ever `verified` after this Mac has read the value back
    /// off the earbuds. Nothing is assumed from the model name.
    enum SupportLevel: String, Codable {
        case unknown
        case verified
        case unsupported
    }

    enum SupportKey: String, Codable, CaseIterable {
        case noiseControl, gameMode, multipoint, touchLock, promptVolume
        case noiseControlStrength, transparencyLevel, voicePackage, ldac, leAudio
        case touchMapping, equaliser, findEarbud

        var title: String {
            switch self {
            case .noiseControl: "Noise-control mode"
            case .gameMode: "Game Mode"
            case .multipoint: "Multipoint"
            case .touchLock: "Touch lock"
            case .promptVolume: "Prompt volume"
            case .noiseControlStrength: "ANC strength"
            case .transparencyLevel: "Transparency level"
            case .voicePackage: "Voice package"
            case .ldac: "LDAC"
            case .leAudio: "LE Audio"
            case .touchMapping: "Touch mapping"
            case .equaliser: "Equaliser"
            case .findEarbud: "Find earbud"
            }
        }
    }

    enum State: Equatable {
        case starting
        case ready
        case scanning
        case unavailable(String)

        var label: String {
            switch self {
            case .starting: "Starting Bluetooth…"
            case .ready: "Ready to scan"
            case .scanning: "Scanning nearby BLE devices"
            case .unavailable(let reason): reason
            }
        }
    }

    struct Device: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
        let lastSeen: Date
        let advertisedServices: [String]

        var isSoundPEATS: Bool {
            name.localizedCaseInsensitiveContains("soundpeats") ||
            name.localizedCaseInsensitiveContains("peats")
        }
    }

    struct PairedDevice: Identifiable, Equatable {
        let address: String
        let name: String
        let isConnected: Bool

        var id: String { address }

        var isSoundPEATS: Bool {
            name.localizedCaseInsensitiveContains("soundpeats") ||
            name.localizedCaseInsensitiveContains("peats")
        }
    }

    struct ClassicService: Identifiable, Equatable {
        let id: String
        let name: String
        let rfcommChannel: UInt8?
    }

    struct CoreDeviceStatus: Equatable, Codable {
        var leftBattery: Int? = nil
        var rightBattery: Int? = nil
        var caseBattery: Int? = nil
        var firmware: String? = nil
        var noiseControl: PeatsNoiseControlMode? = nil
        var gameMode: PeatsToggle? = nil
        var multipoint: PeatsToggle? = nil
        var touchLock: PeatsToggle? = nil
        var promptVolume: UInt8? = nil
        var noiseControlStrength: UInt8? = nil
        var transparencyLevel: UInt8? = nil
        var voicePackage: UInt8? = nil
        var ldac: PeatsToggle? = nil
        var leAudio: PeatsToggle? = nil
    }

    private var central: CBCentralManager!
    private var deviceIndex: [UUID: Device] = [:]
    private var stopTask: Task<Void, Never>?
    private var serviceRefreshTask: Task<Void, Never>?
    private var connectionMonitorTask: Task<Void, Never>?
    private var lastConnectionState: [String: Bool] = [:]
    private let rfcommTester = RFCOMMOpenTester()
    private let rfcommReadProbe = RFCOMMReadProbe()
    private let rfcommWriteProbe = RFCOMMWriteProbe()
    private let rfcommRawProbe = RFCOMMRawProbe()
    private let scanDuration: Duration = .seconds(12)

    private(set) var state: State = .starting
    private(set) var devices: [Device] = []
    private(set) var pairedDevices: [PairedDevice] = []
    private(set) var classicServices: [String: [ClassicService]] = [:]
    private(set) var serviceDiscoveryStatus: [String: String] = [:]
    private(set) var channelTestStatus: [String: String] = [:]
    private(set) var readProbeStatus: [String: String] = [:]
    private(set) var controlStatus: [String: String] = [:]
    private(set) var ancControlInProgress: Set<String> = []
    private var pendingANCVerification: [String: PeatsNoiseControlMode] = [:]
    private(set) var gameModeControlInProgress: Set<String> = []
    private var pendingGameModeVerification: [String: PeatsToggle] = [:]
    private(set) var multipointControlInProgress: Set<String> = []
    private var pendingMultipointVerification: [String: PeatsToggle] = [:]
    private(set) var touchLockControlInProgress: Set<String> = []
    private var pendingTouchLockVerification: [String: PeatsToggle] = [:]
    private(set) var byteControlInProgress: [String: Set<ByteControlSetting>] = [:]
    private var pendingByteVerification: [String: [ByteControlSetting: UInt8]] = [:]
    private(set) var ldacControlInProgress: Set<String> = []
    private var pendingLDACVerification: [String: PeatsToggle] = [:]
    private(set) var leAudioControlInProgress: Set<String> = []
    private var pendingLEAudioVerification: [String: PeatsToggle] = [:]
    private(set) var coreDeviceStatus: [String: CoreDeviceStatus] = [:]
    private(set) var lastScanDate: Date?
    private(set) var lowBatteryNotificationsEnabled = UserDefaults.standard.bool(forKey: "peatsProbe.lowBatteryNotificationsEnabled")
    private(set) var verifiedHistory: [VerifiedSettingHistoryEntry] = []
    private(set) var savedProfiles: [SavedProfile] = []
    private var lowBatteryNotificationKeys: Set<String> = []

    /// Live RFCOMM frame log, fed by every probe in the app.
    let protocolLog = ProtocolLog()
    private(set) var diagnosticsStatus: [String: String] = [:]
    private(set) var diagnosticsRunning = false
    /// Opcodes this Q3 Pro answered during a diagnostics run, keyed by address.
    private(set) var discoveredOpcodes: [String: [DiscoveredOpcode]] = [:]
    /// Opcodes that were the last thing written before the link died. They are
    /// never sent again by a sweep unless the operator clears them.
    private(set) var suspectOpcodes: [String: [String]] = [:]
    /// The opcode a dropped sweep never reached, so it can be picked up again.
    private(set) var sweepResumePoint: [String: UInt8] = [:]
    /// Features proven on this specific device, so the UI never presents an
    /// unproven control as if it worked.
    private(set) var supportState: [String: [SupportKey: SupportLevel]] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        rfcommTester.onFinish = { [weak self] address, message in
            Task { @MainActor in
                self?.channelTestStatus[address] = message
            }
        }
        rfcommReadProbe.onFinish = { [weak self] address, message in
            Task { @MainActor in
                self?.readProbeStatus[address] = message
            }
        }
        rfcommReadProbe.onValue = { [weak self] address, command, value in
            Task { @MainActor in
                self?.record(value, from: command, for: address)
            }
        }
        rfcommWriteProbe.onFinish = { [weak self] address, command, message, confirmed, shouldReadBack in
            Task { @MainActor in
                guard let self else { return }
                self.controlStatus[address] = message
                switch command {
                case .noiseControl:
                    self.ancControlInProgress.remove(address)
                    guard shouldReadBack else {
                        self.pendingANCVerification[address] = nil
                        return
                    }
                    self.scheduleANCReadBack(for: address)
                case .gameMode:
                    self.gameModeControlInProgress.remove(address)
                    guard shouldReadBack else {
                        self.pendingGameModeVerification[address] = nil
                        return
                    }
                    self.scheduleGameModeReadBack(for: address)
                case .multipoint:
                    self.multipointControlInProgress.remove(address)
                    guard shouldReadBack else {
                        self.pendingMultipointVerification[address] = nil
                        return
                    }
                    self.scheduleMultipointReadBack(for: address)
                case .touchLock:
                    self.touchLockControlInProgress.remove(address)
                    guard shouldReadBack else {
                        self.pendingTouchLockVerification[address] = nil
                        return
                    }
                    self.scheduleTouchLockReadBack(for: address)
                case .noiseControlStrength:
                    self.finishByteWrite(.noiseControlStrength, for: address, shouldReadBack: shouldReadBack)
                case .transparencyLevel:
                    self.finishByteWrite(.transparencyLevel, for: address, shouldReadBack: shouldReadBack)
                case .promptVolume:
                    self.finishByteWrite(.promptVolume, for: address, shouldReadBack: shouldReadBack)
                case .voicePackage:
                    self.finishByteWrite(.voicePackage, for: address, shouldReadBack: shouldReadBack)
                case .ldac:
                    self.ldacControlInProgress.remove(address)
                    guard shouldReadBack else {
                        self.pendingLDACVerification[address] = nil
                        return
                    }
                    self.scheduleLDACReadBack(for: address)
                case .leAudio:
                    self.leAudioControlInProgress.remove(address)
                    guard shouldReadBack else {
                        self.pendingLEAudioVerification[address] = nil
                        return
                    }
                    self.scheduleLEAudioReadBack(for: address)
                default:
                    break
                }
            }
        }
        rfcommReadProbe.onLog = { [weak self] entry in
            Task { @MainActor in self?.protocolLog.append(entry) }
        }
        rfcommWriteProbe.onLog = { [weak self] entry in
            Task { @MainActor in self?.protocolLog.append(entry) }
        }
        rfcommRawProbe.onLog = { [weak self] entry in
            Task { @MainActor in self?.protocolLog.append(entry) }
        }
        rfcommRawProbe.onStatus = { [weak self] address, message in
            Task { @MainActor in self?.diagnosticsStatus[address] = message }
        }
        rfcommRawProbe.onReply = { [weak self] address, reply in
            Task { @MainActor in self?.recordDiscovered(reply, for: address) }
        }
        rfcommRawProbe.onLinkDropped = { [weak self] address, suspect, resumeAt in
            Task { @MainActor in self?.recordLinkDrop(suspect: suspect, resumeAt: resumeAt, for: address) }
        }
        rfcommRawProbe.onFinish = { [weak self] address, message in
            Task { @MainActor in
                self?.diagnosticsStatus[address] = message
                self?.diagnosticsRunning = false
            }
        }
        loadLocalState()
        refreshPairedDevices()
        startConnectionMonitor()
    }

    func scan() {
        refreshPairedDevices()
        guard central.state == .poweredOn else {
            updateState(for: central.state)
            return
        }

        stopTask?.cancel()
        deviceIndex.removeAll()
        devices.removeAll()
        lastScanDate = Date()
        state = .scanning

        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        stopTask = Task { [weak self] in
            try? await Task.sleep(for: self?.scanDuration ?? .seconds(12))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        guard central.isScanning else { return }
        central.stopScan()
        state = .ready
    }

    func clear() {
        deviceIndex.removeAll()
        devices.removeAll()
    }

    /// Reads macOS's existing paired-device list. It does not initiate a connection.
    func refreshPairedDevices() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        pairedDevices = devices.map { device in
            PairedDevice(
                address: device.addressString,
                name: device.name ?? device.nameOrAddress,
                isConnected: device.isConnected()
            )
        }
        .sorted { lhs, rhs in
            if lhs.isSoundPEATS != rhs.isSoundPEATS { return lhs.isSoundPEATS }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        for device in pairedDevices {
            loadLastKnownStatus(for: device.address)
            loadDiscovered(for: device.address)
            loadSuspects(for: device.address)
            loadSupport(for: device.address)
        }
    }

    var preferredPairedDevice: PairedDevice? {
        pairedDevices.first { $0.isSoundPEATS && $0.isConnected } ??
            pairedDevices.first { $0.isSoundPEATS }
    }

    var menuBarStatusLabel: String {
        guard let device = preferredPairedDevice else { return "PeatsProbe" }
        guard device.isConnected else { return "Q3 Pro offline" }
        guard let status = coreDeviceStatus[device.address] else { return "Q3 Pro connected" }
        let values = [status.leftBattery, status.rightBattery].compactMap { $0 }
        guard let battery = values.min() else { return "Q3 Pro connected" }
        return "Q3 \(battery)%"
    }

    var menuBarStatusDetail: String {
        guard let device = preferredPairedDevice else { return "No paired SOUNDPEATS device found" }
        guard device.isConnected else { return "\(device.name) is disconnected; showing saved state." }
        return "\(device.name) is connected"
    }

    func refreshPreferredDeviceStatus() {
        guard let device = preferredPairedDevice, device.isConnected else { return }
        refreshCoreDeviceStatus(for: device.address)
    }

    func setPreferredNoiseControl(_ mode: PeatsNoiseControlMode) {
        guard let device = preferredPairedDevice, device.isConnected else { return }
        setNoiseControl(mode, for: device.address)
    }

    func togglePreferredGameMode() {
        guard let device = preferredPairedDevice, device.isConnected else { return }
        let current = coreDeviceStatus[device.address]?.gameMode ?? .off
        setGameMode(current == .on ? .off : .on, for: device.address)
    }

    func togglePreferredTouchLock() {
        guard let device = preferredPairedDevice, device.isConnected else { return }
        let current = coreDeviceStatus[device.address]?.touchLock ?? .off
        setTouchLock(current == .on ? .off : .on, for: device.address)
    }

    func setLowBatteryNotificationsEnabled(_ enabled: Bool) {
        lowBatteryNotificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "peatsProbe.lowBatteryNotificationsEnabled")
        guard enabled else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    func saveCurrentProfile(for address: String) {
        guard let status = coreDeviceStatus[address] else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        savedProfiles.insert(
            SavedProfile(
                id: UUID(),
                address: address,
                name: "Snapshot \(formatter.string(from: Date()))",
                date: Date(),
                status: status
            ),
            at: 0
        )
        savedProfiles = Array(savedProfiles.prefix(20))
        persistLocalState()
    }

    func profiles(for address: String) -> [SavedProfile] {
        savedProfiles.filter { $0.address == address }
    }

    func recentHistory(for address: String, limit: Int = 8) -> [VerifiedSettingHistoryEntry] {
        Array(verifiedHistory.filter { $0.address == address }.prefix(limit))
    }

    /// Starts an SDP catalogue request only. SDP lists services; it sends no vendor command.
    func discoverServices(for address: String) {
        guard let device = pairedDevice(with: address) else {
            serviceDiscoveryStatus[address] = "Could not find the paired device"
            return
        }

        serviceRefreshTask?.cancel()
        serviceDiscoveryStatus[address] = "Reading service catalogue…"
        let result = device.performSDPQuery(nil as AnyObject?)
        guard result == kIOReturnSuccess else {
            serviceDiscoveryStatus[address] = "Could not start service discovery (IOKit \(result))"
            return
        }

        serviceRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.loadCachedServices(for: address)
        }
    }

    func services(for address: String) -> [ClassicService] {
        classicServices[address, default: []]
    }

    func statusForServiceDiscovery(at address: String) -> String? {
        serviceDiscoveryStatus[address]
    }

    /// Uses the current asynchronous IOBluetooth API to open and immediately
    /// close a channel. No bytes are ever written.
    func testRFCOMMOpenClose(for address: String, channelID: BluetoothRFCOMMChannelID) {
        guard let device = pairedDevice(with: address), device.isConnected() else {
            channelTestStatus[address] = "Device is no longer connected"
            return
        }

        channelTestStatus[address] = "Opening RFCOMM channel \(channelID) asynchronously without sending data…"
        rfcommTester.start(device: device, address: address, channelID: channelID)
    }

    func statusForChannelTest(at address: String) -> String? {
        channelTestStatus[address]
    }

    func readLeftBattery(for address: String, channelID: BluetoothRFCOMMChannelID) {
        read([.leftBattery], for: address, channelID: channelID)
    }

    /// Refreshes all state currently requested for the Q3 Pro app shell in one
    /// RFCOMM session: batteries, firmware, and noise-control mode.
    func refreshCoreDeviceStatus(for address: String, channelID: BluetoothRFCOMMChannelID = 1) {
        read([.leftBattery, .rightBattery, .caseBattery, .firmware, .noiseControl], for: address, channelID: channelID)
    }

    func coreStatus(for address: String) -> CoreDeviceStatus? {
        coreDeviceStatus[address]
    }

    /// Sends one deliberate ANC-mode change. The writer does not retry; it
    /// starts a separate read-back only when the earbud acknowledges the write.
    func setNoiseControl(
        _ mode: PeatsNoiseControlMode,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }

        ancControlInProgress.insert(address)
        pendingANCVerification[address] = mode
        controlStatus[address] = "Opening RFCOMM channel \(channelID) to change ANC mode…"
        rfcommWriteProbe.write(.noiseControl(mode), to: device, address: address, channelID: channelID)
    }

    func statusForControl(at address: String) -> String? {
        controlStatus[address]
    }

    func isANCControlInProgress(at address: String) -> Bool {
        ancControlInProgress.contains(address)
    }

    /// Sends one deliberate low-latency mode change. The write is never
    /// retried; a separate live read follows whether or not it is acknowledged.
    func setGameMode(
        _ value: PeatsToggle,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }

        gameModeControlInProgress.insert(address)
        pendingGameModeVerification[address] = value
        controlStatus[address] = "Opening RFCOMM channel \(channelID) to set Game Mode \(value.displayValue)…"
        rfcommWriteProbe.write(.gameMode(value), to: device, address: address, channelID: channelID)
    }

    func isGameModeControlInProgress(at address: String) -> Bool {
        gameModeControlInProgress.contains(address)
    }

    /// Sends one deliberate multipoint change. Enabling multipoint can alter
    /// the connection topology, so the app sends once and waits for a read-back.
    func setMultipoint(
        _ value: PeatsToggle,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }

        multipointControlInProgress.insert(address)
        pendingMultipointVerification[address] = value
        controlStatus[address] = "Opening RFCOMM channel \(channelID) to set Multipoint \(value.displayValue)…"
        rfcommWriteProbe.write(.multipoint(value), to: device, address: address, channelID: channelID)
    }

    func isMultipointControlInProgress(at address: String) -> Bool {
        multipointControlInProgress.contains(address)
    }

    /// Sends one deliberate touch-lock change and follows it with a live read.
    func setTouchLock(
        _ value: PeatsToggle,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }

        touchLockControlInProgress.insert(address)
        pendingTouchLockVerification[address] = value
        controlStatus[address] = "Opening RFCOMM channel \(channelID) to set Touch Lock \(value.displayValue)…"
        rfcommWriteProbe.write(.touchLock(value), to: device, address: address, channelID: channelID)
    }

    func isTouchLockControlInProgress(at address: String) -> Bool {
        touchLockControlInProgress.contains(address)
    }

    /// Sends one explicit byte-valued setting change. The temporary diagnostic
    /// controls read the live value before offering an edit, avoiding an assumed
    /// device-specific range.
    func setByteControl(
        _ setting: ByteControlSetting,
        to value: UInt8,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }

        byteControlInProgress[address, default: []].insert(setting)
        pendingByteVerification[address, default: [:]][setting] = value
        controlStatus[address] = "Opening RFCOMM channel \(channelID) to set \(setting.title) to \(value)…"
        rfcommWriteProbe.write(setting.writeCommand(value), to: device, address: address, channelID: channelID)
    }

    /// Reads an explicit list of safe, idempotent state commands in one session.
    func readCommands(_ commands: [PeatsReadCommand], for address: String, channelID: BluetoothRFCOMMChannelID = 1) {
        read(commands, for: address, channelID: channelID)
    }

    func readByteControl(
        _ setting: ByteControlSetting,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        read([setting.readCommand], for: address, channelID: channelID)
    }

    func isByteControlInProgress(_ setting: ByteControlSetting, at address: String) -> Bool {
        byteControlInProgress[address, default: []].contains(setting)
    }

    /// Compatibility helpers keep the prompt-volume diagnostic control concise.
    func setPromptVolume(
        _ value: UInt8,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        setByteControl(.promptVolume, to: value, for: address, channelID: channelID)
    }

    func readPromptVolume(for address: String, channelID: BluetoothRFCOMMChannelID = 1) {
        readByteControl(.promptVolume, for: address, channelID: channelID)
    }

    func isPromptVolumeControlInProgress(at address: String) -> Bool {
        isByteControlInProgress(.promptVolume, at: address)
    }

    func setLDAC(_ value: PeatsToggle, for address: String, channelID: BluetoothRFCOMMChannelID = 1) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }

        ldacControlInProgress.insert(address)
        pendingLDACVerification[address] = value
        controlStatus[address] = "Opening RFCOMM channel \(channelID) to set LDAC \(value.displayValue)…"
        rfcommWriteProbe.write(.ldac(value), to: device, address: address, channelID: channelID)
    }

    func isLDACControlInProgress(at address: String) -> Bool {
        ldacControlInProgress.contains(address)
    }

    func setLEAudio(_ value: PeatsToggle, for address: String, channelID: BluetoothRFCOMMChannelID = 1) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }

        leAudioControlInProgress.insert(address)
        pendingLEAudioVerification[address] = value
        controlStatus[address] = "Opening RFCOMM channel \(channelID) to set LE Audio \(value.displayValue)…"
        rfcommWriteProbe.write(.leAudio(value), to: device, address: address, channelID: channelID)
    }

    func isLEAudioControlInProgress(at address: String) -> Bool {
        leAudioControlInProgress.contains(address)
    }


    // MARK: - On-Mac protocol discovery
    //
    // These three tools exist so an unproven feature can be worked out on this
    // Mac. They replace sniffing the vendor's phone app: the earbuds themselves
    // are the source of truth about which opcodes exist and how they encode.

    /// Opens the control channel and writes nothing, logging every frame the
    /// earbuds push while the operator presses the stems. Read-only by design.
    func startPassiveListen(
        for address: String,
        duration: TimeInterval = 30,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard beginDiagnostics(for: address) else { return }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            diagnosticsStatus[address] = "Device is no longer connected"
            diagnosticsRunning = false
            return
        }
        protocolLog.note("Passive listen started for \(Int(duration))s — no packet will be written")
        rfcommRawProbe.listen(from: device, address: address, channelID: channelID, duration: duration)
    }

    /// Writes one operator-composed packet exactly once and records the reply.
    func sendRawPacket(
        opcode: (UInt8, UInt8),
        payload: [UInt8],
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard beginDiagnostics(for: address) else { return }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            diagnosticsStatus[address] = "Device is no longer connected"
            diagnosticsRunning = false
            return
        }
        let packet = PeatsPacket(opcode: opcode, payload: payload)
        rfcommRawProbe.send(packet, to: device, address: address, channelID: channelID)
    }

    /// Sends every request opcode in `range` once, with an empty payload, and
    /// records which ones the firmware answers. The caller must warn the
    /// operator: a range can contain setting-changing opcodes.
    func startOpcodeSweep(
        family: UInt8 = 0x03,
        range: ClosedRange<UInt8>,
        evenOnly: Bool = true,
        for address: String,
        channelID: BluetoothRFCOMMChannelID = 1
    ) {
        guard beginDiagnostics(for: address) else { return }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            diagnosticsStatus[address] = "Device is no longer connected"
            diagnosticsRunning = false
            return
        }
        let quarantined = Set(suspectOpcodes[address] ?? [])
        let all = stride(from: Int(range.lowerBound), through: Int(range.upperBound), by: 1)
            .filter { !evenOnly || $0 % 2 == 0 }
            .map { PeatsPacket(opcode: (family, UInt8($0))) }
        let packets = all.filter { !quarantined.contains(String(format: "%02X %02X", $0.opcode.0, $0.opcode.1)) }
        let skipped = all.count - packets.count
        guard !packets.isEmpty else {
            diagnosticsStatus[address] = "Every opcode in that range is quarantined as a suspect"
            diagnosticsRunning = false
            return
        }
        sweepResumePoint[address] = nil
        protocolLog.note("Opcode sweep \(String(format: "%02X %02X…%02X", family, range.lowerBound, range.upperBound)) — \(packets.count) \(evenOnly ? "even (read-side) " : "")packets, one send each" + (skipped > 0 ? ", \(skipped) quarantined opcode\(skipped == 1 ? "" : "s") skipped" : ""))
        rfcommRawProbe.sweep(packets, to: device, address: address, channelID: channelID)
    }

    func cancelDiagnostics() {
        rfcommRawProbe.cancel()
        diagnosticsRunning = false
    }

    /// Quarantines whatever was written immediately before the link died and
    /// stores where to pick the sweep back up.
    private func recordLinkDrop(suspect: PeatsPacket?, resumeAt: PeatsPacket?, for address: String) {
        if let suspect {
            let hex = String(format: "%02X %02X", suspect.opcode.0, suspect.opcode.1)
            var list = suspectOpcodes[address] ?? []
            if !list.contains(hex) { list.append(hex) }
            suspectOpcodes[address] = list.sorted()
            persistSuspects(for: address)
            protocolLog.note("Link dropped after \(hex) — quarantined, it will be skipped by future sweeps")
        }
        if let resumeAt {
            sweepResumePoint[address] = resumeAt.opcode.1
        }
    }

    func clearSuspectOpcodes(for address: String) {
        suspectOpcodes[address] = []
        sweepResumePoint[address] = nil
        persistSuspects(for: address)
    }

    private func persistSuspects(for address: String) {
        UserDefaults.standard.set(suspectOpcodes[address] ?? [], forKey: "peatsProbe.suspectOpcodes.\(address)")
    }

    private func loadSuspects(for address: String) {
        guard suspectOpcodes[address] == nil,
              let list = UserDefaults.standard.array(forKey: "peatsProbe.suspectOpcodes.\(address)") as? [String] else { return }
        suspectOpcodes[address] = list
    }

    func clearDiscoveredOpcodes(for address: String) {
        discoveredOpcodes[address] = []
        persistDiscovered(for: address)
    }

    func statusForDiagnostics(at address: String) -> String? {
        diagnosticsStatus[address]
    }

    func supportLevel(_ key: SupportKey, for address: String) -> SupportLevel {
        supportState[address]?[key] ?? .unknown
    }

    /// Marks a feature unsupported after the operator confirms the control had
    /// no effect, so the app stops offering a write that does nothing.
    func markUnsupported(_ key: SupportKey, for address: String) {
        markSupport(key, level: .unsupported, for: address)
    }

    func resetSupport(_ key: SupportKey, for address: String) {
        markSupport(key, level: .unknown, for: address)
    }

    private func markSupport(_ key: SupportKey, level: SupportLevel, for address: String) {
        var map = supportState[address] ?? [:]
        guard map[key] != level else { return }
        map[key] = level
        supportState[address] = map
        persistSupport(for: address)
    }

    /// Any value the earbuds actually returned counts as proof of support.
    private func noteVerified(_ key: SupportKey, for address: String) {
        markSupport(key, level: .verified, for: address)
    }

    private func beginDiagnostics(for address: String) -> Bool {
        guard !diagnosticsRunning else {
            diagnosticsStatus[address] = "A diagnostics session is already running"
            return false
        }
        guard !hasPendingControlVerification(for: address) else {
            diagnosticsStatus[address] = "A setting verification is still running"
            return false
        }
        diagnosticsRunning = true
        return true
    }

    private func recordDiscovered(_ reply: RFCOMMRawProbe.Reply, for address: String) {
        let hex = String(format: "%02X %02X", reply.packet.opcode.0, reply.packet.opcode.1)
        let requestHex = reply.request.map { String(format: "%02X %02X", $0.opcode.0, $0.opcode.1) } ?? "unsolicited"
        var list = discoveredOpcodes[address] ?? []
        let entry = DiscoveredOpcode(
            hex: hex,
            requestHex: requestHex,
            payload: reply.packet.payload,
            describedAs: PeatsFrameDescriber.describe(reply.packet),
            date: Date()
        )
        if let index = list.firstIndex(where: { $0.hex == hex }) {
            list[index] = entry
        } else {
            list.append(entry)
        }
        discoveredOpcodes[address] = list.sorted { $0.hex < $1.hex }
        persistDiscovered(for: address)
    }

    private func persistDiscovered(for address: String) {
        UserDefaults.standard.set(
            try? JSONEncoder().encode(discoveredOpcodes[address] ?? []),
            forKey: "peatsProbe.discoveredOpcodes.\(address)"
        )
    }

    private func loadDiscovered(for address: String) {
        guard discoveredOpcodes[address] == nil,
              let data = UserDefaults.standard.data(forKey: "peatsProbe.discoveredOpcodes.\(address)"),
              let list = try? JSONDecoder().decode([DiscoveredOpcode].self, from: data) else { return }
        discoveredOpcodes[address] = list
    }

    private func persistSupport(for address: String) {
        let raw = (supportState[address] ?? [:]).reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue }
        UserDefaults.standard.set(raw, forKey: "peatsProbe.supportState.\(address)")
    }

    private func loadSupport(for address: String) {
        guard supportState[address] == nil,
              let raw = UserDefaults.standard.dictionary(forKey: "peatsProbe.supportState.\(address)") as? [String: String] else { return }
        supportState[address] = raw.reduce(into: [SupportKey: SupportLevel]()) { result, pair in
            guard let key = SupportKey(rawValue: pair.key), let level = SupportLevel(rawValue: pair.value) else { return }
            result[key] = level
        }
    }

    /// One explicit, audible locate command. Untested on this firmware, so the
    /// UI must present it as unverified until the earbud actually chimes.
    func findEarbud(left: Bool, for address: String, channelID: BluetoothRFCOMMChannelID = 1) {
        guard !hasPendingControlVerification(for: address) else {
            controlStatus[address] = "Another setting change or verification is already running"
            return
        }
        guard let device = pairedDevice(with: address), device.isConnected() else {
            controlStatus[address] = "Device is no longer connected"
            return
        }
        controlStatus[address] = "Sending one find-\(left ? "left" : "right") command…"
        rfcommWriteProbe.write(left ? .findLeft : .findRight, to: device, address: address, channelID: channelID)
    }

    private func read(_ commands: [PeatsReadCommand], for address: String, channelID: BluetoothRFCOMMChannelID) {
        guard let device = pairedDevice(with: address), device.isConnected() else {
            readProbeStatus[address] = "Device is no longer connected"
            return
        }
        readProbeStatus[address] = "Opening RFCOMM channel \(channelID) for \(commands.count) safe device read\(commands.count == 1 ? "" : "s")…"
        rfcommReadProbe.read(commands, from: device, address: address, channelID: channelID)
    }

    private func hasPendingControlVerification(for address: String) -> Bool {
        pendingANCVerification[address] != nil ||
            pendingGameModeVerification[address] != nil ||
            pendingMultipointVerification[address] != nil ||
            pendingTouchLockVerification[address] != nil ||
            pendingByteVerification[address]?.isEmpty == false ||
            pendingLDACVerification[address] != nil ||
            pendingLEAudioVerification[address] != nil
    }

    func statusForReadProbe(at address: String) -> String? {
        readProbeStatus[address]
    }

    private func record(_ value: PeatsReadValue, from command: PeatsReadCommand, for address: String) {
        var state = coreDeviceStatus[address] ?? CoreDeviceStatus()
        switch (command, value) {
        case (.leftBattery, .percentage(let percentage)):
            state.leftBattery = percentage
            notifyAboutLowBatteryIfNeeded(component: "Left", percentage: percentage, address: address)
        case (.rightBattery, .percentage(let percentage)):
            state.rightBattery = percentage
            notifyAboutLowBatteryIfNeeded(component: "Right", percentage: percentage, address: address)
        case (.caseBattery, .percentage(let percentage)):
            state.caseBattery = percentage
            notifyAboutLowBatteryIfNeeded(component: "Case", percentage: percentage, address: address)
        case (.firmware, .firmware(let firmware)): state.firmware = firmware
        case (.noiseControl, .noiseControl(let mode)):
            state.noiseControl = mode
            noteVerified(.noiseControl, for: address)
            if let expectedMode = pendingANCVerification[address] {
                let currentMode = PeatsReadValue.noiseControl(mode).displayValue
                let expected = PeatsReadValue.noiseControl(expectedMode).displayValue
                controlStatus[address] = mode == expectedMode
                    ? "ANC mode verified: \(currentMode)"
                    : "ANC state is \(currentMode), not the requested \(expected)"
                if mode == expectedMode {
                    recordVerifiedChange(setting: "ANC", value: currentMode, for: address)
                }
                pendingANCVerification[address] = nil
            }
        case (.gameMode, .toggle(let value)):
            state.gameMode = value
            noteVerified(.gameMode, for: address)
            if let expectedValue = pendingGameModeVerification[address] {
                controlStatus[address] = value == expectedValue
                    ? "Game Mode verified: \(value.displayValue)"
                    : "Game Mode is \(value.displayValue), not the requested \(expectedValue.displayValue)"
                if value == expectedValue {
                    recordVerifiedChange(setting: "Game Mode", value: value.displayValue, for: address)
                }
                pendingGameModeVerification[address] = nil
            }
        case (.multipoint, .toggle(let value)):
            state.multipoint = value
            noteVerified(.multipoint, for: address)
            if let expectedValue = pendingMultipointVerification[address] {
                controlStatus[address] = value == expectedValue
                    ? "Multipoint verified: \(value.displayValue)"
                    : "Multipoint is \(value.displayValue), not the requested \(expectedValue.displayValue)"
                if value == expectedValue {
                    recordVerifiedChange(setting: "Multipoint", value: value.displayValue, for: address)
                }
                pendingMultipointVerification[address] = nil
            }
        case (.touchLock, .toggle(let value)):
            state.touchLock = value
            noteVerified(.touchLock, for: address)
            if let expectedValue = pendingTouchLockVerification[address] {
                controlStatus[address] = value == expectedValue
                    ? "Touch Lock verified: \(value.displayValue)"
                    : "Touch Lock is \(value.displayValue), not the requested \(expectedValue.displayValue)"
                if value == expectedValue {
                    recordVerifiedChange(setting: "Touch Lock", value: value.displayValue, for: address)
                }
                pendingTouchLockVerification[address] = nil
            }
        case (.promptVolume, .unsignedByte(let value)):
            state.promptVolume = value
            noteVerified(.promptVolume, for: address)
            verifyByte(.promptVolume, value: value, for: address)
        case (.noiseControlStrength, .unsignedByte(let value)):
            state.noiseControlStrength = value
            noteVerified(.noiseControlStrength, for: address)
            verifyByte(.noiseControlStrength, value: value, for: address)
        case (.transparencyLevel, .unsignedByte(let value)):
            state.transparencyLevel = value
            noteVerified(.transparencyLevel, for: address)
            verifyByte(.transparencyLevel, value: value, for: address)
        case (.voicePackage, .unsignedByte(let value)):
            state.voicePackage = value
            noteVerified(.voicePackage, for: address)
            verifyByte(.voicePackage, value: value, for: address)
        case (.ldac, .toggle(let value)):
            state.ldac = value
            noteVerified(.ldac, for: address)
            if let expectedValue = pendingLDACVerification[address] {
                controlStatus[address] = value == expectedValue
                    ? "LDAC verified: \(value.displayValue)"
                    : "LDAC is \(value.displayValue), not the requested \(expectedValue.displayValue)"
                pendingLDACVerification[address] = nil
            }
        case (.leAudio, .toggle(let value)):
            state.leAudio = value
            noteVerified(.leAudio, for: address)
            if let expectedValue = pendingLEAudioVerification[address] {
                controlStatus[address] = value == expectedValue
                    ? "LE Audio verified: \(value.displayValue)"
                    : "LE Audio is \(value.displayValue), not the requested \(expectedValue.displayValue)"
                pendingLEAudioVerification[address] = nil
            }
        default: break
        }
        coreDeviceStatus[address] = state
        persistLastKnownStatus(state, for: address)
    }

    private func scheduleANCReadBack(for address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.pendingANCVerification[address] != nil else { return }
            self.read([.noiseControl], for: address, channelID: 1)
        }
    }

    private func scheduleGameModeReadBack(for address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.pendingGameModeVerification[address] != nil else { return }
            self.read([.gameMode], for: address, channelID: 1)
        }
    }

    private func scheduleMultipointReadBack(for address: String) {
        Task { @MainActor [weak self] in
            // Multipoint intentionally restarts the earbud connection. Wait for
            // it to come back before opening exactly one live read session.
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.pendingMultipointVerification[address] != nil else { return }
            for _ in 0..<10 {
                self.refreshPairedDevices()
                if self.pairedDevice(with: address)?.isConnected() == true {
                    self.read([.multipoint], for: address, channelID: 1)
                    self.expireMultipointVerification(for: address)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
                guard self.pendingMultipointVerification[address] != nil else { return }
            }
            self.pendingMultipointVerification[address] = nil
            self.controlStatus[address] = "Multipoint changed, but the earbuds did not reconnect in time. The app remains ready after they reconnect."
        }
    }

    private func expireMultipointVerification(for address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(14))
            guard let self, self.pendingMultipointVerification[address] != nil else { return }
            self.pendingMultipointVerification[address] = nil
            self.controlStatus[address] = "Multipoint reconnected, but its live state could not be read. The app is ready to use."
        }
    }

    private func scheduleTouchLockReadBack(for address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.pendingTouchLockVerification[address] != nil else { return }
            self.read([.touchLock], for: address, channelID: 1)
        }
    }

    private func finishByteWrite(_ setting: ByteControlSetting, for address: String, shouldReadBack: Bool) {
        byteControlInProgress[address]?.remove(setting)
        if byteControlInProgress[address]?.isEmpty == true {
            byteControlInProgress[address] = nil
        }
        guard shouldReadBack else {
            pendingByteVerification[address]?[setting] = nil
            return
        }
        scheduleByteReadBack(setting, for: address)
    }

    private func scheduleByteReadBack(_ setting: ByteControlSetting, for address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.pendingByteVerification[address]?[setting] != nil else { return }
            self.read([setting.readCommand], for: address, channelID: 1)
        }
    }

    private func scheduleLDACReadBack(for address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.pendingLDACVerification[address] != nil else { return }
            self.read([.ldac], for: address, channelID: 1)
        }
    }

    private func scheduleLEAudioReadBack(for address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.pendingLEAudioVerification[address] != nil else { return }
            self.read([.leAudio], for: address, channelID: 1)
        }
    }

    private func verifyByte(_ setting: ByteControlSetting, value: UInt8, for address: String) {
        guard let expectedValue = pendingByteVerification[address]?[setting] else { return }
        controlStatus[address] = value == expectedValue
            ? "\(setting.title) verified: \(value)"
            : "\(setting.title) is \(value), not the requested \(expectedValue)"
        if value == expectedValue {
            recordVerifiedChange(setting: setting.title, value: "\(value)", for: address)
        }
        pendingByteVerification[address]?[setting] = nil
    }

    private func startConnectionMonitor() {
        connectionMonitorTask?.cancel()
        connectionMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard let self, !Task.isCancelled else { return }
                self.refreshPairedDevices()
                self.handleConnectionChanges()
            }
        }
    }

    private func handleConnectionChanges() {
        for device in pairedDevices where device.isSoundPEATS {
            let previous = lastConnectionState[device.address]
            lastConnectionState[device.address] = device.isConnected
            guard previous == false, device.isConnected else { continue }
            guard !hasPendingControlVerification(for: device.address) else { continue }
            controlStatus[device.address] = "Reconnected. Refreshing live status…"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self,
                      self.pairedDevice(with: device.address)?.isConnected() == true,
                      !self.hasPendingControlVerification(for: device.address) else { return }
                self.refreshCoreDeviceStatus(for: device.address)
            }
        }
    }

    private func notifyAboutLowBatteryIfNeeded(component: String, percentage: Int, address: String) {
        let key = "\(address).\(component)"
        if percentage > 25 {
            lowBatteryNotificationKeys.remove(key)
            return
        }
        guard lowBatteryNotificationsEnabled, percentage <= 20,
              !lowBatteryNotificationKeys.contains(key) else { return }
        lowBatteryNotificationKeys.insert(key)
        let content = UNMutableNotificationContent()
        content.title = "SOUNDPEATS Q3 Pro battery low"
        content.body = "\(component) battery is at \(percentage)%"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "peatsProbe.\(key)", content: content, trigger: nil)
        )
    }

    private func recordVerifiedChange(setting: String, value: String, for address: String) {
        verifiedHistory.insert(
            VerifiedSettingHistoryEntry(id: UUID(), address: address, setting: setting, value: value, date: Date()),
            at: 0
        )
        verifiedHistory = Array(verifiedHistory.prefix(100))
        persistLocalState()
    }

    private func loadLocalState() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "peatsProbe.verifiedHistory.v1"),
           let history = try? decoder.decode([VerifiedSettingHistoryEntry].self, from: data) {
            verifiedHistory = history
        }
        if let data = UserDefaults.standard.data(forKey: "peatsProbe.savedProfiles.v1"),
           let profiles = try? decoder.decode([SavedProfile].self, from: data) {
            savedProfiles = profiles
        }
    }

    private func persistLocalState() {
        let encoder = JSONEncoder()
        UserDefaults.standard.set(
            try? encoder.encode(verifiedHistory),
            forKey: "peatsProbe.verifiedHistory.v1"
        )
        UserDefaults.standard.set(
            try? encoder.encode(savedProfiles),
            forKey: "peatsProbe.savedProfiles.v1"
        )
    }

    private func loadLastKnownStatus(for address: String) {
        guard coreDeviceStatus[address] == nil,
              let data = UserDefaults.standard.data(forKey: "peatsProbe.lastKnownStatus.\(address)"),
              let status = try? JSONDecoder().decode(CoreDeviceStatus.self, from: data) else { return }
        coreDeviceStatus[address] = status
    }

    private func persistLastKnownStatus(_ status: CoreDeviceStatus, for address: String) {
        UserDefaults.standard.set(
            try? JSONEncoder().encode(status),
            forKey: "peatsProbe.lastKnownStatus.\(address)"
        )
    }

    private func loadCachedServices(for address: String) {
        guard let device = pairedDevice(with: address) else { return }
        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        classicServices[address] = records.enumerated().map { index, record in
            var channel: BluetoothRFCOMMChannelID = 0
            let hasRFCOMMChannel = record.getRFCOMMChannelID(&channel) == kIOReturnSuccess
            return ClassicService(
                id: "\(address)-\(index)-\(record.getServiceName() ?? "unnamed")",
                name: record.getServiceName() ?? "Unnamed Bluetooth service",
                rfcommChannel: hasRFCOMMChannel ? channel : nil
            )
        }
        serviceDiscoveryStatus[address] = records.isEmpty
            ? "No SDP services returned. This model may hide its control service."
            : "Found \(records.count) Bluetooth service\(records.count == 1 ? "" : "s")"
    }

    private func pairedDevice(with address: String) -> IOBluetoothDevice? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.first { $0.addressString == address }
    }

    private func updateState(for managerState: CBManagerState) {
        state = switch managerState {
        case .poweredOn: .ready
        case .poweredOff: .unavailable("Bluetooth is turned off")
        case .unauthorized: .unavailable("Bluetooth access was not granted")
        case .unsupported: .unavailable("This Mac does not support Bluetooth LE")
        case .resetting: .unavailable("Bluetooth is resetting—try again shortly")
        case .unknown: .starting
        @unknown default: .unavailable("Bluetooth reported an unknown state")
        }
    }

    private func publishDevices() {
        devices = deviceIndex.values.sorted {
            if $0.isSoundPEATS != $1.isSoundPEATS { return $0.isSoundPEATS }
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

extension BluetoothScanner: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateState(for: central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let fallbackName = peripheral.name ?? "Unnamed Bluetooth device"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { $0.uuidString }
            .sorted()
        deviceIndex[peripheral.identifier] = Device(
            id: peripheral.identifier,
            name: advertisedName ?? fallbackName,
            rssi: RSSI.intValue,
            lastSeen: Date(),
            advertisedServices: services
        )
        publishDevices()
    }
}
