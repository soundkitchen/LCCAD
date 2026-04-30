# LCCAD 技術アーキテクチャ

## 技術スタック

| 項目 | 選定 | 理由 |
|------|------|------|
| **言語** | Swift | macOS ネイティブ、パフォーマンス、型安全性 |
| **UI フレームワーク** | SwiftUI (主) + AppKit (補) | 宣言的 UI、macOS 標準パーツ活用 |
| **描画エンジン** | Core Graphics | 2D ベクター描画、ベジエ曲線サポート |
| **GPU レンダリング** | Metal (将来) | 大量の図形描画時の高速化 |
| **プロジェクト管理** | XcodeGen | `project.yml` でプロジェクト定義、.xcodeproj を VCS から除外 |
| **ビルド** | xcodebuild | CI/CD 対応、コマンドライン操作 |
| **パッケージ管理** | Swift Package Manager | Apple 公式、Xcode 統合 |
| **テスト** | XCTest | 標準テストフレームワーク |
| **最小 OS** | macOS 14.0 Sonoma | SwiftUI の最新機能活用 |

## プロジェクト構成

### XcodeGen (project.yml)

```yaml
name: LCCAD
options:
  bundleIdPrefix: com.lccad
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  generateEmptyDirectories: true

targets:
  LCCAD:
    type: application
    platform: macOS
    sources:
      - Sources/LCCAD
    resources:
      - Sources/LCCAD/Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lccad.app
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: 1
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.9"
        INFOPLIST_FILE: Sources/LCCAD/Resources/Info.plist
    scheme:
      testTargets:
        - LCCADTests

  LCCADTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests/LCCADTests
    dependencies:
      - target: LCCAD
```

### ディレクトリ構造

```
Sources/LCCAD/
├── App/
│   ├── LCCADApp.swift           # @main エントリポイント、Settings シーン
│   ├── AppCommands.swift        # macOS メニューバー定義 (File/Edit/View/Arrange/Draw/Stitch)
│   └── AppearanceMode.swift     # カラーモード (System/Light/Dark) 管理
│
├── Models/
│   ├── Document/
│   │   ├── LCCADDocument.swift  # ドキュメントモデル (Codable)
│   │   ├── Layer.swift          # レイヤー
│   │   └── ProjectSettings.swift # PaperSize, PageOrientation, PrintPage, PageLayoutSettings 含む
│   ├── Shapes/
│   │   ├── Shape.swift          # Shape プロトコル、AnyShape（8 cases + group）、LineStyle、StrokeStyle、CodableColor
│   │   ├── GroupShape.swift     # グループ（children: [AnyShape] で再帰構造）
│   │   ├── LineShape.swift
│   │   ├── RectangleShape.swift
│   │   ├── EllipseShape.swift
│   │   ├── ArcShape.swift
│   │   ├── BezierShape.swift
│   │   ├── TextShape.swift
│   │   └── DotShape.swift
│   ├── Stitch/
│   │   ├── PrickingIron.swift   # 目打ち定義
│   │   ├── StitchHole.swift     # 縫い穴
│   │   └── StitchLine.swift     # ステッチライン
│   ├── PrinterCalibration.swift # プリンターキャリブレーション + 永続化ストア
│   └── Geometry/
│       ├── GeometryUtils.swift  # 2D 座標 (mm)、LengthUnit、CGPoint/CGRect 拡張
│       └── Intersection.swift   # 交点計算 (line-line, line-circle, line-arc, arc-arc, circle-circle)
│
├── Views/
│   ├── MainWindow/
│   │   ├── MainEditorView.swift # メインエディタ (3カラム HSplitView)
│   │   ├── ToolbarView.swift    # ツールバー
│   │   └── StatusBarView.swift  # ステータスバー（座標表示 + ズーム直接入力）
│   ├── LeftPanel/
│   │   ├── LeftPanelView.swift
│   │   └── LayerListView.swift
│   ├── RightPanel/
│   │   ├── RightPanelView.swift
│   │   ├── PositionSection.swift  # X/Y 直接入力で図形移動
│   │   ├── SizeSection.swift
│   │   ├── StrokeSection.swift    # ColorPicker + 線幅入力 + 線種ピッカー
│   │   ├── ArcSection.swift
│   │   ├── StitchSection.swift
│   │   ├── TextSection.swift
│   │   └── PageSection.swift     # ページレイアウト編集 (Page ツール時)
│   ├── Shared/
│   │   ├── InputField.swift     # PropertySection, PropertyField, EditablePropertyField
│   │   ├── DesignTokens.swift   # Pencil デザイン変数の Swift 転写
│   │   └── LineStylePreview.swift # 線種プレビュー描画 (SwiftUI Canvas)
│   ├── PrickingIronSheet.swift  # 目打ち管理シート
│   └── SettingsView.swift       # 設定画面（カラーモード切替、プリンターキャリブレーション）
│
├── ViewModels/
│   └── EditorViewModel.swift    # エディタ全体の状態管理（マルチセレクト対応）
│
├── Canvas/
│   ├── CanvasView.swift         # キャンバス SwiftUI View + ジェスチャー
│   ├── CanvasRenderer.swift     # Core Graphics 描画ロジック
│   ├── CanvasTransform.swift    # パン/ズーム座標変換
│   ├── GridRenderer.swift       # 適応グリッド描画（1-2-5 系列、10 分割固定）
│   ├── SnapEngine.swift         # スナップ計算
│   ├── SnapOverlay.swift        # スナップインジケータ描画
│   ├── SelectionOverlay.swift   # 選択ハンドル描画（マルチセレクト、マーキー選択）
│   ├── PageLayoutOverlay.swift # ページフレーム・オーバーラップゾーン描画
│   ├── PageSnapEngine.swift    # ページ間スナップ計算
│   ├── DrawingPreviewRenderer.swift # 描画中プレビュー
│   ├── RulerRenderer.swift      # ルーラー描画
│   ├── RulerView.swift          # ルーラー配置 (上辺・左辺)
│   └── ScrollZoomView.swift     # ホイールズーム + 中ボタンパン
│
├── Tools/
│   ├── OffsetTool.swift
│   ├── TrimTool.swift
│   └── BevelTool.swift
│
├── Stitch/
│   ├── AutoStitchEngine.swift   # 自動ステッチ配置アルゴリズム
│   └── PathWalker.swift         # パス歩行
│
├── Export/
│   ├── SVGExporter.swift
│   ├── DXFExporter.swift
│   ├── ExportCoordinator.swift
│   └── PrintCoordinator.swift  # 実寸印刷 + ページベース/自動タイル印刷 + キャリブレーション適用
│
└── Resources/
    ├── Info.plist               # CFBundleLocalizations: en, ja
    ├── Assets.xcassets/
    ├── ja.lproj/                # 日本語ローカライズ（システムダイアログ日本語化）
    └── Localizable.xcstrings    # 日英ローカライズ
```

## アーキテクチャパターン

### MVVM + Document-Based App

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐
│   View      │ ←── │  ViewModel   │ ←── │   Model    │
│  (SwiftUI)  │ ──→ │ (Observable) │ ──→ │ (Codable)  │
└─────────────┘     └──────────────┘     └────────────┘
                           │
                    ┌──────┴──────┐
                    │  Document   │
                    │ (FileWrapper)│
                    └─────────────┘
```

- **Model**: `Codable` な純粋データ型。ファイル保存/読込の単位。
- **ViewModel**: `@Observable` マクロで SwiftUI と連携。ビジネスロジックを持つ。
- **View**: SwiftUI による宣言的 UI。
- **Document**: `ReferenceFileDocument` プロトコルに準拠。Undo/Redo 統合。

### EditorViewModel の主要 API

| カテゴリ | メソッド | 説明 |
|---------|---------|------|
| **選択** | `handleClick(at:shiftHeld:)` | クリック選択。Shift で追加/解除トグル |
| **選択** | `selectAll()` | アクティブレイヤーの全図形を選択 (⌘A) |
| **選択** | `beginMarquee(at:)` / `updateMarquee(to:shiftHeld:)` / `endMarquee()` | マーキー（矩形範囲）選択 |
| **位置編集** | `setSelectedShapePosition(x:y:)` | boundingBox.origin 基準で絶対座標移動（Undo 対応） |
| **移動** | `moveSelectedShapes(by:)` | 全選択図形を一括移動 |
| **削除** | `deleteSelectedShapes()` | 全選択図形を一括削除（Undo 対応） |
| **ストローク編集** | `updateStroke(_:)` | 選択図形の stroke.color / stroke.width / stroke.lineStyle を更新（Undo 対応） |
| **テキスト編集** | `updateTextProperty(_:)` | TextShape のプロパティ更新（Undo 対応） |
| **描画** | `handleDrag(startLocation:currentLocation:phase:shiftHeld:)` | ドラッグ描画。shiftHeld で正方形/正円制約 |
| **ズーム** | `setZoomPercentage(_:)` | パーセント指定ズーム。キャンバス中心基準 |
| **ズーム** | `zoomToFit()` | 実際のキャンバスサイズに基づく Fit |
| **整列** | `alignSelectedShapes(_:)` | 左/右/上/下/水平中央/垂直中央揃え（Undo 対応） |
| **分布** | `distributeSelectedShapes(_:)` | 水平/垂直等間隔分布（3個以上必要、Undo 対応） |
| **反転** | `mirrorSelectedShapes(_:copy:)` | 縦軸/横軸で反転。in-place（中心軸）または copy（端軸で複製＋反転）（Undo 対応） |
| **ページ** | `addPage(at:)` | キャンバスクリック位置にページ追加（Undo 対応） |
| **ページ** | `deleteSelectedPage()` | 選択ページ削除（Undo 対応） |
| **ページ** | `moveSelectedPage(by:)` | ページドラッグ移動（PageSnapEngine 連動） |
| **ページ** | `updatePageProperty(_:)` | 右パネルからのプロパティ変更（Undo 対応） |

### マルチセレクト

選択モデルは `selectedShapeIds: Set<UUID>` で複数図形の同時選択に対応:

| 操作 | 動作 |
|------|------|
| **クリック** | 単一選択（他は解除） |
| **Shift+クリック** | 追加/解除トグル |
| **空白ドラッグ** | マーキー（矩形範囲）選択 |
| **⌘A** | 全選択 |
| **⌘D** | 全解除 |
| **ドラッグ（選択図形上）** | 全選択図形を一括移動 |
| **Delete** | 全選択図形を一括削除 |

複数選択時、Properties パネルは「N items selected」表示 + 共通 Stroke 編集。

#### 選択ヒットテストの設計メモ

- **`handleClick` のスナップ**: 描画ツールでは `snappedWorldPoint` を介してクリック座標がグリッド・端点・中点・中心・交点に吸着するが、**選択ツールではスナップを通さず生の `screenToWorld` を使う**。グリッド外を通る図形（曲線など）の表面をクリックしたときに、座標がグリッドに引き寄せられて図形を外す事故を防ぐため。
- **ドラッグ初動の優先順位**（`CanvasView.makePanGesture`）:
  1. `EditorViewModel.startBezierPointDrag` を試行（単一 bezier 選択時のみ true）。ハンドル/アンカーは曲線輪郭から離れていることが多く、輪郭ヒットテストでは拾えないため最優先で判定する
  2. 図形輪郭の `hitTestPublic` → 選択済み図形なら一括移動、未選択ならまず選択して移動
  3. 全部外れたらマーキー選択開始
- **ドラッグ移動のスナップ** (`CanvasView.applySelectMoveSnap`): カーソルではなく **選択範囲の外接矩形の4角＋中心の5点** をスナップリファレンスにする。各点について「ドラッグ後の到達位置」を `EditorViewModel.snapWorldPoint(_:excludedShapeIds:)` に通し、候補が出たもののうち補正量が最小の点を採用、その点で確定したデルタを `moveSelectedShapes(by:)` に適用する。これにより「角を持っていけば角がグリッドに乗る／中心寄りに動かせば中心が乗る」CAD 慣例の挙動になる。カーソル基準だと図形のクリック位置がグリッド外のときに図形側が中途半端な位置に落ちるため避ける。移動中の図形自身は `SnapEngine` の `excludedShapeIds` で候補から除外し、自己スナップを防ぐ。フレーム間の差分適用は `moveAccumulatedDelta` で増分管理する。
- **Bezier の輪郭ヒットテスト** (`BezierShape.distanceToCubicBezier`): 各セグメントを 24 分割でサンプリングし、**隣接サンプル間を結ぶ線分への点距離** を計算する（点-点距離ではない）。点-点だとサンプル間に落ちたクリックが原理的に拾えないため、polyline 距離で近似する。

### Mirror（反転 / 反転コピー）

`Shape` プロトコルに `mirror(axis: MirrorAxis)` 要求を追加し、`MirrorAxis` enum で軸を表現:

```swift
enum MirrorAxis {
    case horizontal(y: CGFloat)  // 横軸（y 一定）→ 上下反転
    case vertical(x: CGFloat)    // 縦軸（x 一定）→ 左右反転
}
```

各シェイプは座標を反射するだけだが、以下は専用処理が必要:

- **Arc**: 中心反射 + 角度反転（縦軸なら `π - θ`、横軸なら `-θ`）+ `clockwise` トグル
- **Bezier**: 各制御点をその場で反射。点列順を保つため `controlIn` / `controlOut` の swap は不要（segment topology は不変なので幾何的反射で形状が保持される）
- **Group**: 子に再帰

`EditorViewModel.mirrorSelectedShapes(_:copy:)` がメニューから呼ばれ、選択 bbox から軸を導出する:

| 操作 | 軸 | 使用する bbox |
|------|----|--------------|
| Mirror Horizontally（左右反転、in-place） | `.vertical(x: bbox.midX)` | `selectionBoundingBox`（geometric） |
| Mirror Vertically（上下反転、in-place） | `.horizontal(y: bbox.midY)` | `selectionBoundingBox`（geometric） |
| Mirror Right (Copy) | `.vertical(x: bbox.maxX)` — 元と複製が右端で接する | `selectionVisualBoundingBox`（visual） |
| Mirror Down (Copy) | `.horizontal(y: bbox.maxY)` — 元と複製が下端で接する | `selectionVisualBoundingBox`（visual） |

Copy モードが `visualBoundingBox` を使うのは、`boundingBox` がレンダリングされる ink より大きい図形があるため。`ArcShape` は内接する完全な円の bbox を返し、`BezierShape` は全制御ハンドルを含む。これらの図形を Copy すると、軸が視覚的な端より外側に置かれて隙間ができる。`Shape` プロトコルの `visualBoundingBox` は基本図形では `boundingBox` を返し、`Arc` は始点・終点と弧内の極点（0/π/2/π/3π/2）だけで、`Bezier` は curve を 32 ステップサンプリングした実 extent で構築する。In-place 反転は中心軸を使うため対称性が保たれ visual/geometric の差は表れないので geometric bbox のままで良い。

Copy モードでは `cloneWithFreshIds` で全階層 UUID を再発行（Group の子も含む）、`duplicateStitchLines` で `sourceShapeId` を新 id に張り替えたステッチラインを複製、その後 `regenerateStitchLines` で穴を再生成する。

### ステッチラインの図形追従

`StitchHole.position` は絶対 world 座標で保存されるため、元図形の移動・変形・削除と同期させる必要がある。`EditorViewModel` は `StitchLine.sourceShapeId` を介して 2 方式で追従する:

**平行移動（delta シフト）** — `translateStitchHoles(forShapeIds:by:)`

| 操作 | 穴への反映 |
|------|-----------|
| ドラッグ移動 / エッジスクロール (`moveSelectedShapes`) | 同じ delta だけ `hole.position` をシフト |
| X/Y 入力 (`setSelectedShapePosition`) | 同じ delta だけシフト |
| 整列・分布 (`alignSelectedShapes` / `distributeSelectedShapes`) | 図形ごとの delta でシフト |

**変形（穴再生成）** — `regenerateStitchLines(forShapeIds:)`
- 対象ラインの `sourceShapeId` から現在の図形と `PathWalkerFactory.walker(for:)` を引き、`AutoStitchEngine.generateHoles(along:iron:mode:)` で `holes` を差し替え
- 図形が消えた／walker 非対応の場合はステッチラインごと削除
- `PrickingIron` が見つからない場合は穴を維持（ユーザーデータを保全）

| 操作 | 穴への反映 |
|------|-----------|
| ベジェ制御点ドラッグ (`endBezierPointDrag`) | 再生成 |
| Bevel (`bevelCorner`) | 両ラインの id を保存しつつ短縮後の線で再生成。コーナー arc には生成しない |
| Trim (`trimSelectedShape`) | 元図形が消えるのでステッチラインを削除 |

**削除** — `deleteSelectedShapes` で `sourceShapeId` が一致するステッチラインを除去。

グループ移動・削除では `collectShapeIds(in:)` が子孫 id を再帰収集するため、ネスト内部の図形に紐づいた穴も追従する。Undo は `registerUndo` のドキュメントスナップショットに穴の差分も含まれるため追加処理不要。

### キャンバス描画

```
CanvasView (SwiftUI Canvas + GeometryReader)
  ├── GridRenderer         # 適応グリッド背景（1-2-5 系列、10 分割）
  ├── CanvasRenderer       # 図形描画 (Layer 順)
  ├── StitchRenderer       # ステッチ穴描画
  ├── DrawingPreviewRenderer # ツール操作中のプレビュー
  ├── SnapOverlay          # スナップインジケータ
  ├── SelectionOverlay     # 選択ハンドル / ベジエ制御点 / マーキー矩形
  └── ScrollZoomView       # ホイールズーム + 中ボタンパン (NSView)
```

描画は Core Graphics (`CGContext`) ベースで、`draw()` メソッドでレイヤー順に描画。

### グリッド描画アルゴリズム

業界標準（KiCad, Figma 等）に準拠した適応グリッド:

1. **1-2-5 系列** (`0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100 mm...`) からスクリーン間隔 >= 8px の最小 tier を選択
2. **major = minor × 10** 固定（1-2-5 系列で 3 tier 上 = 常に 10 倍）
3. **minor 線フェード**: スクリーン間隔が閾値付近のとき opacity を 0→1 にスムーズ遷移（fadeRange: 16px）
4. **色はデザイントークン**: `DesignTokens.gridLine` / `gridLineMajor` で Light/Dark 対応
5. **スナップ連動**: `SnapEngine` が `adaptiveSpacings()` を共有し、表示グリッドとスナップ位置が一致

### カラーモード管理

```
AppearanceMode (enum: system / light / dark)
  └── apply() → NSApp.appearance を直接設定（全ウィンドウ即時反映）

LCCADApp
  ├── .onAppear で起動時に保存済み設定を適用
  └── Settings シーン → SettingsView

SettingsView
  └── @AppStorage("appearanceMode") + .onChange で即時 apply()
```

`NSApp.appearance` を使うことで、SwiftUI の `preferredColorScheme` のシーン間伝播遅延を回避。

## 印刷 + プリンターキャリブレーション

### 実寸印刷

`PrintCoordinator` が `NSPrintOperation` を使って実寸 (1:1) 印刷を実行:

- **単位変換**: 1mm = 72/25.4 ポイント（`pointsPerMM ≈ 2.8346`）
- **`scalingFactor = 1.0`**: OS レベルのスケーリングを強制無効化
- **線種対応**: `StrokeStyle.dashPattern` を `CGContext.setLineDash` で反映
- **デュアルモード印刷**:
  - **ページベース** (`pageLayout.pages` あり): 各ページフレームの world origin を用紙の左上にマッピング。用紙サイズ・向きは `PageLayoutSettings` の設定を `NSPrintInfo` に反映。マージン 0（ページフレーム＝用紙）
  - **自動タイリング** (`pageLayout.pages` なし): 従来どおり全図形のバウンディングボックスから自動分割。のりしろ 10mm オーバーラップ、L字コーナーマーク + 十字位置合わせマーク、ページ番号ラベル

### プリンターキャリブレーション

プリンター固有のスケーリング誤差を補正:

```
1. テストページ印刷（150mm 正方形）
2. ノギスで実測 → measuredX, measuredY
3. 補正倍率計算: scaleX = 150.0 / measuredX
4. 印刷時に squareSize * scaleX で補正適用
```

#### データモデル

```swift
struct PrinterCalibration: Codable, Identifiable {
    var printerName: String
    var scaleX: Double   // 補正倍率 (default: 1.0)
    var scaleY: Double
}
```

#### 永続化

- **保存先**: `~/Library/Application Support/LCCAD/printer_calibrations.json`
- **ストア**: `PrinterCalibrationStore` (シングルトン、`@MainActor`、`ObservableObject`)
- **プリンター識別**: `NSPrintOperation.current?.printInfo.printer.name` でマッチング

#### テストページの精度配慮

- ストローク幅 (0.75pt) を考慮し、パス矩形からストローク幅を差し引いて外辺間距離が正確に 150mm になるよう調整
- キャリブレーション済みプリンターではテストページにも補正を適用（検証用）
- キャリブレーション状態をテストページに表示

#### 設定画面

- Settings > Printer Calibration タブ
- プリンタープルダウン（`NSPrinter.printerNames` から選択）
- Grid レイアウトで実測値入力 + 補正倍率表示
- `.sheet(item:)` で毎回正しい値が渡されるよう管理

## 座標系

- **内部座標**: ミリメートル (mm)、原点は左上、Y 軸下方向正
- **表示座標**: mm をスクリーンピクセルに変換（ズーム倍率 × DPI）
- **変換**: `worldToScreen` / `screenToWorld` 関数で相互変換

```swift
struct CanvasTransform {
    var offset: CGPoint    // パン位置（スクリーンピクセル）
    var scale: CGFloat     // ズーム倍率（pixels per mm、デフォルト 3.0）

    func worldToScreen(_ point: CGPoint) -> CGPoint
    func screenToWorld(_ point: CGPoint) -> CGPoint

    var zoomPercentage: Int  // scale / 3.0 * 100
}
```

## ファイル形式 (.lccad)

JSON ベースの独自形式。将来の拡張性を考慮。

```json
{
  "version": "1.0",
  "settings": {
    "unit": "mm",
    "gridSpacing": 10.0,
    "gridMajorInterval": 5
  },
  "prickingIrons": [...],
  "layers": [
    {
      "id": "uuid",
      "name": "Front Panel",
      "visible": true,
      "shapes": [...]
    }
  ],
  "templates": [...],
  "tracingImages": [...]
}
```

## ビルドパイプライン

```bash
# 1. プロジェクト生成
xcodegen generate

# 2. ビルド
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD -configuration Debug build

# 3. テスト
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD test

# 4. アーカイブ (リリース)
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD -configuration Release \
  -archivePath build/LCCAD.xcarchive archive
```

## 依存ライブラリ

初期段階では外部依存なし。Apple 標準フレームワークを最大限活用する方針。
