# 工程13：AI画像・指示交換

更新日：2026-09-30。ファイル交換の基本機能を完了。外部AIにフォルダーを渡し、生成結果をまとめて文書へ取り込める。クラウドAPIの直接呼出しは未実装。

## 操作

1. PNG新規文書または編集対応PSDを開く。
2. 下部のAI指示欄に希望を書き、「AI向けに書き出す」を押す。
3. 表示されたExchange内のジョブフォルダーをCodexへ渡す。request.json、preview.png、inputのレイヤーPNG、instructions.txtが含まれる。
4. 外部で生成したPNGをimagesへ置き、instructions.txtに従ってresult.jsonを作る。PNGを先に完成させ、result.json.tmpからresult.jsonへ名前変更して結果を確定する。
5. 「生成結果を取り込む」でそのジョブのresult.jsonを選ぶ。全操作を検証し、成功した場合だけ文書・プレビューを更新する。
6. PSD保存で変更を確定する。保存後も新しいジョブを書き出し、追加生成・取込を続けられる。

取込成功や同一結果の再送後もジョブのフォルダー表示を保持する。新規作成・PSD読込・保存後の内部再読込・閉じるでは古いジョブを破棄し、表示をリセットする。指示欄は次の制作にも使えるよう保持する。

## 交換形式

schemaVersionは数値1。requestId、jobId、documentId、ifRevisionを要求からそのままコピーする。ifRevisionは文字列。layersは上側レイヤーから並び、各レイヤーをlayerIdで参照する。座標はキャンバス基準、boundsはleft/top/right/bottom。キャンバス寸法は変更しない。

assetsはassetId、相対path、sha256、width、height、pixelFormat（RGBA8）、colorSpace（sRGB）を持つPNG一覧。operationsは次の操作の配列。同じバッチで先に追加したIDを後続操作から参照できる。

| op | 項目（全て必須） |
| --- | --- |
| add_group | layerId、name、parentId、beforeLayerId、visible、opacity |
| add_layer | add_groupと同じ項目＋assetId、bounds |
| replace_layer | layerId、assetId、bounds |
| rename_layer | layerId、name |
| set_attributes | layerId、visible、opacity |
| select_part | layerId（*付き画像またはグループ） |

parentIdが空文字列ならルート、beforeLayerIdが空文字列なら同階層の末尾。opacityは0～255の整数。rename_layerのnameは修飾子を含む完全なPSD名なので、必要な*／!／反転指定を含める。replace_layerは既存の名前・不透明度・表示・親・マスクを保持し、配置差分に合わせてマスク矩形も移動する。

マスクは元文書に保持されるが、出力レイヤーPNGはマスク適用前の画像。要求のhasMaskと合成プレビューを参考にし、マスクの新規追加・削除は行わない。レイヤー削除・既存階層移動、キャンバス変更は交換命令の対象外。

## 保持・失敗・中断

入力を全て作成してからrequest.jsonを公開する。途中のrequest.json.tmpは未完成ジョブとして扱う。

元文書を複製して操作を適用し、描画成功後に取り込む。不正な操作・JSON、異なるジョブ／文書／版、画像形式・寸法・ハッシュ不一致、フォルダー外パス等を拒否する。失敗時は元文書・選択・未保存状態を維持する。同一結果の再取込は再適用せず、同じジョブで内容を変えた再送は拒否する。

通常の再起動・文書切替ではジョブ台帳を破棄する。工程14以降に書き出したジョブは「AIジョブを再開...」から復元できる。書き出し後に編集した場合も古い結果を拒否する。後続の工程14で、再起動復帰・Undo／Redo・パイプ接続・処理状態通知を実装した。詳細は[工程14](アプリ実装_パイプUndoと復帰.md)を参照。生成物フォルダーは自動削除しない。

## 検証

アプリ、ExchangeSmoke、ExchangeUiSmoke、UiSmokeのWin64 Debug／Release Rebuild成功（警告0・エラー0）。

- ExchangeSmoke：両構成65項目合格。全6操作、親と挿入順、PNG色・透明度、マスク保持・位置、不正ID／操作／画像／パス／ハッシュ、失敗バッチ、古い版、重複・改変再送、ジョブ破棄、PSD保存・再読込。
- ExchangeUiSmoke：両構成23項目合格。取込とプレビュー、選択、未保存状態、失敗復帰、ジョブパス保持／リセット、別文書拒否、保存後の再生成・取込。exchange_ui.bmpで画面配置を確認。
- verify_stage13.py：両構成の3 PSDについて各34項目合格。psd-tools／Pillowで階層・順序・名前・属性・PNG／PSD画素・透明度・マスク位置を独立照合。
- UiSmoke：両構成180項目合格。AI欄追加で画面外となった行を先に表示してからスライダーを操作するよう試験を修正した。
- 既存外部照合：Releaseの工程12 536項目、工程11 545項目、実PSD属性690項目合格。

旧PSD原本は現環境にない。UiSmokeにはリポジトリのTests/output/preserved_aiueo.psdとui_original_copy.psdを別フォルダーへコピーして使用した。旧原本と今回のコピーの再照合、実マスクPSDを必要とするPsdRoundTrip全実行、高DPIの手動操作、外部AIによる実画像生成、PSDTool実ホスト互換は今回未確認。

```powershell
# rsvars.batでDelphi環境を設定したシェルで、各dprojをWin64 Debug／Release Rebuildする。
& Tests/Win64/Debug/ExchangeSmoke.exe Tests/output/stage13_final_debug
& Tests/Win64/Release/ExchangeSmoke.exe Tests/output/stage13_final_release
& Tests/Win64/Debug/ExchangeUiSmoke.exe Tests/output/stage13_ui_debug
& Tests/Win64/Release/ExchangeUiSmoke.exe Tests/output/stage13_ui_release
# 独立照合にはPythonのPillowとpsd-toolsが必要。
# python Tests/verify_stage13.py Tests/output/stage13_final_release
```

Release実行ファイルはプロジェクト直下のAIArtToPSD.exe。工程14の基本機能は後続作業で完了。工程9の未対応合成、! 強制表示・反転連動、ダイアログ配色の保留は継続する。
