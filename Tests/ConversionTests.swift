import Foundation

@main enum ConversionTests {
    static func main() {
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-07-04T12:00:00Z")!
        let utc = Zones.region("UTC")
        var count = 0
        func check(_ text: String, _ expected: [String], source: String = "UTC",
                   resolutions: [String:String] = [:], day: DateComponents? = nil) {
            let r = Converter.convert(text, fallback: Zones.region(source), now: now, day: day, resolutions: resolutions)
            let actual = r.times.map { iso.string(from: $0.instant) }
            guard actual == expected else { fatalError("\(text) → \(actual), expected \(expected)\n\(r.messages)") }
            count += 1
        }
        check("9:30 AM Tokyo", ["2026-07-04T00:30:00Z"])
        check("11:45 pm PT", ["2026-07-05T06:45:00Z"])
        check("2026-12-31 11:45 PM New York", ["2027-01-01T04:45:00Z"])
        check("2026-07-04T09:30:12+05:45", ["2026-07-04T03:45:12Z"])
        check("2026-12-31T23:00Z", ["2026-12-31T23:00:00Z"])
        check("9 AM UTC+05:30", ["2026-07-04T03:30:00Z"])
        check("9:00 UTC−0330", ["2026-07-04T12:30:00Z"])
        check("9:00 UTC+8", ["2026-07-04T01:00:00Z"])
        check("9 AM -0400", ["2026-07-04T13:00:00Z"])
        check("3 PM ET / 12 PM PT", ["2026-07-04T19:00:00Z","2026-07-04T19:00:00Z"])
        check("Workshop\nJuly 8, 2026\n10:15 AM\nTokyo", ["2026-07-08T01:15:00Z"])
        check("15 January 2027 at noon London", ["2027-01-15T12:00:00Z"])
        check("midnight", ["2026-07-03T18:15:00Z"], source: "Asia/Kathmandu")
        check("tomorrow 8 PM", ["2026-07-05T20:00:00Z"])
        check("Monday 8 PM", ["2026-07-06T20:00:00Z"])
        check("10:15 KST", ["2025-02-12T01:15:00Z"], day: DateComponents(year: 2025, month: 2, day: 12))
        check("2026-11-01 1:30 am New York", ["2026-11-01T05:30:00Z","2026-11-01T06:30:00Z"])
        check("2026-03-08 2:30 am New York", [])
        check("2026-02-30 9 am", [])
        check("4 PM CST", ["2026-07-04T08:00:00Z"], resolutions: ["CST":"China Standard"])
        precondition(Converter.convert("4 PM CST", fallback: utc).questions.first?.1.count == 3)
        check("9pm PST", ["2026-07-05T05:00:00Z"])
        check("12:00 AM", ["2026-07-04T00:00:00Z"])
        check("12:00 PM", ["2026-07-04T12:00:00Z"])
        check("15:72 UTC", [])
        check("19:00 XYZ", [])
        check("29/12/2026 9 PM", [])
        check("4 PM UTC+16:00", [])
        check("4 PM America/Los_Angeles", ["2026-07-04T23:00:00Z"])
        check("9 PT", ["2026-07-04T16:00:00Z"])
        check("Workshop 2026", [])
        check("London 9am / Tokyo 10am", ["2026-07-04T08:00:00Z","2026-07-04T01:00:00Z"])
        check("9am Tokyo / 10am London", ["2026-07-04T00:00:00Z","2026-07-04T09:00:00Z"])
        check("9pm Eastern Standard Time", ["2026-07-05T02:00:00Z"])
        check("Version 1.2\nMeeting 7pm PT", ["2026-07-05T02:00:00Z"])
        check("11pm Tokyo", ["2026-07-04T14:00:00Z"])
        check("1:15am Australia/Adelaide", ["2026-07-03T15:45:00Z"])
        check("11pm PT, 8am XYZ", ["2026-07-05T06:00:00Z"])
        check("2026-04-05 01:45 Australia/Lord_Howe", ["2026-04-04T14:45:00Z","2026-04-04T15:15:00Z"])
        check("2026-10-04 02:15 Australia/Lord_Howe", [])
        check("3-4 PM PT", ["2026-07-04T22:00:00Z","2026-07-04T23:00:00Z"])
        check("9 am-11 am ET", ["2026-07-04T13:00:00Z","2026-07-04T15:00:00Z"])
        check("11:30–1 pm Tokyo", ["2026-07-04T02:30:00Z","2026-07-04T04:00:00Z"])
        check("2026-12-31 11–1 am Tokyo", ["2026-12-31T14:00:00Z","2026-12-31T16:00:00Z"])
        print("Passed \(count) conversion cases and the abbreviation-choice check.")
    }
}
