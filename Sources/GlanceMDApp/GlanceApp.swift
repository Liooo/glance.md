import AppKit
import ApplicationServices
import Carbon
import GlanceMDCore
import ServiceManagement
import SwiftUI
import WebKit

@main
@MainActor
enum GlanceMDMain {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let renderer = MarkdownRenderer()
    private let selectionReader = SelectionReader()
    private let preferences = PreferencesStore()
    private var statusItem: NSStatusItem?
    private var previewPanel: PreviewPanelController?
    private var hotKeyManager: HotKeyManager?
    private var settingsWindow: NSWindow?
    private var settingsViewModel: SettingsViewModel?
    private var onboardingWindow: NSWindow?
    private var onboardingViewModel: OnboardingViewModel?
    private var systemAppearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_: Notification) {
        observeSystemAppearance()
        applyAppearanceMode()
        previewPanel = PreviewPanelController(renderer: renderer, preferences: preferences)
        configureAppIcon()
        configureStatusItem()
        configureHotKeys()

        if !OnboardingState.isCompleted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_: Notification) {
        hotKeyManager?.stop()
        systemAppearanceObservation?.invalidate()
    }

    func applyTriggerPreferences() {
        hotKeyManager?.updateHotkeys(
            selectedText: preferences.selectedTextHotkey,
            clipboard: preferences.clipboardHotkey
        )
    }

    private func configureHotKeys() {
        let manager = HotKeyManager(
            selectedTextHotkey: preferences.selectedTextHotkey,
            clipboardHotkey: preferences.clipboardHotkey
        ) { [weak self] action in
            Task { @MainActor in
                switch action {
                case .selectedText:
                    self?.toggleSelectedMarkdown()
                case .clipboard:
                    self?.previewClipboard()
                }
            }
        }
        hotKeyManager = manager
        manager.start()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image =
            AppAssets.menuBarIcon()
            ?? NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "Glance.md")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(
            menuItem(
                title: "Preview Selection", action: #selector(previewSelectionFromMenu),
                keyEquivalent: ""))
        menu.addItem(
            menuItem(
                title: "Preview Clipboard", action: #selector(previewClipboardFromMenu),
                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Glance.md", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func configureAppIcon() {
        guard let image = AppAssets.appIcon() else {
            return
        }

        NSApplication.shared.applicationIconImage = image
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func previewSelectionFromMenu() {
        toggleSelectedMarkdown()
    }

    @objc private func previewClipboardFromMenu() {
        previewClipboard()
    }

    @objc private func requestAccessibilityPermission() {
        showOnboarding()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let viewModel = SettingsViewModel(preferences: preferences)
            viewModel.onHotkeysChange = { [weak self] selectedText, clipboard in
                self?.preferences.selectedTextHotkey = selectedText
                self?.preferences.clipboardHotkey = clipboard
                self?.applyTriggerPreferences()
            }
            viewModel.onAppearanceModeChange = { [weak self] appearanceMode in
                self?.preferences.appearanceMode = appearanceMode
                self?.applyAppearanceMode()
            }
            viewModel.onRecordingStateChange = { [weak self] isRecording in
                self?.hotKeyManager?.setEnabled(!isRecording)
            }
            settingsViewModel = viewModel

            let settingsView = SettingsView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Glance.md - Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        settingsViewModel?.refreshPermissions()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func applyAppearanceMode() {
        AppAppearance.apply(preferences.appearanceMode)
        settingsWindow?.appearance = preferences.appearanceMode.nsAppearance
        settingsViewModel?.refreshSystemColorScheme()
        previewPanel?.applyAppearanceMode(preferences.appearanceMode)
    }

    private func observeSystemAppearance() {
        systemAppearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance, options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.preferences.appearanceMode == .system else {
                    return
                }
                self.settingsViewModel?.refreshSystemColorScheme()
                self.previewPanel?.applyAppearanceMode(.system)
            }
        }
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let viewModel = OnboardingViewModel(preferences: preferences)
            viewModel.onComplete = { [weak self] in
                self?.dismissOnboarding()
            }
            viewModel.onHotkeysChange = { [weak self] selectedText in
                self?.preferences.selectedTextHotkey = selectedText
                self?.settingsViewModel?.selectedTextHotkey = selectedText
                self?.applyTriggerPreferences()
            }
            viewModel.onRecordingStateChange = { [weak self] isRecording in
                self?.hotKeyManager?.setEnabled(!isRecording)
            }
            viewModel.onAccessibilityGranted = { [weak self] in
                self?.hotKeyManager?.refreshAfterAccessibilityGranted()
                self?.settingsViewModel?.refreshPermissions()
                self?.bringOnboardingToFront()
            }
            viewModel.onClose = { [weak self] in
                self?.dismissOnboarding()
            }
            onboardingViewModel = viewModel

            let onboardingView = OnboardingView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: onboardingView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Glance.md"
            window.styleMask = [.titled, .closable]
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }

        onboardingViewModel?.refreshPermissions()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func dismissOnboarding() {
        onboardingViewModel?.stopMonitoring()
        onboardingWindow?.close()
        onboardingWindow = nil
        onboardingViewModel = nil
    }

    private func bringOnboardingToFront() {
        guard let window = onboardingWindow else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func previewClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            previewPanel?.showMessage("Clipboard is empty", near: TriggerReason.hotKey.location)
            return
        }

        previewPanel?.show(
            markdown: MarkdownInputNormalizer.normalize(text), near: TriggerReason.hotKey.location)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func toggleSelectedMarkdown() {
        guard previewPanel?.isVisible != true else {
            appLog("closing preview")
            previewPanel?.closeFromToggle()
            return
        }

        appLog("opening preview")
        showSelectedMarkdown(reason: .hotKey)
    }

    private func showSelectedMarkdown(reason: TriggerReason) {
        guard selectionReader.isTrusted else {
            showOnboarding()
            previewPanel?.showMessage("Accessibility permission required", near: reason.location)
            return
        }

        guard let text = selectionReader.selectedText(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            appLog("no selected text")
            previewPanel?.hide()
            return
        }

        appLog("selection captured via accessibility: \(text.count) chars")
        previewPanel?.show(markdown: MarkdownInputNormalizer.normalize(text), near: reason.location)
    }
}

private func appLog(_ message: String) {
    fputs("[glance.md] \(message)\n", stderr)
}

private enum TriggerReason {
    case hotKey

    var location: CGPoint {
        NSEvent.mouseLocation
    }
}

private enum AppAssets {
    static func appIcon() -> NSImage? {
        image(named: "AppIcon", extension: "png")
    }

    static func menuBarIcon() -> NSImage? {
        guard let image = image(named: "MenuBarIconTemplate", extension: "png") else {
            return nil
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Glance.md"
        return image
    }

    private static func image(named name: String, extension pathExtension: String) -> NSImage? {
        guard
            let url = AppResourceBundle.bundle.url(forResource: name, withExtension: pathExtension)
        else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private enum AppResourceBundle {
    static let bundle: Bundle = {
        if let bundledURL = Bundle.main.url(
            forResource: "glance-md_GlanceMDApp", withExtension: "bundle"),
            let bundled = Bundle(url: bundledURL)
        {
            return bundled
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        let adjacentURL = executableURL.appendingPathComponent("glance-md_GlanceMDApp.bundle")
        if let adjacent = Bundle(url: adjacentURL) {
            return adjacent
        }

        return Bundle.main
    }()
}

final class SelectionReader {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermissionPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)

        guard focusedStatus == .success, let focused = focusedValue else {
            return nil
        }

        let focusedElement = focused as! AXUIElement
        if let text = stringAttribute(kAXSelectedTextAttribute, element: focusedElement),
            !text.isEmpty
        {
            return text
        }

        if let text = selectedTextFromFocusedApplication() {
            return text
        }

        return nil
    }

    private func selectedTextFromFocusedApplication() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let text = stringAttribute(kAXSelectedTextAttribute, element: appElement), !text.isEmpty
        {
            return text
        }

        return nil
    }

    private func stringAttribute(_ attribute: String, element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard status == .success else {
            return nil
        }

        return value as? String
    }
}

final class PreferencesStore {
    private enum Key {
        static let legacyHotKeyShortcut = "hotKeyShortcut"
        static let selectedTextHotkey = "selectedTextHotkey"
        static let selectedTextHotkeyCleared = "selectedTextHotkeyCleared"
        static let clipboardHotkey = "clipboardHotkey"
        static let appearanceMode = "appearanceMode"
        static let rememberPreviewSize = "rememberPreviewSize"
        static let previewWidth = "previewWidth"
        static let previewHeight = "previewHeight"
    }

    var selectedTextHotkey: RecordedHotkey? {
        get {
            if UserDefaults.standard.bool(forKey: Key.selectedTextHotkeyCleared) {
                return nil
            }
            if let hotkey = loadHotkey(forKey: Key.selectedTextHotkey) {
                return hotkey
            }
            if let legacy = legacyHotkey() {
                return legacy
            }
            return .defaultSelectedText
        }
        set {
            saveHotkey(newValue, forKey: Key.selectedTextHotkey)
            UserDefaults.standard.set(newValue == nil, forKey: Key.selectedTextHotkeyCleared)
        }
    }

    var clipboardHotkey: RecordedHotkey? {
        get {
            loadHotkey(forKey: Key.clipboardHotkey)
        }
        set {
            saveHotkey(newValue, forKey: Key.clipboardHotkey)
        }
    }

    var appearanceMode: AppearanceMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Key.appearanceMode),
                let mode = AppearanceMode(rawValue: rawValue)
            else {
                return .system
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.appearanceMode)
        }
    }

    var rememberPreviewSize: Bool {
        get {
            UserDefaults.standard.bool(forKey: Key.rememberPreviewSize)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.rememberPreviewSize)
            if !newValue {
                previewSize = nil
            }
        }
    }

    var previewSize: NSSize? {
        get {
            let width = UserDefaults.standard.double(forKey: Key.previewWidth)
            let height = UserDefaults.standard.double(forKey: Key.previewHeight)
            guard width > 0, height > 0 else {
                return nil
            }
            return NSSize(width: width, height: height)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: Key.previewWidth)
                UserDefaults.standard.removeObject(forKey: Key.previewHeight)
                return
            }
            UserDefaults.standard.set(newValue.width, forKey: Key.previewWidth)
            UserDefaults.standard.set(newValue.height, forKey: Key.previewHeight)
        }
    }

    private func loadHotkey(forKey key: String) -> RecordedHotkey? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(RecordedHotkey.self, from: data)
    }

    private func saveHotkey(_ hotkey: RecordedHotkey?, forKey key: String) {
        guard let hotkey, let data = try? JSONEncoder().encode(hotkey) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func legacyHotkey() -> RecordedHotkey? {
        guard let rawValue = UserDefaults.standard.string(forKey: Key.legacyHotKeyShortcut),
            let shortcut = LegacyHotKeyShortcut(rawValue: rawValue)
        else {
            return nil
        }
        return RecordedHotkey(
            keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, isDoubleTap: false,
            doubleTapKey: nil)
    }
}

private enum LegacyHotKeyShortcut: String {
    case commandOptionM
    case commandShiftM
    case controlOptionM

    var keyCode: UInt32 {
        UInt32(kVK_ANSI_M)
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandOptionM:
            UInt32(cmdKey | optionKey)
        case .commandShiftM:
            UInt32(cmdKey | shiftKey)
        case .controlOptionM:
            UInt32(controlKey | optionKey)
        }
    }
}

enum HotKeyAction: UInt32, CaseIterable {
    case selectedText = 1
    case clipboard = 2
}

enum DoubleTapKey: String, Codable, CaseIterable {
    case fn
    case control
    case option
    case shift
    case command

    var displayName: String {
        switch self {
        case .fn:
            "Fn"
        case .control:
            "Control"
        case .option:
            "Option"
        case .shift:
            "Shift"
        case .command:
            "Command"
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .fn:
            .maskSecondaryFn
        case .control:
            .maskControl
        case .option:
            .maskAlternate
        case .shift:
            .maskShift
        case .command:
            .maskCommand
        }
    }
}

struct RecordedHotkey: Codable, Equatable {
    var keyCode: UInt32?
    var modifiers: UInt32?
    var isDoubleTap: Bool
    var doubleTapKey: DoubleTapKey?

    static let defaultSelectedText = RecordedHotkey(
        keyCode: UInt32(kVK_ANSI_M),
        modifiers: UInt32(cmdKey | optionKey),
        isDoubleTap: false,
        doubleTapKey: nil
    )

    var displayString: String {
        if isDoubleTap, let doubleTapKey {
            return "Double-tap \(doubleTapKey.displayName)"
        }

        var parts: [String] = []
        if let modifiers {
            if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
            if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
            if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
            if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        }
        if let keyCode {
            parts.append(Self.keyCodeToString(keyCode))
        }
        return parts.isEmpty ? "Not set" : parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

enum OnboardingState {
    private static let completedKey = "hasCompletedOnboarding"

    static var isCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }
}

enum AccessibilityHelper {
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    static func openSystemSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "Use System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var documentTheme: String? {
        switch self {
        case .system:
            nil
        case .light:
            "light"
        case .dark:
            "dark"
        }
    }

    var previewBackgroundColor: NSColor {
        switch self {
        case .system:
            NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        case .light:
            NSColor(white: 0.98, alpha: 0.95)
        case .dark:
            NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.94)
        }
    }
}

@MainActor
enum AppAppearance {
    static func apply(_ mode: AppearanceMode) {
        NSApplication.shared.appearance = mode.nsAppearance
    }

    static var systemColorScheme: ColorScheme {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark : .light
    }
}

enum HotkeyRecordingTarget {
    case selectedText
    case clipboard
}

@MainActor
final class SettingsViewModel: ObservableObject {
    private let preferences: PreferencesStore

    @Published var selectedTextHotkey: RecordedHotkey?
    @Published var clipboardHotkey: RecordedHotkey?
    @Published var appearanceMode: AppearanceMode {
        didSet { onAppearanceModeChange?(appearanceMode) }
    }
    @Published private var systemColorScheme = AppAppearance.systemColorScheme
    @Published var isRecordingSelectedText = false
    @Published var isRecordingClipboard = false
    @Published var hasAccessibilityPermission = AccessibilityHelper.hasPermission
    @Published var rememberPreviewSize: Bool {
        didSet { preferences.rememberPreviewSize = rememberPreviewSize }
    }
    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }

    var onHotkeysChange: ((RecordedHotkey?, RecordedHotkey?) -> Void)?
    var onAppearanceModeChange: ((AppearanceMode) -> Void)?
    var onRecordingStateChange: ((Bool) -> Void)?

    var settingsColorScheme: ColorScheme {
        appearanceMode.colorScheme ?? systemColorScheme
    }

    private var currentRecordingTarget: HotkeyRecordingTarget?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var lastModifierPressTime: Date?
    private var lastModifierFlags: NSEvent.ModifierFlags = []

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        selectedTextHotkey = preferences.selectedTextHotkey
        clipboardHotkey = preferences.clipboardHotkey
        appearanceMode = preferences.appearanceMode
        rememberPreviewSize = preferences.rememberPreviewSize
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    deinit {
        MainActor.assumeIsolated {
            stopRecording()
        }
    }

    func refreshPermissions() {
        hasAccessibilityPermission = AccessibilityHelper.hasPermission
    }

    func refreshSystemColorScheme() {
        systemColorScheme = AppAppearance.systemColorScheme
    }

    func requestAccessibilityPermission() {
        AccessibilityHelper.openSystemSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshPermissions()
        }
    }

    func startRecording(for target: HotkeyRecordingTarget) {
        stopRecording()
        currentRecordingTarget = target
        lastModifierPressTime = nil
        lastModifierFlags = []
        isRecordingSelectedText = target == .selectedText
        isRecordingClipboard = target == .clipboard
        onRecordingStateChange?(true)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handleKeyEvent(event)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            self?.stopRecording()
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopRecording()
            }
        }
    }

    func stopRecording() {
        removeMonitor(&localKeyMonitor)
        removeMonitor(&globalKeyMonitor)
        removeMonitor(&localClickMonitor)
        removeMonitor(&globalClickMonitor)
        isRecordingSelectedText = false
        isRecordingClipboard = false
        currentRecordingTarget = nil
        onRecordingStateChange?(false)
    }

    func clear(_ target: HotkeyRecordingTarget) {
        switch target {
        case .selectedText:
            selectedTextHotkey = nil
        case .clipboard:
            clipboardHotkey = nil
        }
        saveHotkeys()
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard let target = currentRecordingTarget else {
            return
        }

        if event.type == .flagsChanged {
            let currentFlags = event.modifierFlags.intersection([
                .command, .option, .control, .shift, .function,
            ])
            if !lastModifierFlags.isEmpty && currentFlags.isEmpty {
                let now = Date()
                if let lastModifierPressTime,
                    now.timeIntervalSince(lastModifierPressTime) < 0.3
                {
                    record(
                        RecordedHotkey(
                            keyCode: nil, modifiers: nil, isDoubleTap: true,
                            doubleTapKey: detectDoubleTapKey(from: lastModifierFlags)),
                        for: target
                    )
                    return
                }
                lastModifierPressTime = now
            }
            lastModifierFlags = currentFlags
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        var carbonModifiers: UInt32 = 0
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        record(
            RecordedHotkey(
                keyCode: UInt32(event.keyCode), modifiers: carbonModifiers, isDoubleTap: false,
                doubleTapKey: nil),
            for: target
        )
    }

    private func record(_ hotkey: RecordedHotkey, for target: HotkeyRecordingTarget) {
        switch target {
        case .selectedText:
            selectedTextHotkey = hotkey
            if clipboardHotkey == hotkey {
                clipboardHotkey = nil
            }
        case .clipboard:
            clipboardHotkey = hotkey
            if selectedTextHotkey == hotkey {
                selectedTextHotkey = nil
            }
        }
        saveHotkeys()
        stopRecording()
    }

    private func saveHotkeys() {
        onHotkeysChange?(selectedTextHotkey, clipboardHotkey)
    }

    private func detectDoubleTapKey(from flags: NSEvent.ModifierFlags) -> DoubleTapKey {
        if flags.contains(.function) { return .fn }
        if flags.contains(.command) { return .command }
        if flags.contains(.option) { return .option }
        if flags.contains(.control) { return .control }
        if flags.contains(.shift) { return .shift }
        return .fn
    }

    private func removeMonitor(_ monitor: inout Any?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appLog("failed to update launch at login: \(error)")
        }
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var hasAccessibilityPermission = AccessibilityHelper.hasPermission
    @Published var selectedTextHotkey: RecordedHotkey?
    @Published var isRecordingSelectedText = false

    var onComplete: (() -> Void)?
    var onClose: (() -> Void)?
    var onHotkeysChange: ((RecordedHotkey?) -> Void)?
    var onRecordingStateChange: ((Bool) -> Void)?
    var onAccessibilityGranted: (() -> Void)?

    private var timer: Timer?
    private var lastAccessibilityPermission = AccessibilityHelper.hasPermission
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var lastModifierPressTime: Date?
    private var lastModifierFlags: NSEvent.ModifierFlags = []

    init(preferences: PreferencesStore) {
        selectedTextHotkey = preferences.selectedTextHotkey
    }

    var canFinish: Bool {
        hasAccessibilityPermission && selectedTextHotkey != nil
    }

    func startMonitoring() {
        guard timer == nil else {
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        stopRecording()
    }

    func refreshPermissions() {
        let newPermission = AccessibilityHelper.hasPermission
        if newPermission && !lastAccessibilityPermission {
            onAccessibilityGranted?()
        }
        lastAccessibilityPermission = newPermission
        hasAccessibilityPermission = newPermission
    }

    func requestAccessibilityPermission() {
        AccessibilityHelper.openSystemSettings()
    }

    func completeOnboarding() {
        guard canFinish else {
            return
        }
        OnboardingState.isCompleted = true
        onComplete?()
    }

    func closeOnboarding() {
        onClose?()
    }

    func startRecording() {
        stopRecording()
        lastModifierPressTime = nil
        lastModifierFlags = []
        isRecordingSelectedText = true
        onRecordingStateChange?(true)

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handleKeyEvent(event)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            self?.stopRecording()
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopRecording()
            }
        }
    }

    func stopRecording() {
        removeMonitor(&localKeyMonitor)
        removeMonitor(&globalKeyMonitor)
        removeMonitor(&localClickMonitor)
        removeMonitor(&globalClickMonitor)
        isRecordingSelectedText = false
        onRecordingStateChange?(false)
    }

    func clearHotkey() {
        selectedTextHotkey = nil
        onHotkeysChange?(nil)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            let currentFlags = event.modifierFlags.intersection([
                .command, .option, .control, .shift, .function,
            ])
            if !lastModifierFlags.isEmpty && currentFlags.isEmpty {
                let now = Date()
                if let lastModifierPressTime,
                    now.timeIntervalSince(lastModifierPressTime) < 0.3
                {
                    record(
                        RecordedHotkey(
                            keyCode: nil, modifiers: nil, isDoubleTap: true,
                            doubleTapKey: detectDoubleTapKey(from: lastModifierFlags)))
                    return
                }
                lastModifierPressTime = now
            }
            lastModifierFlags = currentFlags
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        var carbonModifiers: UInt32 = 0
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        record(
            RecordedHotkey(
                keyCode: UInt32(event.keyCode), modifiers: carbonModifiers, isDoubleTap: false,
                doubleTapKey: nil))
    }

    private func record(_ hotkey: RecordedHotkey) {
        selectedTextHotkey = hotkey
        onHotkeysChange?(hotkey)
        stopRecording()
    }

    private func detectDoubleTapKey(from flags: NSEvent.ModifierFlags) -> DoubleTapKey {
        if flags.contains(.function) { return .fn }
        if flags.contains(.command) { return .command }
        if flags.contains(.option) { return .option }
        if flags.contains(.control) { return .control }
        if flags.contains(.shift) { return .shift }
        return .fn
    }

    private func removeMonitor(_ monitor: inout Any?) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                generalSection
                appearanceSection
                hotkeySection
                previewSection
                permissionsSection
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 450, height: 480)
        .preferredColorScheme(viewModel.settingsColorScheme)
        .background(settingsBackground)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)
            Toggle("Launch at Login", isOn: $viewModel.launchAtLogin)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsSectionBackground)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.headline)
            HStack {
                Text("Theme")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Picker("Theme", selection: $viewModel.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsSectionBackground)
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hotkeys")
                .font(.headline)
            hotkeyRow(
                title: "Preview selected text",
                subtitle: "Render selected Markdown",
                hotkey: $viewModel.selectedTextHotkey,
                isRecording: $viewModel.isRecordingSelectedText,
                onClear: { viewModel.clear(.selectedText) },
                onStartRecording: { viewModel.startRecording(for: .selectedText) }
            )
            hotkeyRow(
                title: "Preview clipboard content",
                subtitle: "Render Markdown from the clipboard",
                hotkey: $viewModel.clipboardHotkey,
                isRecording: $viewModel.isRecordingClipboard,
                onClear: { viewModel.clear(.clipboard) },
                onStartRecording: { viewModel.startRecording(for: .clipboard) }
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsSectionBackground)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Misc")
                .font(.headline)
            Toggle("Remember preview popover size", isOn: $viewModel.rememberPreviewSize)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsSectionBackground)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)
            PermissionRow(
                title: "Accessibility",
                isGranted: viewModel.hasAccessibilityPermission,
                action: viewModel.requestAccessibilityPermission
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsSectionBackground)
    }

    private var settingsBackground: Color {
        viewModel.settingsColorScheme == .dark
            ? Color(white: 0.11) : Color(NSColor.windowBackgroundColor)
    }

    private var settingsSectionBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                viewModel.settingsColorScheme == .dark
                    ? Color.white.opacity(0.055) : Color.black.opacity(0.035))
    }

    private func hotkeyRow(
        title: String,
        subtitle: String,
        hotkey: Binding<RecordedHotkey?>,
        isRecording: Binding<Bool>,
        onClear: @escaping () -> Void,
        onStartRecording: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HotkeyRecorderButton(
                hotkey: hotkey,
                isRecording: isRecording,
                onClear: onClear,
                onStartRecording: onStartRecording
            )
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var sampleText = sampleMarkdown
    @State private var selectAllSampleTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("3-Step Setup")
                    .font(.title)
                    .fontWeight(.semibold)
            }
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 14) {
                accessibilityStep
                hotkeyStep
                previewStep
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 14) {
                Text("Glance.md stays in the menu bar. Check Settings for additional tweaks.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    viewModel.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canFinish)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 520, height: 590)
        .onAppear { viewModel.startMonitoring() }
        .onDisappear { viewModel.stopMonitoring() }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("1. Grant Accessibility")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                if viewModel.hasAccessibilityPermission {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else {
                    Button("Open Accessibility") {
                        viewModel.requestAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("Enable GlanceMD so it can read selected text and listen for the preview hotkey.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 18)
        }
    }

    private var hotkeyStep: some View {
        HStack(spacing: 12) {
            Text("2. Click to change preview hotkey")
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            HotkeyRecorderButton(
                hotkey: $viewModel.selectedTextHotkey,
                isRecording: $viewModel.isRecordingSelectedText,
                onClear: viewModel.clearHotkey,
                onStartRecording: viewModel.startRecording
            )
        }
    }

    private var previewStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3. Select text and press hotkey")
                .font(.headline)
                .fontWeight(.bold)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Select All Text") {
                        selectAllSampleTrigger += 1
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                MarkdownSampleTextView(text: $sampleText, selectAllTrigger: $selectAllSampleTrigger)
                    .frame(height: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            }
            .padding(.leading, 18)
        }
    }

    private static let sampleMarkdown = """
        # Sample Markdown

        A **fast** preview for *Markdown* selections: _emphasis_, ~~strikethrough~~, `inline code`, a [web link](https://example.com), and <https://example.com> all get invited.

        Type any word to search, then use the arrows to hop between matches.

        ## Lists and Quotes

        > Quote
        > Continued quote

        - Unordered item
          - Nested unordered item
            - Third-level unordered item
        - Another unordered item
          1. Nested ordered item
             1. Third-level ordered item

        1. Ordered item
           1. Nested ordered item
              1. Third-level ordered item
        2. Another ordered item
           - Nested unordered item
             - Third-level unordered item

        - [x] Completed task
        - [ ] Pending task

        ### Code Sample

        ---

        The divider adds a tiny dramatic pause before the code block.

        ```swift
        struct HelloWorld {
            func run() {
                print("Hello, world!")
            }
        }

        HelloWorld().run()
        ```

        The compact table stays small on purpose.

        | Key | Value |
        | --- | ----- |
        | App | Glance.md |

        ### Wide Table

        This table is wide enough to make wrapped table auto parsing and horizontal scrolling earn its rent.

        | Feature | Heading | Emphasis | Lists | Tasks | Code | Links | Tables | Quotes | Divider | Width | Status |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | Example | `# Title` | `**bold**` | `- item` | `- [ ] item` | fenced block | autolink | pipe table | `> quote` | `---` | long row | Ready |
        | Coverage | section labels | bold and italic | three levels | checkbox items | plain text | URL text | many columns | multiline | horizontal rule | overflow check | Ready |
        | Notes | `## Section` | `_italic_` | mixed markers | completed item | inline code | web link | short table | nested quote | soft break | scroll row | Ready |
        | Preview | `### Detail` | `~~strike~~` | ordered list | pending item | code block | autolink | wide table | blockquote | separator | no wrap | Ready |
        | Layout | title text | styles | indentation | checkboxes | monospace | browser open | columns | callout | spacing | large table | Ready |
        | Reading | summary | contrast | hierarchy | progress | snippets | references | comparison | notes | sections | overflow | Ready |

        ### Mermaid Diagram

        Mermaid fences render as diagrams, with a code/preview toggle for peeking behind the curtain.

        ```mermaid
        sequenceDiagram
            participant User
            participant Glance
            participant Renderer
            User->>Glance: Select Markdown
            User->>Glance: Press hotkey
            Glance->>Renderer: Render preview
            Renderer-->>Glance: Diagram SVG
            Glance-->>User: Show preview
            User->>Glance: Toggle code
            Glance-->>User: Show Mermaid source
        ```

        A small Markdown mess assembled itself on the desk while notes, links, lists, tables, diagrams, and code snippets bumped elbows with stray reminders, borrowed headings, tiny decisions, half-finished thoughts, one suspiciously persistent bullet point, and a link that probably belonged somewhere else, then lined up just long enough to be searched, skimmed, resized, compared, copied into a meeting note, dragged through a surprisingly wide loong sentence that keeps going for layout testing, nudged across a few awkward window widths, inspected with unnecessary seriousness, and then blamed for absolutely nothing in particular.
        """
}

private struct HotkeyRecorderButton: View {
    @Binding var hotkey: RecordedHotkey?
    @Binding var isRecording: Bool
    let onClear: () -> Void
    let onStartRecording: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear hotkey")
            .opacity((hotkey != nil && !isRecording) ? 1 : 0)
            .allowsHitTesting(hotkey != nil && !isRecording)

            Button(action: {
                if !isRecording {
                    onStartRecording()
                }
            }) {
                Text(displayText)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
    }

    private var displayText: String {
        if isRecording {
            return "Press key..."
        }
        if let hotkey {
            return hotkey.displayString
        }
        return "Click to set"
    }
}

private struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct MarkdownSampleTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectAllTrigger: Int

    final class Coordinator {
        var handledSelectAllTrigger = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 16, height: 18)

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        DispatchQueue.main.async {
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
            DispatchQueue.main.async {
                textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
        }

        guard context.coordinator.handledSelectAllTrigger != selectAllTrigger else {
            return
        }

        context.coordinator.handledSelectAllTrigger = selectAllTrigger
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(
                NSRange(location: 0, length: (textView.string as NSString).length))
        }
    }
}

@MainActor
final class PreviewPanelController: NSObject, NSWindowDelegate, WKNavigationDelegate,
    WKScriptMessageHandler
{
    private static let defaultSize = NSSize(width: 348, height: 480)
    private let renderer: MarkdownRenderer
    private let preferences: PreferencesStore
    private let panel: PreviewWindow
    private let containerView = NSView()
    private let webView: PreviewWebView
    private let dragHandle = PreviewDragHandleView()
    private let searchBadge = SearchBadgeView()
    private var keyMonitor: Any?
    private var escapeEventTap: EscapeEventTap?
    private var searchQuery = ""
    private var searchToken = 0
    private var searchHitCount = 0
    private var activeHitIndex = -1
    private var currentMarkdown: String?
    private var mermaidRenderToken = 0
    private var mermaidScriptSource: String?
    private var previousApplication: NSRunningApplication?
    private var shouldRememberCurrentPanelSize = false
    private var isApplyingPanelFrame = false

    init(renderer: MarkdownRenderer, preferences: PreferencesStore) {
        self.renderer = renderer
        self.preferences = preferences

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = PreviewWebView(frame: .zero, configuration: configuration)
        webView.appearance = preferences.appearanceMode.nsAppearance
        panel = PreviewWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.appearance = preferences.appearanceMode.nsAppearance

        super.init()

        panel.delegate = self
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "quickMarkdownSearch")
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 13
        webView.layer?.masksToBounds = true

        configureContainerView()
        dragHandle.applyAppearanceMode(preferences.appearanceMode)
        configureKeyMonitor()
        configureEscapeEventTap()

        configureSearchBadge()
        containerView.addSubview(webView)
        containerView.addSubview(dragHandle)
        containerView.addSubview(searchBadge)

        containerView.translatesAutoresizingMaskIntoConstraints = true
        containerView.frame = NSRect(origin: .zero, size: Self.defaultSize)
        containerView.autoresizingMask = [.width, .height]
        panel.contentView = containerView
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: 280, height: 160)
        panel.onCopy = { [weak self] in
            self?.copySelection()
        }

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            dragHandle.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            dragHandle.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 7),
            dragHandle.widthAnchor.constraint(equalToConstant: 44),
            dragHandle.heightAnchor.constraint(equalToConstant: 18),

            searchBadge.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -10),
            searchBadge.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 9),
            searchBadge.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])
    }

    func show(markdown: String, near point: CGPoint) {
        resetSearch()
        currentMarkdown = markdown
        mermaidRenderToken += 1
        shouldRememberCurrentPanelSize = true
        webView.loadHTMLString(renderer.renderDocument(markdown), baseURL: nil)
        applyDocumentTheme()
        showPanel(near: point, size: preferredPreviewSize)
    }

    func showMessage(_ message: String, near point: CGPoint) {
        resetSearch()
        currentMarkdown = nil
        mermaidRenderToken += 1
        shouldRememberCurrentPanelSize = false
        let body = "<p>\(HTMLMessage.escape(message))</p>"
        webView.loadHTMLString(
            """
            <!doctype html><meta charset="utf-8"><style>
            :root {
              --bg: transparent;
              --fg: rgba(60, 60, 67, 0.68);
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: transparent;
                --fg: rgba(235, 235, 245, 0.62);
              }
            }
            html[data-theme="light"] {
              --bg: transparent;
              --fg: rgba(60, 60, 67, 0.68);
            }
            html[data-theme="dark"] {
              --bg: transparent;
              --fg: rgba(235, 235, 245, 0.62);
            }
            html, body {
              background: var(--bg);
              overflow: hidden;
            }
            body {
              margin: 0;
              padding: 0 16px;
              height: 44px;
              display: flex;
              align-items: center;
              justify-content: center;
              font: 13px -apple-system, BlinkMacSystemFont, sans-serif;
              color: var(--fg);
              text-align: center;
              white-space: nowrap;
            }
            p { margin: 0; }
            </style>\(body)
            """, baseURL: nil)
        applyDocumentTheme()
        showPanel(near: point, size: NSSize(width: 260, height: 44))
    }

    func hide() {
        // The preview is sticky by default. Only explicit toggles close it.
    }

    func applyAppearanceMode(_ mode: AppearanceMode) {
        webView.appearance = mode.nsAppearance
        panel.appearance = mode.nsAppearance
        applyPreviewBackground(for: mode)
        dragHandle.applyAppearanceMode(mode)
        applyDocumentTheme()
        reloadCurrentPreviewForMermaidThemeChange()
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func closeFromToggle() {
        closeAndRestoreFocus()
    }

    func containsScreenPoint(_ point: CGPoint) -> Bool {
        panel.isVisible && panel.frame.insetBy(dx: -3, dy: -3).contains(point)
    }

    func webView(
        _: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
            return
        }

        if let url = navigationAction.request.url, isSafeExternalLink(url) {
            NSWorkspace.shared.open(url)
        } else if let url = navigationAction.request.url {
            appLog("blocked non-web link: \(url.absoluteString)")
        }
        decisionHandler(.cancel)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        applyDocumentTheme()
        scheduleMermaidRenderIfNeeded()
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "quickMarkdownSearch",
            let payload = message.body as? [String: Any],
            let token = payload["token"] as? Int,
            token == searchToken,
            let count = payload["count"] as? Int
        else {
            return
        }

        searchHitCount = count
        if let active = payload["active"] as? Int {
            activeHitIndex = active
        }
        updateSearchBadge(isRunning: (payload["done"] as? Bool) != true)
    }

    func windowDidResize(_: Notification) {
        guard !isApplyingPanelFrame else {
            return
        }

        if shouldRememberCurrentPanelSize, preferences.rememberPreviewSize {
            preferences.previewSize = panel.frame.size
        }
        rerenderMermaidAfterResize()
    }

    private func showPanel(near point: CGPoint, size: NSSize = PreviewPanelController.defaultSize) {
        let origin = clampedOrigin(near: point, size: size)
        let frame = NSRect(origin: origin, size: size)
        applyPanelFrame(frame)
        rememberFrontmostApplication()
        escapeEventTap?.setActive(true)

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
        if panel.frame.width == 0 || panel.frame.height == 0 {
            applyPanelFrame(frame)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else {
                return
            }

            if self.panel.frame.width == 0 || self.panel.frame.height == 0 {
                self.applyPanelFrame(frame)
            }
        }
    }

    private func applyDocumentTheme() {
        webView.evaluateJavaScript(documentThemeScript(for: preferences.appearanceMode))
    }

    private func scheduleMermaidRenderIfNeeded() {
        mermaidRenderToken += 1
        let token = mermaidRenderToken
        webView.evaluateJavaScript("document.querySelector('[data-qm-mermaid]') !== null") {
            [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self,
                    token == self.mermaidRenderToken,
                    result as? Bool == true
                else {
                    return
                }

                self.renderMermaid(token: token)
            }
        }
    }

    private func renderMermaid(token: Int) {
        guard token == mermaidRenderToken else {
            return
        }

        ensureMermaidLoaded(token: token) { [weak self] in
            guard let self, token == self.mermaidRenderToken else {
                return
            }

            self.webView.evaluateJavaScript(
                self.mermaidRenderScript(token: token, theme: self.mermaidThemeName())
            ) { _, error in
                if let error {
                    appLog("failed to render mermaid: \(error)")
                } else if !self.searchQuery.isEmpty {
                    self.runSearch()
                }
            }
        }
    }

    private func ensureMermaidLoaded(token: Int, completion: @escaping () -> Void) {
        webView.evaluateJavaScript("typeof window.mermaid === 'object'") { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self, token == self.mermaidRenderToken else {
                    return
                }

                if result as? Bool == true {
                    completion()
                    return
                }

                guard let source = self.loadMermaidScriptSource() else {
                    self.webView.evaluateJavaScript(
                        self.mermaidUnavailableScript(message: "Mermaid renderer is unavailable."))
                    return
                }

                self.webView.evaluateJavaScript(source) { _, error in
                    DispatchQueue.main.async {
                        guard token == self.mermaidRenderToken else {
                            return
                        }

                        if let error {
                            appLog("failed to load mermaid: \(error)")
                            self.webView.evaluateJavaScript(
                                self.mermaidUnavailableScript(
                                    message: "Failed to load Mermaid renderer."))
                            return
                        }

                        completion()
                    }
                }
            }
        }
    }

    private func loadMermaidScriptSource() -> String? {
        if let mermaidScriptSource {
            return mermaidScriptSource
        }

        guard
            let url = AppResourceBundle.bundle.url(forResource: "mermaid.min", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }

        mermaidScriptSource = source
        return source
    }

    private func mermaidThemeName() -> String {
        let colorScheme = preferences.appearanceMode.colorScheme ?? AppAppearance.systemColorScheme
        return colorScheme == .dark ? "dark" : "default"
    }

    private func reloadCurrentPreviewForMermaidThemeChange() {
        guard panel.isVisible,
            let currentMarkdown,
            currentMarkdown.range(
                of: #"```\s*mermaid\b|~~~\s*mermaid\b"#,
                options: [.regularExpression, .caseInsensitive]) != nil
        else {
            return
        }

        resetSearch()
        mermaidRenderToken += 1
        webView.loadHTMLString(renderer.renderDocument(currentMarkdown), baseURL: nil)
        applyDocumentTheme()
    }

    private func rerenderMermaidAfterResize() {
        guard panel.isVisible else {
            return
        }

        webView.evaluateJavaScript("document.querySelector('[data-qm-mermaid]') !== null") {
            [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self, result as? Bool == true else {
                    return
                }

                self.mermaidRenderToken += 1
                self.renderMermaid(token: self.mermaidRenderToken)
            }
        }
    }

    private func mermaidRenderScript(token: Int, theme: String) -> String {
        let escapedTheme = Self.javascriptStringLiteral(theme)
        return """
            (async () => {
              if (window.__qmMermaidToken && window.__qmMermaidToken > \(token)) return 0;
              window.__qmMermaidToken = \(token);

              const blocks = Array.from(document.querySelectorAll('[data-qm-mermaid]'));
              if (!blocks.length || !window.mermaid) return 0;

              mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'strict',
                theme: \(escapedTheme)
              });

              for (const [index, block] of blocks.entries()) {
                const template = block.querySelector('.qm-mermaid-source');
                const source = (template?.content?.textContent || template?.textContent || '').trimEnd();
                const preview = block.querySelector('.qm-mermaid-preview');
                const loading = block.querySelector('.qm-mermaid-loading');
                const codeBlock = block.querySelector('.qm-mermaid-code code');
                const modeButtons = Array.from(block.querySelectorAll('.qm-mermaid-mode-button'));
                if (!source.trim()) continue;
                if (codeBlock) codeBlock.textContent = source;
                const preferredMode = block.dataset.qmMode || 'preview';

                for (const button of modeButtons) {
                  if (button.dataset.qmReady) continue;
                  button.dataset.qmReady = 'true';
                  button.addEventListener('click', () => {
                    const mode = button.dataset.qmTargetMode || 'preview';
                    block.dataset.qmMode = mode;
                  });
                }

                try {
                  if (preview) preview.innerHTML = '';
                  const result = await mermaid.render(`qm-mermaid-\(token)-${index}`, source);
                  if (window.__qmMermaidToken !== \(token)) return 0;
                  if (preview) {
                    preview.innerHTML = result.svg;
                    result.bindFunctions?.(preview);
                  }
                  if (loading) loading.remove();
                  block.dataset.qmMode = preferredMode;
                } catch (error) {
                  if (window.__qmMermaidToken !== \(token)) return 0;
                  if (preview) preview.innerHTML = '';
                  if (loading) loading.remove();
                  block.querySelector('.qm-mermaid-error-message')?.remove();

                  const message = document.createElement('p');
                  message.className = 'qm-mermaid-error-message';
                  message.textContent = `Mermaid render failed: ${error?.message || error || 'Unknown error'}`;
                  block.insertBefore(message, block.querySelector('.qm-mermaid-code'));
                  block.dataset.qmMode = 'code';
                }
              }

              return blocks.length;
            })();
            """
    }

    private func mermaidUnavailableScript(message: String) -> String {
        let escapedMessage = Self.javascriptStringLiteral(message)
        return """
            (() => {
              for (const block of document.querySelectorAll('[data-qm-mermaid]')) {
                const template = block.querySelector('.qm-mermaid-source');
                const source = (template?.content?.textContent || template?.textContent || '').trimEnd();
                const preview = block.querySelector('.qm-mermaid-preview');
                const loading = block.querySelector('.qm-mermaid-loading');
                const codeBlock = block.querySelector('.qm-mermaid-code code');
                if (preview) preview.innerHTML = '';
                if (loading) loading.remove();
                if (codeBlock) codeBlock.textContent = source;
                block.querySelector('.qm-mermaid-error-message')?.remove();

                const message = document.createElement('p');
                message.className = 'qm-mermaid-error-message';
                message.textContent = \(escapedMessage);

                block.insertBefore(message, block.querySelector('.qm-mermaid-code'));
                block.dataset.qmMode = 'code';
              }
            })();
            """
    }

    private func documentThemeScript(for mode: AppearanceMode) -> String {
        guard let documentTheme = mode.documentTheme else {
            return "document.documentElement.removeAttribute('data-theme');"
        }
        return "document.documentElement.setAttribute('data-theme', '\(documentTheme)');"
    }

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
            let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return encoded
    }

    private func applyPreviewBackground(for mode: AppearanceMode) {
        let backgroundColor = mode.previewBackgroundColor.cgColor
        containerView.layer?.backgroundColor = backgroundColor
        webView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func applyPanelFrame(_ frame: NSRect) {
        isApplyingPanelFrame = true
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        isApplyingPanelFrame = false
    }

    private var preferredPreviewSize: NSSize {
        guard preferences.rememberPreviewSize, let size = preferences.previewSize else {
            return Self.defaultSize
        }

        return NSSize(
            width: max(size.width, panel.minSize.width),
            height: max(size.height, panel.minSize.height)
        )
    }

    private func configureKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            guard self.panel.isVisible else {
                return event
            }

            if event.keyCode == UInt16(kVK_Escape) {
                self.handleEscape()
                return nil
            }

            guard self.panel.frame.contains(NSEvent.mouseLocation) || self.panel.isKeyWindow else {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
                self.copySelection()
                return nil
            }

            if flags.isDisjoint(with: [.command, .control, .option]) {
                if self.handleSearchKey(event) {
                    return nil
                }
            }

            return event
        }
    }

    private func configureEscapeEventTap() {
        escapeEventTap = EscapeEventTap { [weak self] in
            guard let self, self.panel.isVisible else {
                self?.escapeEventTap?.setActive(false)
                return
            }

            self.handleEscape()
        }
    }

    private func handleEscape() {
        guard searchQuery.isEmpty else {
            clearSearch()
            return
        }

        closeAndRestoreFocus()
    }

    private func closeAndRestoreFocus() {
        guard panel.isVisible else {
            return
        }

        panel.orderOut(nil)
        escapeEventTap?.setActive(false)
        restorePreviousApplication()
    }

    private func rememberFrontmostApplication() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return
        }

        previousApplication = frontmostApplication
    }

    private func restorePreviousApplication() {
        guard let previousApplication else {
            return
        }

        self.previousApplication = nil
        guard !previousApplication.isTerminated else {
            return
        }

        previousApplication.activate(options: [])
    }

    private func copySelection() {
        webView.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            guard let text = result as? String, !text.isEmpty else {
                return
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func handleSearchKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case UInt16(kVK_DownArrow):
            guard searchHitCount > 0 else {
                return false
            }
            jumpSearchHit(delta: 1)
            return true
        case UInt16(kVK_UpArrow):
            guard searchHitCount > 0 else {
                return false
            }
            jumpSearchHit(delta: -1)
            return true
        case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
            guard !searchQuery.isEmpty else {
                return false
            }
            searchQuery.removeLast()
            runSearch()
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers,
            characters.count == 1,
            let scalar = characters.unicodeScalars.first,
            !CharacterSet.controlCharacters.contains(scalar)
        else {
            return false
        }

        searchQuery.append(String(characters))
        runSearch()
        return true
    }

    private func clearSearch() {
        searchQuery = ""
        runSearch()
    }

    private func resetSearch() {
        searchQuery = ""
        searchToken += 1
        searchHitCount = 0
        activeHitIndex = -1
        searchBadge.isHidden = true
    }

    private func runSearch() {
        searchToken += 1
        let token = searchToken

        guard !searchQuery.isEmpty else {
            searchBadge.isHidden = true
            searchHitCount = 0
            activeHitIndex = -1
            webView.evaluateJavaScript(highlightScript(query: "", token: token))
            return
        }

        searchHitCount = 0
        activeHitIndex = -1
        updateSearchBadge(isRunning: true)
        webView.evaluateJavaScript(highlightScript(query: searchQuery, token: token))
    }

    private func updateSearchBadge(isRunning: Bool) {
        guard !searchQuery.isEmpty else {
            searchBadge.isHidden = true
            return
        }

        let countText =
            searchHitCount > 0 && activeHitIndex >= 0
            ? "\(activeHitIndex + 1)/\(searchHitCount)"
            : "\(searchHitCount)"
        searchBadge.text = "\(searchQuery)  \(countText)\(isRunning ? "..." : "")"
        searchBadge.isHidden = false
    }

    private func jumpSearchHit(delta: Int) {
        webView.evaluateJavaScript("window.__qmJumpHit && window.__qmJumpHit(\(delta));")
    }

    private func highlightScript(query: String, token: Int) -> String {
        let encodedQuery = String(data: try! JSONEncoder().encode(query), encoding: .utf8) ?? "\"\""
        return """
            (() => {
              const query = \(encodedQuery);
              const token = \(token);
              const post = (count, done, active = -1) => {
                window.webkit?.messageHandlers?.quickMarkdownSearch?.postMessage({ token, count, done, active });
              };

              if (window.__qmSearchJob) window.__qmSearchJob.cancelled = true;
              const job = { cancelled: false, token, hits: [], active: -1 };
              window.__qmSearchJob = job;
              window.__qmJumpHit = (delta) => {
                const state = window.__qmSearchJob;
                if (!state || state.token !== token || !state.hits.length) return;
                setActive(state.active + delta, true);
              };

              const clear = () => {
                document.querySelectorAll('mark[data-qm-hit]').forEach((mark) => {
                  mark.replaceWith(document.createTextNode(mark.textContent || ''));
                });
                document.body.normalize();
              };

              clear();
              if (!query) {
                post(0, true);
                return;
              }

              const lowerQuery = query.toLocaleLowerCase();
              const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                {
                  acceptNode(node) {
                    if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                    const parent = node.parentElement;
                    if (!parent || parent.closest('script, style, svg, mark[data-qm-hit]')) return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                  }
                }
              );

              const nodes = [];
              while (walker.nextNode()) nodes.push(walker.currentNode);

              let index = 0;

              const setActive = (nextIndex, scroll) => {
                if (!job.hits.length) return;
                if (job.active >= 0 && job.hits[job.active]) {
                  job.hits[job.active].classList.remove('qm-active-hit');
                }
                job.active = ((nextIndex % job.hits.length) + job.hits.length) % job.hits.length;
                const active = job.hits[job.active];
                active.classList.add('qm-active-hit');
                if (scroll) active.scrollIntoView({ block: 'center', inline: 'nearest' });
                post(job.hits.length, true, job.active);
              };

              const markNode = (textNode) => {
                const text = textNode.nodeValue || '';
                const lowerText = text.toLocaleLowerCase();
                let cursor = 0;
                let hit = lowerText.indexOf(lowerQuery, cursor);
                if (hit === -1) return;

                const fragment = document.createDocumentFragment();
                while (hit !== -1) {
                  if (hit > cursor) fragment.appendChild(document.createTextNode(text.slice(cursor, hit)));

                  const mark = document.createElement('mark');
                  mark.dataset.qmHit = 'true';
                  mark.textContent = text.slice(hit, hit + query.length);
                  fragment.appendChild(mark);
                  job.hits.push(mark);

                  if (job.hits.length === 1) {
                    setActive(0, true);
                  }

                  cursor = hit + query.length;
                  hit = lowerText.indexOf(lowerQuery, cursor);
                }

                if (cursor < text.length) fragment.appendChild(document.createTextNode(text.slice(cursor)));
                textNode.replaceWith(fragment);
              };

              const step = () => {
                if (job.cancelled) return;
                const deadline = performance.now() + 5;
                while (index < nodes.length && performance.now() < deadline) {
                  markNode(nodes[index]);
                  index += 1;
                }
                post(job.hits.length, index >= nodes.length, job.active);
                if (index < nodes.length) setTimeout(step, 0);
              };

              step();
            })();
            """
    }

    private func configureContainerView() {
        containerView.wantsLayer = true
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.cornerRadius = 13
        containerView.layer?.masksToBounds = true
        applyPreviewBackground(for: preferences.appearanceMode)
        containerView.layer?.borderWidth = 0.7
        containerView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.34).cgColor
    }

    private func configureSearchBadge() {
        searchBadge.translatesAutoresizingMaskIntoConstraints = false
        searchBadge.isHidden = true
    }

    private func clampedOrigin(near point: CGPoint, size: NSSize) -> CGPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let padding: CGFloat = 10

        var x = point.x + 14
        var y = point.y - size.height - 14

        if x + size.width > visible.maxX - padding {
            x = point.x - size.width - 14
        }
        if y < visible.minY + padding {
            y = point.y + 18
        }

        x = min(max(x, visible.minX + padding), visible.maxX - size.width - padding)
        y = min(max(y, visible.minY + padding), visible.maxY - size.height - padding)

        return CGPoint(x: x, y: y)
    }

    private func isSafeExternalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

final class EscapeEventTap: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isActive = false

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        setupEventTap()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    func setActive(_ active: Bool) {
        lock.lock()
        isActive = active
        lock.unlock()
    }

    private func setupEventTap() {
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let eventTap = Unmanaged<EscapeEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    eventTap.enable()
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown,
                    eventTap.shouldConsumeEscape(event)
                else {
                    return Unmanaged.passUnretained(event)
                }

                Task { @MainActor in
                    eventTap.handler()
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            appLog("failed to create escape event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func enable() {
        guard let eventTap else {
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func shouldConsumeEscape(_ event: CGEvent) -> Bool {
        lock.lock()
        let active = isActive
        lock.unlock()

        return active && event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape)
    }
}

final class PreviewWindow: NSWindow {
    var onCopy: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopy?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

final class PreviewDragHandleView: NSView {
    private var dotColor = NSColor.labelColor.withAlphaComponent(0.62)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyAppearanceMode(_ mode: AppearanceMode) {
        switch mode {
        case .system:
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
            dotColor = NSColor.labelColor.withAlphaComponent(0.62)
        case .light:
            layer?.backgroundColor = NSColor(white: 0.9, alpha: 0.62).cgColor
            dotColor = NSColor(white: 0.36, alpha: 0.72)
        case .dark:
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.14).cgColor
            dotColor = NSColor(white: 1, alpha: 0.45)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        dotColor.setFill()

        let dotSize: CGFloat = 3
        let gap: CGFloat = 5
        let totalWidth = dotSize * 3 + gap * 2
        var x = bounds.midX - totalWidth / 2
        let y = bounds.midY - dotSize / 2

        for _ in 0..<3 {
            NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: dotSize, height: dotSize),
                xRadius: dotSize / 2, yRadius: dotSize / 2
            ).fill()
            x += dotSize + gap
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class PreviewWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }
}

final class SearchBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    var text: String {
        get {
            label.stringValue
        }
        set {
            label.stringValue = newValue
            needsLayout = true
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: min(labelSize.width + 22, 320), height: labelSize.height + 8)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
        layer?.borderWidth = 0.6
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        label.preferredMaxLayoutWidth = 290
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 290),
        ])
    }
}

final class HotKeyManager: @unchecked Sendable {
    private var selectedTextHotkey: RecordedHotkey?
    private var clipboardHotkey: RecordedHotkey?
    private let handler: @MainActor (HotKeyAction) -> Void
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastModifierPressTime: [DoubleTapKey: Date] = [:]
    private var lastModifierState: CGEventFlags = []
    private var lastHandledAt: TimeInterval = 0
    private var isEnabled = true

    init(
        selectedTextHotkey: RecordedHotkey?,
        clipboardHotkey: RecordedHotkey?,
        handler: @escaping @MainActor (HotKeyAction) -> Void
    ) {
        self.selectedTextHotkey = selectedTextHotkey
        self.clipboardHotkey = clipboardHotkey
        self.handler = handler
    }

    func updateHotkeys(selectedText: RecordedHotkey?, clipboard: RecordedHotkey?) {
        selectedTextHotkey = selectedText
        clipboardHotkey = clipboard
        restartIfEnabled()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }

        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func refreshAfterAccessibilityGranted() {
        restartIfEnabled()
    }

    func start() {
        guard isEnabled else {
            return
        }

        unregisterAll()
        installCarbonEventHandler()
        registerCarbonHotkey(selectedTextHotkey, action: .selectedText)
        registerCarbonHotkey(clipboardHotkey, action: .clipboard)
        configureLocalMonitor()
        if selectedTextHotkey?.isDoubleTap == true || clipboardHotkey?.isDoubleTap == true {
            setupEventTap()
        }
    }

    func stop() {
        unregisterAll()
    }

    private func restartIfEnabled() {
        guard isEnabled else {
            return
        }
        start()
    }

    private func configureLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.action(matching: event) else {
                return event
            }

            Task { @MainActor in
                self.fire(action)
            }
            return nil
        }
    }

    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                var eventHotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )

                if let action = HotKeyAction(rawValue: eventHotKeyID.id) {
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData)
                        .takeUnretainedValue()
                    Task { @MainActor in
                        manager.fire(action)
                    }
                }

                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    }

    private func registerCarbonHotkey(_ hotkey: RecordedHotkey?, action: HotKeyAction) {
        guard let hotkey, !hotkey.isDoubleTap, let keyCode = hotkey.keyCode else {
            return
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("QMDP")), id: action.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            hotkey.modifiers ?? 0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        } else {
            appLog("failed to register hotkey \(action): \(status)")
        }
    }

    private func setupEventTap() {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passRetained(event)
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = manager.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                if type == .flagsChanged {
                    manager.handleFlagsChanged(event)
                } else if type == .keyDown {
                    manager.lastModifierPressTime.removeAll()
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            appLog("failed to create hotkey event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let currentFlags = event.flags
        checkDoubleTap(
            hotkey: selectedTextHotkey, action: .selectedText, currentFlags: currentFlags)
        checkDoubleTap(hotkey: clipboardHotkey, action: .clipboard, currentFlags: currentFlags)
        lastModifierState = currentFlags
    }

    private func checkDoubleTap(
        hotkey: RecordedHotkey?, action: HotKeyAction, currentFlags: CGEventFlags
    ) {
        guard let hotkey, hotkey.isDoubleTap, let key = hotkey.doubleTapKey else {
            return
        }

        let targetFlag = key.cgEventFlag
        let wasPressed = lastModifierState.contains(targetFlag)
        let isPressed = currentFlags.contains(targetFlag)

        guard isPressed && !wasPressed else {
            return
        }

        let now = Date()
        if let lastPress = lastModifierPressTime[key],
            now.timeIntervalSince(lastPress) < 0.3
        {
            lastModifierPressTime[key] = nil
            Task { @MainActor in
                self.fire(action)
            }
        } else {
            lastModifierPressTime[key] = now
        }
    }

    private func unregisterAll() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        eventHandlerRef = nil
        localMonitor = nil
        runLoopSource = nil
        eventTap = nil
        lastModifierPressTime.removeAll()
    }

    private func action(matching event: NSEvent) -> HotKeyAction? {
        if matches(event, hotkey: selectedTextHotkey) {
            return .selectedText
        }
        if matches(event, hotkey: clipboardHotkey) {
            return .clipboard
        }
        return nil
    }

    private func matches(_ event: NSEvent, hotkey: RecordedHotkey?) -> Bool {
        guard let hotkey, !hotkey.isDoubleTap, let keyCode = hotkey.keyCode else {
            return false
        }

        return event.keyCode == keyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                == modifierFlags(for: hotkey)
    }

    @MainActor
    private func fire(_ action: HotKeyAction) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastHandledAt > 0.2 else {
            return
        }

        lastHandledAt = now
        handler(action)
    }

    private func modifierFlags(for hotkey: RecordedHotkey) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        let modifiers = hotkey.modifiers ?? 0
        if modifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        if modifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if modifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }
        if modifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        return flags
    }
}

private enum HTMLMessage {
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    precondition(string.utf8.count == 4)
    return string.utf8.reduce(0) { result, byte in
        (result << 8) + FourCharCode(byte)
    }
}
