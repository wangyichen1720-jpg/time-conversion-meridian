import AppKit
import Vision
import ImageIO

enum ImageInput {
    case file(URL), data(Data)
}

enum ImageReader {
    static func recognize(_ input: ImageInput) throws -> String {
        let source: CGImageSource?
        switch input {
        case .file(let url): source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case .data(let data): source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw NSError(domain: "Meridian", code: 1, userInfo: [NSLocalizedDescriptionKey: "This image could not be opened. Try a PNG, JPEG or HEIC file."])
        }
        let request = VNRecognizeTextRequest()
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
