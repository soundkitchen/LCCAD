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
│   ├── AppCommands.swift        # macOS メニューバー定義
│   └── AppearanceMode.swift     # カラーモード (System/Light/Dark) 管理
│
├── Models/
│   ├── Document/
│   │   ├── LCCADDocument.swift  # ドキュメントモデル (Codable)
│   │   ├── Layer.swift          # レイヤー
│   │   └── ProjectSettings.swift
│   ├── Shapes/
│   │   ├── Shape.swift          # Shape プロトコル、AnyShape、StrokeStyle、CodableColor
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
│   └── Geometry/
│       ├── GeometryUtils.swift  # 2D 座標 (mm)、LengthUnit、CGPoint/CGRect 拡張
│       └── Intersection.swift   # 交点計算
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
│   │   ├── StrokeSection.swift    # ColorPicker + 線幅入力
│   │   ├── ArcSection.swift
│   │   ├── StitchSection.swift
│   │   └── TextSection.swift
│   ├── Shared/
│   │   ├── InputField.swift     # PropertySection, PropertyField, EditablePropertyField
│   │   └── DesignTokens.swift   # Pencil デザイン変数の Swift 転写
│   └── SettingsView.swift       # 設定画面（カラーモード切替）
│
├── ViewModels/
│   └── EditorViewModel.swift    # エディタ全体の状態管理
│
├── Canvas/
│   ├── CanvasView.swift         # キャンバス SwiftUI View + ジェスチャー
│   ├── CanvasRenderer.swift     # Core Graphics 描画ロジック
│   ├── CanvasTransform.swift    # パン/ズーム座標変換
│   ├── GridRenderer.swift       # 適応グリッド描画（1-2-5 系列、10 分割固定）
│   ├── SnapEngine.swift         # スナップ計算
│   ├── SnapOverlay.swift        # スナップインジケータ描画
│   ├── SelectionOverlay.swift   # 選択ハンドル描画
│   ├── DrawingPreviewRenderer.swift # 描画中プレビュー
│   └── ScrollZoomView.swift     # スクロールズーム
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
│   └── ExportCoordinator.swift
│
└── Resources/
    ├── Info.plist
    ├── Assets.xcassets/
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
| **位置編集** | `setSelectedShapePosition(x:y:)` | boundingBox.origin 基準で絶対座標移動（Undo 対応） |
| **ストローク編集** | `updateStroke(_:)` | 選択図形の stroke.color / stroke.width を更新（Undo 対応） |
| **テキスト編集** | `updateTextProperty(_:)` | TextShape のプロパティ更新（Undo 対応） |
| **描画** | `handleDrag(startLocation:currentLocation:phase:shiftHeld:)` | ドラッグ描画。shiftHeld で正方形/正円制約 |
| **ズーム** | `setZoomPercentage(_:)` | パーセント指定ズーム。キャンバス中心基準 |
| **ズーム** | `zoomToFit()` | 実際のキャンバスサイズに基づく Fit |

### キャンバス描画

```
CanvasView (SwiftUI Canvas + GeometryReader)
  ├── GridRenderer         # 適応グリッド背景（1-2-5 系列、10 分割）
  ├── CanvasRenderer       # 図形描画 (Layer 順)
  ├── StitchRenderer       # ステッチ穴描画
  ├── DrawingPreviewRenderer # ツール操作中のプレビュー
  ├── SnapOverlay          # スナップインジケータ
  └── SelectionOverlay     # 選択ハンドル / ベジエ制御点
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
