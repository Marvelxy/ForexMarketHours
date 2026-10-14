// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelxy
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI

@main
struct ForexMarketHoursApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1140, minHeight: 780)
        }
        .defaultSize(width: 1200, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
