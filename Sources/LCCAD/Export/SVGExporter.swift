import Foundation
import CoreGraphics

enum SVGExporter {
    static func export(document: DocumentData, visibleOnly: Bool = true) -> String {
        let bbox = computeBoundingBox(document: document, visibleOnly: visibleOnly)
        let margin: CGFloat = 5
        let vx = bbox.origin.x - margin
        let vy = bbox.origin.y - margin
        let vw = bbox.width + margin * 2
        let vh = bbox.height + margin * 2

        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             viewBox="\(fmt(vx)) \(fmt(vy)) \(fmt(vw)) \(fmt(vh))"
             width="\(fmt(vw))mm" height="\(fmt(vh))mm">
        """

        for layer in document.layers where (!visibleOnly || layer.isVisible) {
            svg += "\n<g id=\"\(escapeXML(layer.name))\">\n"
            for shape in layer.shapes {
                svg += svgElement(for: shape) + "\n"
            }

            if !layer.stitchLines.isEmpty {
                svg += "<g class=\"stitch\" stroke=\"none\" fill=\"#D4A574\">\n"
                for stitchLine in layer.stitchLines {
                    let iron = document.prickingIrons.first { $0.id == stitchLine.ironId }
                    let r = (iron?.holeSize ?? 1.0) / 2
                    for hole in stitchLine.holes {
                        svg += "  <circle cx=\"\(fmt(hole.position.x))\" cy=\"\(fmt(hole.position.y))\" r=\"\(fmt(r))\"/>\n"
                    }
                }
                svg += "</g>\n"
            }

            svg += "</g>\n"
        }

        svg += "</svg>\n"
        return svg
    }

    // MARK: - Shape → SVG Element

    private static func svgElement(for shape: AnyShape) -> String {
        let strokeAttr = strokeAttributes(shape.stroke)

        switch shape {
        case .line(let line):
            return "<line x1=\"\(fmt(line.startPoint.x))\" y1=\"\(fmt(line.startPoint.y))\" x2=\"\(fmt(line.endPoint.x))\" y2=\"\(fmt(line.endPoint.y))\" \(strokeAttr)/>"

        case .rectangle(let rect):
            var s = "<rect x=\"\(fmt(rect.origin.x))\" y=\"\(fmt(rect.origin.y))\" width=\"\(fmt(rect.size.width))\" height=\"\(fmt(rect.size.height))\""
            if rect.cornerRadius > 0 {
                s += " rx=\"\(fmt(rect.cornerRadius))\""
            }
            s += " \(strokeAttr)/>"
            return s

        case .ellipse(let ellipse):
            return "<ellipse cx=\"\(fmt(ellipse.center.x))\" cy=\"\(fmt(ellipse.center.y))\" rx=\"\(fmt(ellipse.radiusX))\" ry=\"\(fmt(ellipse.radiusY))\" \(strokeAttr)/>"

        case .arc(let arc):
            let start = arc.startPoint
            let end = arc.endPoint
            var sweep = arc.endAngle - arc.startAngle
            if !arc.clockwise {
                if sweep < 0 { sweep += 2 * .pi }
            } else {
                if sweep > 0 { sweep -= 2 * .pi }
            }
            let largeArc = abs(sweep) > .pi ? 1 : 0
            let sweepFlag = arc.clockwise ? 0 : 1
            return "<path d=\"M\(fmt(start.x)),\(fmt(start.y)) A\(fmt(arc.radius)),\(fmt(arc.radius)) 0 \(largeArc) \(sweepFlag) \(fmt(end.x)),\(fmt(end.y))\" \(strokeAttr)/>"

        case .dot(let dot):
            return "<circle cx=\"\(fmt(dot.position.x))\" cy=\"\(fmt(dot.position.y))\" r=\"\(fmt(dot.radius))\" fill=\"\(colorHex(dot.stroke.color))\"/>"

        case .bezier(let bezier):
            guard bezier.points.count >= 2 else { return "" }
            var d = "M\(fmt(bezier.points[0].point.x)),\(fmt(bezier.points[0].point.y))"
            let segCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
            for i in 0..<segCount {
                let j = (i + 1) % bezier.points.count
                let c1 = bezier.points[i].controlOut
                let c2 = bezier.points[j].controlIn
                let end = bezier.points[j].point
                d += " C\(fmt(c1.x)),\(fmt(c1.y)) \(fmt(c2.x)),\(fmt(c2.y)) \(fmt(end.x)),\(fmt(end.y))"
            }
            if bezier.isClosed { d += " Z" }
            return "<path d=\"\(d)\" \(strokeAttr)/>"

        case .text(let text):
            return "<text x=\"\(fmt(text.position.x))\" y=\"\(fmt(text.position.y))\" font-size=\"\(fmt(text.fontSize))\" fill=\"\(colorHex(text.stroke.color))\">\(escapeXML(text.content))</text>"
        }
    }

    // MARK: - Helpers

    private static func strokeAttributes(_ stroke: StrokeStyle) -> String {
        var attrs = "fill=\"none\" stroke=\"\(colorHex(stroke.color))\" stroke-width=\"\(fmt(stroke.width))\""
        if let pattern = stroke.dashPattern, !pattern.isEmpty {
            attrs += " stroke-dasharray=\"\(pattern.map { fmt($0) }.joined(separator: ","))\""
        }
        return attrs
    }

    private static func colorHex(_ c: CodableColor) -> String {
        let r = Int(c.r * 255)
        let g = Int(c.g * 255)
        let b = Int(c.b * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func fmt(_ v: CGFloat) -> String {
        String(format: "%.2f", v)
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func computeBoundingBox(document: DocumentData, visibleOnly: Bool) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity

        for layer in document.layers where (!visibleOnly || layer.isVisible) {
            for shape in layer.shapes {
                let bb = shape.boundingBox
                minX = min(minX, bb.minX)
                minY = min(minY, bb.minY)
                maxX = max(maxX, bb.maxX)
                maxY = max(maxY, bb.maxY)
            }
        }

        guard minX.isFinite else {
            return CGRect(x: 0, y: 0, width: 100, height: 100)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
