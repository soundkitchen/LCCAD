# LCCAD UI デザイン方針

## デザインコンセプト

- **macOS ネイティブ**: システムメニューバー、タイトルバー（トラフィックライト）を活用
- **Figma インスパイア**: クリーンな3カラムレイアウト、ミニマルなツールバー
- **参考アプリの知見を継承**: ステッチ専用ツール、プロパティパネルの構成
- **Light / Dark モード両対応**: テーマ変数で一元管理

## デザインファイル

- `design/lccad.pen` — Pencil デザインファイル（Single Source of Truth）
  - `Main Editor - Light` — ライトモードのメインエディタ
  - `Main Editor - Dark` — ダークモードのメインエディタ
  - `Settings - Light` — ライトモードの設定画面（General タブ）
  - `Settings - Dark` — ダークモードの設定画面（General タブ）
  - `Settings - Calibration - Light` — ライトモードのキャリブレーション設定
  - `Settings - Calibration - Dark` — ダークモードのキャリブレーション設定
  - `Pricking Iron Sheet - Light` — ライトモードの目打ち管理シート
  - `Pricking Iron Sheet - Dark` — ダークモードの目打ち管理シート
  - `Page Properties - Light` — ライトモードのページレイアウト右パネル
  - `Page Properties - Dark` — ダークモードのページレイアウト右パネル

## レイアウト構成

```
┌─────────────────────────────────────────────────────┐
│ ● ● ●          Card Case.lccad                      │ Title Bar (38px)
├─────────────────────────────────────────────────────┤
│ [▶][─][□][○][⌒][~][T][↔]|[⊞][✂][▢]|[🗎]|[⊞][👁] ⟶ │ Toolbar (40px)
├────────┬────────────────────────────┬───────────────┤
│ Layers │                            │  Properties   │
│ Templa │        Canvas              │  Position     │
│────────│        (Grid)              │  Size         │
│ ● Fron │                            │  Stroke       │
│ ○ Back │     ┌──────────────┐       │  ─────────    │
│ ○ Card │     │  Pattern     │       │  Stitch       │
│ ○ Stit │     │              │       │  Settings     │
│        │     └──────────────┘       │               │
│        │                            │               │
│ (240px)│       (flexible)           │    (260px)    │
├────────┴────────────────────────────┴───────────────┤
│ X: 42.5  Y: 128.0         mm  ─ [100%] +  ⊞       │ Status Bar (28px)
└─────────────────────────────────────────────────────┘
```

## カラーシステム

テーマ変数による Light / Dark モード管理。
コード側は `DesignTokens.swift` に転写して使用する。

### カラーモード設定

| 値 | 動作 |
|----|------|
| `System` | OS のダークモード設定に追従（デフォルト） |
| `Light` | 常にライトモード |
| `Dark` | 常にダークモード |

設定は `@AppStorage("appearanceMode")` で永続化。`NSApp.appearance` で全ウィンドウに即時反映。

### 背景色

| 変数名 | Light | Dark | 用途 |
|--------|-------|------|------|
| `bg-app` | #F5F5F5 | #1E1E1E | アプリ全体背景 |
| `bg-panel` | #FFFFFF | #252526 | サイドパネル |
| `bg-toolbar` | #F8F8F8 | #2D2D2D | ツールバー、タイトルバー |
| `bg-canvas` | #F0F0F0 | #1E1E1E | キャンバス背景 |
| `bg-statusbar` | #E8E8E8 | #007ACC | ステータスバー |
| `bg-input` | #FFFFFF | #3C3C3C | 入力フィールド |
| `bg-tool-active` | #E0E0E0 | #404040 | アクティブツール |
| `bg-section` | #F0F0F0 | #2A2A2A | セクションヘッダー |

### テキスト・アイコン

| 変数名 | Light | Dark | 用途 |
|--------|-------|------|------|
| `text-primary` | #1A1A1A | #E0E0E0 | 主テキスト |
| `text-secondary` | #666666 | #999999 | 副テキスト |
| `text-muted` | #999999 | #666666 | 非アクティブテキスト |
| `icon-primary` | #444444 | #CCCCCC | 主アイコン |
| `icon-secondary` | #888888 | #777777 | 副アイコン |

### ボーダー

| 変数名 | Light | Dark | 用途 |
|--------|-------|------|------|
| `border` | #D9D9D9 | #3D3D3D | 主要ボーダー |
| `border-light` | #EBEBEB | #333333 | 軽いボーダー |

### アクセント・特殊色

| 変数名 | 値 | 用途 |
|--------|----|------|
| `accent` | #4A90D9 | アクセントカラー（青） |
| `accent-hover` | #3A7BC8 | ホバー時 |
| `stitch-color` | #D4A574 | ステッチ関連の暖色アクセント |
| `text-on-accent` | #FFFFFF | アクセント上のテキスト |

### グリッド

| 変数名 | Light | Dark | 用途 |
|--------|-------|------|------|
| `grid-line` | #B0B0B0 | #404040 | 補助グリッド (minor) |
| `grid-line-major` | #A8A8A8 | #444444 | 主要グリッド (major) |
| `pattern-stroke` | #333333 | #CCCCCC | パターン図形の線色 |

## ツールバー構成

左から順に:

1. **描画ツール**: 選択 (V), 直線 (L), 矩形 (R), 円 (E), 弧 (A), ベジエ (P), テキスト (T), 寸法線 (D)
2. *セパレータ*
3. **編集ツール**: オフセット, トリミング, 面取り
4. *セパレータ*
5. **レイアウトツール**: ページ
6. *セパレータ*
7. **ステッチツール**: 自動ステッチ, シミュレータ（暖色アイコン）
8. *スペーサー（右寄せ）*
9. **履歴**: Undo (⌘Z), Redo (⇧⌘Z)

各ツールボタンにはショートカットキー付きツールチップを表示。

## 左パネル

- **タブ切替**: Layers / Templates
- **レイヤーアクション**: 追加 / 削除 / 上下移動
- **レイヤーリスト**: 表示/非表示アイコン + レイヤー名
  - アクティブレイヤーは背景色で強調

## 右パネル (Properties)

セクション区切り付きの縦積みレイアウト。図形選択時に表示:

### 1. Position セクション
- **X / Y**: `EditablePropertyField` で直接入力可能
- 表示単位は `ProjectSettings.unit` に従う（内部値は mm）
- 入力確定時に `boundingBox.origin` との差分で図形全体を移動

### 2. Size セクション
- **W / H**: 表示のみ（将来的に編集対応予定）
- **Rotation / Lock**: 回転角度、アスペクト比固定

### 3. Stroke セクション（非テキスト図形）
- **ColorPicker**: 線色を直接変更（Undo 対応）
- **W（線幅）**: `EditablePropertyField` で mm 単位入力（範囲 0.01〜100）
- **Style（線種）**: ドロップダウンで線種を選択（プレビュー線 + スタイル名表示）
  - Solid（実線）、Dashed（破線 3-2mm）、Dotted（点線 0.5-1.5mm）、Dash-Dot（一点鎖線 3-1.5-0.5-1.5mm）
  - キャンバス描画はズーム連動、印刷・SVG・DXF エクスポートにも反映
- デザインに合わせ、カラースウォッチに `cornerRadius: 4` + border

### 3'. Text セクション（テキスト図形）
- Content, Font, Size, Style (Bold/Italic), Alignment, Color

### 4. Arc / Curve セクション（弧図形）
- Radius, Angle, Start/End

### 5. Stitch Settings セクション
- Iron Type（ドロップダウン）, Pitch

## ステータスバー

```
左: X: 42.5  Y: 128.0  (等幅フォント Geist Mono)
右: mm | [-] [100%] [+] | [⊞]
```

- **ズーム直接入力**: 100% 部分が `TextField` で、任意の倍率を入力可能
  - 入力ボックスは `bg-input` 背景 + `border` 枠 + フォーカス時に `accent` 枠
  - Enter / フォーカスアウトで確定、無効値は復元
  - `+` / `-` ボタン、Fit (⌘0) と共存
- **Zoom to Fit**: 実際のキャンバスサイズに基づく（固定サイズではない）

## 設定画面 (Settings)

macOS 標準の `Settings` シーン（⌘,）。TabView で 2 タブ構成:

### General タブ

```
┌──────────────────────────────────┐
│ Settings                         │
├──────────────────────────────────┤
│ [General] [Printer Calibration]  │
│                                  │
│ APPEARANCE                       │
│ Color Mode  [System][Light][Dark]│
│                                  │
└──────────────────────────────────┘
```

- セグメントピッカー（`Picker(.segmented)`）で 3 択
- 選択時に `NSApp.appearance` で即時反映
- `@AppStorage("appearanceMode")` で永続化

### Printer Calibration タブ

```
┌──────────────────────────────────────────┐
│ Settings                                  │
├──────────────────────────────────────────┤
│ [General] [Printer Calibration]           │
│                                           │
│ CALIBRATION                               │
│ テストページを印刷し、150mmの正方形を     │
│ 定規で測定してください。                  │
│ [🖨 テストページを印刷]                   │
│                                           │
│ PRINTER PROFILES                          │
│ ┌───────────────────────────────────────┐ │
│ │ EPSON EP-886A                         │ │
│ │ X: 1.0023  Y: 0.9981     2026/04/20  │ │
│ ├───────────────────────────────────────┤ │
│ │ Brother HL-L2375DW                    │ │
│ │ X: 0.9956  Y: 1.0012     2026/04/15  │ │
│ └───────────────────────────────────────┘ │
│ [+ キャリブレーション追加]    [Edit][削除] │
└──────────────────────────────────────────┘
```

- プリンターごとに補正倍率 (scaleX/scaleY) を管理
- プロファイルの追加・編集・削除
- プリンター名はシステム認識プリンターからプルダウン選択
- 実測値入力で補正倍率を自動計算（Grid レイアウト）

## 共通入力コンポーネント

### EditablePropertyField

Position / Zoom / Stroke 幅で共通利用する編集可能な数値入力フィールド:

| 項目 | 仕様 |
|------|------|
| **構成** | ラベル (10px semibold) + TextField (11px) + サフィックス (9px) |
| **確定** | Enter キーまたはフォーカスアウト |
| **無効値** | 数値パース失敗時は直前の値に巻き戻し |
| **範囲** | オプションの `ClosedRange<CGFloat>` でクランプ |
| **フォーカス表示** | 枠線が `accent` 色に変化 |
| **外部値同期** | 編集中でなければ外部の value 変更に追従 |
| **スタイル** | `bg-input` 背景、`border` 枠、`cornerRadius: 4`、高さ 28px |

### PropertyField（表示専用）

Size セクション等で使用する読み取り専用フィールド。`EditablePropertyField` と同じ見た目。

## フォント

- **UI**: Inter
- **等幅 (座標表示等)**: Geist Mono

## アイコン

- **デザインファイル**: Lucide Icons
- **コード**: SF Symbols（対応表は CLAUDE.md 参照）
- **サイズ**: 16x16 (ツールバー), 14x14 (パネル内), 12x12 (ステータスバー)
