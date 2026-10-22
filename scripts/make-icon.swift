// Draws the Home Widgets app icon — three stacked layers in soft neutral greys on a clear
// background — and writes Resources/AppIcon.icns and Resources/AppIcon.png.
//
// Run from the repo root:  swift scripts/make-icon.swift

import AppKit

let canvas: CGFloat = 1024

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white + 0.01, alpha: alpha)
}

/// Points in a top-down 1024 grid, flipped for Core Graphics.
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: canvas - y) }

func rhombus(centerY y: CGFloat, halfWidth w: CGFloat, halfHeight h: CGFloat, radius: CGFloat) -> CGPath {
    let corners = [point(512, y - h), point(512 + w, y), point(512, y + h), point(512 - w, y)]
    let path = CGMutablePath()
    let start = CGPoint(x: (corners[3].x + corners[0].x) / 2, y: (corners[3].y + corners[0].y) / 2)
    path.move(to: start)
    for i in 0..<4 {
        path.addArc(tangent1End: corners[i], tangent2End: corners[(i + 1) % 4], radius: radius)
    }
    path.closeSubpath()
    return path
}

func chevron(centerY y: CGFloat, halfWidth w: CGFloat, halfHeight h: CGFloat, thickness: CGFloat) -> CGPath {
    let line = CGMutablePath()
    line.move(to: point(512 - w, y))
    line.addLine(to: point(512, y + h))
    line.addLine(to: point(512 + w, y))
    return line.copy(strokingWithWidth: thickness, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func fill(_ path: CGPath, in context: CGContext, top: CGFloat, bottom: CGFloat) {
    // A soft shadow so the glyph still reads on a light Dock.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: gray(0, 0.28))
    context.addPath(path)
    context.setFillColor(gray(bottom))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    let box = path.boundingBox
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [gray(top), gray(bottom)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
    context.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)

    // Shrink a little around the centre so the glyph has room to breathe.
    context.translateBy(x: 512, y: 512)
    context.scaleBy(x: 0.9, y: 0.9)
    context.translateBy(x: -512, y: -512)

    // Isometric 30° slopes; the chevrons sit parallel under the top layer with equal gaps.
    let slope: CGFloat = 0.5774
    let thickness: CGFloat = 70
    let layerWidth: CGFloat = 410
    let chevronWidth = layerWidth - thickness / 2
    let gap: CGFloat = 40
    let first = (gap + thickness * 0.75) / 0.866
    let second = (gap + thickness) / 0.866
    let top: CGFloat = 388
    fill(chevron(centerY: top + first + second, halfWidth: chevronWidth, halfHeight: chevronWidth * slope, thickness: thickness),
         in: context, top: 0.66, bottom: 0.54)
    fill(chevron(centerY: top + first, halfWidth: chevronWidth, halfHeight: chevronWidth * slope, thickness: thickness),
         in: context, top: 0.82, bottom: 0.7)
    fill(rhombus(centerY: top, halfWidth: layerWidth, halfHeight: layerWidth * slope, radius: 30), in: context, top: 1.0, bottom: 0.86)

    return grayPNG(rep)
}

/// The icon is all greys, so store one grey channel plus alpha instead of RGBA: same look, far smaller files.
func grayPNG(_ rep: NSBitmapImageRep) -> Data {
    let width = rep.pixelsWide, height = rep.pixelsHigh
    var pixels = [UInt8](repeating: 0, count: width * height * 2)
    for y in 0..<height {
        for x in 0..<width {
            let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .clear
            let index = (y * width + x) * 2
            pixels[index] = UInt8((color.redComponent * 0.3 + color.greenComponent * 0.59 + color.blueComponent * 0.11) * 255 + 0.5)
            pixels[index + 1] = UInt8(color.alphaComponent * 255 + 0.5)
        }
    }
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 16, bytesPerRow: width * 2,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

let resources = URL(fileURLWithPath: "Resources", isDirectory: true)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
// Each pixel size once: 32×32 is the same picture as 16×16@2x, and so on, so the duplicates are left out.
let names = [16: "16x16", 32: "16x16@2x", 64: "32x32@2x", 128: "128x128", 256: "128x128@2x", 512: "256x256@2x", 1024: "512x512@2x"]
for (pixels, name) in names {
    try render(pixels: pixels).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try render(pixels: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
