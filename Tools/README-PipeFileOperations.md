# パイプによる PSD 読込と明示的上書き保存

2026-10-24。本体 `AIArtToPSD.dpr` / `AIArtToPSD.dproj` の追加仕様。ユーザーが修正版をビルド・起動し、PID 8368で13PSDの読込・同一パス明示上書き・再読込・内容照合を実機確認した。GUIによる代替操作、こちらでのビルド・起動は行っていない。

実行記録は `PSD\Performance_20261024_98d7e6\制作記録\再保存_20261024_5d8e3b\pipe-resave-summary.json`、拒否・再送検査は同じ場所の `pipe-guard-verification.json`。レイヤーRGBA・キャンバス・座標・階層・名前・表示・重ね順・初期合成が全13件一致し、修正されたフォルダー用RGBAチャンネルも検証した。既存のバックアップZIPはCRC・元バイト一致を再確認した。

既存の同じ名前付きパイプ、schemaVersion=1、UIスレッドのディスパッチを使う。`client` 省略は従来どおり Codex、明示 `codex` / `dot` の両方で以下を受け付ける。ポート、常駐プロセス、ACL変更は追加しない。

## ビルド後の確認

ユーザーがメインプロジェクト `V:\DelphiProg\AIArtToPSD\AIArtToPSD.dpr` を再ビルドして起動した後、PC実行タスクから現在のPIDを取得する。通常起動アプリへの接続は、これまでと同じ正式承認付き実行経路を使用する。

```powershell
Get-Process AIArtToPSD | Select-Object Id,Path,StartTime
.\Tools\Invoke-ArtRoute.ps1 -ProcessId 12345 -InputJson '{"command":"status","args":{},"requestId":"fileops-status"}'
```

`data.fileOperationsVersion=1` と `data.commands` 内の `open` を確認する。旧PIDを再利用しない。複数アプリがあれば対象パスと文書を特定する。未保存文書がある場合は読込を中止する。アプリのダイアログやレイヤー名の編集中も open/save は拒否する。

## open

現在の `status` に文書がなければ `documentId:""`, `ifRevision:"0"`。文書があれば現在のIDとrevisionを指定する。未保存文書の暗黙破棄は行わない。PSD解析または最初の描画が失敗した場合は元文書を保持する。

```json
{"command":"open","requestId":"resave-violin-open-001","args":{"fileName":"V:\\DelphiProg\\AIArtToPSD\\PSD\\Performance_20261024_98d7e6\\violin\\violin_performance_candidate.psd","documentId":"","ifRevision":"0","includePixelHashes":true,"limit":64}}
```

`Invoke-ArtRoute.ps1 -ProcessId <現在PID> -InputFile <上記JSONファイル>` で送る。出力例（識別子・ハッシュは説明用）:

```json
{"schemaVersion":1,"ok":true,"requestId":"dot:resave-violin-open-001","client":"dot","data":{"documentId":"<新文書ID>","revision":"<新revision>","fileName":"V:\\...\\violin_performance_candidate.psd","modified":false,"width":1024,"height":1536,"fileSha256":"<実際に読込んだPSDバイトの64桁SHA256>","layers":[],"hasMore":false}}
```

実応答には既存 `document` と同じレイヤー情報が入る。`layers:[]` はここでは省略例。64ノードを超える場合は `document` の offset/limit で全ページを取得する。`fileSha256` は応答作成時のディスク再読込ではなく、文書が読み込んだ元バイトをハッシュする。

## save

従来の save は引き続き新規ファイル専用。`overwrite` 省略または false なら既存ファイルを拒否する。上書きする場合は **真偽値** `overwrite:true` と **文字列** `expectedFileSha256` を指定する。

```json
{"command":"save","requestId":"resave-violin-save-001","args":{"fileName":"V:\\DelphiProg\\AIArtToPSD\\PSD\\Performance_20261024_98d7e6\\violin\\violin_performance_candidate.psd","documentId":"<open応答の文書ID>","ifRevision":"<open応答のrevision>","overwrite":true,"expectedFileSha256":"<open応答のfileSha256>","includePixelHashes":true,"limit":64}}
```

上書き先は現在開いているPSDと同じ絶対パスに限定する。文書ID/revision、元PSDバイトSHA256、ディスク上PSD SHA256の一致を検査する。読込後に他者がファイルを変更した場合は再確認する。旧SHAを指定して繰り返し上書きできない。

既存の本体保存処理（変更なし保存、プロパティ保存、必要時の画像構成保存）で同じディレクトリに一意の一時PSDを書き、再読込による寸法検証と FlushFileBuffers 後に ReplaceFile で置換する。元ファイルを削除してから保存する方式へはフォールバックしない。新規保存は既存ファイルを置換しない MoveFileEx を使う。一時ファイルは CREATE_NEW で自分が作成したものだけを失敗時に掃除する。

元ファイルはハッシュ検査と一時保存中は deny-write で開くが、Windowsの置換直前にハンドルを解放する必要がある。別プロセスとの完全なハッシュ比較・置換の単一操作を保証するものではない。複数ツールから同じPSDを同時編集しないこと。

成功すると本体が保存先を再読込し、新しい文書ID/revision、`modified:false`、保存済み元バイトの `fileSha256` を返す。次の操作はこの応答のIDを使用する。

## エラーと再送

- `command_failed`: 検査・解析・保存等の失敗。応答内容と現在の status/document、ファイル状態を確認する。
- `command_committed`: 文書切替または保存先への公開が済んだ後の失敗。再読込・履歴更新・応答構築等の失敗が該当する。保存先と現在文書を読み取りで確認し、盲目的に別IDで再試行しない。
- 成功応答と、上記の実行済み失敗応答は、呼出元＋requestId単位で直近64件を本体メモリに保持する。同一内容の再送は同じ結果を返し、open/saveを再実行しない。同じIDの違う内容は拒否する。アプリ終了後や保持窓を超えた要求の永続的な重複排除ではない。
- timeout は「未実行」を意味しない。まず status/document とファイルを確認し、保持窓内なら同じID・同じJSONで結果を回収する。

## 今回の13PSD再保存の再開

楽器フォルダには追加ログを作らず、既存の制作記録 `PSD\Performance_20261024_98d7e6\制作記録\再保存_20261024_5d8e3b` を使う。`manifest.json` の13パスとSHAを使用し、他の素材・ZIPは処理しない。

1. バックアップ `PSD13_上書き前_20261024T014242Z.zip` は13ファイルのCRCと元バイト一致を検証済み。再開前に現在ファイルのSHAをmanifestと照合し、変化があればユーザー編集として停止する。
2. PIDと追加機能を確認し、modified=falseを確認。各PSDを open し、document全ページ・レイヤーRGBAハッシュ・previewを採取する。開いた元バイトSHAはバックアップのSHAと照合する。
3. 同一パスへ上記明示saveを1回実行。応答で保存後の文書IDを取得する。異常時は残りへの上書きを止める。
4. 明示openで再読込し、キャンバス・座標・階層・名前・表示・重ね順・元RGBA・初期合成を保存前と比較する。バイト全体SHAは保存形式修正で変わり得る。
5. 制作記録内の `inspect_resave.py check <instrument>` は既存の独立PSD指紋との照合用。`observe.ps1` には旧PIDが入っているため、そのまま再利用しない。ビルド後のPIDを使ってパイプのみで実施する。

GUI中止時点の上書きは0件。その後、ユーザーが修正版を起動し、**パイプだけで13/13件を上書き・再読込・検証完了**。GUIのファイル選択欄入力は失敗しており、GUIによる読込・上書きは実行されていない。最終状態はアコーディオンPSDを開き modified=false。

## 検査ソース

`Tests/ClientProtocolSmoke.dpr` に open 再送と実行済みエラーの再送抑止を追加。`Tests/PipeFileOperationsSmoke.dpr` は新規専用、明示上書き、ハッシュ不一致、別パス、外部変更、ロック、旧ベースライン再送、RGBA保持、一時ファイル掃除を一時生成データだけで検査する。実行先は存在しない新規ディレクトリ必須。

補助のDelphiテスト2本は今回コンパイル・実行していない。通常起動した本体では上記13PSD保存、従来Codexのclient省略status、dot status、保存成功要求の同一ID再送、既定上書き拒否、不一致SHA拒否、古いrevisionのopen拒否、同じIDの内容変更拒否を確認済み。再送でファイル時刻・バイト・現在文書が変わらないことも確認した。故障注入（保存後の再読込失敗、置換中のOS障害）と未保存文書を実際に作る検査は行っていない。
