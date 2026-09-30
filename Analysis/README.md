# PSD解析用補助ツール

AIArtToPSDのアプリ実装とは独立した調査用コード。元PSD・既存リーダーは読み取り専用で参照する。2026-09-30の第三段階の再実行用。

## 実行

プロジェクト直下からPython 3.11以降で実行する。使用した環境はCodex付属Python、画像の独立照合には同環境のPillowを使用。追加インストールなし。

```powershell
$analysisPython = 'C:\Users\vramw\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& $analysisPython Analysis\inspect_psd.py 'D:\aviutl110\PSD_Data' 'D:\DelphiProg\test\AIArtToPSD\Analysis\results'
& $analysisPython Analysis\summarize_psd.py
```

inspect_psd.pyは標準ライブラリのみでも解析可能。Pillowがあれば検査用合成画像PNGを作る。summarize_psd.pyはPillowが必要。
出力先のsamples.json、summary.json、ファイル別一覧、検査用PNGは再実行で更新される。PSD_Dataには書き込まない。

## 対応・検査範囲

PSD版1の構造のみ。PSBは明示的に対象外。全ファイルのSHA-256、ヘッダー、領域、レイヤーextra、名前・lsct/lsdk・各タグ、チャンネル、マスク矩形、リソース、外側タグ、合成画像を記録する。
ファイル単位の例外を記録して次へ進むため、終了コード0だけで全件成功とは判断しない。samples.jsonのstatus/error/warningsを必ず確認する。

RGB8bit・5MB以下・16MP以下の28件はレイヤーRaw/RLE画像を展開。大きいPSDはRawの期待長とRLE行長表の合計を検査し、画素の全展開はしない。合成画像はRLE表と終端を検査。小さい7件はPillowとの全画素照合を行う。
ZIP展開の補助分岐はあるが今回実サンプルなし。ID-3、非8bitの予測復元、複雑なマスク属性、ICC変換、ブレンド・クリッピング・グループの再合成は検証対象外。完全な汎用PSDリーダーではない。
4チャンネルのPNGプレビューでは第4平面を暫定的にαとして扱う。追加チャンネルの意味の決定や色再現性の確認には用いない。

## 記録

- results/samples.json：ファイル別詳細とハッシュ。
- results/summary.json：全体の集計、重複グループ、Pillow独立照合、末尾警告の追加確認。
- results/PSD解析_ファイル別一覧.md：全ファイル一覧と小さいサンプルのレコード順。
- results/previews/：ハッシュ先頭16文字の名前で保存した検査用画像。

非PSDのAppleDoubleファイル1件は除外。合成画像後に非ゼロの余剰データがあるPSD1件は警告を残す。詳細と未解決事項はプロジェクト直下のPSD解析_構造とサンプル.mdを参照する。
