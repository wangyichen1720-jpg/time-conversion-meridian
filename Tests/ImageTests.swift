import Foundation
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main enum ImageTests {
    static func main() throws {
        let w = 1000, h = 320
        let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:w,height:h))
        let attributes: [NSAttributedString.Key:Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,46,nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)
        ]
        for (i,string) in ["Project review","2026-12-31","11:45 PM New York"].enumerated() {
            ctx.textPosition = CGPoint(x:45,y:h-75-i*80)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:string,attributes:attributes)),ctx)
        }
        let data = NSMutableData()
        let target = CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(target,ctx.makeImage()!,nil);precondition(CGImageDestinationFinalize(target))
        let text = try ImageReader.recognize(.data(data as Data))
        print("Recognized:\n" + text)
        let result = Converter.convert(text,fallback:Zones.region("UTC"))
        let instant = try XCTUnwrap(result.times.first?.instant)
        let local = Converter.calendar(TimeZone(identifier:"Asia/Seoul")!).dateComponents([.year,.month,.day,.hour,.minute],from:instant)
        precondition(local == DateComponents(year:2027,month:1,day:1,hour:13,minute:45), "Incorrect Seoul result: \(local)")
        if CommandLine.arguments.count == 2 { try data.write(toFile:CommandLine.arguments[1]) }
        print("Passed screenshot → recognized text → Seoul time (Jan 1, 2027, 1:45 PM).")
    }
    enum Failure: Error { case missingTime }
    static func XCTUnwrap<T>(_ value:T?) throws -> T {
        guard let value else { throw Failure.missingTime }
        return value
    }
}
