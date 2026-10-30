// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelous Akpotu (Marvelxy)
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI
import Sparkle

@main
struct ForexMarketHoursApp: App {
    @StateObject private var updaterManager = UpdaterManager()

    var body: some Scene {
        WindowGroup {
            RootView(updater: updaterManager.updater)
                .frame(minWidth: 1140, minHeight: 780)
        }
        .defaultSize(width: 1200, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterManager.updater)
            }
        }
        Settings {
            AboutView(updater: updaterManager.updater)
                .padding(20)
        }
    }
}

// MARK: - Tabbed root

struct RootView: View {
    let updater: SPUUpdater?

    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ContentView(updater: updater)
                .tabItem { Label("Market Hours", systemImage: "globe.americas.fill") }
                .tag(0)

            IntervalTimerView()
                .tabItem { Label("Timer", systemImage: "timer") }
                .tag(1)
        }
        .preferredColorScheme(.dark)
    }
}
