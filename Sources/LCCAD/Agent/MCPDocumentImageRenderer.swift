import AppKit
import SwiftUI

/// エージェントが描いた結果を自分で確かめるための画像出力 (#79)。表示中のレイヤーの図形と
/// ステッチ穴を、キャンバスと同じ `CanvasRenderer` で白背景の PNG に描く。
/// グリッド・選択・プレビューは描かない
@MainActor
enum MCPDocumentImageRenderer {
    static let defaultWidth = 1600
    static let widthRange = 200...4096
    /// 図形の外接矩形のまわりに取る余白 (px)
    static let padding: CGFloat = 24

    struct Rendered {
        let png: Data
        let pixelWidth: Int
        let pixelHeight: Int
        /// 1mm あたりのピクセル数
        let pixelsPerMillimeter: CGFloat
        /// 画像に収めた範囲 (mm)
        let bounds: CGRect
    }

    struct NothingToRender: Error, CustomStringConvertible {
        var description: String { "There are no visible shapes to render" }
    }

    struct EncodingFailed: Error, CustomStringConvertible {
        var description: String { "Failed to encode the image as PNG" }
    }

    static func renderPNG(document: DocumentData, width requestedWidth: Int) throws -> Rendered {
        let shapes = document.layers.filter(\.isVisible).flatMap(\.shapes)
        guard let box = shapes.combinedBoundingBox else { throw NothingToRender() }

        let width = min(max(requestedWidth, widthRange.lowerBound), widthRange.upperBound)
        let available = CGFloat(width) - padding * 2
        // 幅がほぼない(縦線など)ときは高さで合わせる。両方ほぼなければ 10 px/mm
        var scale: CGFloat
        if box.width > 0.0001 {
            scale = available / box.width
        } else if box.height > 0.0001 {
            scale = available / box.height
        } else {
            scale = 10
        }
        // 縦長の図形で高さが上限を超えないようにする
        let maxHeight = CGFloat(widthRange.upperBound)
        if box.height * scale + padding * 2 > maxHeight {
            scale = (maxHeight - padding * 2) / box.height
        }
        let height = Int((box.height * scale + padding * 2).rounded(.up))

        var transform = CanvasTransform()
        transform.scale = scale
        transform.offset = CGPoint(x: padding - box.minX * scale, y: padding - box.minY * scale)
        let renderer = CanvasRenderer(transform: transform, colorScheme: .light, unit: document.settings.unit)

        let content = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            renderer.drawDocumentContent(document, in: context)
        }
        .frame(width: CGFloat(width), height: CGFloat(height))
        .environment(\.colorScheme, .light)

        let imageRenderer = ImageRenderer(content: content)
        imageRenderer.scale = 1
        guard let cgImage = imageRenderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw EncodingFailed()
        }
        return Rendered(png: png, pixelWidth: cgImage.width, pixelHeight: cgImage.height,
                        pixelsPerMillimeter: scale, bounds: box)
    }
}
