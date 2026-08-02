import XCTest
@testable import LCCAD

@MainActor
final class EditorViewModelZoomTests: XCTestCase {

    private func makeEditor(shapes: [AnyShape]) -> EditorViewModel {
        var doc = DocumentData.empty()
        doc.layers[0].shapes = shapes
        let editor = EditorViewModel(document: doc)
        editor.canvasSize = CGSize(width: 800, height: 600)
        return editor
    }

    // MARK: - Zoom to Fit

    func testZoomToFitFitsBoundingBoxInsideView() {
        let rect = RectangleShape(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 100, height: 50))
        let editor = makeEditor(shapes: [.rectangle(rect)])

        editor.zoomToFit()

        // 幅制約が支配: (800 - 24*2) / 100 = 7.52
        XCTAssertEqual(editor.transform.scale, 7.52, accuracy: 1e-9)

        // 外接矩形の中心がビュー中央に来る
        let screenCenter = editor.transform.worldToScreen(CGPoint(x: 60, y: 45))
        XCTAssertEqual(screenCenter.x, 400, accuracy: 1e-9)
        XCTAssertEqual(screenCenter.y, 300, accuracy: 1e-9)

        // 外接矩形の四隅が余白の内側に収まる
        let topLeft = editor.transform.worldToScreen(CGPoint(x: 10, y: 20))
        let bottomRight = editor.transform.worldToScreen(CGPoint(x: 110, y: 70))
        XCTAssertGreaterThanOrEqual(topLeft.x, 24 - 1e-9)
        XCTAssertGreaterThanOrEqual(topLeft.y, 24 - 1e-9)
        XCTAssertLessThanOrEqual(bottomRight.x, 800 - 24 + 1e-9)
        XCTAssertLessThanOrEqual(bottomRight.y, 600 - 24 + 1e-9)
    }

    func testZoomToFitUsesHeightWhenHeightGoverns() {
        // 縦長図形: (600 - 48) / 200 = 2.76 が (800 - 48) / 50 = 15.04 より小さい
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 50, height: 200))
        let editor = makeEditor(shapes: [.rectangle(rect)])

        editor.zoomToFit()

        XCTAssertEqual(editor.transform.scale, 2.76, accuracy: 1e-9)
    }

    func testZoomToFitEmptyDocumentFallsBackToActualSize() {
        let editor = makeEditor(shapes: [])

        editor.zoomToFit()

        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.x, 400, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 300, accuracy: 1e-9)
    }

    func testZoomToFitIgnoresHiddenLayers() {
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 50))
        let editor = makeEditor(shapes: [.rectangle(rect)])
        editor.document.layers[0].isVisible = false

        editor.zoomToFit()

        // 表示中の図形がないので Actual Size と同じ
        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.x, 400, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 300, accuracy: 1e-9)
    }

    func testZoomToFitHorizontalLineUsesWidthAxis() {
        // 高さゼロの水平線: 幅軸のみで Fit
        let line = LineShape(start: CGPoint(x: 0, y: 10), end: CGPoint(x: 100, y: 10))
        let editor = makeEditor(shapes: [.line(line)])

        editor.zoomToFit()

        XCTAssertEqual(editor.transform.scale, 7.52, accuracy: 1e-9)
        let screenCenter = editor.transform.worldToScreen(CGPoint(x: 50, y: 10))
        XCTAssertEqual(screenCenter.x, 400, accuracy: 1e-9)
        XCTAssertEqual(screenCenter.y, 300, accuracy: 1e-9)
    }

    func testZoomToFitDegeneratePointCentersAt100Percent() {
        // 幅も高さもゼロ(点状): 最大ズームに飛ばさず 100% で中心へ
        let line = LineShape(start: CGPoint(x: 30, y: 40), end: CGPoint(x: 30, y: 40))
        let editor = makeEditor(shapes: [.line(line)])

        editor.zoomToFit()

        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9)
        let screenPoint = editor.transform.worldToScreen(CGPoint(x: 30, y: 40))
        XCTAssertEqual(screenPoint.x, 400, accuracy: 1e-9)
        XCTAssertEqual(screenPoint.y, 300, accuracy: 1e-9)
    }

    func testZoomToFitTinyCanvasFallsBackToActualSize() {
        // キャンバスが余白(24px * 2)より小さい: 無言 no-op にせず Actual Size に揃える
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 100, height: 50))
        let editor = makeEditor(shapes: [.rectangle(rect)])
        editor.canvasSize = CGSize(width: 40, height: 40)

        editor.zoomToFit()

        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.x, 20, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 20, accuracy: 1e-9)
    }

    func testZoomToFitClampsToMinimumScale() {
        // 巨大図形: (800 - 48) / 10000 = 0.0752 → 下限 0.5 にクランプ
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 10000, height: 100))
        let editor = makeEditor(shapes: [.rectangle(rect)])

        editor.zoomToFit()

        XCTAssertEqual(editor.transform.scale, 0.5, accuracy: 1e-9)
    }

    func testZoomToFitClampsToMaximumScale() {
        // 極小図形: (600 - 48) / 1 = 552 → 上限 50 にクランプ
        let rect = RectangleShape(origin: .zero, size: CGSize(width: 1, height: 1))
        let editor = makeEditor(shapes: [.rectangle(rect)])

        editor.zoomToFit()

        XCTAssertEqual(editor.transform.scale, 50, accuracy: 1e-9)
    }

    // MARK: - Actual Size

    func testZoomToActualSizeResetsScaleAndCentersOrigin() {
        let rect = RectangleShape(origin: CGPoint(x: 10, y: 20), size: CGSize(width: 100, height: 50))
        let editor = makeEditor(shapes: [.rectangle(rect)])
        editor.transform.scale = 12.0
        editor.transform.offset = CGPoint(x: -500, y: 700)

        editor.zoomToActualSize()

        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.x, 400, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 300, accuracy: 1e-9)
    }

    // MARK: - Display Baseline (実寸 100%)

    func testUpdateDisplayBaselineFirstCallAppliesActualSizeStartup() {
        let editor = makeEditor(shapes: [])

        editor.updateDisplayBaseline(pointsPerMm: 5.0)

        // 初回は起動時表示として実寸 100% を適用
        XCTAssertEqual(editor.transform.baselineScale, 5.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.scale, 5.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.zoomPercentage, 100)
        XCTAssertEqual(editor.transform.offset.x, 400, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 300, accuracy: 1e-9)
    }

    func testUpdateDisplayBaselineLaterCallKeepsScaleAndRelabels() {
        let editor = makeEditor(shapes: [])
        editor.updateDisplayBaseline(pointsPerMm: 5.0)
        editor.setZoomPercentage(200)  // scale = 10

        // 別ディスプレイへ移動: 見た目の scale は維持し % 表記だけ変わる
        editor.updateDisplayBaseline(pointsPerMm: 4.0)

        XCTAssertEqual(editor.transform.scale, 10.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.baselineScale, 4.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.zoomPercentage, 250)
    }

    func testUpdateDisplayBaselineRejectsInvalidValues() {
        let editor = makeEditor(shapes: [])

        editor.updateDisplayBaseline(pointsPerMm: 0)
        editor.updateDisplayBaseline(pointsPerMm: -3)
        editor.updateDisplayBaseline(pointsPerMm: .infinity)
        editor.updateDisplayBaseline(pointsPerMm: .nan)

        // 無効値では基準もズームも変わらない
        XCTAssertEqual(editor.transform.baselineScale, 3.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9)

        // 無効値で初回適用フラグが消費されていないこと
        editor.updateDisplayBaseline(pointsPerMm: 5.0)
        XCTAssertEqual(editor.transform.scale, 5.0, accuracy: 1e-9)
    }

    func testUpdateDisplayBaselineWaitsForCanvasSize() {
        // canvasSize 未供給の状態で密度だけ届いた場合、初回適用はサイズ確定まで保留
        let editor = EditorViewModel(document: DocumentData.empty())

        editor.updateDisplayBaseline(pointsPerMm: 5.0)

        XCTAssertEqual(editor.transform.baselineScale, 5.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9, "サイズ確定前に適用しない")

        editor.canvasSize = CGSize(width: 1000, height: 800)

        // サイズ確定と同時に実寸 100% を適用し、実サイズの中心に原点を置く
        XCTAssertEqual(editor.transform.scale, 5.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.x, 500, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 400, accuracy: 1e-9)
    }

    func testUpdateDisplayBaselineRejectsImplausibleDensity() {
        let editor = makeEditor(shapes: [])

        // EDID 不明時の 72dpi 推定値(2x 仮想ディスプレイで約 1.4pt/mm)や
        // 極端な高密度は誤推定として無視する
        editor.updateDisplayBaseline(pointsPerMm: 1.4)
        editor.updateDisplayBaseline(pointsPerMm: 15.1)

        XCTAssertEqual(editor.transform.baselineScale, 3.0, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.scale, 3.0, accuracy: 1e-9)
    }

    func testZoomToActualSizeUsesBaseline() {
        let editor = makeEditor(shapes: [])
        editor.updateDisplayBaseline(pointsPerMm: 4.85)
        editor.transform.scale = 12.0
        editor.transform.offset = CGPoint(x: -500, y: 700)

        editor.zoomToActualSize()

        XCTAssertEqual(editor.transform.scale, 4.85, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.zoomPercentage, 100)
    }

    func testSetZoomPercentageUsesBaseline() {
        let editor = makeEditor(shapes: [])
        editor.updateDisplayBaseline(pointsPerMm: 5.0)

        editor.setZoomPercentage(200)
        XCTAssertEqual(editor.transform.scale, 10.0, accuracy: 1e-9)

        // クランプは scale 単位（CanvasTransform.maxScale = 50）
        editor.setZoomPercentage(100_000)
        XCTAssertEqual(editor.transform.scale, 50.0, accuracy: 1e-9)
    }

    func testZoomToFitDegenerateFallbackUsesBaseline() {
        let line = LineShape(start: CGPoint(x: 30, y: 40), end: CGPoint(x: 30, y: 40))
        let editor = makeEditor(shapes: [.line(line)])
        editor.updateDisplayBaseline(pointsPerMm: 5.0)

        editor.zoomToFit()

        // 点状の退化 bbox は実寸 100% で中心配置
        XCTAssertEqual(editor.transform.scale, 5.0, accuracy: 1e-9)
        let screenPoint = editor.transform.worldToScreen(CGPoint(x: 30, y: 40))
        XCTAssertEqual(screenPoint.x, 400, accuracy: 1e-9)
        XCTAssertEqual(screenPoint.y, 300, accuracy: 1e-9)
    }
}
