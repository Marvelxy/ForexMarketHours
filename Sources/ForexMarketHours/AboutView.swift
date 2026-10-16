// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelous Akpotu (Marvelxy)
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI
import Sparkle

// MARK: - About panel

/// About this app: identity, version, author, update controls.
struct AboutView: View {
    let updater: SPUUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forex Market Hours")
                        .font(.title2.bold())
                    Text(AppInfo.versionString)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text("A beautiful, interactive visualizer for forex trading sessions. Session hours are computed locally on your Mac — no account, no tracking.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Created by \(AppInfo.authorName) (\(AppInfo.authorHandle))")
                    .font(.callout.bold())
                Link(AppInfo.authorEmail, destination: URL(string: "mailto:\(AppInfo.authorEmail)")!)
                    .font(.callout)
                Link("github.com/Marvelxy", destination: AppInfo.githubProfile)
                    .font(.callout)
                Link("github.com/Marvelxy/ForexMarketHours", destination: AppInfo.repository)
                    .font(.callout)
            }

            Text("\(AppInfo.copyright) — GNU General Public License v3.0 or later.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("SOFTWARE UPDATES")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
                HStack(spacing: 8) {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Link("View releases", destination: AppInfo.releases)
                        .font(.callout)
                }
                UpdateSettingsView(updater: updater)
                Text("Updates are delivered automatically via Sparkle. The app checks about once a day; you can also check manually at any time.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        // No padding/size here: call sites (page section, Settings) provide it.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
