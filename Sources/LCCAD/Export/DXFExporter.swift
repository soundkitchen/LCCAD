import Foundation
import CoreGraphics

struct DXFExportOptions: Sendable {
    var flipY: Bool = false
}

enum DXFExporter {
    static func export(document: DocumentData, options: DXFExportOptions = .init()) -> String {
        var dxf = ""
        dxf += headerSection()
        dxf += tablesSection(document: document)
        dxf += entitiesSection(document: document, options: options)
        dxf += "0\nEOF\n"
        return dxf
    }

    // MARK: - Sections

    private static func headerSection() -> String {
        """
        0
        SECTION
        2
        HEADER
        9
        $ACADVER
        1
        AC1009
        0
        ENDSEC

        """
    }

    private static func tablesSection(document: DocumentData) -> String {
        // Collect all distinct non-solid line styles used in the document
        var usedStyles = Set<LineStyle>()
        for layer in document.layers {
            for shape in layer.shapes {
                if shape.stroke.lineStyle != .solid {
                    usedStyles.insert(shape.stroke.lineStyle)
                }
            }
        }

        var s = "0\nSECTION\n2\nTABLES\n"

        // LTYPE table
        s += "0\nTABLE\n2\nLTYPE\n70\n\(usedStyles.count + 1)\n"
        // CONTINUOUS is always defined
        s += "0\nLTYPE\n2\nCONTINUOUS\n70\n0\n3\nSolid line\n72\n65\n73\n0\n40\n0.0\n"
        for style in usedStyles {
            s += ltypeDefinition(for: style)
        }
        s += "0\nENDTAB\n"

        // LAYER table
        s += "0\nTABLE\n2\nLAYER\n70\n\(document.layers.count + 1)\n"
        for layer in document.layers {
            s += "0\nLAYER\n2\n\(sanitize(layer.name))\n70\n0\n62\n7\n6\nCONTINUOUS\n"
        }
        s += "0\nLAYER\n2\nSTITCH\n70\n0\n62\n1\n6\nCONTINUOUS\n"
        s += "0\nENDTAB\n0\nENDSEC\n"
        return s
    }

    private static func ltypeDefinition(for style: LineStyle) -> String {
        guard let pattern = style.dashPattern else { return "" }
        // DXF LTYPE: positive = dash, 0 = dot (very short dash), negative = gap
        var elements: [CGFloat] = []
        for (i, val) in pattern.enumerated() {
            if i % 2 == 0 {
                // Dash segment: use 0 for dots (values < 0.6mm)
                elements.append(val < 0.6 ? 0 : val)
            } else {
                // Gap segment: negative value
                elements.append(-val)
            }
        }
        let totalLen = elements.reduce(0) { $0 + abs($1) }
        var s = "0\nLTYPE\n2\n\(style.dxfName)\n70\n0\n3\n\(style.displayName)\n72\n65\n"
        s += "73\n\(elements.count)\n40\n\(fmt(totalLen))\n"
        for e in elements {
            s += "49\n\(fmt(e))\n"
        }
        return s
    }

    private static func entitiesSection(document: DocumentData, options: DXFExportOptions) -> String {
        var s = "0\nSECTION\n2\nENTITIES\n"

        for layer in document.layers where layer.isVisible {
            let layerName = sanitize(layer.name)
            for shape in layer.shapes {
                s += dxfEntities(for: shape, layer: layerName, options: options)
            }
            for stitchLine in layer.stitchLines {
                for hole in stitchLine.holes {
                    s += pointEntity(x: hole.position.x, y: yVal(hole.position.y, options), layer: "STITCH")
                }
            }
        }

        s += "0\nENDSEC\n"
        return s
    }

    // MARK: - Shape → DXF Entities

    private static func dxfEntities(for shape: AnyShape, layer: String, options: DXFExportOptions) -> String {
        let lt = shape.stroke.lineStyle.dxfName

        switch shape {
        case .line(let line):
            return lineEntity(
                x1: line.startPoint.x, y1: yVal(line.startPoint.y, options),
                x2: line.endPoint.x, y2: yVal(line.endPoint.y, options),
                layer: layer, linetype: lt
            )

        case .rectangle(let rect):
            let o = rect.origin
            let w = rect.size.width
            let h = rect.size.height
            let corners = [
                (o.x, o.y), (o.x + w, o.y),
                (o.x + w, o.y + h), (o.x, o.y + h),
            ]
            var s = ""
            for i in 0..<4 {
                let j = (i + 1) % 4
                s += lineEntity(
                    x1: corners[i].0, y1: yVal(corners[i].1, options),
                    x2: corners[j].0, y2: yVal(corners[j].1, options),
                    layer: layer, linetype: lt
                )
            }
            return s

        case .arc(let arc):
            // DXF ARC uses degrees, center-based, CCW convention
            let startDeg = arc.startAngle * 180 / .pi
            let endDeg = arc.endAngle * 180 / .pi
            return arcEntity(
                cx: arc.center.x, cy: yVal(arc.center.y, options),
                radius: arc.radius,
                startAngle: options.flipY ? -endDeg : startDeg,
                endAngle: options.flipY ? -startDeg : endDeg,
                layer: layer, linetype: lt
            )

        case .ellipse:
            // R12 doesn't support ELLIPSE — approximate with polyline
            return ""  // TODO: polyline approximation

        case .dot(let dot):
            return pointEntity(x: dot.position.x, y: yVal(dot.position.y, options), layer: layer)

        case .bezier(let bezier):
            // Approximate with polyline
            guard bezier.points.count >= 2 else { return "" }
            var s = ""
            let segCount = bezier.isClosed ? bezier.points.count : bezier.points.count - 1
            for i in 0..<segCount {
                let j = (i + 1) % bezier.points.count
                let p0 = bezier.points[i].point
                let p1 = bezier.points[i].controlOut
                let p2 = bezier.points[j].controlIn
                let p3 = bezier.points[j].point
                // Sample 20 points per segment
                var prevPt = p0
                for step in 1...20 {
                    let t = CGFloat(step) / 20
                    let pt = BezierSegmentPathWalker.evalCubic(t: t, p0: p0, p1: p1, p2: p2, p3: p3)
                    s += lineEntity(
                        x1: prevPt.x, y1: yVal(prevPt.y, options),
                        x2: pt.x, y2: yVal(pt.y, options),
                        layer: layer, linetype: lt
                    )
                    prevPt = pt
                }
            }
            return s

        case .text(let text):
            return textEntity(
                x: text.position.x, y: yVal(text.position.y, options),
                height: text.fontSize, content: text.content, layer: layer
            )
        }
    }

    // MARK: - DXF Entity Builders

    private static func lineEntity(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat,
                                    layer: String, linetype: String = "CONTINUOUS") -> String {
        "0\nLINE\n8\n\(layer)\n6\n\(linetype)\n10\n\(fmt(x1))\n20\n\(fmt(y1))\n11\n\(fmt(x2))\n21\n\(fmt(y2))\n"
    }

    private static func arcEntity(cx: CGFloat, cy: CGFloat, radius: CGFloat,
                                   startAngle: CGFloat, endAngle: CGFloat,
                                   layer: String, linetype: String = "CONTINUOUS") -> String {
        "0\nARC\n8\n\(layer)\n6\n\(linetype)\n10\n\(fmt(cx))\n20\n\(fmt(cy))\n40\n\(fmt(radius))\n50\n\(fmt(startAngle))\n51\n\(fmt(endAngle))\n"
    }

    private static func pointEntity(x: CGFloat, y: CGFloat, layer: String) -> String {
        "0\nPOINT\n8\n\(layer)\n10\n\(fmt(x))\n20\n\(fmt(y))\n"
    }

    private static func textEntity(x: CGFloat, y: CGFloat, height: CGFloat, content: String, layer: String) -> String {
        "0\nTEXT\n8\n\(layer)\n10\n\(fmt(x))\n20\n\(fmt(y))\n40\n\(fmt(height))\n1\n\(content)\n"
    }

    // MARK: - Helpers

    private static func yVal(_ y: CGFloat, _ options: DXFExportOptions) -> CGFloat {
        options.flipY ? -y : y
    }

    private static func fmt(_ v: CGFloat) -> String {
        String(format: "%.4f", v)
    }

    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
    }
}
