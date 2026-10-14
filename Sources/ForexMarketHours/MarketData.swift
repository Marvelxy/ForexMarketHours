// Forex Market Hours — interactive forex session visualizer for macOS.
// Copyright (C) 2026 Marvelxy
// SPDX-License-Identifier: GPL-3.0-or-later — see LICENSE.
import SwiftUI

// MARK: - Session model (hours expressed in standard UTC anchors)

struct TradingSession: Identifiable, Hashable {
    let id: String
    let city: String
    let region: String
    let timeZoneID: String
    /// Opening hour in UTC (0..<24, fractional allowed)
    let openUTC: Double
    /// Closing hour in UTC (0..<24). May be <= openUTC when the session wraps midnight.
    let closeUTC: Double
    let color: Color
    let pairs: [String]
    let blurb: String
    /// 1...5 baseline volatility
    let volatility: Int

    /// True if the given UTC wall-hour falls inside the session.
    func isOpen(atUTCHour h: Double) -> Bool {
        let t = h.truncatingRemainder(dividingBy: 24)
        if closeUTC > openUTC {
            return t >= openUTC && t < closeUTC
        } else {
            return t >= openUTC || t < closeUTC
        }
    }

    /// Session length in hours.
    var lengthHours: Double {
        closeUTC > openUTC ? closeUTC - openUTC : (24 - openUTC) + closeUTC
    }

    /// Elapsed hours since open for a UTC hour known to be inside the session.
    func elapsedHours(atUTCHour h: Double) -> Double {
        let t = h.truncatingRemainder(dividingBy: 24)
        if closeUTC > openUTC { return t - openUTC }
        return t >= openUTC ? t - openUTC : (24 - openUTC) + t
    }

    /// Hours until the next state change (open or close) from a UTC hour.
    func hoursToNextChange(fromUTCHour h: Double) -> Double {
        let t = h.truncatingRemainder(dividingBy: 24)
        let open = isOpen(atUTCHour: t)
        let boundary = open ? closeUTC : openUTC
        var delta = boundary - t
        while delta <= 0 { delta += 24 }
        return delta
    }
}

enum MarketData {
    static let sessions: [TradingSession] = [
        TradingSession(
            id: "sydney", city: "Sydney", region: "Asia-Pacific",
            timeZoneID: "Australia/Sydney",
            openUTC: 21, closeUTC: 6,
            color: Color(red: 0.13, green: 0.83, blue: 0.93),
            pairs: ["AUD/USD", "NZD/USD", "AUD/JPY"],
            blurb: "Opens the trading week out of Wellington/Sydney. Calm, range-bound flow — ideal for patient range strategies on AUD and NZD pairs.",
            volatility: 2
        ),
        TradingSession(
            id: "tokyo", city: "Tokyo", region: "Asian",
            timeZoneID: "Asia/Tokyo",
            openUTC: 0, closeUTC: 9,
            color: Color(red: 0.98, green: 0.75, blue: 0.23),
            pairs: ["USD/JPY", "EUR/JPY", "GBP/JPY"],
            blurb: "The Asian powerhouse. JPY crosses wake up here; watch for Bank of Japan headlines and steady trend-building into the European handover.",
            volatility: 3
        ),
        TradingSession(
            id: "frankfurt", city: "Frankfurt", region: "European",
            timeZoneID: "Europe/Berlin",
            openUTC: 6, closeUTC: 15,
            color: Color(red: 0.70, green: 0.45, blue: 0.95),
            pairs: ["EUR/USD", "EUR/GBP", "USD/CHF"],
            blurb: "Continental Europe's open — DAX, ECB and euro flow. Paired with London it forms the deepest EUR liquidity of the day.",
            volatility: 4
        ),
        TradingSession(
            id: "london", city: "London", region: "European",
            timeZoneID: "Europe/London",
            openUTC: 7, closeUTC: 16,
            color: Color(red: 0.38, green: 0.65, blue: 1.0),
            pairs: ["EUR/USD", "GBP/USD", "EUR/GBP", "XAU/USD"],
            blurb: "The highest-volume session on the planet. EUR, GBP and CHF pairs move most here — breakouts, tightest spreads, and the morning order-flow surge. Gold (XAU/USD) runs hottest here into New York.",
            volatility: 5
        ),
        TradingSession(
            id: "newyork", city: "New York", region: "North American",
            timeZoneID: "America/New_York",
            openUTC: 12, closeUTC: 21,
            color: Color(red: 0.20, green: 0.83, blue: 0.60),
            pairs: ["EUR/USD", "GBP/USD", "USD/CAD", "XAU/USD"],
            blurb: "Wall Street hours. US data drops land here and the London overlap delivers peak liquidity — the most traded window of the day, and prime time for gold (XAU/USD).",
            volatility: 4
        ),
    ]

    struct Overlap: Identifiable {
        let id: String
        let name: String
        let startUTC: Double
        let endUTC: Double
        let note: String
        let intensity: Int // 1...3

        func isActive(atUTCHour h: Double) -> Bool {
            let t = h.truncatingRemainder(dividingBy: 24)
            if endUTC > startUTC { return t >= startUTC && t < endUTC }
            return t >= startUTC || t < endUTC
        }
    }

    static let overlaps: [Overlap] = [
        Overlap(id: "syd-tyo", name: "Sydney × Tokyo", startUTC: 0, endUTC: 6,
                note: "Longest overlap, gentle Asia-Pacific flow", intensity: 1),
        Overlap(id: "tyo-fra", name: "Tokyo × Frankfurt", startUTC: 6, endUTC: 9,
                note: "Asia closes as the continent opens", intensity: 1),
        Overlap(id: "fra-lon", name: "Frankfurt × London", startUTC: 7, endUTC: 15,
                note: "Core European hours — deepest EUR liquidity", intensity: 2),
        Overlap(id: "lon-ny", name: "London × New York", startUTC: 12, endUTC: 16,
                note: "Peak liquidity — tightest spreads on majors", intensity: 3),
    ]

    // MARK: Clock helpers

    static func utcHour(of date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    static func openSessions(atUTCHour h: Double) -> [TradingSession] {
        sessions.filter { $0.isOpen(atUTCHour: h) }
    }

    static func activeOverlaps(atUTCHour h: Double) -> [Overlap] {
        overlaps.filter { $0.isActive(atUTCHour: h) }
    }

    /// Forex is closed: all Saturday (UTC), Sunday before 21:00 UTC, Friday from 21:00 UTC.
    static func marketClosed(at date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wd = cal.component(.weekday, from: date) // 1=Sun ... 7=Sat
        let h = utcHour(of: date)
        if wd == 7 { return true }                       // Saturday
        if wd == 1 { return h < 21 }                     // Sunday before Sydney open
        if wd == 6 { return h >= 21 }                    // Friday after NY close
        return false
    }

    /// 0...100 liquidity gauge from open sessions + overlaps.
    static func liquidity(atUTCHour h: Double) -> (value: Int, label: String) {
        let open = openSessions(atUTCHour: h)
        let ov = activeOverlaps(atUTCHour: h)
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

    func rangeString(openUTC: Double, closeUTC: Double, reference: Date) -> String {
        "\(hourLabel(wallHour(fromUTCHour: openUTC, reference: reference))) – \(hourLabel(wallHour(fromUTCHour: closeUTC, reference: reference)))"
    }
}
