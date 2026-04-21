# LCCAD Phase 2 TODO

Phase 1（MVP 基盤）完了を受け、「実用的に使える CAD」にするための機能群を整理する。
UI を変更する項目は、実装前に `design/lccad.pen` を更新して確認してからコードへ反映する。

## 実装順序

依存関係・実用性・リスクを考慮した推奨順序。

| 順序 | タスク | 工数 | リスク | 状態 |
|------|--------|------|--------|------|
| 1 | A. マルチセレクト | 大 | 中 | ✅ 完了 |
| 2 | B. プリント + キャリブレーション | 大 | 中 | ✅ 完了 |
| 3 | C. ルーラー表示 | 中 | 低 | ✅ 完了 |
| 4 | D. 目打ち管理シート | 中 | 低 | 未着手 |
| 5 | E. カーブ系 Trim / Offset | 大 | 高 | 一部実装 |
| 6 | F. 整列・分布ツール | 中 | 低 | 未着手 |

### 依存関係

```
A (マルチセレクト)
 └── F (整列・分布) — A が前提

B (プリント+キャリブレーション) — 独立
C (ルーラー) — 独立
D (目打ち管理) — 独立
E (カーブ Trim/Offset) — 独立
```

A と B は独立しており並行して進められる。

---

## A. マルチセレクト（複数選択）

- 背景
  - 現在 `selectedShapeId: UUID?` で単一選択のみ。
  - 複数図形の一括移動・削除・プロパティ変更ができず、実用上のボトルネック。
  - 後続機能（整列・グループ化等）の前提となる基盤機能。
- やること
  - `selectedShapeId: UUID?` → `selectedShapeIds: Set<UUID>` に変更。
  - クリックで単一選択、Shift+クリックで追加/解除。
  - ドラッグによる矩形選択（マーキー選択）。
  - `⌘A` で全選択。
  - 複数選択時のバウンディングボックス表示・一括移動・一括削除。
  - Properties パネルは複数選択時に共通プロパティのみ表示（または「N items selected」）。
  - Undo / Redo 対応。
- 主な影響箇所
  - `Sources/LCCAD/ViewModels/EditorViewModel.swift` — 選択モデル全面変更
  - `Sources/LCCAD/Canvas/CanvasView.swift` — マーキー選択描画、ヒットテスト変更
  - `Sources/LCCAD/Canvas/SelectionOverlay.swift` — 複数バウンディングボックス対応
  - `Sources/LCCAD/Views/RightPanel/RightPanelView.swift` — 複数選択時の表示
- 完了条件
  - Shift+クリックで複数図形を選択・解除できる。
  - ドラッグで矩形範囲内の図形をまとめて選択できる。
  - 複数選択状態で移動・削除が正しく動作する。
  - Undo / Redo で選択状態と図形操作の両方が正しく戻る。

## B. プリント + キャリブレーション

レザークラフトでは型紙の実寸印刷が必須。1mm のずれも許容できないため、プリンターごとのキャリブレーションが重要。

### B-1. 基本印刷

- やること
  - `NSPrintOperation` による実寸 (1:1) 印刷。
  - 用紙サイズに応じた自動タイル分割（複数ページにまたがる型紙対応）。
  - タイル境界ののりしろ・位置合わせマーク。
  - 印刷プレビュー対応。
  - メニュー: File > Print (⌘P)。
- 主な影響箇所
  - `Sources/LCCAD/App/LCCADApp.swift` — Print コマンド追加
  - `Sources/LCCAD/Export/` — 印刷用レンダリングロジック（新規）
- 完了条件
  - ⌘P でプリントダイアログが開き、キャンバス内容が実寸で印刷される。
  - 用紙からはみ出る図面が複数ページに正しく分割される。

### B-2. プリンターキャリブレーション

- やること
  - キャリブレーション印刷: 100mm の正方形を印刷するテストページ。
  - 実測値の入力 UI: 印刷結果を定規で測り、X/Y 方向の実測値を入力。
  - 補正倍率の自動計算: `scaleX = 100.0 / measuredX`, `scaleY = 100.0 / measuredY`。
  - **プリンター別プロファイル保存**: プリンター名をキーに補正値を永続化。
  - 印刷時にプリンターを選択すると、対応するキャリブレーション値を自動適用。
  - キャリブレーション未設定のプリンターでは警告を表示（任意でスキップ可）。
- プロファイル管理
  - 設定画面にキャリブレーション管理セクションを追加。
  - プリンター別プロファイル一覧の表示・編集・削除。
  - 「キャリブレーション印刷」ボタンからテストページを直接印刷。
  - 保存先: `~/Library/Application Support/LCCAD/printer_calibrations.json`。
- データ構造（案）
  ```swift
  struct PrinterCalibration: Codable, Identifiable {
      var id: UUID
      var printerName: String
      var scaleX: Double  // 補正倍率 (default: 1.0)
      var scaleY: Double
      var createdAt: Date
      var updatedAt: Date
  }
  ```
- 主な影響箇所
  - `Sources/LCCAD/Models/` — `PrinterCalibration` モデル（新規）
  - `Sources/LCCAD/Views/Settings/SettingsView.swift` — キャリブレーション管理 UI
  - `Sources/LCCAD/Export/` — 印刷時のスケール補正適用
- 完了条件
  - キャリブレーションテストページを印刷できる。
  - 実測値を入力して補正倍率が計算・保存される。
  - プリンターごとに異なるキャリブレーション値を保持できる。
  - 印刷時に選択したプリンターのキャリブレーション値が自動適用される。
  - 設定画面からプロファイルを管理（一覧・編集・削除）できる。

## C. ルーラー表示

- 背景
  - `ProjectSettings` に `showRuler: Bool` が既に存在するが、描画が未実装。
- やること
  - キャンバス上辺・左辺にルーラーを描画。
  - ズーム・パンに連動して目盛りが動く。
  - 単位系 (mm / inch) に応じた目盛り表示。
  - マウス位置に対応するルーラー上のインジケーター。
  - View > Show Ruler (⌘R) でトグル。
- 主な影響箇所
  - `Sources/LCCAD/Canvas/` — ルーラー描画（新規）
  - `Sources/LCCAD/Views/MainWindow/MainEditorView.swift` — ルーラー配置
- 完了条件
  - ルーラーが表示され、ズーム・パンに正しく連動する。
  - mm / inch 切替で目盛りが変わる。
  - トグルで表示/非表示を切り替えられる。

## D. 目打ち管理シート

- 背景
  - `PrickingIron` モデルは実装済みだが、UI からの CRUD ができない。
  - ツールバーの StitchSection にプルダウンはあるが、追加・編集は不可。
- やること
  - 目打ち管理シート（モーダル or シート）を追加。
  - 目打ちの種類 (Diamond / French / Round / Flat)、ピッチ、刃数、角度、サイズを編集。
  - プリセット（よく使う設定）の追加・削除。
  - ドキュメント内の `prickingIrons` 配列を直接編集。
- 主な影響箇所
  - `Sources/LCCAD/Views/` — 目打ち管理シート（新規）
  - `Sources/LCCAD/Views/RightPanel/StitchSection.swift` — 管理シートへの導線
  - `Sources/LCCAD/ViewModels/EditorViewModel.swift` — 目打ち CRUD API
- 完了条件
  - UI から目打ちの追加・編集・削除ができる。
  - 変更がドキュメントに保存され、再読込後も維持される。

## E. カーブ系 Trim / Offset

- 背景
  - Trim / Offset は現在 Line（直線）のみ対応。
  - 曲線を含む型紙を作るには Arc / Bezier への対応が必要。
- 現状（一部実装済み）
  - **Trim**: Line-Line, Arc-Line, Bezier-Line は線分近似で対応済み。
  - **Offset**: Line, Rectangle, Ellipse は対応済み。
- 残作業
  - **Trim**: Arc-Arc, Bezier-Bezier の真の曲線交差計算。
  - **Offset**: Arc のオフセット（半径加減）、Bezier の近似オフセット。
  - 交点計算の精度担保（数値的安定性）。
- 主な影響箇所
  - `Sources/LCCAD/Tools/TrimTool.swift`
  - `Sources/LCCAD/Tools/OffsetTool.swift`
  - `Sources/LCCAD/Models/Shapes/` — 交点計算ユーティリティ
- 完了条件
  - Arc / Bezier を含む交差でトリムが正しく動作する。
  - Arc / Bezier のオフセットが視覚的に正しい結果を返す。
  - 既存の Line 対応が壊れない。

## F. 整列・分布ツール

- 前提: A（マルチセレクト）の完了が必要。
- やること
  - 左揃え・右揃え・上揃え・下揃え・水平中央・垂直中央。
  - 水平等間隔分布・垂直等間隔分布。
  - メニュー or ツールバーからアクセス。
- 主な影響箇所
  - `Sources/LCCAD/ViewModels/EditorViewModel.swift` — 整列・分布ロジック
  - `Sources/LCCAD/App/AppCommands.swift` — メニュー項目追加
- 完了条件
  - 複数図形を選択し、各種整列・分布が正しく動作する。
  - Undo / Redo 対応。
