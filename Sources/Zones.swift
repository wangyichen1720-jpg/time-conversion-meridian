import Foundation

struct ZoneOption: Hashable, Identifiable {
    let id: String
    let label: String
    var zone: TimeZone { TimeZone(identifier: id)! }
}

enum Zones {
    static let regions = Set(["Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific"])
    static let all: [ZoneOption] = {
        let identifiers = Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", "Asia/Kolkata", "Asia/Kathmandu", "Europe/Kyiv", "America/Nuuk"])
        return identifiers.filter { TimeZone(identifier: $0) != nil && ($0 == "UTC" || regions.contains(String($0.split(separator: "/").first ?? ""))) }
            .map { ZoneOption(id: $0, label: label($0)) }
            .sorted { ($0.label, $0.id) < ($1.label, $1.id) }
    }()
    static func label(_ id: String) -> String {
        String(id.split(separator: "/").last ?? Substring(id)).replacingOccurrences(of: "_", with: " ")
    }
    static func menuName(_ id: String) -> String {
        switch id {
        case "Asia/Shanghai": return "SH"
        case "America/Los_Angeles": return "LA"
        case "America/New_York": return "NYC"
        default: return label(id)
        }
    }
    static func utcOffset(_ seconds: Int) -> String {
        let minutes = abs(seconds) / 60
        return String(format: "UTC%@%02d:%02d", seconds < 0 ? "−" : "+", minutes / 60, minutes % 60)
    }
    static func displayName(_ name: String, in zone: TimeZone, at date: Date = Date()) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let offset = utcOffset(seconds)
        let minutes = abs(seconds) / 60
        let formatted = String(format: "UTC%@%d:%02d", seconds < 0 ? "−" : "+", minutes / 60, minutes % 60)
        if name == offset { return formatted }
        if name.hasSuffix("(" + offset + ")") { return name.replacingOccurrences(of: offset, with: formatted) }
        return name + " (" + formatted + ")"
    }
    static func displayName(_ identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return label(identifier) }
        return displayName(label(identifier), in: zone)
    }
    struct Choice: Hashable {
        let id: String
        let label: String
        let zone: TimeZone
    }
    static func region(_ id: String) -> Choice {
        Choice(id: id, label: label(id), zone: TimeZone(identifier: id)!)
    }
    static func fixed(_ minutes: Int) -> Choice {
        let label = utcOffset(minutes * 60)
        return Choice(id: label, label: label, zone: TimeZone(secondsFromGMT: minutes * 60)!)
    }
    static let aliases: [String: [Choice]] = {
        var table: [String: [Choice]] = [:]
        for item in all {
            let choice = region(item.id)
            table[item.id.lowercased()] = [choice]
            table[item.label.lowercased(), default: []].append(choice)
        }
        func set(_ keys: String, _ zones: [Choice]) {
            for key in keys.components(separatedBy: "|") { table[key.lowercased()] = zones }
        }
        let named = [
            ("PT|Pacific Time|Pacific", "America/Los_Angeles"), ("ET|Eastern Time|Eastern", "America/New_York"),
            ("CT|Central Time", "America/Chicago"), ("MT|Mountain Time", "America/Denver"),
            ("UK time|UK", "Europe/London"), ("Korea|Korea Standard Time", "Asia/Seoul"),
            ("Japan", "Asia/Tokyo"), ("China|Beijing|China Standard Time", "Asia/Shanghai"),
            ("India|Mumbai|New Delhi|India Standard Time", "Asia/Kolkata"), ("Nepal", "Asia/Kathmandu"),
            ("NYC", "America/New_York"), ("San Francisco|Seattle|California", "America/Los_Angeles"),
            ("UAE|Abu Dhabi", "Asia/Dubai"), ("Germany", "Europe/Berlin"), ("France", "Europe/Paris")
        ]
        for (keys, id) in named { set(keys, [region(id)]) }
        let offsets = [
            ("GMT|UTC|Zulu", 0), ("PST|Pacific Standard Time", -480), ("PDT|Pacific Daylight Time", -420), ("MST|Mountain Standard Time", -420), ("MDT|Mountain Daylight Time", -360),
            ("CDT|Central Daylight Time", -300), ("EST|Eastern Standard Time", -300), ("EDT|Eastern Daylight Time", -240), ("Central Standard Time", -360), ("AKST", -540), ("AKDT", -480),
            ("HST", -600), ("CET", 60), ("CEST", 120), ("EET", 120), ("EEST", 180),
            ("JST|KST", 540), ("HKT|SGT|PHT|AWST", 480), ("AEST", 600), ("AEDT", 660),
            ("ACST", 570), ("ACDT", 630), ("NZST", 720), ("NZDT", 780), ("MSK", 180)
        ]
        for (keys, offset) in offsets { set(keys, [fixed(offset)]) }
        func meaning(_ name: String, _ minutes: Int) -> Choice {
            let z = fixed(minutes)
            return Choice(id: name, label: name + " (" + z.label + ")", zone: z.zone)
        }
        set("CST", [meaning("China Standard", 480), meaning("Central Standard", -360), meaning("Cuba Standard", -300)])
        set("IST", [meaning("India Standard", 330), meaning("Irish Standard", 60), meaning("Israel Standard", 120)])
        set("BST", [meaning("British Summer", 60), meaning("Bangladesh Standard", 360), meaning("Bougainville Standard", 660)])
        return table
    }()
}
