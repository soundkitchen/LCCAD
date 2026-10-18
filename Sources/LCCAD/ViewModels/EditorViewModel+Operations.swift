import Foundation

// MARK: - 画面に依存しない操作 (#78)
//
// 画面のジェスチャーやパネルを通さずに呼べる操作。UI もこれを呼び、
// 外部からの操作(エージェント用の操作 API、#75)も同じ経路を通す。

/// 操作の前提が満たされていないときのエラー
enum EditorOperationError: Error, Equatable {
    /// ファイルを扱う操作で、エディタに `LCCADFileDocument` が結び付いていない
    case noFileDocument
}

extension EditorViewModel {

    /// キャンバスでのドラッグ(図形・ページの移動、ベジェの点の編集)の途中か。
    /// 途中はドラッグ前の document を Undo の起点として持っているので、その間に外から
    /// document を変えると、ドラッグを終えたときの Undo 1 回で外からの変更まで戻ってしまう。
    /// 外部からの操作は、この間は document を変えない(review #86)
    var isGestureInProgress: Bool {
        moveUndoSnapshot != nil || bezierEditUndoSnapshot != nil || pageMoveUndoSnapshot != nil
    }

    // MARK: - Document

    /// `url` の .lccad を開き、エディタの状態を新しい document に合わせる(パネルなし)。
    /// 未保存の変更は確認しない。読み込みに失敗したら document もエディタの状態も変えない
    func openDocument(at url: URL) throws {
        guard let fileDocument else { throw EditorOperationError.noFileDocument }
        try fileDocument.read(from: url)
        adoptLoadedDocumentIfNeeded()
    }

    /// 新規の空ドキュメントにし、エディタの状態を合わせる。未保存の変更は確認しない
    func newDocument() throws {
        guard let fileDocument else { throw EditorOperationError.noFileDocument }
        fileDocument.resetToNewDocument()
        adoptLoadedDocumentIfNeeded()
    }

    /// `LCCADFileDocument` の document が開く・新規で丸ごと置き換わっていたら、エディタの
    /// document を差し替え、古い document を指す状態(選択・アクティブレイヤー・Undo 履歴)を
    /// リセットする。`openDocument(at:)` / `newDocument()` はその場で呼び、メニューの
    /// 開く・新規はキャンバスが `loadGeneration` の変化で呼ぶ。合わせ済みなら何もしないので、
    /// 置き換え直後にエディタで行った編集が後から消されることはない
    func adoptLoadedDocumentIfNeeded() {
        guard let fileDocument, fileDocument.loadGeneration != adoptedLoadGeneration else { return }
        adoptedLoadGeneration = fileDocument.loadGeneration
        document = fileDocument.data
        activeLayerIndex = safeActiveLayerIndex
        selectedShapeIds = []
        // 破棄した document を ⌘Z で戻せないように Undo 履歴を消す
        undoManager?.removeAllActions()
    }

    // MARK: - Layers
    //
    // レイヤー操作は従来どおり Undo を登録しない。
    // Undo でレイヤーが減ると `activeLayerIndex` が範囲外のまま残ることがあるので、
    // 添字は範囲内に丸めた `safeActiveLayerIndex` を使う

    /// 新しいレイヤーを末尾に追加し、アクティブにする
    func addLayer() {
        let newLayer = Layer(name: "Layer \(document.layers.count + 1)")
        document.layers.append(newLayer)
        activeLayerIndex = document.layers.count - 1
    }

    /// アクティブレイヤーを削除する。最後の 1 枚は削除しない
    func removeActiveLayer() {
        guard document.layers.count > 1 else { return }
        let index = safeActiveLayerIndex
        document.layers.remove(at: index)
        activeLayerIndex = min(index, document.layers.count - 1)
    }

    /// アクティブレイヤーを 1 つ上(リストの前)へ移す
    func moveActiveLayerUp() {
        let index = safeActiveLayerIndex
        guard index > 0 else { return }
        document.layers.swapAt(index, index - 1)
        activeLayerIndex = index - 1
    }

    /// アクティブレイヤーを 1 つ下(リストの後ろ)へ移す
    func moveActiveLayerDown() {
        let index = safeActiveLayerIndex
        guard index < document.layers.count - 1 else { return }
        document.layers.swapAt(index, index + 1)
        activeLayerIndex = index + 1
    }

    /// レイヤーの表示 / 非表示を切り替える
    func toggleLayerVisibility(at index: Int) {
        guard document.layers.indices.contains(index) else { return }
        document.layers[index].isVisible.toggle()
    }

    // MARK: - Export

    /// 現在の document を SVG として `url` に書き出す(パネルなし)
    func exportSVG(to url: URL) throws {
        try ExportCoordinator.writeSVG(document: document, to: url)
    }

    /// 現在の document を DXF として `url` に書き出す(パネルなし)
    func exportDXF(to url: URL, options: DXFExportOptions = .init()) throws {
        try ExportCoordinator.writeDXF(document: document, options: options, to: url)
    }
}
