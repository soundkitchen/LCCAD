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
            let corners = rect.rotatedCorners  // [TL, TR, BR, BL] after rotation
            var s = ""
            for i in 0..<4 {
                let j = (i + 1) % 4
                s += lineEntity(
                    x1: corners[i].x, y1: yVal(corners[i].y, options),
                    x2: corners[j].x, y2: yVal(corners[j].y, options),
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

        case .ellipse(let ellipse):
            // R12 has no ELLIPSE entity — approximate the (possibly rotated)
            // ellipse with a closed loop of LINE segments, matching the bezier
            // approach. Y-flip is handled per-point by yVal, so no separate
            // angle adjustment is needed for flipY.
            let segments = 72  // 5° resolution
            var pts: [CGPoint] = []
            pts.reserveCapacity(segments)
            for i in 0..<segments {
                let theta = CGFloat(i) / CGFloat(segments) * 2 * .pi
                var p = CGPoint(
                    x: ellipse.center.x + ellipse.radiusX * cos(theta),
                    y: ellipse.center.y + ellipse.radiusY * sin(theta)
                )
                if ellipse.rotation != 0 {
                    p = p.rotated(around: ellipse.center, angle: ellipse.rotation)
                }
                pts.append(p)
            }
            var s = ""
            for i in 0..<segments {
                let a = pts[i]
                let b = pts[(i + 1) % segments]
                s += lineEntity(
                    x1: a.x, y1: yVal(a.y, options),
                    x2: b.x, y2: yVal(b.y, options),
                    layer: layer, linetype: lt
                )
            }
            return s

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
            // DXF TEXT rotation is degrees CCW around the insertion point. Our
            // rotation pivots around the unrotated bbox center, so the
            // insertion point needs to be rotated to match.
            let rotatedPos = text.rotation == 0
                ? text.position
                : text.position.rotated(around: text.unrotatedCenter, angle: text.rotation)
            let rotDeg = text.rotation * 180 / .pi
            return textEntity(
                x: rotatedPos.x, y: yVal(rotatedPos.y, options),
                height: text.fontSize, content: text.content,
                rotationDeg: options.flipY ? -rotDeg : rotDeg,
                layer: layer
            )

        case .group(let group):
            return group.children.map { dxfEntities(for: $0, layer: layer, options: options) }.joined()
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

    private static func textEntity(x: CGFloat, y: CGFloat, height: CGFloat, content: String, rotationDeg: CGFloat = 0, layer: String) -> String {
        var s = "0\nTEXT\n8\n\(layer)\n10\n\(fmt(x))\n20\n\(fmt(y))\n40\n\(fmt(height))\n1\n\(sanitizeText(content))\n"
        if rotationDeg != 0 {
            s += "50\n\(fmt(rotationDeg))\n"
        }
        return s
    }

    // MARK: - Helpers

    private static func yVal(_ y: CGFloat, _ options: DXFExportOptions) -> CGFloat {
        options.flipY ? -y : y
    }

    private static func fmt(_ v: CGFloat) -> String {
        String(format: "%.4f", v)
    }

    /// Sanitize a DXF layer / linetype name. DXF is a newline-delimited format,
    /// so any control character embedded in user input could be interpreted as
    /// an entity delimiter. Replace spaces, control chars, and brace characters
    /// with `_`.
    private static func sanitize(_ name: String) -> String {
        var result = ""
        result.reserveCapacity(name.count)
        for scalar in name.unicodeScalars {
            if scalar.value < 0x20 || scalar == " " || scalar == "{" || scalar == "}" {
                result.append("_")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// Sanitize DXF TEXT content. DXF TEXT values must not contain raw
    /// newlines or carriage returns (they would terminate the value early).
    /// Other control characters are also stripped defensively.
    private static func sanitizeText(_ content: String) -> String {
        var result = ""
        result.reserveCapacity(content.count)
        for scalar in content.unicodeScalars {
            if scalar.value < 0x20 {
                result.append(" ")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
