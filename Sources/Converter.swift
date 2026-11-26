import Foundation

struct ConvertedTime {
    let instant: Date
    let clock: String
    let source: Zones.Choice
    let sourceLabel: String
    let usesDefaultZone: Bool
    let fold: String?

    var menuZoneName: String {
        switch source.id {
        case "America/Los_Angeles": return "LA"
        case "America/New_York": return "NYC"
        default:
            if source.id.contains("/") { return source.label }
            if sourceLabel.count <= 5 && sourceLabel.allSatisfy(\.isLetter) {
                return sourceLabel.uppercased()
            }
            return source.label
        }
    }
}
struct ConversionReport {
    var times: [ConvertedTime] = []
    var messages: [String] = []
    var questions: [(String, [Zones.Choice])] = []
}

private struct Hit {
    let range: NSRange
    let value: String
    let parts: [String]
    var end: Int { NSMaxRange(range) }
}

private extension NSRegularExpression {
    convenience init(_ pattern: String) { try! self.init(pattern: pattern) }
    func hits(_ string: String) -> [Hit] {
        let ns = string as NSString
        return matches(in: string, range: NSRange(location: 0, length: ns.length)).map { m in
            let groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            return Hit(range: m.range, value: groups[0], parts: groups)
        }
    }
}

enum Converter {
    static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let monthPattern = #"jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"#
    private static let dates = NSRegularExpression(#"(?i)(?<![a-z0-9])(?:(\d{4})-(\d{1,2})-(\d{1,2})|("# + monthPattern + #")\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?|(\d{1,2})(?:st|nd|rd|th)?\s+("# + monthPattern + #")(?:,?\s+(\d{4}))?|(today|tomorrow|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday))(?![a-z0-9]|:)|(?<!\d)(\d{4})-(\d{2})-(\d{2})(?=T\d)"#)
    private static let numericDate = NSRegularExpression(#"(?<!\d)(?:\d{1,2}/\d{1,2}(?:/\d{2,4})?|\d{1,2}[.-]\d{1,2}[.-]\d{2,4})(?!\d)"#)
    private static let clocks = NSRegularExpression(#"(?i)(?:(?<![\p{L}\d:+.\-])|(?<=\dT)|(?<=[mM.]-))(?:(\d{1,2})(?::(\d{2})(?::(\d{2}))?)?(?:\s*([ap])\.?m\.?)?|(noon|midnight))(?!\d|:[0-9])"#)
    private static let zones = NSRegularExpression({
        let names = Zones.aliases.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return #"(?i)(?:(?<![\p{L}_])(?:UTC|GMT)\s*[+\-−]\s*\d{1,4}(?::\d{2})?|(?<=\d)[+\-−]\d{2}:?\d{2}(?!\d)|(?<!\S)[+\-−]\d{2}:?\d{2}(?!\d)|(?<=\d)Z\b|(?<![\p{L}\d_/])(?:"# + names + #")(?![\p{L}\d_/]))"#
    }())
    private static let offset = NSRegularExpression(#"(?i)^(?:UTC|GMT)?\s*([+\-−])\s*(\d{1,2})(?::?(\d{2}))?$"#)
    private static let shortRange = NSRegularExpression(#"(?i)(?<![\d:\-/])(\d{1,2})(:\d{2})?\s*[-–—]\s*(\d{1,2})(:\d{2})?\s*([ap])\.?m\.?(?![a-z])"#)
    private static func expandRanges(_ line: String) -> String {
        let expanded = NSMutableString(string: line)
        for hit in shortRange.hits(line).reversed() {
            let p = hit.parts
            guard let start = Int(p[1]), let end = Int(p[3]), (1...12).contains(start), (1...12).contains(end) else { continue }
            let endPM = p[5].lowercased() == "p"
            // An omitted AM/PM starts at the nearest preceding reading of that clock.
            let startMinutes = start % 12 * 60 + (Int(p[2].dropFirst()) ?? 0)
            let endMinutes = end % 12 * 60 + (Int(p[4].dropFirst()) ?? 0)
            let startPM = (startMinutes > endMinutes) != endPM
            let left = p[1] + p[2] + (startPM ? " PM" : " AM")
            let right = p[3] + p[4] + (endPM ? " PM" : " AM")
            expanded.replaceCharacters(in: hit.range, with: left + " – " + right)
        }
        return expanded as String
    }
    private static let unknown = NSRegularExpression(#"^\s+([A-Z]{2,6})(?:\b|$)"#)

    static func calendar(_ tz: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = tz
        return calendar
    }

    private static func sourceDay(_ hit: Hit?, now: Date, in cal: Calendar, override: DateComponents?) -> DateComponents {
        let current = cal.dateComponents([.year,.month,.day], from: now)
        guard let hit else { return override ?? current }
        let p = hit.parts
        if !p[1].isEmpty || !p[11].isEmpty {
            let i = p[1].isEmpty ? 11 : 1
            return DateComponents(year: Int(p[i]), month: Int(p[i+1]), day: Int(p[i+2]))
        }
        if !p[4].isEmpty || !p[8].isEmpty {
            let md = !p[4].isEmpty
            let month = months.firstIndex(of: String(p[md ? 4 : 8].lowercased().prefix(3)))! + 1
            return DateComponents(year: Int(p[md ? 6 : 9]) ?? current.year, month: month, day: Int(p[md ? 5 : 7]))
        }
        let word = p[10].lowercased()
        let weekdays = ["sunday","monday","tuesday","wednesday","thursday","friday","saturday"]
        let advance = weekdays.firstIndex(of: word).map { ($0 + 1 - cal.component(.weekday, from: now) + 7) % 7 }
            ?? (word == "tomorrow" ? 1 : word == "yesterday" ? -1 : 0)
        return cal.dateComponents([.year,.month,.day], from: cal.date(byAdding: .day, value: advance, to: now)!)
    }
    private static func choices(_ h: Hit) -> [Zones.Choice] {
        if h.value.lowercased() == "z" { return [Zones.fixed(0)] }
        if let named = Zones.aliases[h.value.lowercased()] { return named }
        guard let m = offset.hits(h.value).first, let hour = Int(m.parts[2]) else { return [] }
        let minute = Int(m.parts[3]) ?? 0
        guard minute < 60, hour <= 14, hour < 14 || minute == 0 else { return [] }
        return [Zones.fixed((hour * 60 + minute) * (m.parts[1] == "+" ? 1 : -1))]
    }
    static func convert(_ text: String, fallback: Zones.Choice, now: Date = Date(), day: DateComponents? = nil,
                        resolutions: [String: String] = [:]) -> ConversionReport {
        var result = ConversionReport()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return result }
        guard text.utf16.count <= 16000 else {
            result.messages = ["Use a shorter excerpt (up to 16,000 characters)."]
            return result
        }
        let lines = text.components(separatedBy: .newlines).map(expandRanges)
        let zoneHits = lines.map { zones.hits($0) }
        let uniqueZones = Dictionary(grouping: zoneHits.flatMap { $0 }, by: { $0.value.lowercased() })
        let sharedZone = uniqueZones.count == 1 ? uniqueZones.values.first?.first : nil
        var lastDate: Hit?
        var lastZoneHeader: Hit?
        let allDates = lines.flatMap { dates.hits($0) }
        let sharedDate = Set(allDates.map { $0.value.lowercased() }).count == 1 ? allDates.first : nil
        var unsafeDate = false
        for (i,line) in lines.enumerated() {
            let ns = line as NSString
            let dz = dates.hits(line), zz = zoneHits[i]
            if !numericDate.hits(line).filter({ n in
                !(dz + zz).contains { NSIntersectionRange(n.range, $0.range).length > 0 }
            }).isEmpty {
                unsafeDate = true
                result.messages.append("Write the date as YYYY-MM-DD or spell out the month.")
            } else if !dz.isEmpty { unsafeDate = false }
            let matches = clocks.hits(line).filter { h in
                if (dz + zz).contains(where: { NSIntersectionRange(h.range, $0.range).length > 0 }) { return false }
                if !h.parts[2].isEmpty || !h.parts[4].isEmpty || !h.parts[5].isEmpty { return true }
                // A bare hour must stand alone or touch a named zone.
                let adjacent = zz.contains { z in
                    let left = min(h.end, z.end), right = max(h.range.location, z.range.location)
                    return right >= left && right - left <= 2 && ns.substring(with: NSRange(location: left,length: right-left)).trimmingCharacters(in: .whitespaces).isEmpty
                }
                return adjacent || line.trimmingCharacters(in: .whitespaces) == h.value
            }
            var previousClock: (end: Int, seconds: Int, source: String, day: DateComponents)?
            for (j,h) in matches.enumerated() {
                guard !unsafeDate else { continue }
                let next = j+1 < matches.count ? matches[j+1].range.location : ns.length
                let suffix = zz.first { $0.range.location >= h.end && $0.range.location < next }
                let prefix = zz.last { $0.end <= h.range.location }
                let separators = CharacterSet(charactersIn: "/;|,")
                func isSeparated(_ lower: Int, _ upper: Int) -> Bool {
                    ns.substring(with: NSRange(location: lower, length: upper - lower)).rangeOfCharacter(from: separators) != nil
                }
                let prefixInClause = prefix.flatMap { isSeparated($0.end, h.range.location) ? nil : $0 }
                let suffixInClause = suffix.flatMap { isSeparated(h.end, $0.range.location) ? nil : $0 }
                if suffixInClause == nil, let token = unknown.hits(ns.substring(from: h.end)).first?.parts[1],
                   !["ON","AT","TO","IN","AM","PM"].contains(token), Zones.aliases[token.lowercased()] == nil {
                    result.messages.append("Unrecognized zone “" + token + "”. Use a city or UTC offset.")
                    continue
                }
                let zoneHit = suffixInClause ?? prefixInClause ?? suffix ?? prefix ?? lastZoneHeader ?? sharedZone
                var choice = fallback
                if let z = zoneHit {
                    let options = choices(z)
                    if let selected = options.first(where: { $0.id == resolutions[z.value.uppercased()] }) ?? (options.count == 1 ? options[0] : nil) {
                        choice = selected
                    } else if options.isEmpty { result.messages.append("Check the UTC offset “" + z.value + "”."); continue }
                    else {
                        let key = z.value.uppercased()
                        if !result.questions.contains(where: { $0.0 == key }) { result.questions.append((key, options)) }
                        continue
                    }
                }
                var hour = Int(h.parts[1]) ?? (h.parts[5].lowercased() == "noon" ? 12 : 0)
                let minute = Int(h.parts[2]) ?? 0, second = Int(h.parts[3]) ?? 0
                if !h.parts[4].isEmpty {
                    guard (1...12).contains(hour) else { result.messages.append("Check the hour in “" + h.value + "”."); continue }
                    hour = hour % 12 + (h.parts[4].lowercased() == "p" ? 12 : 0)
                }
                guard hour < 24, minute < 60, second < 60 else { result.messages.append("Check the time “" + h.value + "”."); continue }
                let cal = calendar(choice.zone)
                let localDate = dz.last { $0.end <= h.range.location } ?? dz.first ?? lastDate ?? sharedDate
                var components = sourceDay(localDate, now: now, in: cal, override: day)
                let clockSeconds = hour * 3600 + minute * 60 + second
                if let previous = previousClock, previous.source == choice.id {
                    let gap = ns.substring(with: NSRange(location: previous.end, length: h.range.location - previous.end))
                               .trimmingCharacters(in: .whitespaces).lowercased()
                    if ["-", "–", "—", "to"].contains(gap), let priorDay = cal.date(from: previous.day),
                       let endDay = cal.date(byAdding: .day, value: clockSeconds < previous.seconds ? 1 : 0, to: priorDay) {
                        components = cal.dateComponents([.year, .month, .day], from: endDay)
                    }
                }
                previousClock = (h.end, clockSeconds, choice.id, components)
                var noon = components; noon.hour = 12
                guard let anchor = cal.date(from: noon), cal.dateComponents([.year,.month,.day], from: anchor) == components else {
                    result.messages.append("That calendar date does not exist."); continue
                }
                // Interpret the wall clock as UTC, then undo every possible source
                // offset around it. Round-tripping handles folds of any duration.
                var wall = components
                wall.hour = hour; wall.minute = minute; wall.second = second
                let neutral = calendar(TimeZone(secondsFromGMT: 0)!).date(from: wall)!
                let low = neutral.addingTimeInterval(-86400), high = neutral.addingTimeInterval(86400)
                var offsets: Set<Int> = [choice.zone.secondsFromGMT(for: low), choice.zone.secondsFromGMT(for: high)]
                var cursor = low
                while let change = choice.zone.nextDaylightSavingTimeTransition(after: cursor), change <= high {
                    offsets.insert(choice.zone.secondsFromGMT(for: change))
                    cursor = change.addingTimeInterval(1)
                }
                let instants = offsets.map { neutral.addingTimeInterval(-Double($0)) }.filter {
                    cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: $0) == wall
                }.sorted()
                if instants.isEmpty { result.messages.append("“" + h.value + "” is skipped by a clock change in " + choice.label + ".") }
                for (k,date) in instants.enumerated() {
                    result.times.append(ConvertedTime(instant: date, clock: h.value, source: choice,
                        sourceLabel: zoneHit?.value ?? fallback.label,
                        usesDefaultZone: zoneHit == nil,
                        fold: instants.count > 1 ? (k == 0 ? "First occurrence" : "Second occurrence") : nil))
                }
            }
            if let d = dz.last { lastDate = d }
            if matches.isEmpty, let z = zz.last { lastZoneHeader = z }
            else if !zz.isEmpty { lastZoneHeader = nil }
        }
        var seen = Set<String>()
        result.messages = result.messages.filter { seen.insert($0).inserted }
        if result.times.isEmpty && result.questions.isEmpty && result.messages.isEmpty {
            result.messages = ["Try a time such as 9:30 AM Tokyo."]
        }
        return result
    }
}
