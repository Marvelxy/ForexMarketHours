// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelous Akpotu (Marvelxy)
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI
import AppKit

// MARK: - System beep sounds

enum BeepSound {
    static let names = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    static func play(_ name: String) {
        guard let sound = NSSound(named: name) else {
            NSSound.beep()
            return
        }
        sound.volume = 1
        sound.play()
    }
}

// MARK: - Repeating interval timer

struct IntervalTimerView: View {
    @AppStorage("timer.intervalMinutes") private var intervalMinutes = 5
    @AppStorage("timer.soundName") private var soundName = "Glass"

    @State private var isRunning = false
    @State private var deadline = Date.distantFuture
    @State private var pausedRemaining: TimeInterval = 0
    @State private var beeps = 0
    @State private var now = Date()

    private let intervals = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var intervalSeconds: TimeInterval { TimeInterval(intervalMinutes * 60) }

    private var remaining: TimeInterval {
        if isRunning { return max(0, deadline.timeIntervalSince(now)) }
        if pausedRemaining > 0 { return pausedRemaining }
        return max(0, nextAlignedDate(after: now).timeIntervalSince(now))
    }

    private var progress: Double {
        guard intervalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / intervalSeconds))
    }

    private var phaseLabel: String {
        if isRunning { return "RUNNING" }
        if pausedRemaining > 0 { return "PAUSED" }
        return "READY"
    }

    private var phaseColor: Color {
        if isRunning { return .green }
        if pausedRemaining > 0 { return .orange }
        return .secondary
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    header
                    timerCard
                    soundCard
                    tipsCard
                }
                .padding(16)
            }
            .scrollIndicators(.never)
        }
        .preferredColorScheme(.dark)
        .onReceive(tick) { date in
            now = date
            guard isRunning else { return }
            guard now >= deadline else { return }

            BeepSound.play(soundName)
            beeps += 1

            // If the Mac slept, skip past any missed intervals without
            // firing a burst of overlapping beeps.
            var next = deadline
            while next <= now { next = next.addingTimeInterval(intervalSeconds) }
            deadline = next
        }
        .onChange(of: intervalMinutes) { _, _ in
            let current = Date()
            now = current
            if isRunning {
                deadline = nextAlignedDate(after: current)
            } else {
                pausedRemaining = 0
            }
        }
    }

    // MARK: Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.03, green: 0.05, blue: 0.11),
                     Color(red: 0.06, green: 0.09, blue: 0.20),
                     Color(red: 0.04, green: 0.07, blue: 0.14)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(colors: [.cyan.opacity(0.10), .clear],
                           center: .topTrailing, startRadius: 50, endRadius: 600)
        )
        .overlay(
            RadialGradient(colors: [.purple.opacity(0.08), .clear],
                           center: .bottomLeading, startRadius: 50, endRadius: 500)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    Text("Interval Timer")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    statusPill
                }
                Text("A repeating beep at your chosen interval — for trading check-ins, news breaks or focus sprints.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(DisplayZone.local.clockString(for: now))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                Text("\(DisplayZone.local.label) (\(DisplayZone.local.abbreviation))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusPill: some View {
        Text(phaseLabel)
            .font(.caption.bold())
            .foregroundStyle(phaseColor)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(phaseColor.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(phaseColor.opacity(0.4), lineWidth: 1))
    }

    // MARK: Timer card

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT BEEP")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                    Text(timeString(remaining))
                        .font(.system(size: 62, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(isRunning ? Color.cyan : .primary)
                    Text("Every \(intervalMinutes) minute\(intervalMinutes == 1 ? "" : "s") · \(beeps) beep\(beeps == 1 ? "" : "s") so far")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Button {
                        toggle()
                    } label: {
                        Label(toggleTitle, systemImage: isRunning ? "pause.fill" : "play.fill")
                            .frame(minWidth: 92)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Reset") { reset() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!isRunning && pausedRemaining == 0 && beeps == 0)
                }
            }

            ProgressView(value: progress)
                .tint(.cyan)

            HStack(spacing: 10) {
                Text("Repeat every")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Interval", selection: $intervalMinutes) {
                    ForEach(intervals, id: \.self) { minutes in
                        Text("\(minutes) minute\(minutes == 1 ? "" : "s")").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
                Spacer()
                if isRunning {
                    Text("Next beep \(DisplayZone.local.clockString(for: deadline))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if pausedRemaining > 0 {
                    Text("Paused with \(timeString(pausedRemaining)) left")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                } else {
                    Text("Next beep \(DisplayZone.local.clockString(for: nextAlignedDate(after: now)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    // MARK: Sound card

    private var soundCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BEEP SOUND")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(1.5)
            HStack(spacing: 10) {
                Picker("Sound", selection: $soundName) {
                    ForEach(BeepSound.names, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                Button {
                    BeepSound.play(soundName)
                } label: {
                    Label("Preview", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("Uses the built-in macOS alert sounds.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .glassCard()
    }

    private var tipsCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("The timer runs while this tab is open.")
                    .font(.callout.bold())
                Text("Beeps follow the clock: a 5-minute interval fires at :00, :05, :10 and so on, so pressing Start simply picks up the time left in the current block. If the Mac sleeps, the timer resumes without firing missed beeps in a burst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .glassCard()
    }

    // MARK: Controls

    private var toggleTitle: String {
        if isRunning { return "Pause" }
        return pausedRemaining > 0 ? "Resume" : "Start"
    }

    private func toggle() {
        if isRunning {
            pausedRemaining = max(0, deadline.timeIntervalSince(Date()))
            isRunning = false
        } else {
            let current = Date()
            deadline = nextAlignedDate(after: current)
            pausedRemaining = 0
            isRunning = true
            now = current
        }
    }

    private func reset() {
        isRunning = false
        pausedRemaining = 0
        deadline = .distantFuture
        beeps = 0
        now = Date()
    }

    /// Next clock-aligned boundary (e.g. :00, :05, :10 for a 5-minute interval).
    private func nextAlignedDate(after date: Date) -> Date {
        let interval = max(1, intervalSeconds)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let elapsed = date.timeIntervalSince(startOfDay)
        let periods = floor(elapsed / interval) + 1
        return startOfDay.addingTimeInterval(periods * interval)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
