# LCCAD

macOS ネイティブのレザークラフト専用 CAD アプリケーションです。菱目打ちの自動配置、実寸印刷（プリンターキャリブレーション対応）、型紙向けの SVG / DXF エクスポートなど、レザークラフト工房での利用を想定した機能を揃えています。

## Status

開発中（現行バージョン `0.1.0`）。作者本人のマシンでの動作は確認済み、公開配布はまだ行っていません。

## 主な機能

- **描画ツール**: 直線、矩形、楕円、円弧（3 点指定）、ベジェ曲線、テキスト
- **編集ツール**: Offset（平行コピー）、Trim（交点でカット）、Bevel（角の丸め）
- **整列 / 分布**: 左右上下・中央揃え、水平・垂直分布
- **反転 / 反転コピー**: 選択範囲を縦軸・横軸で反転、または右隣・下隣にコピー反転（左右対称な型紙作成に便利）
- **グルーピング**: 複数図形のまとめ上げ・解除、ネスト可
- **レイヤー管理**: 表示/非表示、複数レイヤー
- **ステッチ穴の自動配置**: 菱目 / フレンチ / ラウンド / フラットなど目打ちタイプに対応。固定ピッチ・可変ピッチを選択可能。図形の移動・変形に追従
- **線種**: 実線 / 破線 / 点線 / 一点鎖線
- **ルーラー表示**: ズーム・パン連動、mm / inch 切替
- **ページレイアウト**: 任意のページ枠を配置し、プリンタ用紙サイズに合わせて印刷
- **実寸印刷**: プリンターごとの校正値（実測 150mm 正方形からの補正倍率）を保存して反映
- **エクスポート**: `.lccad`（独自 JSON）/ SVG / DXF

## 必要環境

- macOS 14.0 (Sonoma) 以降
- Xcode 15 以降（ビルド時）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## ビルド

```bash
# Xcode プロジェクト生成
xcodegen generate

# Debug ビルド
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD -configuration Debug build

# Release ビルド（署名は自分の Apple Developer Team に置き換えて下さい）
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD -configuration Release \
  -allowProvisioningUpdates build

# テスト
xcodebuild -project LCCAD.xcodeproj -scheme LCCAD test
```

Makefile ショートカットも利用できます（一覧は `make help`）:

```bash
make run       # Debug ビルドして起動
make test      # テスト実行
make install   # Release ビルドして /Applications/LCCAD.app を入れ替え
```

`project.yml` 内の `DEVELOPMENT_TEAM` は作者の Apple Developer Team ID を指しています。フォークしてビルドする場合は、ご自身の Team ID に書き換えてください。

## プロジェクト構成

```
LCCAD/
├── Sources/LCCAD/
│   ├── App/             # エントリポイント、コマンド、外観モード
│   ├── Canvas/          # キャンバス描画（Grid / Ruler / Snap / Page overlay）
│   ├── Export/          # .lccad, SVG, DXF, 印刷
│   ├── Models/          # 図形・ステッチ・ドキュメントモデル
│   ├── Stitch/          # ステッチ穴生成エンジン、パスウォーカー
│   ├── Tools/           # Offset, Trim, Bevel
│   ├── ViewModels/      # EditorViewModel
│   └── Views/           # SwiftUI ビュー（3 カラムレイアウト + シート）
├── Tests/LCCADTests/    # XCTest
├── docs/                # 技術ドキュメント
├── design/              # Pen デザインファイル（UI の単一情報源）
└── project.yml          # XcodeGen 設定
```

詳細は [`docs/architecture.md`](docs/architecture.md) と [`docs/design.md`](docs/design.md) を参照してください。

## ライセンス

MIT License — [LICENSE](LICENSE) 参照。

## 著者

Takanobu Izukawa
