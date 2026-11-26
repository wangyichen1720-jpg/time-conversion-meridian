import SwiftUI
import AppKit

private let muted = Color(nsColor: .secondaryLabelColor)
private let field = Color(nsColor: .textBackgroundColor)
private let green = Color(red: 0.067, green: 0.213, blue: 0.182)
private let brass = Color(red: 0.90, green: 0.75, blue: 0.45)
private let rule = Color(nsColor: .separatorColor)

private struct IconButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let icon: String, label: String
    var action: () -> Void

    var body: some View {
        let button = Button(action: action) { Image(systemName: icon).frame(width: 15, height: 17) }
        Group {
            if #available(macOS 26.0, *), !reduceTransparency {
                button.buttonStyle(.glass).buttonBorderShape(.circle)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .controlSize(.regular).help(label).accessibilityLabel(label)
    }
}

private struct NavigationBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 7) { content }
            .padding(.horizontal, 16).frame(height: 46)
    }
}

struct Interface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    static let size = NSSize(width: 476, height: 430)
    @ObservedObject var model: Model
    var body: some View {
        Group {
            switch model.page {
            case .converter: converter
            case .settings: SettingsView(model: model)
            case .source, .destination: ZoneList(model: model).id(model.page == .source)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background {
            if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
        }
    }

    var converter: some View {
        VStack(spacing: 0) {
            TimelineView(.everyMinute) { timeline in
                ClockCard(model: model, now: timeline.date)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        textPanel.frame(maxWidth: .infinity)
                        imagePanel.frame(width: 166)
                    }
                    if let question = model.report.questions.first {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Which time zone is “" + question.0 + "”?").fontWeight(.semibold)
                            ForEach(question.1, id: \.id) { zone in
                                Button(zone.label) { model.resolutions[question.0] = zone.id }.buttonStyle(.link)
                            }
                        }.font(.system(size: 12))
                    }
                    ForEach(model.report.messages, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(muted) }
                    if let message = model.message { Text(message).font(.system(size: 12)) }
                }.padding(14)
            }
        }
    }

    private var textPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Time text").font(.system(size: 16, weight: .semibold))
                Spacer()
                if !model.text.isEmpty {
                    Button("Clear") { model.text = "" }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted)
                }
            }.frame(height: 23)
            TimeEditor(text: $model.text, pasteImage: { model.accept(.general, textAllowed: false) })
                .frame(height: 80)
                .background(field)
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("e.g. 9:30 AM Tokyo").foregroundStyle(muted).font(.system(size: 14))
                            .padding(.leading, 11).padding(.top, 9).allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(rule))
            Button { model.zoneList(destination: false) } label: {
                HStack(spacing: 4) {
                    Text("Default zone").foregroundStyle(muted)
                    Text(Zones.label(model.fallback)).fontWeight(.semibold).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }.buttonStyle(.plain).font(.system(size: 11)).frame(height: 22)
                .help("Source time zone for text without a zone")
        }
        .padding(13).background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(contrast == .increased ? Color.primary : rule))
    }

    private var imagePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screenshot").font(.system(size: 16, weight: .semibold)).frame(height: 23)
            VStack(spacing: 5) {
                Image(systemName: model.reading ? "text.viewfinder" : "photo.on.rectangle.angled")
                    .font(.system(size: 20)).accessibilityHidden(true)
                Text(model.reading ? "Reading image…" : "Drop or choose image")
                    .font(.system(size: 11, weight: .medium))
                if let name = model.imageName {
                    Text(name).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                }
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity).frame(height: 80)
            .background(RoundedRectangle(cornerRadius: 6).fill(field))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .overlay(DropArea(model: model))
            .accessibilityElement(children: .ignore).accessibilityLabel("Drop a screenshot or choose an image")
            .accessibilityAddTraits(.isButton).accessibilityAction { model.chooseFile?() }
            Button { model.paste() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Paste")
                    Spacer()
                    Text("⌘V").foregroundStyle(muted)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).frame(height: 22)
                .help("Paste a screenshot or time")
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(contrast == .increased ? Color.primary : rule))
    }
}

private struct ClockCard: View {
    @ObservedObject var model: Model
    let now: Date
    private func sourceName(_ hit: ConvertedTime) -> String {
        if hit.usesDefaultZone { return hit.source.label + " (default)" }
        let token = hit.sourceLabel
        guard let aliases = Zones.aliases[token.lowercased()] else {
            return token.uppercased() == "Z" ? "UTC" : "Fixed offset"
        }
        let offset = Zones.utcOffset(hit.source.zone.secondsFromGMT(for: hit.instant))
        if aliases.count > 1 {
            let meaning = hit.source.label.replacingOccurrences(of: " (" + offset + ")", with: "")
            return token.uppercased() + " · " + meaning
        }
        if token.contains("/") || token.caseInsensitiveCompare(hit.source.label) == .orderedSame {
            return hit.source.label
        }
        if token.count <= 4 && token.allSatisfy(\.isLetter) {
            let abbreviation = token.uppercased()
            return hit.source.id.contains("/") ? abbreviation + " · " + hit.source.label : abbreviation
        }
        return token
    }

    var body: some View {
        let hit = model.current
        let target = model.target
        let seconds = hit?.clock.filter { $0 == ":" }.count == 2
        return VStack(alignment: .leading, spacing: 0) {
            NavigationBar {
                if let hit {
                    Dial(date: hit.instant, zone: target)
                        .frame(width: 25, height: 25).background(green, in: Circle()).accessibilityHidden(true)
                } else {
                    Image(systemName: "globe.europe.africa").font(.system(size: 16)).foregroundStyle(.secondary)
                }
                Text("Meridian").font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
                if hit != nil {
                    if model.report.times.count > 1 {
                        IconButton(icon: "chevron.left", label: "Previous time") { model.index -= 1 }.disabled(model.index == 0)
                        Text("\(model.index+1)/\(model.report.times.count)").monospacedDigit().font(.system(size: 11))
                        IconButton(icon: "chevron.right", label: "Next time") { model.index += 1 }.disabled(model.index == model.report.times.count - 1)
                    }
                    IconButton(icon: "doc.on.doc", label: "Copy result") { model.copyResult() }
                }
                IconButton(icon: "gearshape", label: "Settings") { model.page = .settings }
            }
            Group {
                if let hit {
                    HStack(alignment: .top, spacing: 16) {
                        TimeReadout(title: "Detected time", instant: hit.instant, zone: hit.source.zone,
                                    zoneName: sourceName(hit), military: model.military, seconds: seconds,
                                    note: hit.fold)
                        Rectangle().fill(.white.opacity(0.24)).frame(width: 1)
                        TimeReadout(title: "Converted time", instant: hit.instant, zone: target,
                                    zoneName: Zones.label(target.identifier), military: model.military, seconds: seconds,
                                    chooseZone: { model.zoneList(destination: true) })
                    }.fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 12) {
                        TimeReadout(title: "Local clock", instant: now, zone: target,
                                    zoneName: Zones.label(target.identifier), military: model.military, seconds: false,
                                    chooseZone: { model.zoneList(destination: true) })
                        Dial(date: now, zone: target).frame(width: 82, height: 82).accessibilityHidden(true)
                    }
                }
            }
            .foregroundStyle(.white).padding(.horizontal, 15).padding(.vertical, 12)
            .background(green, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 14)
        }
    }
}

private struct TimeReadout: View {
    let title: String
    let instant: Date
    let zone: TimeZone
    let zoneName: String
    let military: Bool
    let seconds: Bool
    var note: String?
    var chooseZone: (() -> Void)?

    var body: some View {
        let pattern = (military ? "HH:mm" : "h:mm") + (seconds ? ":ss" : "")
        return VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).tracking(1.3)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(brass)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Model.format(instant, pattern, zone))
                    .font(.system(size: seconds ? 34 : 43, weight: .regular, design: .serif)).monospacedDigit()
                if !military {
                    Text(Model.format(instant, "a", zone)).font(.system(size: 13, weight: .semibold))
                }
            }.lineLimit(1).minimumScaleFactor(0.8)
            Text(Model.format(instant, "EEEE, MMM d", zone))
                .font(.system(size: 24, weight: .medium, design: .serif))
                .lineLimit(1).minimumScaleFactor(0.80)
                .accessibilityLabel(Model.format(instant, "EEEE, MMMM d", zone))
            Group {
                if let chooseZone {
                    Button(action: chooseZone) {
                        HStack(spacing: 4) {
                            Text(zoneName)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                    }.buttonStyle(.plain).help("Choose your local time zone")
                } else {
                    Text(zoneName)
                }
            }.font(.system(size: 14, weight: .semibold)).padding(.top, 5)
            Text(Zones.utcOffset(zone.secondsFromGMT(for: instant)))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.83))
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(brass) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct Dial: View {
    let date: Date, zone: TimeZone
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width,size.height)/2 - 1, c = CGPoint(x:size.width/2,y:size.height/2)
            func point(_ turn: Double, _ length: Double) -> CGPoint {
                let angle = turn * .pi * 2 - .pi/2
                return CGPoint(x:c.x+cos(angle)*length, y:c.y+sin(angle)*length)
            }
            func line(_ a: CGPoint,_ b: CGPoint,_ color: Color,_ width: CGFloat) {
                var path = Path(); path.move(to:a); path.addLine(to:b)
                ctx.stroke(path, with:.color(color), style:StrokeStyle(lineWidth:width,lineCap:.round))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x:c.x-r,y:c.y-r,width:2*r,height:2*r)), with:.color(brass.opacity(0.52)), lineWidth:0.8)
            let small = r < 20
            for i in stride(from: 0, to: 60, by: small ? 15 : 1) {
                let major = i % 5 == 0
                line(point(Double(i)/60, r * 0.93), point(Double(i)/60, r * (major ? 0.80 : 0.88)),
                     major ? brass : .white.opacity(0.42), small ? 0.8 : (major ? 1.4 : 0.7))
            }
            let parts = Converter.calendar(zone).dateComponents([.hour,.minute,.second], from:date)
            let m = Double(parts.minute!) + Double(parts.second!)/60, h = Double(parts.hour! % 12) + m/60
            line(c, point(h/12,r*0.46), .white, small ? 1.4 : 2.8)
            line(c, point(m/60,r*0.71), brass, small ? 1 : 1.8)
            let hub = small ? 1.0 : 2.6
            ctx.fill(Path(ellipseIn:CGRect(x:c.x-hub,y:c.y-hub,width:hub*2,height:hub*2)), with:.color(brass))
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings") { model.page = .converter }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    setting("My local time zone", model.destination == "device" ? "Follow Mac · " + Zones.label(model.target.identifier) : Zones.label(model.destination)) { model.zoneList(destination:true) }
                    Divider()
                    setting("Default source zone", Zones.label(model.fallback)) { model.zoneList(destination:false) }
                    Divider()
                    Toggle("24-hour clock", isOn:$model.military)
                    Toggle("Show detected zone’s live time in menu bar", isOn: $model.showDetectedClock)
                    Divider()
                    Toggle("Choose a source date", isOn:$model.customDay)
                    if model.customDay {
                        DatePicker("Source date", selection:$model.date, displayedComponents:.date)
                    } else {
                        Text("Undated times use today’s date in the source zone.").font(.system(size:12)).foregroundStyle(muted)
                    }
                }.toggleStyle(.switch).font(.system(size:13)).padding(20)
            }
            Divider()
            Button("Quit Meridian") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal,20).padding(.vertical,10)
        }
    }
    func setting(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { VStack(alignment:.leading,spacing:4) { Text(title).fontWeight(.semibold); Text(value).foregroundStyle(muted) }; Spacer(); Image(systemName:"chevron.right").foregroundStyle(muted) }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct PageHeader: View {
    let title: String
    let back: () -> Void
    var body: some View {
        NavigationBar { IconButton(icon:"chevron.left", label:"Back", action:back); Text(title).font(.system(size:18,weight:.medium,design:.serif)); Spacer() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct ZoneList: View {
    @ObservedObject var model: Model
    @State private var search = ""
    @FocusState private var focused: Bool
    private var target: Bool { model.page == .destination }
    private let common = ["UTC","America/Los_Angeles","America/New_York","Europe/London","Europe/Paris","Asia/Kolkata","Asia/Shanghai","Asia/Seoul","Asia/Tokyo","Australia/Sydney"]
    private var items: [ZoneOption] {
        let all = Zones.all
        let query = search.trimmingCharacters(in:.whitespaces).lowercased()
        if query.isEmpty {
            return common.compactMap { id in all.first { $0.id == id } } + all.filter { !common.contains($0.id) }
        }
        let aliases = Set((Zones.aliases[query] ?? []).map(\.id))
        return all.filter { ($0.label + " " + $0.id).localizedCaseInsensitiveContains(query) || aliases.contains($0.id) }
    }
    var body: some View {
        VStack(spacing:0) {
            PageHeader(title:target ? "My local time zone" : "Default source zone") { model.page = model.zoneReturn }
            HStack { Image(systemName:"magnifyingglass").foregroundStyle(muted); TextField("Search cities or time zones",text:$search).textFieldStyle(.plain).focused($focused) }
                .padding(10).background(field).clipShape(RoundedRectangle(cornerRadius:7)).padding(12)
            ScrollView {
                LazyVStack(spacing:0) {
                    if target && search.isEmpty { row("device", "Follow my Mac", TimeZone.current.identifier) }
                    ForEach(items) { item in row(item.id, item.label, item.id) }
                }
            }
        }.onAppear { focused = true }
    }
    func row(_ id:String, _ label:String, _ detail:String) -> some View {
        Button {
            if target { model.destination = id } else { model.fallback = id }
            model.page = model.zoneReturn
        } label: {
            HStack { VStack(alignment:.leading,spacing:2) { Text(label).font(.system(size:13,weight:.medium)); Text(detail).font(.system(size:10)).foregroundStyle(muted) }; Spacer()
                if (target ? model.destination : model.fallback) == id { Image(systemName:"checkmark").foregroundStyle(Color.accentColor) }
            }.padding(.horizontal,20).padding(.vertical,6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
