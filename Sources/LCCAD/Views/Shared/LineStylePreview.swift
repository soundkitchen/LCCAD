import SwiftUI

struct LineStylePreview: View {
    let style: LineStyle
    var color: Color = .primary

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            let dash: [CGFloat]
            if let pattern = style.dashPattern {
                // Scale mm values for preview visibility (~3x)
                dash = pattern.map { $0 * 3 }
            } else {
                dash = []
            }
            context.stroke(
                path,
                with: .color(color),
                style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: dash)
            )
        }
    }
}
