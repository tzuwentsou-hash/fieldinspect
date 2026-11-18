import CoreGraphics
import ImageIO
import SwiftUI
import UIKit

enum CalloutTool: String, CaseIterable, Identifiable {
    case freehand = "Circle / Draw"
    case arrow = "Arrow"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .freehand: return String(localized: "Circle / Draw")
        case .arrow: return String(localized: "Arrow")
        }
    }

    var sfSymbol: String {
        switch self {
        case .freehand: return "scribble.variable"
        case .arrow: return "arrow.up.right"
        }
    }
}

/// Normalized [0, 1] stroke coordinates so annotations scale identically across preview and baked 1600px JPEG.
struct CalloutStroke: Identifiable, Hashable {
    let id: UUID
    let tool: CalloutTool
    var points: [CGPoint] // Normalized 0.0...1.0 relative to image display frame

    init(id: UUID = UUID(), tool: CalloutTool, points: [CGPoint] = []) {
        self.id = id
        self.tool = tool
        self.points = points
    }
}

/// Handles memory-safe image downsampling (<= 1600px) and baking red Canvas callouts onto JPEGs.
enum ImageProcessor {
    /// Downsamples raw photo data to longest edge <= 1600px without decoding the full-res bitmap into RAM.
    static func downsampleAndCompress(
        data: Data,
        maxDimension: CGFloat = AppConfig.Media.maxImageDimension,
        quality: CGFloat = AppConfig.Media.jpegCompressionQuality
    ) -> Data? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return compressToTargetJPEG(uiImage, initialQuality: quality)
    }

    /// Downsamples a `UIImage` (e.g. from camera capture) to longest edge <= 1600px and compresses to JPEG.
    static func processUIImage(
        _ image: UIImage,
        maxDimension: CGFloat = AppConfig.Media.maxImageDimension,
        quality: CGFloat = AppConfig.Media.jpegCompressionQuality
    ) -> Data? {
        // UIImage.draw(in:) already applies imageOrientation, so draw the camera image straight into the
        // downsized canvas. (Re-rendering a full-resolution "normalized" copy first doubled peak memory
        // for every 12–48 MP capture — exactly the OOM risk this pipeline exists to avoid.)
        let size = image.size
        let longest = max(size.width, size.height)

        let targetSize: CGSize
        if longest > maxDimension, longest > 0 {
            let scale = maxDimension / longest
            targetSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        } else {
            targetSize = size
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return compressToTargetJPEG(resized, initialQuality: quality)
    }

    /// Bakes normalized red callout strokes directly onto the downsampled JPEG image.
    static func bakeAnnotations(
        onto jpegData: Data,
        strokes: [CalloutStroke],
        quality: CGFloat = AppConfig.Media.jpegCompressionQuality
    ) -> Data {
        guard !strokes.isEmpty, let baseImage = UIImage(data: jpegData) else {
            return jpegData
        }

        let size = baseImage.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let lineWidth = max(4.0, min(size.width, size.height) * 0.008)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let annotated = renderer.image { context in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.setStrokeColor(UIColor(red: 0.92, green: 0.12, blue: 0.12, alpha: 1.0).cgColor)
            cg.setFillColor(UIColor(red: 0.92, green: 0.12, blue: 0.12, alpha: 1.0).cgColor)
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            for stroke in strokes where stroke.points.count >= 2 {
                switch stroke.tool {
                case .freehand:
                    let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                    cg.beginPath()
                    cg.move(to: pts[0])
                    for pt in pts.dropFirst() {
                        cg.addLine(to: pt)
                    }
                    cg.strokePath()

                case .arrow:
                    guard let first = stroke.points.first, let last = stroke.points.last else { continue }
                    let start = CGPoint(x: first.x * size.width, y: first.y * size.height)
                    let end = CGPoint(x: last.x * size.width, y: last.y * size.height)
                    drawArrow(in: cg, from: start, to: end, lineWidth: lineWidth)
                }
            }
        }

        return compressToTargetJPEG(annotated, initialQuality: quality) ?? jpegData
    }

    /// The rect an image of `imageSize` occupies when aspect-fit (`.scaledToFit()`) and centered in `container`.
    /// Callout strokes are normalized against this rect — not the letterboxed canvas — so the on-screen
    /// markup lands on exactly the same pixels when baked onto the JPEG.
    static func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - fitted.width) / 2,
            y: (container.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private static func drawArrow(in cg: CGContext, from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }

        let angle = atan2(dy, dx)
        let headLength = max(lineWidth * 4.2, min(length * 0.35, 48))
        let headAngle: CGFloat = .pi / 6

        cg.beginPath()
        cg.move(to: start)
        cg.addLine(to: end)
        cg.strokePath()

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        cg.beginPath()
        cg.move(to: end)
        cg.addLine(to: p1)
        cg.addLine(to: p2)
        cg.closePath()
        cg.fillPath()
    }

    private static func compressToTargetJPEG(_ image: UIImage, initialQuality: CGFloat) -> Data? {
        var quality = initialQuality
        guard var data = image.jpegData(compressionQuality: quality) else { return nil }
        while data.count > AppConfig.Media.targetMaxBytes && quality > 0.45 {
            quality -= 0.1
            if let smaller = image.jpegData(compressionQuality: quality) {
                data = smaller
            } else {
                break
            }
        }
        return data
    }
}
