import AppKit
import Combine
import UniformTypeIdentifiers

final class Model: ObservableObject {
    enum Page { case converter, settings, destination, source }
    @Published var page: Page = .converter
    var zoneReturn: Page = .converter
    @Published var text = "" { didSet { if !readingResult { invalidateRead() }; recalculate() } }
    @Published var destination: String { didSet { defaults.set(destination, forKey: "destination") } }
    @Published var fallback: String { didSet { defaults.set(fallback, forKey: "source"); recalculate() } }
    @Published var military: Bool { didSet { defaults.set(military, forKey: "24Hour") } }
    @Published var customDay = false { didSet { recalculate() } }
    @Published var date = Date() { didSet { recalculate() } }
    @Published var index = 0
    @Published var report = ConversionReport()
    @Published var reading = false
    @Published var message: String?
    @Published var imageName: String?
    @Published var resolutions: [String:String] = [:] { didSet { recalculate() } }
    private let defaults: UserDefaults
    private var generation = UUID()
    private var readingResult = false
    private var work: DispatchWorkItem?
    private var calculation: UInt64 = 0
    private let queue = DispatchQueue(label: "Meridian.conversion", qos: .userInitiated)
    private let imageQueue = DispatchQueue(label: "Meridian.images", qos: .userInitiated)
    var chooseFile: (() -> Void)?
    var current: ConvertedTime? { report.times.indices.contains(index) ? report.times[index] : nil }
    var target: TimeZone { destination == "device" ? .autoupdatingCurrent : TimeZone(identifier: destination) ?? .current }
    var source: Zones.Choice { Zones.region(fallback) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "destination") ?? "device"
        destination = saved == "device" || TimeZone(identifier: saved) != nil ? saved : "device"
        let src = defaults.string(forKey: "source") ?? "UTC"
        fallback = TimeZone(identifier: src) != nil ? src : "UTC"
        military = defaults.bool(forKey: "24Hour")
    }
    func recalculate() {
        work?.cancel()
        calculation &+= 1
        let revision = calculation
        let value = text, src = source, resolver = resolutions
        let day = customDay ? Converter.calendar(.current).dateComponents([.year,.month,.day], from: date) : nil
        index = 0; report = ConversionReport()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let task = DispatchWorkItem { [weak self] in
            let report = Converter.convert(value, fallback: src, day: day, resolutions: resolver)
            DispatchQueue.main.async {
                guard let self, self.calculation == revision else { return }
                self.report = report
            }
        }
        work = task
        queue.asyncAfter(deadline: .now() + 0.10, execute: task)
    }
    func invalidateRead() {
        generation = UUID(); reading = false; imageName = nil; message = nil
    }
    func beginImage() -> UUID {
        text = ""; page = .converter; reading = true
        return generation
    }
    func read(_ input: ImageInput, name: String, token: UUID? = nil) {
        let id = token ?? beginImage()
        guard generation == id else { return }
        imageQueue.async { [weak self] in
            let result = Result { try ImageReader.recognize(input) }
            DispatchQueue.main.async {
                guard let self, self.generation == id else { return }
                self.reading = false
                switch result {
                case .success(let text):
                    self.readingResult = true; self.text = text; self.readingResult = false
                    self.imageName = name
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
    func failRead(_ error: Error, token: UUID) {
        guard generation == token else { return }
        reading = false; message = error.localizedDescription
    }
    func zoneList(destination: Bool) {
        zoneReturn = page; page = destination ? .destination : .source
    }
    func copyResult() {
        guard let hit = current else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let value = Self.format(hit.instant, "EEE, d MMM yyyy", target) + " · " + Self.format(hit.instant, military ? "HH:mm:ss" : "h:mm:ss a", target) + " " + Zones.label(target.identifier) + " (" + Zones.utcOffset(target.secondsFromGMT(for: hit.instant)) + ")"
        pb.setString(value, forType: .string)
    }
    static func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone
        f.dateFormat = pattern; return f.string(from: date)
    }
    static let dropTypes = Array(Set([NSPasteboard.PasteboardType.fileURL, .tiff, .png, .string] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }))
    static func hasImage(_ pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) ||
        pb.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) ||
        pb.availableType(from: [.png, .tiff]) != nil || pb.canReadObject(forClasses: [NSImage.self], options: nil)
    }
    @discardableResult func accept(_ pb: NSPasteboard, textAllowed: Bool = true) -> Bool {
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly:true]) as? [URL])?.first {
            read(.file(url), name: url.lastPathComponent); return true
        }
        if let receiver = (pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver])?.first {
            let id = beginImage()
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Meridian-" + UUID().uuidString, isDirectory: true)
            do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
            catch { failRead(error, token: id); return true }
            receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: .main) { [weak self] url, error in
                defer { try? FileManager.default.removeItem(at: dir) }
                do {
                    if let error { throw error }
                    let data = try Data(contentsOf: url)
                    self?.read(.data(data), name: url.lastPathComponent, token: id)
                } catch { self?.failRead(error, token: id) }
            }
            return true
        }
        if let type = pb.availableType(from: [.png, .tiff]), let data = pb.data(forType: type) {
            read(.data(data), name: "Screenshot"); return true
        }
        if let image = (pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first, let data = image.tiffRepresentation {
            read(.data(data), name: "Image"); return true
        }
        if textAllowed, let string = pb.string(forType: .string), !string.isEmpty {
            page = .converter; text = string; return true
        }
        return false
    }
    func paste() {
        if !accept(.general) { message = "Copy an image or a time, then paste it here." }
    }
}
