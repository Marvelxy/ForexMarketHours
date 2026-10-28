// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelous Akpotu (Marvelxy)
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI

// MARK: - Session model (hours expressed in each market's local time)

struct TradingSession: Identifiable, Hashable {
    let id: String
    let city: String
    let region: String
    let timeZoneID: String
    /// Opening hour in the session's own timezone (0..<24, fractional allowed).
    let openLocal: Double
    /// Closing hour in the session's own timezone (0..<24). May be <= openLocal
    /// when the session wraps local midnight.
    let closeLocal: Double
    let color: Color
    let pairs: [String]
    let blurb: String
    /// 1...5 baseline volatility
    let volatility: Int

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// The instant at `hour` local time on the local day containing `reference`.
    private func localDate(hour: Double, on reference: Date) -> Date {
        let start = calendar.startOfDay(for: reference)
        return start.addingTimeInterval(hour * 3600)
    }

    /// Opening instant on the local day containing `reference`.
    func openDate(on reference: Date) -> Date {
        localDate(hour: openLocal, on: reference)
    }

    /// Closing instant on the local day containing `reference`.
    func closeDate(on reference: Date) -> Date {
        var close = localDate(hour: closeLocal, on: reference)
        if closeLocal <= openLocal {
            close = calendar.date(byAdding: .day, value: 1, to: close) ?? close
        }
        return close
    }

    /// True if the given instant falls inside the session (Monday–Friday local).
    /// Weekend filtering makes the session list naturally empty over the weekend.
    func isOpen(at date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sun ... 7 = Sat
        guard weekday != 1, weekday != 7 else { return false }
        return date >= openDate(on: date) && date < closeDate(on: date)
    }

    /// Session length in hours (local wall time).
    var lengthHours: Double {
        closeLocal > openLocal ? closeLocal - openLocal : (24 - openLocal) + closeLocal
    }

    /// Elapsed hours since open for an instant known to be inside the session.
    func elapsedHours(at date: Date) -> Double {
        date.timeIntervalSince(openDate(on: date)) / 3600
    }

    /// Next open instant strictly after `date` (skips weekends).
    func nextOpenDate(after date: Date) -> Date {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            let weekday = calendar.component(.weekday, from: day)
            if weekday != 1, weekday != 7 {
                let open = localDate(hour: openLocal, on: day)
                if open > date { return open }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)
                ?? day.addingTimeInterval(86_400)
        }
        return date
    }

    /// Hours until the next state change (open or close) from an instant.
    func hoursToNextChange(from date: Date) -> Double {
        let boundary = isOpen(at: date) ? closeDate(on: date) : nextOpenDate(after: date)
        return max(0, boundary.timeIntervalSince(date) / 3600)
    }

    /// UTC wall-hour (0..<24) at which the session opens on the reference day.
    func openUTCHour(on reference: Date) -> Double {
        MarketData.utcHour(of: openDate(on: reference))
    }

    /// UTC wall-hour (0..<24) at which the session closes on the reference day.
    func closeUTCHour(on reference: Date) -> Double {
        MarketData.utcHour(of: closeDate(on: reference))
    }
}

enum MarketData {
    static let sessions: [TradingSession] = [
        TradingSession(
            id: "sydney", city: "Sydney", region: "Asia-Pacific",
            timeZoneID: "Australia/Sydney",
            openLocal: 7, closeLocal: 16,
            color: Color(red: 0.13, green: 0.83, blue: 0.93),
            pairs: ["AUD/USD", "NZD/USD", "AUD/JPY"],
            blurb: "Opens the trading week out of Wellington/Sydney. Calm, range-bound flow — ideal for patient range strategies on AUD and NZD pairs.",
            volatility: 2
        ),
        TradingSession(
            id: "tokyo", city: "Tokyo", region: "Asian",
            timeZoneID: "Asia/Tokyo",
            openLocal: 9, closeLocal: 18,
            color: Color(red: 0.98, green: 0.75, blue: 0.23),
            pairs: ["USD/JPY", "EUR/JPY", "GBP/JPY"],
            blurb: "The Asian powerhouse. JPY crosses wake up here; watch for Bank of Japan headlines and steady trend-building into the European handover.",
            volatility: 3
        ),
        TradingSession(
            id: "frankfurt", city: "Frankfurt", region: "European",
            timeZoneID: "Europe/Berlin",
            openLocal: 8, closeLocal: 17,
            color: Color(red: 0.70, green: 0.45, blue: 0.95),
            pairs: ["EUR/USD", "EUR/GBP", "USD/CHF"],
            blurb: "Continental Europe's open — DAX, ECB and euro flow. Paired with London it forms the deepest EUR liquidity of the day.",
            volatility: 4
        ),
        TradingSession(
            id: "london", city: "London", region: "European",
            timeZoneID: "Europe/London",
            openLocal: 8, closeLocal: 17,
            color: Color(red: 0.38, green: 0.65, blue: 1.0),
            pairs: ["EUR/USD", "GBP/USD", "EUR/GBP", "XAU/USD"],
            blurb: "The highest-volume session on the planet. EUR, GBP and CHF pairs move most here — breakouts, tightest spreads, and the morning order-flow surge. Gold (XAU/USD) runs hottest here into New York.",
            volatility: 5
        ),
        TradingSession(
            id: "newyork", city: "New York", region: "North American",
            timeZoneID: "America/New_York",
            openLocal: 8, closeLocal: 17,
            color: Color(red: 0.20, green: 0.83, blue: 0.60),
            pairs: ["EUR/USD", "GBP/USD", "USD/CAD", "XAU/USD"],
            blurb: "Wall Street hours. US data drops land here and the London overlap delivers peak liquidity — the most traded window of the day, and prime time for gold (XAU/USD).",
            volatility: 4
        ),
    ]

    static func session(_ id: String) -> TradingSession? {
        sessions.first { $0.id == id }
    }

    struct Overlap: Identifiable {
        let id: String
        let name: String
        let firstSessionID: String
        let secondSessionID: String
        let note: String
        let intensity: Int // 1...3

        func isActive(at date: Date) -> Bool {
            guard let a = MarketData.session(firstSessionID),
                  let b = MarketData.session(secondSessionID) else { return false }
            return a.isOpen(at: date) && b.isOpen(at: date)
        }
    }

    static let overlaps: [Overlap] = [
        Overlap(id: "syd-tyo", name: "Sydney × Tokyo",
                firstSessionID: "sydney", secondSessionID: "tokyo",
                note: "Longest overlap, gentle Asia-Pacific flow", intensity: 1),
        Overlap(id: "tyo-fra", name: "Tokyo × Frankfurt",
                firstSessionID: "tokyo", secondSessionID: "frankfurt",
                note: "Asia closes as the continent opens", intensity: 1),
        Overlap(id: "fra-lon", name: "Frankfurt × London",
                firstSessionID: "frankfurt", secondSessionID: "london",
                note: "Core European hours — deepest EUR liquidity", intensity: 2),
        Overlap(id: "lon-ny", name: "London × New York",
                firstSessionID: "london", secondSessionID: "newyork",
                note: "Peak liquidity — tightest spreads on majors", intensity: 3),
    ]

    // MARK: Clock helpers

    static func utcHour(of date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    static func openSessions(at date: Date) -> [TradingSession] {
        sessions.filter { $0.isOpen(at: date) }
    }

    static func activeOverlaps(at date: Date) -> [Overlap] {
        overlaps.filter { $0.isActive(at: date) }
    }

    /// The spot market is closed whenever no session is running (the weekend).
    static func marketClosed(at date: Date) -> Bool {
        sessions.allSatisfy { !$0.isOpen(at: date) }
    }

    /// Earliest next session open after `date`.
    static func nextMarketOpen(after date: Date) -> Date? {
        sessions.map { $0.nextOpenDate(after: date) }.min()
    }

    /// 0...100 liquidity gauge from open sessions + overlaps.
    static func liquidity(at date: Date) -> (value: Int, label: String) {
        let open = openSessions(at: date)
        let ov = activeOverlaps(at: date)
        var score = open.count * 22 + ov.reduce(0) { $0 + $1.intensity * 8 }
        if open.isEmpty { score = 3 }
        score = min(100, score)
        let label: String
        switch score {
        case 0..<25: label = "Quiet"
        case 25..<55: label = "Active"
        case 55..<85: label = "High"
        default: label = "Peak"
        }
        return (score, label)
    }

    static func countdownString(hours: Double) -> String {
        let totalSeconds = max(0, Int(hours * 3600))
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return String(format: "%ds", s)
    }

    // MARK: Wall-hour segments (for the 24-hour map)

    /// [lower, upper] wall-hour segments handling midnight wrap.
    static func segments(open a: Double, close b: Double) -> [ClosedRange<Double>] {
        let s = (a + 24).truncatingRemainder(dividingBy: 24)
        let e = (b + 24).truncatingRemainder(dividingBy: 24)
        if e > s { return [s...e] }
        if e == s { return [0...24] }
        return [s...24, 0...e].filter { $0.upperBound > $0.lowerBound }
    }

    static func intersect(_ lhs: [ClosedRange<Double>],
                          _ rhs: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        for a in lhs {
            for b in rhs {
                let lower = max(a.lowerBound, b.lowerBound)
                let upper = min(a.upperBound, b.upperBound)
                if upper > lower { result.append(lower...upper) }
            }
        }
        return result
    }

    /// Session window expressed as segments in the given display zone.
    static func displaySegments(for session: TradingSession,
                                in zone: DisplayZone,
                                reference: Date) -> [ClosedRange<Double>] {
        let open = zone.wallHour(fromUTCHour: session.openUTCHour(on: reference), reference: reference)
        let close = zone.wallHour(fromUTCHour: session.closeUTCHour(on: reference), reference: reference)
        return segments(open: open, close: close)
    }

    /// Overlap window (intersection of both sessions) in the given display zone.
    static func displaySegments(for overlap: Overlap,
                                in zone: DisplayZone,
                                reference: Date) -> [ClosedRange<Double>] {
        guard let a = session(overlap.firstSessionID),
              let b = session(overlap.secondSessionID) else { return [] }
        return intersect(displaySegments(for: a, in: zone, reference: reference),
                         displaySegments(for: b, in: zone, reference: reference))
    }

    static func rangeString(for overlap: Overlap,
                            in zone: DisplayZone,
                            reference: Date) -> String {
        let segments = displaySegments(for: overlap, in: zone, reference: reference)
        guard !segments.isEmpty else { return "--" }
        return segments
            .map { "\(zone.hourLabel($0.lowerBound)) – \(zone.hourLabel($0.upperBound))" }
            .joined(separator: " · ")
    }
}

// MARK: - Display time zones

enum DisplayZone: String, CaseIterable, Identifiable {
    case local, utc, sydney, tokyo, frankfurt, london, newyork
    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local"
        case .utc: return "UTC"
        case .sydney: return "Sydney"
        case .tokyo: return "Tokyo"
        case .frankfurt: return "Frankfurt"
        case .london: return "London"
        case .newyork: return "New York"
        }
    }

    var timeZone: TimeZone {
        switch self {
        case .local: return .current
        case .utc: return TimeZone(identifier: "UTC")!
        case .sydney: return TimeZone(identifier: "Australia/Sydney") ?? .current
        case .tokyo: return TimeZone(identifier: "Asia/Tokyo") ?? .current
        case .frankfurt: return TimeZone(identifier: "Europe/Berlin") ?? .current
        case .london: return TimeZone(identifier: "Europe/London") ?? .current
        case .newyork: return TimeZone(identifier: "America/New_York") ?? .current
        }
    }

    var abbreviation: String {
        timeZone.abbreviation(for: Date()) ?? label
    }

    /// "9:00 PM" style formatting of a wall hour in this zone.
    func hourLabel(_ wallHour: Double) -> String {
        let h = Int(wallHour) % 24
        let m = Int((wallHour - floor(wallHour)) * 60)
        var comps = DateComponents()
        comps.hour = h; comps.minute = m
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        // Anchor on a fixed reference day; only wall time matters.
        comps.year = 2026; comps.month = 1; comps.day = 5
        guard let d = cal.date(from: comps) else { return "--" }
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = "ha"
        return f.string(from: d).lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// Convert a UTC wall-hour on the reference day into this zone's wall-hour (0..<24).
    /// Handles DST offsets and wrap-around.
    func wallHour(fromUTCHour utc: Double, reference: Date) -> Double {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let startOfUTCDay = utcCal.startOfDay(for: reference)
        let instant = startOfUTCDay.addingTimeInterval(utc * 3600)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: instant)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// Wall-hour of an instant in this zone.
    func wallHour(of date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    func clockString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = "h:mm:ss a"
        return f.string(from: date)
    }

    func weekdayString(for date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }

    /// Session hours on the reference day, shown in this zone.
    func rangeString(for session: TradingSession, reference: Date) -> String {
        "\(hourLabel(wallHour(of: session.openDate(on: reference)))) – \(hourLabel(wallHour(of: session.closeDate(on: reference))))"
    }
}
