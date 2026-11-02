import XCTest
@testable import LCCAD

extension EditorViewModel {
    /// テスト用に表示を直接決める(transform は private(set) なので restoreView(_:) を通す)。
    /// 表示を変えたことにする(起動時の表示のままではなくなる)
    func setViewForTesting(scale: CGFloat? = nil, offset: CGPoint? = nil) {
        var snapshot = viewSnapshot
        if let scale { snapshot.transform.scale = scale }
        if let offset { snapshot.transform.offset = offset }
        snapshot.keepsInitialViewCentered = false
        restoreView(snapshot)
    }
}

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
        editor.setViewForTesting(scale: 12.0, offset: CGPoint(x: -500, y: 700))

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

    /// 密度が取れない環境でも、フォールバックの基準で起動時の実寸 100% を済ませる(review #100)
    func testDisplayDensityUnavailableAppliesActualSizeWithFallback() {
        let editor = EditorViewModel(document: DocumentData.empty())

        editor.markDisplayDensityUnavailable()
        XCTAssertFalse(editor.isViewReady, "キャンバス実サイズが揃うまでは済まない")

        editor.canvasSize = CGSize(width: 1000, height: 800)

        XCTAssertTrue(editor.isViewReady)
        XCTAssertEqual(editor.transform.baselineScale, CanvasTransform.fallbackBaselineScale, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.scale, CanvasTransform.fallbackBaselineScale, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.x, 500, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 400, accuracy: 1e-9)

        // あとで別のディスプレイで密度が取れたら、% 表記の基準だけ更新する
        editor.updateDisplayBaseline(pointsPerMm: 6.0)
        XCTAssertEqual(editor.transform.scale, CanvasTransform.fallbackBaselineScale, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.zoomPercentage, 50)
    }

    func testDisplayDensityUnavailableKeepsSuppliedBaseline() {
        let editor = EditorViewModel(document: DocumentData.empty())
        editor.updateDisplayBaseline(pointsPerMm: 5.0)

        editor.markDisplayDensityUnavailable()
        editor.canvasSize = CGSize(width: 800, height: 600)

        XCTAssertTrue(editor.isViewReady)
        XCTAssertEqual(editor.transform.scale, 5.0, accuracy: 1e-9)
    }

    // MARK: - 起動後のキャンバスの大きさの変化 (#101)

    /// 起動時の実寸 100% を済ませた editor(キャンバス 800×600、100% = 5 pt/mm)
    private func makeStartedEditor() -> EditorViewModel {
        let editor = makeEditor(shapes: [])
        editor.updateDisplayBaseline(pointsPerMm: 5.0)
        XCTAssertTrue(editor.isViewReady)
        return editor
    }

    func testResizeAfterStartupRecentersOrigin() {
        let editor = makeStartedEditor()

        // ウィンドウの復元・最大化でキャンバスが大きくなる
        editor.canvasSize = CGSize(width: 3154, height: 2006)

        XCTAssertEqual(editor.transform.scale, 5.0, accuracy: 1e-9, "ズーム率は変えない")
        XCTAssertEqual(editor.transform.offset.x, 1577, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 1003, accuracy: 1e-9)

        // 表示に触れていなければ、何度変わっても中央に置き直す
        editor.canvasSize = CGSize(width: 1000, height: 700)
        XCTAssertEqual(editor.transform.offset.x, 500, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 350, accuracy: 1e-9)
    }

    func testResizeBeforeStartupDoesNotMoveView() {
        // 起動時の適用より前(密度が未確定)の大きさの変化では、表示を動かさない
        let editor = EditorViewModel(document: DocumentData.empty())
        editor.canvasSize = CGSize(width: 800, height: 600)
        let before = editor.transform

        editor.canvasSize = CGSize(width: 1200, height: 900)

        XCTAssertFalse(editor.isViewReady)
        XCTAssertEqual(editor.transform.offset, before.offset)
    }

    func testResizeAfterViewChangeKeepsView() {
        let operations: [(String, (EditorViewModel) -> Void)] = [
            ("zoomIn", { $0.zoomIn() }),
            ("zoomOut", { $0.zoomOut() }),
            ("zoom(by:center:)", { $0.zoom(by: 1.1, center: CGPoint(x: 100, y: 100)) }),
            ("zoomToFit", { $0.zoomToFit() }),
            ("zoomToActualSize", { $0.zoomToActualSize() }),
            ("setZoomPercentage", { $0.setZoomPercentage(150) }),
            ("centerView", { $0.centerView(on: CGPoint(x: 10, y: 20)) }),
            ("panView", { $0.panView(by: CGPoint(x: 30, y: -40)) }),
        ]
        for (name, operation) in operations {
            let editor = makeStartedEditor()
            operation(editor)
            let after = editor.transform

            editor.canvasSize = CGSize(width: 1600, height: 1200)

            // 表示を変えたあとは置き直さない(左上を基準にそのまま)
            XCTAssertEqual(editor.transform.scale, after.scale, accuracy: 1e-9, name)
            XCTAssertEqual(editor.transform.offset.x, after.offset.x, accuracy: 1e-9, name)
            XCTAssertEqual(editor.transform.offset.y, after.offset.y, accuracy: 1e-9, name)
        }
    }

    /// 図形を描いたあとは、パネルの幅やウィンドウの大きさが変わっても図面を動かさない (#101 review)
    func testResizeAfterEditKeepsView() {
        let editor = makeStartedEditor()
        editor.addShape(.line(LineShape(start: .zero, end: CGPoint(x: 10, y: 0))))
        let after = editor.transform

        editor.canvasSize = CGSize(width: 1600, height: 1200)

        XCTAssertEqual(editor.transform.offset.x, after.offset.x, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, after.offset.y, accuracy: 1e-9)
    }

    /// 開く・新規で document を置き換えるのは編集ではないので、置き直しは続く (#101 review)
    func testResizeAfterReplacingDocumentStillRecenters() {
        let editor = makeStartedEditor()
        var loaded = DocumentData.empty()
        loaded.layers[0].shapes = [.line(LineShape(start: .zero, end: CGPoint(x: 10, y: 0)))]

        editor.replaceDocument(with: loaded)
        editor.canvasSize = CGSize(width: 1600, height: 1200)

        XCTAssertEqual(editor.document.layers[0].shapes.count, 1)
        XCTAssertEqual(editor.transform.offset.x, 800, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 600, accuracy: 1e-9)
    }

    /// マーキー選択の最中は始点を画面座標で持つので、置き直さない (#101 review)
    func testResizeDuringMarqueeDoesNotMoveView() {
        let editor = makeStartedEditor()
        editor.marqueeStart = CGPoint(x: 100, y: 100)

        editor.canvasSize = CGSize(width: 1600, height: 1200)
        XCTAssertEqual(editor.transform.offset.x, 400, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 300, accuracy: 1e-9)

        // マーキーが終われば、次に大きさが変わったときに置き直す
        editor.marqueeStart = nil
        editor.canvasSize = CGSize(width: 1000, height: 700)
        XCTAssertEqual(editor.transform.offset.x, 500, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 350, accuracy: 1e-9)
    }

    func testRestoreViewRestoresRecenteringState() {
        let editor = makeStartedEditor()
        let snapshot = editor.viewSnapshot
        editor.panView(by: CGPoint(x: 50, y: 0))

        editor.restoreView(snapshot)
        editor.canvasSize = CGSize(width: 1600, height: 1200)

        // 控えた時点では起動時の表示のままだったので、また置き直す
        XCTAssertEqual(editor.transform.offset.x, 800, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 600, accuracy: 1e-9)
    }

    func testZoomByKeepsGivenPoint() {
        let editor = makeStartedEditor()
        let worldAtCursor = editor.transform.screenToWorld(CGPoint(x: 120, y: 80))

        editor.zoom(by: 1.5, center: CGPoint(x: 120, y: 80))

        XCTAssertEqual(editor.transform.scale, 7.5, accuracy: 1e-9)
        let screenPoint = editor.transform.worldToScreen(worldAtCursor)
        XCTAssertEqual(screenPoint.x, 120, accuracy: 1e-9)
        XCTAssertEqual(screenPoint.y, 80, accuracy: 1e-9)
    }

    func testZoomToActualSizeUsesBaseline() {
        let editor = makeEditor(shapes: [])
        editor.updateDisplayBaseline(pointsPerMm: 4.85)
        editor.setViewForTesting(scale: 12.0, offset: CGPoint(x: -500, y: 700))

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

    // MARK: - Zoom In / Out

    /// 中心を渡さないズームは、キャンバスの中央の点を動かさない (#101)
    func testZoomInOutWithoutCenterKeepsCanvasCenter() {
        let editor = makeEditor(shapes: [])
        editor.canvasSize = CGSize(width: 2000, height: 1200)
        editor.setViewForTesting(scale: 4.0, offset: CGPoint(x: 300, y: 200))
        let worldAtCenter = editor.transform.screenToWorld(CGPoint(x: 1000, y: 600))

        editor.zoomIn()
        XCTAssertEqual(editor.transform.scale, 4.8, accuracy: 1e-9)
        var screenPoint = editor.transform.worldToScreen(worldAtCenter)
        XCTAssertEqual(screenPoint.x, 1000, accuracy: 1e-9)
        XCTAssertEqual(screenPoint.y, 600, accuracy: 1e-9)

        editor.zoomOut()
        XCTAssertEqual(editor.transform.scale, 4.0, accuracy: 1e-9)
        screenPoint = editor.transform.worldToScreen(worldAtCenter)
        XCTAssertEqual(screenPoint.x, 1000, accuracy: 1e-9)
        XCTAssertEqual(screenPoint.y, 600, accuracy: 1e-9)
    }

    func testZoomInWithCenterKeepsGivenPoint() {
        let editor = makeEditor(shapes: [])
        editor.setViewForTesting(scale: 4.0, offset: CGPoint(x: 300, y: 200))
        let worldAtCursor = editor.transform.screenToWorld(CGPoint(x: 50, y: 70))

        editor.zoomIn(center: CGPoint(x: 50, y: 70))

        let screenPoint = editor.transform.worldToScreen(worldAtCursor)
        XCTAssertEqual(screenPoint.x, 50, accuracy: 1e-9)
        XCTAssertEqual(screenPoint.y, 70, accuracy: 1e-9)
    }

    // MARK: - Pan

    func testCenterViewPutsWorldPointAtCanvasCenterKeepingScale() {
        let editor = makeEditor(shapes: [])
        editor.setViewForTesting(scale: 6.0)

        editor.centerView(on: CGPoint(x: 25, y: -10))

        XCTAssertEqual(editor.transform.scale, 6.0, accuracy: 1e-9)
        let screenPoint = editor.transform.worldToScreen(CGPoint(x: 25, y: -10))
        XCTAssertEqual(screenPoint.x, 400, accuracy: 1e-9)
        XCTAssertEqual(screenPoint.y, 300, accuracy: 1e-9)
    }

    func testPanViewMovesDrawingByScreenDelta() {
        let editor = makeEditor(shapes: [])
        editor.setViewForTesting(offset: CGPoint(x: 400, y: 300))

        editor.panView(by: CGPoint(x: 3.7, y: -12))

        // 図面が右へ 3.7pt、上へ 12pt 動く
        XCTAssertEqual(editor.transform.offset.x, 403.7, accuracy: 1e-9)
        XCTAssertEqual(editor.transform.offset.y, 288, accuracy: 1e-9)
    }

    func testVisibleWorldRect() {
        let editor = makeEditor(shapes: [])
        editor.setViewForTesting(scale: 4.0, offset: CGPoint(x: 400, y: 300))

        let rect = editor.visibleWorldRect

        XCTAssertEqual(rect.minX, -100, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, -75, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 200, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 150, accuracy: 1e-9)
    }

    func testZoomPercentageRangeFollowsBaseline() {
        let editor = makeEditor(shapes: [])
        editor.updateDisplayBaseline(pointsPerMm: 5.0)

        // scale の範囲 0.5〜50 pt/mm を、100% = 5 pt/mm で割る
        XCTAssertEqual(editor.zoomPercentageRange.lowerBound, 10, accuracy: 1e-9)
        XCTAssertEqual(editor.zoomPercentageRange.upperBound, 1000, accuracy: 1e-9)
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
