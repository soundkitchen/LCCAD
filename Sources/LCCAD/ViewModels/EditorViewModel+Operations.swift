import Foundation

// MARK: - 画面に依存しない操作 (#78)
//
// 画面のジェスチャーやパネルを通さずに呼べる操作。UI もこれを呼び、
// 外部からの操作(エージェント用の操作 API、#75)も同じ経路を通す。

extension EditorViewModel {

    // MARK: - Layers
    //
    // レイヤー操作は従来どおり Undo を登録しない。

    /// 新しいレイヤーを末尾に追加し、アクティブにする
    func addLayer() {
        let newLayer = Layer(name: "Layer \(document.layers.count + 1)")
        document.layers.append(newLayer)
        activeLayerIndex = document.layers.count - 1
    }

    /// アクティブレイヤーを削除する。最後の 1 枚は削除しない
    func removeActiveLayer() {
        guard document.layers.count > 1 else { return }
        document.layers.remove(at: activeLayerIndex)
        activeLayerIndex = min(activeLayerIndex, document.layers.count - 1)
    }

    /// アクティブレイヤーを 1 つ上(リストの前)へ移す
    func moveActiveLayerUp() {
        guard activeLayerIndex > 0 else { return }
        document.layers.swapAt(activeLayerIndex, activeLayerIndex - 1)
        activeLayerIndex -= 1
    }

    /// アクティブレイヤーを 1 つ下(リストの後ろ)へ移す
    func moveActiveLayerDown() {
        guard activeLayerIndex < document.layers.count - 1 else { return }
        document.layers.swapAt(activeLayerIndex, activeLayerIndex + 1)
        activeLayerIndex += 1
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
