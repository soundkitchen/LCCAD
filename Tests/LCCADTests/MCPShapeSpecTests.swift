import XCTest
@testable import LCCAD

/// `add_shapes` の図形の指定 (#79)
final class MCPShapeSpecTests: XCTestCase {

    private func decode(_ json: String) throws -> AnyShape {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MCPShapeSpec.self, from: Data(json.utf8)).shape
    }

    func testLine() throws {
        guard case .line(let line) = try decode(#"{"type":"line","start":[0,0],"end":[10,5]}"#) else {
            return XCTFail("not a line")
        }
        XCTAssertEqual(line.startPoint, CGPoint(x: 0, y: 0))
        XCTAssertEqual(line.endPoint, CGPoint(x: 10, y: 5))
        XCTAssertEqual(line.stroke, .default)
    }

    func testRectangleWithStroke() throws {
        let json = ##"{"type":"rectangle","x":1,"y":2,"width":30,"height":20,"corner_radius":3,"stroke":{"color":"#FF000080","line_style":"dashed"}}"##
        guard case .rectangle(let rect) = try decode(json) else { return XCTFail("not a rectangle") }
        XCTAssertEqual(rect.origin, CGPoint(x: 1, y: 2))
        XCTAssertEqual(rect.size, CGSize(width: 30, height: 20))
        XCTAssertEqual(rect.cornerRadius, 3)
        XCTAssertEqual(rect.stroke.color, CodableColor(r: 1, g: 0, b: 0, a: 128.0 / 255))
        XCTAssertEqual(rect.stroke.lineStyle, .dashed)
        XCTAssertEqual(rect.stroke.dashPattern, LineStyle.dashed.dashPattern)
        XCTAssertEqual(rect.stroke.width, StrokeStyle.fixedWidth)
    }

    func testEllipse() throws {
        guard case .ellipse(let ellipse) = try decode(#"{"type":"ellipse","center":[5,5],"radius_x":4,"radius_y":2}"#) else {
            return XCTFail("not an ellipse")
        }
        XCTAssertEqual(ellipse.center, CGPoint(x: 5, y: 5))
        XCTAssertEqual(ellipse.radiusX, 4)
        XCTAssertEqual(ellipse.radiusY, 2)
    }

    /// 円弧はキャンバスの円弧ツールと同じ 3 点の計算を使う
    func testArcMatchesThreePointTool() throws {
        let json = #"{"type":"arc","start":[0,0],"end":[20,0],"through":[10,-10]}"#
        guard case .arc(let arc) = try decode(json) else { return XCTFail("not an arc") }
        let expected = try XCTUnwrap(EditorViewModel.arcFrom3Points(
            p1: CGPoint(x: 0, y: 0), p2: CGPoint(x: 20, y: 0), p3: CGPoint(x: 10, y: -10)))
        XCTAssertEqual(arc.center.x, expected.center.x, accuracy: 1e-9)
        XCTAssertEqual(arc.center.y, expected.center.y, accuracy: 1e-9)
        XCTAssertEqual(arc.radius, 10, accuracy: 1e-9)
        XCTAssertEqual(arc.clockwise, expected.clockwise)
    }

    func testCollinearArcIsRejected() {
        XCTAssertThrowsError(try decode(#"{"type":"arc","start":[0,0],"end":[20,0],"through":[10,0]}"#))
    }

    func testBezierControlsDefaultToAnchor() throws {
        let json = #"{"type":"bezier","points":[{"point":[0,0],"control_out":[5,-5]},{"point":[10,0]}],"closed":true}"#
        guard case .bezier(let bezier) = try decode(json) else { return XCTFail("not a bezier") }
        XCTAssertTrue(bezier.isClosed)
        XCTAssertEqual(bezier.points[0].controlIn, CGPoint(x: 0, y: 0))
        XCTAssertEqual(bezier.points[0].controlOut, CGPoint(x: 5, y: -5))
        XCTAssertEqual(bezier.points[1].controlIn, CGPoint(x: 10, y: 0))
    }

    func testPolylineBecomesStraightBezier() throws {
        guard case .bezier(let bezier) = try decode(#"{"type":"polyline","points":[[0,0],[10,0],[10,10]]}"#) else {
            return XCTFail("not a bezier")
        }
        XCTAssertFalse(bezier.isClosed)
        XCTAssertEqual(bezier.points.map(\.point), [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
        XCTAssertTrue(bezier.points.allSatisfy { $0.controlIn == $0.point && $0.controlOut == $0.point })
    }

    func testText() throws {
        let json = #"{"type":"text","position":[3,4],"content":"Card","font_size":8,"bold":true,"align":"center"}"#
        guard case .text(let text) = try decode(json) else { return XCTFail("not a text") }
        XCTAssertEqual(text.position, CGPoint(x: 3, y: 4))
        XCTAssertEqual(text.content, "Card")
        XCTAssertEqual(text.fontSize, 8)
        XCTAssertTrue(text.isBold)
        XCTAssertEqual(text.textAlignment, .center)
    }

    func testDimensionMatchesThreePointTool() throws {
        let json = #"{"type":"dimension","start":[0,0],"end":[40,0],"offset_point":[20,-6],"kind":"horizontal"}"#
        guard case .dimensionLine(let dim) = try decode(json) else { return XCTFail("not a dimension") }
        let expected = DimensionLineShape(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 40, y: 0),
                                          third: CGPoint(x: 20, y: -6), kind: .horizontal)
        XCTAssertEqual(dim.offset, expected.offset)
        XCTAssertEqual(dim.kind, .horizontal)
    }

    func testEachShapeGetsANewId() throws {
        let json = #"{"type":"line","start":[0,0],"end":[1,1]}"#
        XCTAssertNotEqual(try decode(json).id, try decode(json).id)
    }

    func testRejectsInvalidValues() {
        XCTAssertThrowsError(try decode(#"{"type":"polyline","points":[[0,0]]}"#))
        XCTAssertThrowsError(try decode(#"{"type":"rectangle","x":0,"y":0,"width":-1,"height":2}"#))
        XCTAssertThrowsError(try decode(#"{"type":"line","start":[0],"end":[1,1]}"#))
        XCTAssertThrowsError(try decode(#"{"type":"line","start":[0,0,0],"end":[1,1]}"#))
        XCTAssertThrowsError(try decode(#"{"type":"line","start":[0,0],"end":[1,1],"stroke":{"color":"red"}}"#))
        XCTAssertThrowsError(try decode(#"{"type":"star","points":[[0,0],[1,1]]}"#))
    }

    func testColorParsing() throws {
        XCTAssertEqual(try MCPColor.parse("#00FF00"), CodableColor(r: 0, g: 1, b: 0))
        XCTAssertEqual(try MCPColor.parse("#0000ff40").a, 64.0 / 255)
        XCTAssertThrowsError(try MCPColor.parse("00FF00"))
        XCTAssertThrowsError(try MCPColor.parse("#00FF0"))
        XCTAssertThrowsError(try MCPColor.parse("#GGGGGG"))
    }
}
