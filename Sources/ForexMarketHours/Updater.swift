// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelous Akpotu (Marvelxy)
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI
import Sparkle

// MARK: - Sparkle updater wiring (SwiftUI lifecycle)

/// Owns the Sparkle updater controller for the app's lifetime.
/// Kept as a long-lived object in ``ForexMarketHoursApp`` so the
/// SPUUpdater and its delegates are never deallocated.
final class UpdaterManager: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var updater: SPUUpdater { controller.updater }
}

// MARK: - Check for Updates menu item

/// Publishes when a manual update check can run, so the menu item
/// enables/disables correctly.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// "Check for Updates…" menu item. The intermediate view is required so the
/// disabled state tracks correctly on all macOS versions.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

// MARK: - Update settings (automatic checks toggle)

/// Sparkle-backed "automatically check for updates" toggle for Settings.
struct UpdateSettingsView: View {
    @ObservedObject private var viewModel: UpdateSettingsViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = UpdateSettingsViewModel(updater: updater)
    }

    var body: some View {
        Toggle("Automatically check for updates", isOn: $viewModel.automaticallyChecks)
            .toggleStyle(.switch)
            .help("Check for new versions in the background (about once a day)")
        if !viewModel.canCheckForUpdates {
            Text("Automatic checks are unavailable while an update check is running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

final class UpdateSettingsViewModel: ObservableObject {
    @Published var automaticallyChecks: Bool {
        didSet {
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }
    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecks = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

// MARK: - App version helpers

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionString: String { "Version \(version) (\(build))" }

    static let authorName = "Marvelous Akpotu"
    static let authorHandle = "Marvelxy"
    static let authorEmail = "still4marvelous@gmail.com"
    static let githubProfile = URL(string: "https://github.com/Marvelxy")!
    static let repository = URL(string: "https://github.com/Marvelxy/ForexMarketHours")!
    static let releases = URL(string: "https://github.com/Marvelxy/ForexMarketHours/releases")!

    static var copyright: String { "© 2026 \(authorName) (\(authorHandle))" }
}
