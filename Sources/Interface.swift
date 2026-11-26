import SwiftUI
import AppKit

private let paper = Color(red: 0.975, green: 0.969, blue: 0.943)
private let ink = Color(red: 0.10, green: 0.16, blue: 0.14)
private let muted = Color(red: 0.31, green: 0.36, blue: 0.32)
private let green = Color(red: 0.067, green: 0.213, blue: 0.182)
private let brass = Color(red: 0.90, green: 0.75, blue: 0.45)
private let rule = Color(red: 0.81, green: 0.83, blue: 0.78)

private struct IconButton: View {
    let icon: String, label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).frame(width: 27, height: 27).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct Interface: View {
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
        .background(paper).foregroundStyle(ink).preferredColorScheme(.light)
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
                .background(.white)
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
        .padding(13).background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(rule))
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
            .foregroundStyle(green).frame(maxWidth: .infinity).frame(height: 80)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.52)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(green.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.90, green: 0.93, blue: 0.89)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(green.opacity(0.20)))
    }
}

private struct ClockCard: View {
    @ObservedObject var model: Model
    let now: Date
    private func sourceDescription(_ hit: ConvertedTime) -> String {
        let parts = [hit.clock + " " + hit.sourceLabel, Model.format(hit.instant, "MMM d", hit.source.zone), hit.fold]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        let hit = model.current
        let date = hit?.instant ?? now
        let tz = model.target
        let showSeconds = hit.map { $0.clock.filter { $0 == ":" }.count == 2 } ?? false
        let pattern = (model.military ? "HH:mm" : "h:mm") + (showSeconds ? ":ss" : "")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "globe.europe.africa").font(.system(size: 16)).foregroundStyle(brass)
                Text("Meridian").font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
                IconButton(icon: "gearshape", label: "Settings") { model.page = .settings }
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit == nil ? "LOCAL CLOCK" : "CONVERTED TIME").tracking(1.5).font(.system(size: 9, weight: .bold)).foregroundStyle(brass)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Model.format(date, pattern, tz)).font(.system(size: showSeconds ? 40 : 47, weight: .regular, design: .serif)).monospacedDigit()
                        if !model.military { Text(Model.format(date, "a", tz)).font(.system(size: 12, weight: .medium)).foregroundStyle(brass) }
                    }.lineLimit(1).minimumScaleFactor(0.75)
                    Text(Model.format(date, "EEEE, MMM d, yyyy", tz))
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.85)
                        .accessibilityLabel("Local date, " + Model.format(date, "EEEE, MMMM d, yyyy", tz))
                    HStack(spacing: 8) {
                        Button { model.zoneList(destination: true) } label: {
                            HStack(spacing: 4) {
                                Text(Zones.label(tz.identifier)).fontWeight(.semibold).lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                            }
                        }.buttonStyle(.plain).help("Choose your local time zone")
                        Text(Zones.utcOffset(tz.secondsFromGMT(for: date))).foregroundStyle(.white.opacity(0.78))
                    }.font(.system(size: 12)).padding(.top, 5)
                }
                Spacer(minLength: 0)
                Dial(date: date, zone: tz).frame(width: 82, height: 82).accessibilityHidden(true)
            }.padding(.top, 7)
            if let hit {
                Rectangle().fill(.white.opacity(0.20)).frame(height: 1).padding(.top, 10)
                HStack(spacing: 4) {
                    Text(sourceDescription(hit))
                        .font(.system(size: 11)).lineLimit(1).help(hit.source.label + " · " + Zones.utcOffset(hit.source.zone.secondsFromGMT(for: hit.instant)))
                    Spacer(minLength: 2)
                    if model.report.times.count > 1 {
                        IconButton(icon: "chevron.left", label: "Previous time") { model.index -= 1 }.disabled(model.index == 0)
                        Text("\(model.index+1)/\(model.report.times.count)").monospacedDigit().font(.system(size: 10))
                        IconButton(icon: "chevron.right", label: "Next time") { model.index += 1 }.disabled(model.index == model.report.times.count-1)
                    }
                    IconButton(icon: "doc.on.doc", label: "Copy result") { model.copyResult() }
                }.frame(height: 26)
            }
        }.foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 11).padding(.bottom, hit == nil ? 16 : 5)
            .background(green)
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
            for i in 0..<60 {
                let major = i % 5 == 0
                line(point(Double(i)/60, r-3), point(Double(i)/60, r-(major ? 8 : 4.8)), major ? brass : .white.opacity(0.42), major ? 1.4 : 0.7)
            }
            let parts = Converter.calendar(zone).dateComponents([.hour,.minute,.second], from:date)
            let m = Double(parts.minute!) + Double(parts.second!)/60, h = Double(parts.hour! % 12) + m/60
            line(c, point(h/12,r*0.46), .white, 2.8); line(c, point(m/60,r*0.71), brass, 1.8)
            ctx.fill(Path(ellipseIn:CGRect(x:c.x-2.6,y:c.y-2.6,width:5.2,height:5.2)), with:.color(brass))
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Settings") { model.page = .converter }
            VStack(alignment: .leading, spacing: 18) {
                setting("My local time zone", model.destination == "device" ? "Follow Mac · " + Zones.label(model.target.identifier) : Zones.label(model.destination)) { model.zoneList(destination:true) }
                Divider()
                setting("Default source zone", Zones.label(model.fallback)) { model.zoneList(destination:false) }
                Divider()
                Toggle("24-hour clock", isOn:$model.military)
                Divider()
                Toggle("Choose a source date", isOn:$model.customDay)
                if model.customDay {
                    DatePicker("Source date", selection:$model.date, displayedComponents:.date)
                } else {
                    Text("Undated times use today’s date in the source zone.").font(.system(size:12)).foregroundStyle(muted)
                }
                Spacer()
                Button("Quit Meridian") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(muted)
            }.toggleStyle(.switch).font(.system(size:13)).padding(20)
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
        HStack { IconButton(icon:"chevron.left", label:"Back", action:back); Text(title).font(.system(size:18,weight:.medium,design:.serif)); Spacer() }
        .padding(.horizontal,14).frame(height:55).foregroundStyle(.white).background(green)
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
                .padding(10).background(.white.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius:7)).padding(12)
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
                if (target ? model.destination : model.fallback) == id { Image(systemName:"checkmark").foregroundStyle(green) }
            }.padding(.horizontal,20).padding(.vertical,6).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
