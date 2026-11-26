import AppKit
import Vision
import ImageIO

enum ImageInput {
    case file(URL), data(Data)
}

enum ImageReader {
    static func recognize(_ input: ImageInput, request: VNRecognizeTextRequest = VNRecognizeTextRequest(),
                          cancelled: () -> Bool = { false }, preview: ((CGImage) -> Void)? = nil) throws -> String {
        guard !cancelled() else { throw CancellationError() }
        let source: CGImageSource?
        switch input {
        case .file(let url): source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case .data(let data): source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 280,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let source, let preview,
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            preview(thumbnail)
        }
        guard !cancelled() else { throw CancellationError() }
        options[kCGImageSourceThumbnailMaxPixelSize] = 4096
        guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw NSError(domain: "Meridian", code: 1, userInfo: [NSLocalizedDescriptionKey: "This image could not be opened. Try a PNG, JPEG or HEIC file."])
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else {
            throw NSError(domain: "Meridian", code: 2, userInfo: [NSLocalizedDescriptionKey: "No text found. Try a sharper crop around the time."])
        }
        return lines.joined(separator: "\n")
    }
}
