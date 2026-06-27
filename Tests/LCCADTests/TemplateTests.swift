import XCTest
@testable import LCCAD

@MainActor
final class TemplateTests: XCTestCase {

    private func makeEditor(shapes: [AnyShape]) -> EditorViewModel {
        var doc = DocumentData.empty()
        doc.layers[0].shapes = shapes
        let editor = EditorViewModel(document: doc)
        editor.undoManager = UndoManager()
        return editor
    }

    // MARK: - Combined bounds helper

    func testCombinedBoundingBoxUnionsAllShapes() {
        let a = DotShape(position: CGPoint(x: 0, y: 0))
        let b = DotShape(position: CGPoint(x: 10, y: 0))
        let box = [AnyShape.dot(a), .dot(b)].combinedBoundingBox!
        // Dots have radius 1.5 → union spans x ∈ [-1.5, 11.5], midX = 5.
        XCTAssertEqual(box.midX, 5, accuracy: 1e-9)
        XCTAssertNil([AnyShape]().combinedBoundingBox)
    }

    // MARK: - Model

    func testCodableRoundTripPreservesShapesNameAndId() throws {
        let line = LineShape(start: CGPoint(x: -5, y: 0), end: CGPoint(x: 5, y: 0))
        let rect = RectangleShape(origin: CGPoint(x: -3, y: -3), size: CGSize(width: 6, height: 6))
        let template = Template(name: "カードケース", shapes: [.line(line), .rectangle(rect)])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(template)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Template.self, from: data)

        XCTAssertEqual(decoded.id, template.id)
        XCTAssertEqual(decoded.name, template.name)
        XCTAssertEqual(decoded.shapes, template.shapes)
    }

    func testBoundingBoxIsNilWhenEmpty() {
        let template = Template(name: "empty", shapes: [])
        XCTAssertNil(template.boundingBox)
    }

    // MARK: - buildTemplate

    func testBuildTemplateFlattenKeepsShapesAndCentersAtOrigin() throws {
        let dotA = DotShape(position: CGPoint(x: 0, y: 0))
        let dotB = DotShape(position: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.dot(dotA), .dot(dotB)])
        editor.selectedShapeIds = [dotA.id, dotB.id]

        let template = try XCTUnwrap(editor.buildTemplate(name: "pair", asGroup: false))

        XCTAssertEqual(template.shapes.count, 2)
        let box = try XCTUnwrap(template.boundingBox)
        XCTAssertEqual(box.midX, 0, accuracy: 1e-9, "combined bbox must be centered on origin")
        XCTAssertEqual(box.midY, 0, accuracy: 1e-9)
    }

    func testBuildTemplateGroupWrapsInSingleGroup() throws {
        let dotA = DotShape(position: CGPoint(x: 0, y: 0))
        let dotB = DotShape(position: CGPoint(x: 10, y: 0))
        let editor = makeEditor(shapes: [.dot(dotA), .dot(dotB)])
        editor.selectedShapeIds = [dotA.id, dotB.id]

        let template = try XCTUnwrap(editor.buildTemplate(name: "grouped", asGroup: true))

        XCTAssertEqual(template.shapes.count, 1)
        guard case .group(let group) = template.shapes[0] else {
            return XCTFail("expected a single group")
        }
        XCTAssertEqual(group.children.count, 2)
    }

    func testBuildTemplateUsesFreshIds() throws {
        let dot = DotShape(position: CGPoint(x: 5, y: 5))
        let editor = makeEditor(shapes: [.dot(dot)])
        editor.selectedShapeIds = [dot.id]

        let template = try XCTUnwrap(editor.buildTemplate(name: "t", asGroup: false))
        XCTAssertNotEqual(template.shapes[0].id, dot.id, "stored shape must not share the live shape's id")
    }

    func testBuildTemplateFallsBackToGeneratedName() throws {
        let dot = DotShape(position: .zero)
        let editor = makeEditor(shapes: [.dot(dot)])
        editor.selectedShapeIds = [dot.id]

        let template = try XCTUnwrap(editor.buildTemplate(name: "   ", asGroup: false))
        XCTAssertFalse(template.name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testBuildTemplateReturnsNilWithoutSelection() {
        let dot = DotShape(position: .zero)
        let editor = makeEditor(shapes: [.dot(dot)])
        XCTAssertNil(editor.buildTemplate(name: "t", asGroup: false))
    }

    // MARK: - placeTemplate

    func testPlaceTemplateCentersOnPointAndSelects() {
        // Centered template: a 10mm line straddling the origin.
        let line = LineShape(start: CGPoint(x: -5, y: 0), end: CGPoint(x: 5, y: 0))
        let template = Template(name: "line", shapes: [.line(line)])
        let editor = makeEditor(shapes: [])

        editor.placeTemplate(template, at: CGPoint(x: 50, y: 40))

        XCTAssertEqual(editor.document.layers[0].shapes.count, 1)
        let box = editor.document.layers[0].shapes.combinedBoundingBox!
        XCTAssertEqual(box.midX, 50, accuracy: 1e-9)
        XCTAssertEqual(box.midY, 40, accuracy: 1e-9)
        XCTAssertEqual(editor.selectedShapeIds, Set(editor.document.layers[0].shapes.map(\.id)))
    }

    func testPlaceTemplateTwiceProducesDistinctFreshIds() {
        let line = LineShape(start: CGPoint(x: -5, y: 0), end: CGPoint(x: 5, y: 0))
        let template = Template(name: "line", shapes: [.line(line)])
        let editor = makeEditor(shapes: [])

        editor.placeTemplate(template, at: CGPoint(x: 10, y: 10))
        editor.placeTemplate(template, at: CGPoint(x: 20, y: 20))

        let ids = editor.document.layers[0].shapes.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1], "each placement must use fresh ids")
        XCTAssertFalse(ids.contains(line.id), "placed shapes must not reuse the template's stored id")
    }

    func testPlaceTemplateGroupClonesChildrenWithFreshIds() {
        let child = DotShape(position: CGPoint(x: 0, y: 0))
        let group = GroupShape(children: [.dot(child)])
        let template = Template(name: "g", shapes: [.group(group)])
        let editor = makeEditor(shapes: [])

        editor.placeTemplate(template, at: CGPoint(x: 5, y: 5))

        guard case .group(let placed) = editor.document.layers[0].shapes[0] else {
            return XCTFail("expected a group")
        }
        XCTAssertNotEqual(placed.id, group.id)
        XCTAssertNotEqual(placed.children[0].id, child.id, "group children must get fresh ids")
    }

    func testPlaceTemplateUndoRemovesShapes() {
        let line = LineShape(start: CGPoint(x: -5, y: 0), end: CGPoint(x: 5, y: 0))
        let template = Template(name: "line", shapes: [.line(line)])
        let editor = makeEditor(shapes: [])

        editor.placeTemplate(template, at: CGPoint(x: 0, y: 0))
        XCTAssertEqual(editor.document.layers[0].shapes.count, 1)

        editor.undoManager?.undo()
        XCTAssertEqual(editor.document.layers[0].shapes.count, 0)
    }
}
