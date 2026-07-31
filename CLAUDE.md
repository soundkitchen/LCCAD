# LCCAD - レザークラフト CAD for macOS

## Project Overview

macOS ネイティブのレザークラフト専用 CAD アプリケーション。
既存の参考アプリの機能をベースに、
macOS に最適化した高速・安定なアプリケーションを目指す。

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI + AppKit (必要に応じて)
- **Graphics**: Core Graphics / Metal (レンダリング高速化)
- **Project Management**: XcodeGen (`project.yml` → `.xcodeproj` 生成)
- **Build**: `xcodebuild`
- **Minimum Target**: macOS 14.0 (Sonoma)

## Project Structure

```
LCCAD/
├── CLAUDE.md              # このファイル（AGENTS.md は CLAUDE.md へのシンボリックリンク）
├── docs/                  # ドキュメント
│   ├── research.md        # 参考アプリ リサーチ結果
│   ├── design.md          # UI デザイン方針
│   └── architecture.md    # 技術アーキテクチャ
├── design/
│   └── lccad.pen          # Pen デザインファイル
├── project.yml            # XcodeGen 設定
├── Sources/
│   └── LCCAD/
│       ├── App/           # アプリエントリポイント
│       ├── Models/        # データモデル
│       ├── Views/         # SwiftUI ビュー
│       ├── ViewModels/    # ViewModel 層
│       ├── Canvas/        # キャンバス描画エンジン
│       ├── Tools/         # 描画ツール群
│       ├── Stitch/        # ステッチ関連ロジック
│       ├── Export/        # SVG/DXF エクスポート
│       └── Resources/     # アセット・ローカライズ
├── Tests/
│   └── LCCADTests/
└── Packages/              # SPM ローカルパッケージ (必要に応じて)
```

## Development Commands

```bash
# XcodeGen でプロジェクト生成
xcodegen generate

# ビルド
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD -configuration Debug build

# テスト
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD test

# リリースビルド
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD -configuration Release build

# Makefile ショートカット（make help で一覧）
make run       # Debug ビルドして起動
make test      # xcodegen + テスト
make install   # Release ビルドして /Applications/LCCAD.app を入れ替え
make design    # Pen でデザインファイルを開く
make xcode     # Xcode でプロジェクトを開く
```

## Conventions

- SwiftUI を優先し、AppKit は SwiftUI でカバーできない箇所のみ使用
- キャンバス描画は `Canvas` ビュー (SwiftUI) または `NSView` + Core Graphics
- 座標系は左上原点、Y 軸下方向正（macOS 標準の flipped coordinate）
- 単位系は内部的にミリメートル (mm)、表示時に mm/inch 切替
- ファイル形式は独自フォーマット (.lccad)、JSON ベース（prettified）
- メニューバーは macOS システムメニューバーを使用（ウィンドウ内には配置しない）
- Light / Dark モード両対応
- ストローク幅は 0.1mm 固定（`StrokeStyle.fixedWidth`）。印刷キャリブレーションを安定させるためユーザーは変更不可。古いファイルの幅は読込時に 0.1mm へ正規化される
- 破線パターンは mm 単位で `LineStyle.dashPattern` に一元定義（dashed [0.6, 0.4] / dotted [0.2, 0.35] / dashDot [1, 0.4, 0.2, 0.4]）

## Workflow Rules

- **UI 変更は必ず Pen（旧 Pencil）デザインファイル (`design/lccad.pen`) の更新から始める。** デザインを先に更新し、スクリーンショットで確認した上でコードに反映する。コードだけ先に変えてデザインファイルと乖離させてはならない。
- **Pen デザインファイルの保存**: Pen MCP（MCP サーバー名は `pencil` のまま）でのデザイン作業が完了したら、必ずユーザーに保存を依頼する（Pen MCP はエディタ内メモリ上で変更を保持しており、自動保存されない）。デザインファイルは `design/lccad.pen` で一元管理。Pen エディタでもこのパスを直接開く。
- **デザイントークンの管理**: Pen デザインファイルの変数定義が信頼できる唯一の情報源 (Single Source of Truth)。コード側は `DesignTokens.swift` に転写して使用する。色を変更する場合は必ずデザイン変数を先に更新する。
- **Worktree ブランチのマージ禁止**: worktree で並行作業した場合、ブランチ上で必ずコミットし、main へのマージはユーザーの明示的な許可を得てから行う。worktree のファイルを main に直接コピーしてはならない。作業完了後はブランチ名と変更サマリーを報告し、ユーザーのレビューを待つ。
- **アイコンの対応**: デザインファイルは lucide アイコン、コードは SF Symbols を使用。以下の対応表を維持すること:

| ツール | Pen (lucide) | Code (SF Symbols) |
|--------|----------------|-------------------|
| Select | mouse-pointer | cursorarrow |
| Line | minus | minus |
| Rect | square | square |
| Circle | circle | circle |
| Arc | radius | circle.and.line.horizontal |
| Bezier | spline | point.topleft.down.to.point.bottomright.curvepath |
| Text | type | character |
| Bevel | squircle | app |
| Box Stitch | target | circle.circle |

## Key Design Decisions

- メニューは macOS ネイティブのシステムメニューバーを使う
- ツールバーはウィンドウ上部（タイトルバー直下）に配置
- 3 カラムレイアウト: 左パネル (Layers/Templates) / キャンバス / 右パネル (Properties)
- ステッチ関連のツール・プロパティは暖色系 (#D4A574) でアクセントを付ける
- 起動時にファイル選択ダイアログは出さず、即座に新規キャンバスを表示する（WindowGroup ベース）
- ファイル操作 (Save/Open) はメニューから手動で行う

## Drawing Tool UX

各描画ツールの操作体系:

| ツール | 操作方法 | プレビュー |
|--------|---------|-----------|
| **Line** | クリック2点 or ドラッグ | 始点ドット + ダッシュ線 + 長さラベル |
| **Rectangle** | ドラッグ | ダッシュ枠 + 半透明塗り + サイズラベル |
| **Ellipse** | ドラッグ | ダッシュ楕円 + 中心クロスヘア + サイズラベル |
| **Arc** | 3クリック（始点 → 終点 → 膨らみ方向） | 2点目まではダッシュ線 + 長さラベル（弦長）、3点目でダッシュ弧 + 半径ラベル。3点目の位置で弧の方向が変わる |
| **Bezier** | クリックで制御点を追加、Enter/Escape で確定 | 確定セグメント実線 + 次セグメントダッシュ + 制御点ドット |
| **Text** | クリックで配置 | — |
| **寸法線** | 3クリック（始点 → 終点 → ラベル位置） | 2点目まではダッシュ線 + 長さラベル、3点目で寸法線プレビュー + 測定値ラベル |

- **寸法値ラベルの配置は JIS 製図流**: 寸法線に沿って回転し、読み姿勢での上側（横線=線の上、縦線=90°回転して線の左）に「文字高の半分 + 隙間（`labelGap` = 0.8mm）」だけ離して置く。配置ジオメトリは `DimensionLineShape`（`labelDirection` / `labelUpNormal` / `labelRotation` / `labelCenter`）に一元定義し、キャンバス・プレビュー・SVG・DXF・印刷の全描画がこれを参照する。ただしキャンバス・プレビューはフォントを画面上でクランプ（9〜40px）するため、隙間も `labelGap` 比で描画フォントサイズから画面座標で算出する。ラベル矩形（回転考慮）はヒットテスト対象で、数値クリックでも寸法線を選択できる

共通: Escape でキャンセル、スナップは描画ツール全般で有効（**選択ツールのクリックはスナップしない** — 図形のグリッド外の部分も狙ってクリックできるようにするため）

## Selection / Edit UX

- **クリック選択**: スナップ無効。クリック位置をそのままヒットテスト（tolerance 5px screen distance）
- **Shift+クリック**: 選択に追加 / 解除トグル
- **空白ドラッグ**: マーキー（矩形範囲）選択
- **選択図形上のドラッグ**: 一括移動。スナップは **選択範囲の外接矩形の4角＋中心の5点** をリファレンスに評価し、最もスナップ補正量が小さい点を採用する（カーソル位置ではなく図形側がグリッド/端点/中点/中心/交点に乗る）。移動中の図形自身はスナップ候補から除外
- **ベジェ単一選択時**: アンカー（青四角）/ ハンドル（青丸）が表示され、それぞれをドラッグで編集可能（ハンドルが曲線輪郭から離れた位置にあっても掴める）
- **ベジェハンドル shift ドラッグ**: 対称ハンドルのピン留めを解除して片側だけ動かす

## Canvas Behavior

- **グリッド**: ズームレベルに応じて粒度が自動切替（0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100mm...）
- **スナップ**: 表示中のグリッド粒度に連動。端点・中点・1/4分割点・中心・交点にもスナップ
- **ズーム**: マウスホイール（カーソル位置中心） or ステータスバー +/- ボタン
- **パン**: マウス中ボタンドラッグ
- **スナップ表示**: 端点=ダイヤモンド、中点=三角、中心=クロスヘア、交点=X（すべて緑色）
