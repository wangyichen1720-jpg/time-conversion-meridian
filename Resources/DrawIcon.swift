import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
// ICNS stores each PNG as a four-character type and a big-endian chunk length.
func chunk(_ tag: String, _ payload: Data) -> Data {
    var length = UInt32(payload.count + 8).bigEndian
    var data = Data(tag.utf8)
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
    data.append(payload)
    return data
}
let types = [16:["icp4","ic11"], 32:["icp5","ic12"], 128:["ic07","ic13"],
             256:["ic08","ic14"], 512:["ic09","ic10"]]
var icons = Data()
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ r:CGFloat, _ g:CGFloat, _ b:CGFloat)->CGColor { CGColor(srgbRed:r,green:g,blue:b,alpha:1) }
let gold = color(0.91,0.77,0.52), cream = color(0.98,0.96,0.89)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let size = base*scale
        let ctx = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x:CGFloat(size)/1024, y:CGFloat(size)/1024)
        let tile = CGPath(roundedRect:CGRect(x:80,y:80,width:864,height:864),cornerWidth:196,cornerHeight:196,transform:nil)
        ctx.addPath(tile); ctx.clip()
        let fill = CGGradient(colorsSpace:space,colors:[color(0.14,0.34,0.27),color(0.035,0.16,0.14)] as CFArray,locations:[0,1])!
        ctx.drawLinearGradient(fill,start:CGPoint(x:240,y:920),end:CGPoint(x:740,y:70),options:[])
        ctx.setStrokeColor(gold); ctx.setLineWidth(15)
        ctx.strokeEllipse(in:CGRect(x:217,y:217,width:590,height:590))
        func tip(_ turn:Double, _ r:Double)->CGPoint {
            let a = .pi/2-turn * .pi*2
            return CGPoint(x:512+cos(a)*r,y:512+sin(a)*r)
        }
        func line(_ p:CGPoint,_ q:CGPoint,_ width:CGFloat,_ stroke:CGColor) {
            ctx.setStrokeColor(stroke);ctx.setLineWidth(width);ctx.setLineCap(.round);ctx.move(to:p);ctx.addLine(to:q);ctx.strokePath()
        }
        for i in 0..<12 { line(tip(Double(i)/12,263),tip(Double(i)/12,i%3 == 0 ? 224 : 242),i%3 == 0 ? 13 : 9,gold) }
        let center = CGPoint(x:512,y:512)
        line(tip(0.835,145),center,33,cream);line(center,tip(0.126,206),22,cream)
        ctx.setFillColor(gold);ctx.fillEllipse(in:CGRect(x:489,y:489,width:46,height:46))
        let png = NSMutableData()
        let dest = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest,ctx.makeImage()!,nil)
        precondition(CGImageDestinationFinalize(dest))
        icons.append(chunk(types[base]![scale-1], png as Data))
    }
}
try chunk("icns", icons).write(to: output, options: .atomic)
