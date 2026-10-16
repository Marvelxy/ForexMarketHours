// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelous Akpotu (Marvelxy)
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI
import AppKit
import UserNotifications
import Sparkle

// Shows banners even when the app is frontmost.
final class ForegroundNotifyDelegate: NSObject, UNUserNotificationCenterDelegate {    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

// Tick counter that never invalidates the view (plain var, not @Published),
// so skipped background ticks cost zero redraw.
final class BackgroundGate: ObservableObject {
    var ticks = 0
}

// MARK: - Main view

struct ContentView: View {
    /// Sparkle updater, injected by the App for the About sheet's
    /// "Check for Updates…" button. Nil in previews.
    let updater: SPUUpdater?
    @State private var now = Date()
    @State private var scrubUTCHour: Double? = nil   // nil == LIVE
    @State private var isPlaying = false
    @State private var selectedID: String? = "london"
    @State private var zone: DisplayZone = .local
    @State private var hoverWallHour: Double? = nil
    @AppStorage("alertsEnabled") private var alertsEnabled = true
    @State private var lastOpenState: [String: Bool] = [:]
    @State private var notifyDelegate = ForegroundNotifyDelegate()
    @State private var showDetail = false
    @State private var notifyBlocked = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bgGate = BackgroundGate()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Effective moment being inspected
    private var liveUTCHour: Double { MarketData.utcHour(of: now) }
    private var effUTCHour: Double { scrubUTCHour ?? liveUTCHour }
    private var isLive: Bool { scrubUTCHour == nil && !isPlaying }
    private var effWallHour: Double { zone.wallHour(fromUTCHour: effUTCHour, reference: now) }

    private var effDate: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let sod = cal.startOfDay(for: now)
        return sod.addingTimeInterval(effUTCHour * 3600)
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        header
                        statusStrip
                        timelineCard
                        sessionGrid
                        if showDetail, let s = selectedSession {
                            detailPanel(s)
                                .id("detail")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        overlapStrip
                        aboutSection
                        footer
                    }
                    .padding(16)
                }
                .scrollIndicators(.never)
                .onChange(of: selectedID) { _, new in
                    // Any session click (card, timeline bar, gutter label) reveals the long card.
                    if new != nil { showDetail = true }
                }
                .onChange(of: showDetail) { _, open in
                    if open {
                        // Let the expand transition finish, then bring the card into view.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { proxy.scrollTo("detail", anchor: .center) }
                        }
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDetail)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            UNUserNotificationCenter.current().delegate = notifyDelegate
            refreshNotifyStatus()
        }
        .onReceive(tick) { t in
            bgGate.ticks += 1
            if scenePhase != .active {
                // Background: wake every ~30s so open/close chimes and popups
                // still fire, but otherwise let the CPU fully idle (App Nap).
                guard bgGate.ticks % 30 == 0 else { return }
            }
            now = t
            if isPlaying {
                let cur = scrubUTCHour ?? liveUTCHour
                let next = (cur + 0.25).truncatingRemainder(dividingBy: 24) // 15 market-min / sec
                scrubUTCHour = next
                checkSessionTransitions(atUTCHour: next, at: t)
            } else if scrubUTCHour == nil {
                checkSessionTransitions(atUTCHour: liveUTCHour, at: t)
            }
        }
    }

    // MARK: Session open/close chimes (live + play modes)

    /// Bright bell when a session opens, higher ping when one closes.
    private func playAlert(opened: Bool) {
        let name = opened ? "Glass" : "Ping"
        if let sound = NSSound(named: name) {
            sound.volume = 0.9
            sound.play()
        } else {
            NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: false)?.play()
        }
    }

    private func stateSnapshot(atUTCHour h: Double) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: MarketData.sessions.map { ($0.id, $0.isOpen(atUTCHour: h)) })
    }

    /// Permission state for the macOS banner popup. If the user blocked it in
    /// System Settings, the system drops our popups silently — so we surface it.
    private func refreshNotifyStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    print("notify auth granted: \(granted)")
                    DispatchQueue.main.async { self.notifyBlocked = !granted }
                }
            case .denied:
                print("notify auth status: denied — popups blocked by system")
                DispatchQueue.main.async { self.notifyBlocked = true }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { self.notifyBlocked = false }
            @unknown default:
                break
            }
        }
    }

    /// Immediate test banner — verifies system delivery independent of session logic.
    private func sendTestNotification() {
        postTestNotification()
        refreshNotifyStatus()
    }

    private func postTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Forex Market Hours"
        content.body = "Test banner — session open/close alerts are working."
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "forex-test", content: content, trigger: nil))
    }

    /// Banner notification per session transition (time-sensitive so it breaks through Focus).
    private func notifySession(_ s: TradingSession, opened: Bool, atUTCHour h: Double) {
        let content = UNMutableNotificationContent()
        let delta = s.hoursToNextChange(fromUTCHour: h)
        if opened {
            content.title = "\(s.city) session is open"
            content.body = "Closes in \(MarketData.countdownString(hours: delta)) · \(s.pairs.joined(separator: ", ")) in focus"
        } else {
            content.title = "\(s.city) session closed"
            content.body = "Reopens in \(MarketData.countdownString(hours: delta)) · \(zone.rangeString(openUTC: s.openUTC, closeUTC: s.closeUTC, reference: now)) \(zone.label)"
        }
        content.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: "forex-\(s.id)-\(opened ? "open" : "close")",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func checkSessionTransitions(atUTCHour h: Double, at date: Date) {
        let current = stateSnapshot(atUTCHour: h)
        defer { lastOpenState = current }
        guard !lastOpenState.isEmpty, alertsEnabled, !MarketData.marketClosed(at: date) else { return }
        var opened = false, closed = false
        for s in MarketData.sessions {
            if lastOpenState[s.id] == false && current[s.id] == true {
                opened = true
                notifySession(s, opened: true, atUTCHour: h)
            }
            if lastOpenState[s.id] == true && current[s.id] == false {
                closed = true
                notifySession(s, opened: false, atUTCHour: h)
            }
        }
        if opened { playAlert(opened: true) }
        if closed {
            if opened {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.playAlert(opened: false) }
            } else {
                playAlert(opened: false)
            }
        }
    }

    private var selectedSession: TradingSession? {
        MarketData.sessions.first { $0.id == selectedID }
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
            RadialGradient(colors: [.blue.opacity(0.14), .clear],
                           center: .topTrailing, startRadius: 50, endRadius: 600)
        )
        .overlay(
            RadialGradient(colors: [.cyan.opacity(0.08), .clear],
                           center: .bottomLeading, startRadius: 50, endRadius: 500)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "globe.americas.fill")
                        .font(.title2)
                        .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    Text("Forex Market Hours")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    marketPill
                }
                Text("Sydney · Tokyo · Frankfurt · London · New York — live, in your timezone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Clocks
            VStack(alignment: .trailing, spacing: 2) {
                Text(zone.clockString(for: effDate))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                Text("\(zone.label) (\(zone.abbreviation))  ·  UTC \(utcLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Controls
            VStack(alignment: .trailing, spacing: 8) {
                Picker("Timezone", selection: $zone) {
                    ForEach(DisplayZone.allCases) { z in Text(z.label).tag(z) }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                HStack(spacing: 8) {
                    Button {
                        alertsEnabled.toggle()
                    } label: {
                        Label(alertsEnabled ? "Alerts" : "Muted", systemImage: alertsEnabled ? "bell.fill" : "bell.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Bell + banner notification when a session opens (Glass) or closes (Ping)")
                    Button {
                        sendTestNotification()
                    } label: {
                        Label("Test", systemImage: "bell.badge")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Send a test banner to verify system notifications arrive")
                    Button {
                        isPlaying.toggle()
                        if isPlaying {
                            if scrubUTCHour == nil { scrubUTCHour = liveUTCHour }
                            // seed baseline so the first play tick can't false-trigger
                            lastOpenState = stateSnapshot(atUTCHour: scrubUTCHour ?? liveUTCHour)
                        }
                    } label: {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        scrubUTCHour = nil; isPlaying = false
                        // reseed: jumping from a preview hour back to live must not chime
                        lastOpenState = stateSnapshot(atUTCHour: MarketData.utcHour(of: now))
                    } label: {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLive)
                }
                if notifyBlocked {
                    Text("Popups blocked — allow in System Settings → Notifications → Forex Market Hours")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 240)
                }
            }
        }
    }

    private var utcLabel: String {
        let h = Int(effUTCHour), m = Int((effUTCHour - Double(h)) * 60)
        return String(format: "%02d:%02d", h, m)
    }

    private var marketPill: some View {
        let closed = MarketData.marketClosed(at: effDate)
        let openCount = MarketData.openSessions(atUTCHour: effUTCHour).count
        return HStack(spacing: 6) {
            Circle().fill(closed ? Color.red : Color.green).frame(width: 8, height: 8)
                .shadow(color: closed ? .red : .green, radius: 6)
            Text(closed ? "CLOSED" : (isLive ? "OPEN · \(openCount) SESSION\(openCount == 1 ? "" : "S")" : "PREVIEW"))
                .font(.caption.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((closed ? Color.red : Color.green).opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke((closed ? Color.red : Color.green).opacity(0.4), lineWidth: 1))
        .foregroundStyle(closed ? .red : .green)
    }

    // MARK: Status strip (liquidity + weekend notice)

    private var statusStrip: some View {
        HStack(spacing: 14) {
            let liq = MarketData.liquidity(atUTCHour: effUTCHour)
            let closed = MarketData.marketClosed(at: effDate)
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Liquidity · \(closed ? "Closed" : liq.label)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    LiquidityBar(value: closed ? 0 : liq.value)
                        .frame(width: 180)
                }
            }
            Divider().frame(height: 30)
            if closed {
                Label("Weekend — the market reopens Sunday 21:00 UTC with Sydney.", systemImage: "moon.zzz.fill")
                    .font(.callout).foregroundStyle(.orange)
            } else if let ov = MarketData.activeOverlaps(atUTCHour: effUTCHour).max(by: { $0.intensity < $1.intensity }) {
                Label("\(ov.name) overlap is live — \(ov.note.lowercased()).", systemImage: "bolt.fill")
                    .font(.callout).foregroundStyle(.yellow)
            } else {
                let open = MarketData.openSessions(atUTCHour: effUTCHour).map(\.city).joined(separator: " · ")
                Label(open.isEmpty ? "Between sessions — quiet patch." : "\(open) in session.",
                      systemImage: "clock.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !isLive {
                Text("Previewing \(zone.hourLabel(effWallHour)) \(zone.label) — drag the timeline or press Live to return")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .glassCard()
    }

    // MARK: Timeline

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("24-HOUR SESSION MAP")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    .tracking(1.5)
                Spacer()
                if let w = hoverWallHour {
                    Text("\(zone.hourLabel(w)) \(zone.label) · \(hoverSummary(wall: w))")
                        .font(.caption).foregroundStyle(.cyan).monospacedDigit()
                } else {
                    Text("Drag to scrub · click a bar to inspect · times in \(zone.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ZStack {
                TimelineView(
                    now: now,
                    zone: zone,
                    effUTCHour: effUTCHour,
                    isLive: isLive,
                    marketClosed: MarketData.marketClosed(at: effDate),
                    selectedID: $selectedID,
                    scrubUTCHour: $scrubUTCHour,
                    hoverWallHour: $hoverWallHour,
                    onStopPlaying: { isPlaying = false }
                )
                .frame(height: 214)
                // Weekends: the spot market is closed, so grey the map out
                // rather than showing live-looking colored bars.
                .saturation(MarketData.marketClosed(at: effDate) ? 0 : 1)
                .opacity(MarketData.marketClosed(at: effDate) ? 0.45 : 1)
                .allowsHitTesting(true)
                if MarketData.marketClosed(at: effDate) {
                    Label("MARKET CLOSED — reopens Sunday 21:00 UTC with Sydney", systemImage: "moon.zzz.fill")
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.65), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 14) {
                ForEach(MarketData.sessions) { s in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 12, height: 8)
                        Text(s.city).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.yellow.opacity(0.25)).frame(width: 12, height: 8)
                    Text("Overlap").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .glassCard()
    }

    private func hoverSummary(wall: Double) -> String {
        let off = zone.wallHour(fromUTCHour: 0, reference: now)
        let utc = (wall - off + 48).truncatingRemainder(dividingBy: 24)
        let open = MarketData.openSessions(atUTCHour: utc)
        return open.isEmpty ? "no session" : open.map(\.city).joined(separator: "+")
    }

    // MARK: Session cards

    private var sessionGrid: some View {
        HStack(spacing: 12) {
            ForEach(MarketData.sessions) { s in
                SessionCard(
                    session: s, now: now, zone: zone,
                    effUTCHour: effUTCHour, effDate: effDate,
                    selected: selectedID == s.id
                )
                .onTapGesture {
                    if selectedID == s.id && showDetail { showDetail = false }
                    else { selectedID = s.id; showDetail = true }
                }
            }
        }
    }

    private func detailPanel(_ s: TradingSession) -> some View {
        let open = !MarketData.marketClosed(at: effDate) && s.isOpen(atUTCHour: effUTCHour)
        let delta = s.hoursToNextChange(fromUTCHour: effUTCHour)
        return HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [s.color, s.color.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(s.city) session").font(.headline)
                    Text(s.region).font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: Capsule())
                    Spacer()
                    Button("Close") { showDetail = false }.buttonStyle(.link).font(.caption)
                }
                Text(s.blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    InfoChip(title: "LOCAL", value: localRange(s))
                    InfoChip(title: zone.label.uppercased(), value: zone.rangeString(openUTC: s.openUTC, closeUTC: s.closeUTC, reference: now))
                    InfoChip(title: open ? "CLOSES IN" : "OPENS IN", value: MarketData.countdownString(hours: delta), accent: s.color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TOP PAIRS").font(.caption2.bold()).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(s.pairs, id: \.self) { p in
                                Text(p).font(.caption.bold()).monospacedDigit()
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(s.color.opacity(0.15), in: Capsule())
                                    .foregroundStyle(s.color)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .glassCard(border: s.color.opacity(0.35))
    }

    private func localRange(_ s: TradingSession) -> String {
        guard let tz = TimeZone(identifier: s.timeZoneID) else { return "--" }
        let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "ha"
        func at(_ utc: Double) -> String {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let d = cal.startOfDay(for: now).addingTimeInterval(utc * 3600)
            return f.string(from: d).lowercased().replacingOccurrences(of: " ", with: "")
        }
        return "\(at(s.openUTC)) – \(at(s.closeUTC))"
    }

    // MARK: Overlaps + footer

    private var overlapStrip: some View {
        HStack(spacing: 14) {
            ForEach(MarketData.overlaps) { ov in
                let active = !MarketData.marketClosed(at: effDate) && ov.isActive(atUTCHour: effUTCHour)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: active ? "bolt.fill" : "bolt")
                            .foregroundStyle(active ? .yellow : .secondary)
                        Text(ov.name).font(.callout.bold())
                        if ov.intensity == 3 {
                            Text("BEST TO TRADE").font(.caption2.bold()).foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.yellow, in: Capsule())
                        }
                    }
                    Text("\(zone.hourLabel(zone.wallHour(fromUTCHour: ov.startUTC, reference: now))) – \(zone.hourLabel(zone.wallHour(fromUTCHour: ov.endUTC, reference: now))) \(zone.label)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Text(ov.note).font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(border: active ? Color.yellow.opacity(0.5) : nil)
                .shadow(color: active ? .yellow.opacity(0.25) : .clear, radius: 12)
            }
        }
    }

    // MARK: About (inline on-page section)

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT")
                .font(.caption.bold()).foregroundStyle(.secondary)
                .tracking(1.5)
            if let updater {
                AboutView(updater: updater)
            } else {
                // Previews / updater-less hosts: still show the essentials.
                VStack(spacing: 8) {
                    Text("Forex Market Hours").font(.headline)
                    Text("© 2026 Marvelous Akpotu (Marvelxy)")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .glassCard()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Session hours use standard UTC anchors; local times shift with daylight saving. Weekends closed Sat + Sun before 21:00 UTC.")
            Text("·")
            Text(AppInfo.versionString)
                .monospacedDigit()
        }
        .font(.caption).foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Timeline (interactive)

struct TimelineView: View {
    let now: Date
    let zone: DisplayZone
    let effUTCHour: Double
    let isLive: Bool
    /// When true (weekend), skip live-looking progress shimmer on the bars.
    var marketClosed = false
    @Binding var selectedID: String?
    @Binding var scrubUTCHour: Double?
    @Binding var hoverWallHour: Double?
    let onStopPlaying: () -> Void

    private var effWall: Double { zone.wallHour(fromUTCHour: effUTCHour, reference: now) }
    private let laneHeight: CGFloat = 28
    private let laneGap: CGFloat = 8
    private let topPad: CGFloat = 22
    private let bottomPad: CGFloat = 20
    private let gutter: CGFloat = 100 // label column left of the chart

    private var lanesHeight: CGFloat {
        CGFloat(MarketData.sessions.count) * laneHeight + CGFloat(MarketData.sessions.count - 1) * laneGap
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let chartW = w - gutter
            // NB: wall == 24 is midnight at the END of the day and must map to the
            // right edge. Wrapping it to 0 collapses the evening piece of every
            // wrapped session (e.g. Sydney 10pm-12am) to zero width.
            let x: (Double) -> CGFloat = { wall in
                let w = wall >= 24 ? 24 : wall.truncatingRemainder(dividingBy: 24)
                return gutter + CGFloat(w / 24) * chartW
            }
            ZStack {
                // gridlines + axis
                ForEach(0..<9) { i in
                    let tickHour = Double(i * 3)
                    let px = gutter + chartW * CGFloat(tickHour / 24)
                    Path { p in p.move(to: CGPoint(x: px, y: topPad - 6)); p.addLine(to: CGPoint(x: px, y: h - bottomPad + 6)) }
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                    Text(zone.hourLabel(tickHour))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        .position(x: min(max(px, gutter + 20), w - 20), y: h - 9)
                    Text(zone.hourLabel(tickHour))
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                        .position(x: min(max(px, gutter + 20), w - 20), y: 10)
                }
                // overlap bands
                ForEach(MarketData.overlaps) { ov in
                    let a = zone.wallHour(fromUTCHour: ov.startUTC, reference: now)
                    let b = zone.wallHour(fromUTCHour: ov.endUTC, reference: now)
                    ForEach(wallSegments(a, b), id: \.self) { seg in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.yellow.opacity(0.05 + 0.02 * Double(ov.intensity)))
                            .frame(width: max(0, x(seg.upperBound) - x(seg.lowerBound)),
                                   height: lanesHeight + 8)
                            .position(x: (x(seg.lowerBound) + x(seg.upperBound)) / 2,
                                      y: topPad + lanesHeight / 2 - 4)
                    }
                }
                // session lanes
                ForEach(Array(MarketData.sessions.enumerated()), id: \.element.id) { idx, s in
                    let y = topPad + CGFloat(idx) * (laneHeight + laneGap)
                    let a = zone.wallHour(fromUTCHour: s.openUTC, reference: now)
                    let b = zone.wallHour(fromUTCHour: s.closeUTC, reference: now)
                    // track
                    RoundedRectangle(cornerRadius: 9)
                        .fill(.white.opacity(0.05))
                        .frame(width: chartW, height: laneHeight)
                        .position(x: gutter + chartW / 2, y: y + laneHeight / 2)
                    // bar segments
                    ForEach(wallSegments(a, b), id: \.self) { seg in
                        let bx = x(seg.lowerBound)
                        let bw = max(0, x(seg.upperBound) - x(seg.lowerBound))
                        let isOpenEdge = abs(seg.lowerBound - a) < 0.001
                        let isCloseEdge = abs(seg.upperBound - b) < 0.001
                        ZStack {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(LinearGradient(colors: [s.color, s.color.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: s.color.opacity(selectedID == s.id ? 0.8 : 0.35), radius: selectedID == s.id ? 10 : 5)
                            if !marketClosed, s.isOpen(atUTCHour: effUTCHour) {
                                // elapsed shimmer: brighter elapsed portion
                                GeometryReader { _ in
                                    let frac = elapsedFraction(session: s, wallOpen: a)
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(.white.opacity(0.18))
                                        .frame(width: bw * CGFloat(frac))
                                }
                            }
                            // True open/close times printed inside the bar, so a wrapped
                            // session (e.g. Sydney 10pm-7am) can't read as opening at 12am.
                            HStack(spacing: 0) {
                                if isOpenEdge && bw > 54 {
                                    Text(zone.hourLabel(a))
                                        .font(.caption2.bold())
                                        .foregroundStyle(.black.opacity(0.7))
                                        .padding(.leading, 8)
                                }
                                Spacer(minLength: 0)
                                if isCloseEdge && bw > (isOpenEdge ? 108 : 54) {
                                    Text(zone.hourLabel(b))
                                        .font(.caption2.bold())
                                        .foregroundStyle(.black.opacity(0.7))
                                        .padding(.trailing, 8)
                                }
                            }
                            .frame(width: bw)
                        }
                        .frame(width: bw, height: laneHeight - 6)
                        .position(x: bx + bw / 2, y: y + laneHeight / 2)
                        .onTapGesture { selectedID = s.id }
                        // boundary pins: glowing filled dot = opens, hollow dot = closes
                        if isOpenEdge {
                            Circle()
                                .fill(s.color)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().fill(.white).frame(width: 3.5, height: 3.5))
                                .shadow(color: s.color.opacity(0.9), radius: 5)
                                .position(x: bx, y: y + laneHeight / 2)
                        }
                        if isCloseEdge {
                            Circle()
                                .fill(Color(red: 0.05, green: 0.07, blue: 0.14))
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(s.color, lineWidth: 2.5))
                                .position(x: bx + bw, y: y + laneHeight / 2)
                        }
                    }
                }
                // session labels in their own gutter, left of the chart
                ForEach(Array(MarketData.sessions.enumerated()), id: \.element.id) { idx, s in
                    let y = topPad + CGFloat(idx) * (laneHeight + laneGap)
                    HStack(spacing: 7) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.city)
                            .font(.callout.bold())
                            .foregroundStyle(selectedID == s.id ? .white : .secondary)
                    }
                    .frame(width: gutter - 12, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = s.id }
                    .position(x: gutter / 2, y: y + laneHeight / 2)
                }
                // now / preview marker
                let mx = x(effWall)
                Path { p in p.move(to: CGPoint(x: mx, y: 4)); p.addLine(to: CGPoint(x: mx, y: h - bottomPad + 6)) }
                    .stroke(isLive ? Color.green : Color.orange, lineWidth: 2)
                Circle()
                    .fill(isLive ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                    .shadow(color: (isLive ? Color.green : Color.orange).opacity(0.9), radius: 8)
                    .position(x: mx, y: 8)
                Text(isLive ? "NOW" : zone.hourLabel(effWall).uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(isLive ? .green : .orange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke((isLive ? Color.green : Color.orange).opacity(0.6), lineWidth: 1))
                    .position(x: min(max(mx, gutter + 44), w - 40), y: 24)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        onStopPlaying()
                        let wall = wallFromX(g.location.x, chartW)
                        scrubUTCHour = utcFromWall(wall)
                        hoverWallHour = wall
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverWallHour = wallFromX(loc.x, chartW)
                case .ended:
                    hoverWallHour = nil
                }
            }
            .onTapGesture { loc in
                onStopPlaying()
                scrubUTCHour = utcFromWall(wallFromX(loc.x, chartW))
            }
        }
    }

    private func utcFromWall(_ wall: Double) -> Double {
        let offset = zone.wallHour(fromUTCHour: 0, reference: now)
        return (wall - offset + 48).truncatingRemainder(dividingBy: 24)
    }

    /// Chart x-position (points) -> wall hour, clamped to the chart area.
    private func wallFromX(_ px: CGFloat, _ chartW: CGFloat) -> Double {
        let wall = Double((px - gutter) / chartW) * 24
        return min(max(wall, 0), 23.9999)
    }

    /// [lower, upper] wall-hour segments handling midnight wrap.
    private func wallSegments(_ a: Double, _ b: Double) -> [ClosedRange<Double>] {
        let s = (a + 24).truncatingRemainder(dividingBy: 24)
        let e = (b + 24).truncatingRemainder(dividingBy: 24)
        if e > s { return [s...e] }
        if e == s { return [0...24] }
        return [s...24, 0...e]
    }

    private func elapsedFraction(session s: TradingSession, wallOpen: Double) -> Double {
        let elapsed = s.elapsedHours(atUTCHour: effUTCHour)
        return min(1, max(0, elapsed / s.lengthHours))
    }
}

// MARK: - Session card

struct SessionCard: View {
    let session: TradingSession
    let now: Date
    let zone: DisplayZone
    let effUTCHour: Double
    let effDate: Date
    let selected: Bool

    var body: some View {
        // Weekends: the whole market is shut, so every session reads closed.
        let open = !MarketData.marketClosed(at: effDate) && session.isOpen(atUTCHour: effUTCHour)
        let delta = session.hoursToNextChange(fromUTCHour: effUTCHour)
        let frac: Double = open
            ? session.elapsedHours(atUTCHour: effUTCHour) / session.lengthHours
            : 1 - delta / (24 - session.lengthHours)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                PulseDot(color: session.color, active: open)
                Text(session.city).font(.headline)
                Spacer()
                Text(open ? "OPEN" : "CLOSED")
                    .font(.caption2.bold())
                    .foregroundStyle(open ? .green : .secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((open ? Color.green : Color.gray).opacity(0.15), in: Capsule())
            }
            Text(zone.rangeString(openUTC: session.openUTC, closeUTC: session.closeUTC, reference: now))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            Text("\(open ? "Closes" : "Opens") in \(MarketData.countdownString(hours: delta))")
                .font(.system(size: 19, weight: .bold)).foregroundStyle(open ? session.color : .secondary).monospacedDigit()
            ProgressView(value: min(1, max(0, frac)))
                .tint(open ? session.color : .gray)
            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { i in
                    Circle().fill(i <= session.volatility ? (open ? session.color : .gray.opacity(0.7)) : .white.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
                Text("volatility").font(.caption2).foregroundStyle(.tertiary)
            }
            Text(session.pairs.joined(separator: "  ·  "))
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(border: selected ? session.color.opacity(0.6) : nil)
        .saturation(open ? 1 : 0)
        .opacity(open ? 1 : 0.55)
    }
}

// MARK: - Small components

struct PulseDot: View {
    let color: Color
    let active: Bool
    // Static glow on purpose: the old repeatForever pulse kept the renderer
    // at full frame rate forever and measurably cost battery.
    var body: some View {
        Circle().fill(active ? color : .gray.opacity(0.5))
            .frame(width: 9, height: 9)
            .shadow(color: active ? color.opacity(0.9) : .clear, radius: active ? 5 : 0)
    }
}

struct LiquidityBar: View {
    let value: Int
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(value) / 100)
            }
        }
        .frame(height: 8)
    }
}

struct InfoChip: View {
    let title: String
    let value: String
    var accent: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.callout.bold()).monospacedDigit()
                .foregroundStyle(accent ?? .primary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func glassCard(border: Color? = nil) -> some View {
        self
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(border ?? .white.opacity(0.09), lineWidth: 1))
    }
}
