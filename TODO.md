# LCCAD TODO

UI を変更する項目は、実装前に `design/lccad.pen` を更新して確認してからコードへ反映する。

## Phase 3（実用 CAD 化の継続強化）

レザークラフトの実作業フロー（左右対称パーツ、寸法管理、テンプレート再利用など）にフィットさせるための機能群。

| 順序 | タスク | 工数 | リスク | 状態 |
|------|--------|------|--------|------|
| 1 | L. 反転 / 反転コピー（Mirror） | 中 | 低 | ✅ 完了 |
| 2 | M. テンプレート機能 | 大 | 中 | 未着手 |
| 3 | N. 寸法線 / Array（配列複製） | 中 | 中 | 未着手 |

### L. 反転 / 反転コピー（Mirror）

- 背景
  - レザークラフトでは左右対称な型紙パーツが頻出（カードホルダー、カバン両側など）。
  - 「左半分を作って右半分を反転コピー」という基本フローが手作業だった。
- やったこと
  - `MirrorAxis` enum と `Shape.mirror(axis:)` プロトコル要求を追加。各シェイプ（Line/Rect/Ellipse/Arc/Bezier/Text/Dot/Group）に実装。
    - Arc: 角度反転 + clockwise トグル
    - Bezier: 各制御点を in-place 反射（点列順を保つため swap は不要）
    - Group: 子に再帰
  - `EditorViewModel.mirrorSelectedShapes(_:copy:)` を追加。in-place は選択 bbox 中心、copy は選択 bbox 端の軸で反転。
  - `cloneWithFreshIds` で全階層 UUID を再発行、`duplicateStitchLines` でステッチラインも引き継ぐ。
  - メニュー: Arrange > Mirror Horizontally (⇧⌘|) / Mirror Vertically (⇧⌘_) / Mirror Right Copy (⌥⌘M) / Mirror Down Copy (⌃⌘M)。
  - 後追い修正: `Shape.visualBoundingBox` を導入し Copy モードの軸計算を tight 化。`ArcShape.boundingBox` が完全な円、`BezierShape.boundingBox` が制御ハンドル込みのため Down Copy で隙間が出ていた問題を解消（特に S 字ベジェで顕著）。`selectionVisualBoundingBox` は Copy モードのみで使用、in-place は中心軸なので geometric bbox のまま。
- 完了条件
  - 4 メニュー項目から正しく動作する。✅
  - Group 含めて全シェイプ種で形状が幾何的に保たれる（21 サンプル点で検証）。✅
  - ステッチ穴が反転後の軌跡上に再生成される。✅
  - Copy モードで複製が視覚的にも flush（Arc / Bezier 含む）。✅
  - Undo / Redo 対応。✅

---

# Phase 2 TODO（完了）

Phase 1（MVP 基盤）完了を受け、「実用的に使える CAD」にするための機能群を整理した。

## 実装順序

依存関係・実用性・リスクを考慮した推奨順序。

| 順序 | タスク | 工数 | リスク | 状態 |
|------|--------|------|--------|------|
| 1 | A. マルチセレクト | 大 | 中 | ✅ 完了 |
| 2 | B. プリント + キャリブレーション | 大 | 中 | ✅ 完了 |
| 3 | C. ルーラー表示 | 中 | 低 | ✅ 完了 |
| 4 | D. 目打ち管理シート | 中 | 低 | ✅ 完了 |
| 5 | E. カーブ系 Trim / Offset | 大 | 高 | ✅ 完了 |
| 6 | F. 整列・分布ツール | 中 | 低 | ✅ 完了 |
| 7 | G. ステッチ穴の図形追従 | 小 | 低 | ✅ 完了 |
| 8 | H. 線種サポート | 小 | 低 | ✅ 完了 |
| 9 | I. ページレイアウトエディタ | 大 | 中 | ✅ 完了 |
| 10 | J. オブジェクトのグルーピング | 中 | 低 | ✅ 完了 |
| 11 | K. 図形変形時のステッチ穴再生成 | 中 | 中 | ✅ 完了 |

### 依存関係

```
A (マルチセレクト)
 └── F (整列・分布) — A が前提

B (プリント+キャリブレーション) — 独立
C (ルーラー) — 独立
D (目打ち管理) — 独立
E (カーブ Trim/Offset) — 独立
G (ステッチ穴追従) — 独立
```

A と B は独立しており並行して進められる。
H と I は独立しており、E/F/G とも独立。H → I の順で実装する。

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

## G. ステッチ穴の図形追従

- 背景
  - ステッチ穴 (`StitchHole`) は絶対座標で保存されている。
  - 元の図形を移動してもステッチ穴が追従せず、置いてけぼりになる。
- やったこと
  - `EditorViewModel` にヘルパー `collectShapeIds(in:)` / `translateStitchHoles(forShapeIds:by:)` を追加。
  - 移動パス全て（ドラッグ・X/Y 入力・整列・分布）で、図形の `translate` と同じ delta を穴 `position` にも適用。
  - 図形削除時には `sourceShapeId` が一致するステッチラインも一緒に削除（孤児ステッチライン防止）。
  - グループ移動・削除ではネストした子の id も再帰的に拾う。
- 主な影響箇所
  - `Sources/LCCAD/ViewModels/EditorViewModel.swift` — 移動・削除・整列・分布
- 完了条件
  - 図形を移動するとステッチ穴が追従する。✅
  - Undo / Redo 対応（`registerUndo` のドキュメントスナップショットに穴の変更も含まれる）。✅

## K. 図形変形時のステッチ穴再生成

- 背景
  - G で「平行移動」には穴が追従するが、変形（ベジェ制御点ドラッグ等）では穴が元の軌跡に残る。
- やったこと
  - `EditorViewModel` に汎用ヘルパー `regenerateStitchLines(forShapeIds:)` を追加。
    - 図形が消えた／walker 非対応 → ステッチラインを削除
    - `PrickingIron` が見つからない → 既存の穴を維持（ユーザーデータを失わない）
    - それ以外 → `AutoStitchEngine.generateHoles` で `holes` を再生成（`StitchLine.mode` を維持）
  - フック 3 か所:
    - `endBezierPointDrag()` — 制御点ドラッグ確定時
    - `bevelCorner()` — Bevel 実行時。元ラインの id を保存するため `BevelResult.line1/line2` を `LineShape(id: ..., start:end:stroke:)` で再構築
    - `trimSelectedShape()` — トリムで消えた元図形 id 由来のステッチラインをヘルパーで drop
- 主な影響箇所
  - `Sources/LCCAD/ViewModels/EditorViewModel.swift`
- 完了条件
  - ベジェ制御点を動かすと、そのベジェに貼られた穴が新しい軌跡上に再生成される。✅
  - Bevel で両ラインのステッチが短縮後の線上に再生成される。✅
  - Trim で消えた図形のステッチラインが削除される。✅
  - Undo / Redo 対応（document スナップショットに含まれる）。✅

## H. 線種サポート

- 背景
  - `StrokeStyle.dashPattern: [CGFloat]?` は既にモデルに存在するが、描画・UI ともに未使用。
  - レザークラフトでは折り線（破線）、ステッチガイド（点線）、縫い代（一点鎖線）などの線種が必要。
- やること
  - `LineStyle` enum を追加: `solid` / `dashed`(3-2mm) / `dotted`(0.5-1.5mm) / `dashDot`(3-1.5-0.5-1.5mm)。
  - `StrokeStyle` に `lineStyle: LineStyle` プロパティを追加（後方互換あり）。
  - キャンバス描画 (`CanvasRenderer`) で dash パターンをズーム連動で描画。
  - 印刷 (`PrintCoordinator`) で `CGContext.setLineDash` を適用。
  - SVG エクスポートで `stroke-dasharray` 属性を出力。
  - DXF エクスポートで LTYPE テーブル + エンティティ参照を追加。
  - 右パネル `StrokeSection` に線種ピッカー（プレビュー付き）を追加。
- 主な影響箇所
  - `Sources/LCCAD/Models/Shapes/Shape.swift` — `LineStyle` enum、`StrokeStyle` 変更
  - `Sources/LCCAD/Canvas/CanvasRenderer.swift` — dash パターン描画
  - `Sources/LCCAD/Export/PrintCoordinator.swift` — 印刷時 dash 描画
  - `Sources/LCCAD/Export/SVGExporter.swift` — `stroke-dasharray` 出力
  - `Sources/LCCAD/Export/DXFExporter.swift` — LTYPE + group code 6
  - `Sources/LCCAD/Views/RightPanel/StrokeSection.swift` — 線種ピッカー UI
  - `Sources/LCCAD/Views/Shared/LineStylePreview.swift` — 新規: プレビュービュー
- 完了条件
  - 4種の線種を選択・適用でき、キャンバス上で正しく描画される。
  - ズームに連動して dash パターンがスケールする。
  - 印刷・SVG・DXF エクスポートに線種が反映される。
  - 古いファイル（`lineStyle` なし）が実線として正しく開ける。

## I. ページレイアウトエディタ

- 背景
  - 現在の印刷は全図形のバウンディングボックスから自動タイリングするのみ。
  - どのパーツを何ページ目に含めるか、ユーザーが制御できない。
  - 大きなパーツが2ページに跨ぐ場合、貼り合わせ用のオーバーラップも必要。
- 方式: 自由配置 + 専用 Page ツール + ページ間スナップ
- やること
  - データモデル: `PrintPage`（origin, paperSize, orientation, margin）、`PageLayoutSettings`（pages 配列, overlapMM, showPageFrames）を `ProjectSettings` に追加。
  - 専用 Page ツール: ツールバーに追加。クリックでページ追加、ドラッグで移動、Delete で削除。
  - ページ間スナップ: ページをドラッグ中、隣接ページと `overlapMM` 分だけ重なる位置に吸着。
  - キャンバスオーバーレイ (`PageLayoutOverlay`): ページフレーム枠・番号・印刷可能領域・オーバーラップゾーンを描画。
  - 右パネル (`PageSection`): ページリスト、用紙サイズ・向き・位置・マージンの編集。
  - メニュー: View > Show Page Frames (⇧⌘P)。
  - 印刷統合: `PrintCoordinator` をページフレームベースの印刷に対応（フォールバック: ページなしなら従来の自動タイリング）。
  - ステータスバーにページ数表示。
- 主な影響箇所
  - `Sources/LCCAD/Models/Document/ProjectSettings.swift` — `PrintPage`, `PaperSize`, `PageLayoutSettings` 追加
  - `Sources/LCCAD/ViewModels/EditorViewModel.swift` — `.page` ツール、ページ選択・ドラッグ
  - `Sources/LCCAD/Canvas/CanvasView.swift` — オーバーレイ挿入、Page ツール操作
  - `Sources/LCCAD/Canvas/PageLayoutOverlay.swift` — 新規: ページフレーム描画
  - `Sources/LCCAD/Canvas/PageSnapEngine.swift` — 新規: ページ間スナップ
  - `Sources/LCCAD/Views/Toolbar/ToolbarView.swift` — Page ツールボタン
  - `Sources/LCCAD/Views/RightPanel/PageSection.swift` — 新規: ページプロパティ UI
  - `Sources/LCCAD/Views/RightPanel/RightPanelView.swift` — Page ツール時の分岐
  - `Sources/LCCAD/Views/StatusBar/StatusBarView.swift` — ページ数表示
  - `Sources/LCCAD/Views/Shared/DesignTokens.swift` — ページ関連カラートークン
  - `Sources/LCCAD/Export/PrintCoordinator.swift` — 自由配置ページ対応
  - `Sources/LCCAD/App/AppCommands.swift` — Show Page Frames メニュー
- 完了条件
  - Page ツールでキャンバス上にページフレームを追加・移動・削除できる。
  - ページ間スナップでオーバーラップ量に応じた吸着が動作する。
  - 右パネルで用紙サイズ・向き・位置を編集できる。
  - ⌘P で印刷: 各ページフレームの内容が正しいページに印刷される。
  - ページレイアウト未設定の古いファイルでは従来の自動タイリングにフォールバック。
  - Undo / Redo 対応。
