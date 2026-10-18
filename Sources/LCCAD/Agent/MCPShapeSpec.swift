import Foundation

/// `add_shapes` で受け取る図形の指定 (#79)。座標と長さはすべて mm で、座標系はキャンバスと同じ
/// 左上原点・Y 軸下向き。点は `[x, y]` の配列で表す。図形の id は外から受け取らず、
/// 作るたびに新しい id を振る
struct MCPShapeSpec: Decodable {
    let shape: AnyShape

    enum Kind: String, Decodable, CaseIterable {
        case line, rectangle, ellipse, arc, bezier, polyline, text, dimension
    }

    private enum CodingKeys: String, CodingKey {
        case type, stroke
        case start, end, through
        case x, y, width, height, cornerRadius
        case center, radiusX, radiusY
        case points, closed
        case position, content, fontSize, fontName, bold, italic, align
        case offsetPoint, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        let stroke = try c.decodeIfPresent(MCPStrokeSpec.self, forKey: .stroke)?.strokeStyle ?? .default

        switch kind {
        case .line:
            let start = try c.decode(MCPPoint.self, forKey: .start).cgPoint
            let end = try c.decode(MCPPoint.self, forKey: .end).cgPoint
            shape = .line(LineShape(start: start, end: end, stroke: stroke))

        case .rectangle:
            let x = try Self.finite(c, .x)
            let y = try Self.finite(c, .y)
            let width = try Self.positive(c, .width)
            let height = try Self.positive(c, .height)
            let cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
            guard cornerRadius >= 0, cornerRadius.isFinite else {
                throw Self.invalid(c, .cornerRadius, "corner_radius must be 0 or more")
            }
            shape = .rectangle(RectangleShape(
                origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height),
                cornerRadius: cornerRadius, stroke: stroke))

        case .ellipse:
            let center = try c.decode(MCPPoint.self, forKey: .center).cgPoint
            let radiusX = try Self.positive(c, .radiusX)
            let radiusY = try Self.positive(c, .radiusY)
            shape = .ellipse(EllipseShape(center: center, radiusX: radiusX, radiusY: radiusY, stroke: stroke))

        case .arc:
            // キャンバスの円弧ツールと同じく、始点・終点と、弧が通る 1 点で指定する
            let start = try c.decode(MCPPoint.self, forKey: .start).cgPoint
            let end = try c.decode(MCPPoint.self, forKey: .end).cgPoint
            let through = try c.decode(MCPPoint.self, forKey: .through).cgPoint
            guard var arc = EditorViewModel.arcFrom3Points(p1: start, p2: end, p3: through) else {
                throw Self.invalid(c, .through, "start, end and through must not be on one line")
            }
            arc.stroke = stroke
            shape = .arc(arc)

        case .bezier:
            let points = try c.decode([MCPBezierPoint].self, forKey: .points)
            guard points.count >= 2 else { throw Self.invalid(c, .points, "bezier needs at least 2 points") }
            let closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
            shape = .bezier(BezierShape(points: points.map(\.bezierPoint), isClosed: closed, stroke: stroke))

        case .polyline:
            // 直線区間だけのベジェ(制御点 = アンカー)として表す
            let points = try c.decode([MCPPoint].self, forKey: .points)
            guard points.count >= 2 else { throw Self.invalid(c, .points, "polyline needs at least 2 points") }
            let closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
            let bezierPoints = points.map { p in
                BezierPoint(point: p.cgPoint, controlIn: p.cgPoint, controlOut: p.cgPoint)
            }
            shape = .bezier(BezierShape(points: bezierPoints, isClosed: closed, stroke: stroke))

        case .text:
            let position = try c.decode(MCPPoint.self, forKey: .position).cgPoint
            let content = try c.decode(String.self, forKey: .content)
            var text = TextShape(position: position, content: content, stroke: stroke)
            if let fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) {
                guard fontSize > 0, fontSize.isFinite else { throw Self.invalid(c, .fontSize, "font_size must be positive") }
                text.fontSize = fontSize
            }
            if let fontName = try c.decodeIfPresent(String.self, forKey: .fontName) { text.fontName = fontName }
            if let bold = try c.decodeIfPresent(Bool.self, forKey: .bold) { text.isBold = bold }
            if let italic = try c.decodeIfPresent(Bool.self, forKey: .italic) { text.isItalic = italic }
            if let align = try c.decodeIfPresent(TextAlignment.self, forKey: .align) { text.textAlignment = align }
            shape = .text(text)

        case .dimension:
            // キャンバスの寸法線ツールと同じく、測る 2 点と、寸法線を置く位置の 1 点で指定する
            let start = try c.decode(MCPPoint.self, forKey: .start).cgPoint
            let end = try c.decode(MCPPoint.self, forKey: .end).cgPoint
            let offsetPoint = try c.decode(MCPPoint.self, forKey: .offsetPoint).cgPoint
            let dimensionKind = try c.decodeIfPresent(DimensionKind.self, forKey: .kind) ?? .aligned
            shape = .dimensionLine(DimensionLineShape(start: start, end: end, third: offsetPoint, kind: dimensionKind, stroke: stroke))
        }
    }

    private static func finite(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> CGFloat {
        let value = try c.decode(Double.self, forKey: key)
        guard value.isFinite else { throw invalid(c, key, "\(key.stringValue) must be a finite number") }
        return value
    }

    private static func positive(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> CGFloat {
        let value = try finite(c, key)
        guard value > 0 else { throw invalid(c, key, "\(key.stringValue) must be positive") }
        return value
    }

    private static func invalid(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys, _ message: String) -> DecodingError {
        DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: message)
    }
}

/// `[x, y]` の配列で表す点
struct MCPPoint: Decodable {
    let x: CGFloat
    let y: CGFloat

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let x = try c.decode(Double.self)
        let y = try c.decode(Double.self)
        guard c.isAtEnd, x.isFinite, y.isFinite else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "A point must be [x, y] with two finite numbers"))
        }
        self.x = x
        self.y = y
    }
}

/// ベジェのアンカー。制御点を省いたらアンカーと同じ位置(角)にする
struct MCPBezierPoint: Decodable {
    let point: MCPPoint
    let controlIn: MCPPoint?
    let controlOut: MCPPoint?

    var bezierPoint: BezierPoint {
        let anchor = point.cgPoint
        return BezierPoint(point: anchor,
                           controlIn: controlIn?.cgPoint ?? anchor,
                           controlOut: controlOut?.cgPoint ?? anchor)
    }
}

/// 線の色と線種。線幅は 0.1mm 固定なので受け取らない
struct MCPStrokeSpec: Decodable {
    let color: String?
    let lineStyle: LineStyle?

    var strokeStyle: StrokeStyle {
        get throws {
            let codableColor = try color.map(MCPColor.parse) ?? StrokeStyle.default.color
            return StrokeStyle(color: codableColor, lineStyle: lineStyle ?? .solid)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        lineStyle = try c.decodeIfPresent(LineStyle.self, forKey: .lineStyle)
        // 色の書式はここで確かめ、どの図形の指定が悪いかをエラーの位置で示す
        if let color {
            do { _ = try MCPColor.parse(color) } catch {
                throw DecodingError.dataCorruptedError(forKey: .color, in: c, debugDescription: "\(error)")
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case color, lineStyle }
}

/// `#RRGGBB` / `#RRGGBBAA` の色 (sRGB)
enum MCPColor {
    struct InvalidColor: Error, CustomStringConvertible {
        let text: String
        var description: String { "Invalid color \"\(text)\". Use #RRGGBB or #RRGGBBAA" }
    }

    static func parse(_ text: String) throws -> CodableColor {
        var hex = text.trimmingCharacters(in: .whitespaces)
        guard hex.hasPrefix("#") else { throw InvalidColor(text: text) }
        hex.removeFirst()
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            throw InvalidColor(text: text)
        }
        let hasAlpha = hex.count == 8
        let shift: UInt64 = hasAlpha ? 8 : 0
        let r = CGFloat((value >> (16 + shift)) & 0xFF) / 255
        let g = CGFloat((value >> (8 + shift)) & 0xFF) / 255
        let b = CGFloat((value >> shift) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        return CodableColor(r: r, g: g, b: b, a: a)
    }
}
