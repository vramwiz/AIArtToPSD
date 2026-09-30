# PSD実装：最小読み書き

更新日：2026-09-30。第五段階として、設計書12節のCore・境界付きリーダー・最小Rawライターを実装した。

## 成果

- `Source/Core/ArtDocument.pas`：RGBA8の非乗算画素、上から下のレイヤー順、階層、名前、可視状態、不透明度、座標、内部ID。新規ドキュメントの検証と通常ブレンドの合成。
- `Source/Persistence/PSD/ArtPsd.pas`：独立したPSD読み書き。既存リーダーは参照のみで、コードはコピーしていない。
- `Tests/PsdRoundTrip.dpr`／`.dproj`：画面から独立したDelphiコンソール試験。
- `Tests/verify_output.py`：psd-toolsとPillowによる別実装での出力照合。
- アプリのdpr／dprojに新ユニットを登録。画面操作への組み込みはまだ行っていない。

## 読込範囲

PSDv1、RGB、8bit、Raw／PackBits RLE。レイヤー情報なし、単独レイヤー、入れ子グループ、Unicode名、負の座標、RGB＋透明チャンネルを扱う。境界付き読み込みで領域長・行展開長を確認し、破損時は現在のドキュメントを置き換えない。

原PSDのバイト列と未対応項目一覧を保持する。マスク、クリッピング、特殊ブレンド、未知タグ等は記録・保持されても描画対応済みとはしない。既存PSDの再保存は本段階では拒否する。未知情報を保持した再構築・編集は次工程。

上限はキャンバス各辺30,000、画素数1,600万、ファイル・主要展開バッファ合計512MiB、階層128。全処理のピークメモリ保証ではなく、初期版の入力制限である。大きい解析サンプル全件の読込対応は今回の完了条件に含めていない。PSB、ZIP、16／32bit、RGB以外は未対応。

## 新規書込範囲

通常画像レイヤー、画像の不透明度、可視状態、全不透明のpass-throughグループ、空グループ、Unicode名、負の座標。各画像はRGBA4チャンネルをRawで記録する。フォルダーの境界レコードと順序、`luni`、`lyid`、`lsct`を出力する。

合成画像はRGBを白背景に合成した値として記録し、別チャンネルに透明度を保存する。負のレイヤー数で最初の追加合成チャンネルが透明度であることを示す。これは外部ライブラリのPSD表現と照合した。透明領域のRGBも各レイヤーではそのまま保持する。

保存は同じフォルダーの一時ファイルに書込み、再読込による構造検査後に置換する。未対応描画や不正なツリーは保存前に拒否する。書込先に既存ファイルがある場合も、検証失敗で内容を変更しない。

## 検証結果

Delphi 37.0、Win64 Debug／Release：アプリ本体と確認用プロジェクトのRebuild成功。警告0、エラー0。

Delphi試験は両構成で82項目合格：生成2件の往復、構造・画素一致、日本語・絵文字、不透明度・非表示・負座標・空フォルダー、破損5種類で現在データ保持、未対応保存で保存先保持。

既存PSDは`layer_test.psd`、`sample.psd`、`sampleyh.psd`、`sampleyh63.psd`、`sampleyh63x255.psd`、`sample_alpha.psd`、`aiueo.psd`の7件で読込を確認。レイヤー数0／1／4／24、グループの復元等を検査した。第三段階の72件解析とは検証範囲が異なる。

psd-tools 1.21.0とPillowによる独立試験は51項目合格：生成2件の階層・名前・座標・属性・レイヤーRGBA全画素と、合成RGB／透明度全画素を照合。psd-toolsの列挙順は下から上なので、Coreの上から下の順に合わせて比較した。

結果・生成PSDは`Tests/output/`。Photoshop・PSDTool・AviUtlの実ホスト操作は未検証。`!`／`*`は名前として保存し、PSDTool固有の切替動作は今後の検証対象。

## 再実行

RAD Studio 37.0のrsvars.batを読み込んだ環境で実行：

```bat
msbuild Tests\PsdRoundTrip.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /v:minimal /nologo
Tests\Win64\Debug\PsdRoundTrip.exe D:\aviutl110\PSD_Data D:\DelphiProg\test\AIArtToPSD\Tests\output
msbuild Tests\PsdRoundTrip.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /v:minimal /nologo
Tests\Win64\Release\PsdRoundTrip.exe D:\aviutl110\PSD_Data D:\DelphiProg\test\AIArtToPSD\Tests\output
```

独立照合はPythonのPillow、numpy、psd-toolsが必要。アプリ本体にはPython依存を追加していない。今回はpsd-toolsとattrsを一時フォルダー`%TEMP%\AIArtToPSD_psd_verify`に配置し、付属PythonのPillow／numpyと利用した。

```powershell
$env:PYTHONPATH = Join-Path $env:TEMP 'AIArtToPSD_psd_verify'
& 'C:\Users\vramw\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' Tests\verify_output.py Tests\output
```

## 次の段階

1. 未対応情報の保持を維持した既存PSDの再保存を設計・実装する。変更なしの保存と編集後の再構築を分ける。
2. RLE書込を追加し、Raw書込との画素・属性一致を確認する。
3. マスク・クリッピング・特殊ブレンド等の扱いを確定し、対応できない編集は明示して止める。
4. その後、テンプレートのライブラリを利用した画面・PNG／JSON交換・パイプ連携へ進む。

初期版は未知情報を読み飛ばして編集可能と宣言しない。元サンプルPSDと参照リーダーは変更していない。
