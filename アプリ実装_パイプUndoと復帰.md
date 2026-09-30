# 工程14：外部パイプ・Undo／Redo・処理状態・再開

更新日：2026-09-30。基本機能を完了。

## 操作

「編集 → 元に戻す」（Ctrl+Z）と「やり直す」（Ctrl+Y）を追加。名前・表示・不透明度、排他パーツ切替、PNG追加・置換・配置、グループ追加、AI結果取込を対象とする。AI結果の全命令は1操作として戻す。

16操作分をメモリに保持し、選択レイヤーと未保存状態も戻す。画像配列は変更時に置き換える方式で、変更しない画素と元PSDのアーカイブは履歴間で共有する。新しい編集はRedoを破棄する。失敗した編集や値を変えない操作は履歴を確定しない。

新規文書・PSD読込・保存成功後の内部再読込・文書を閉じる・ジョブ再開は履歴の境界とし、保存をまたいだUndoは行わない。Undo／Redo時は文書の版を進め、古いAIジョブを失効させる。

AI状態欄は生成待ち・生成中・取込待ち・失敗・中止・取込完了を表示。「AI処理を中止」は以後の結果取込を止め、cancelledマーカーを保存する。外部生成処理の終了はワーカーが状態を確認して行う。取込・書出し中は状態表示と待機カーソルを出すが、同期的な画像／PSD処理の途中停止には対応しない。

## 再起動・中断からの再開

工程14以降の書出しでは、ジョブへsnapshot.psd（書出し時点の文書）、recovery.json（PSDと要求のSHA-256）、connection.json（現在のパイプ接続先）を追加する。全ファイル完成後にrequest.jsonを公開する。スナップショット保存が未対応・失敗の場合はジョブを成立させない。

「ファイル → AIジョブを再開...」でジョブのrecovery.jsonを選ぶ。ハッシュ、キャンバス、階層・名前・表示・不透明度・座標を検証し、要求のレイヤーID・文書ID・版・指示を復元する。connection.jsonを現在の接続先へ更新する。result.jsonがあれば取込待ちとして再開し、改めて結果を取り込める。復元文書は未保存の新規文書として扱い、保存先を選ぶ。

復帰地点はジョブを書き出した時点。以後の手動編集やUndo履歴を自動保存する機能ではない。取込済みで未保存の結果は、書出し時点へ戻してから結果を再適用する。保存済みPSDを使う場合は通常の「開く」を使う。工程13以前のスナップショットを持たないジョブは再開できない。

中止マーカーを持つジョブは再開しても取込を拒否する。改変・欠損した要求やPSDの再開失敗では、現在の文書を保持し処理状態を解除する。

## 外部パイプ

既存のSource/Lib/Pipe/PipeServerTThread.pasを無変更で再利用。メッセージ型・UTF-8の双方向通信。独自の長さプレフィックスは追加しない。ArtPipeBridgeは専用通知ウィンドウでメインスレッドへ処理を渡す。派生スレッドで初期化完了まで実行を待たせ、終了時は同期I/Oと通知待ちを解除してから既存部品を解放する。

起動ごとに固有のパイプ名を使う。接続情報を%LOCALAPPDATA%\AIArtToPSD\pipesへ保存し、通常終了時に削除する。ジョブ内のconnection.jsonにも接続先を書く。外部ワーカーは再接続時にconnection.jsonを読み直す。異常終了で残った接続情報は、プロセスと接続可否で失効を確認する。

1メッセージはUTF-8で最大60,000バイト（文字数30,000以下）。要求は以下のJSON形式。

```json
{"schemaVersion":1,"requestId":"呼出しごとのID","command":"status","args":{}}
```

応答はschemaVersion、requestId、okを持ち、成功時はdata、失敗時はerror.code／error.messageを返す。重複キー・不正な型・未知命令はエラーとして返し、サーバーは次の接続を受け付ける。

| command | args | 動作 |
| --- | --- | --- |
| status | {}、またはjobId | 文書ID／版、編集・未保存・Undo状態、ジョブ状態・進捗・staleを取得 |
| export | prompt | ジョブを作成し、jobId・directoryを返す |
| progress | jobId、state、progress、message | running／ready／failedを通知。progressは0～100、messageは1,000文字以内 |
| import | jobId | 発行済みジョブのresult.jsonを検証・取込。完了後に成功応答 |
| cancel | jobId | 結果取込を中止 |
| undo／redo | {} | 編集履歴を戻す／進める |
| recover | directory | スナップショットから再開。現在の文書が未保存なら拒否 |

requestIdは応答との照合用。取込の二重適用防止はjobIdと結果ハッシュで行う。タイムアウト後はstatusで完了状態を確認し、同じ結果を再送する。exportを無条件に再送すると別ジョブが作られる。

PowerShell 7用のTools/Send-ArtCommand.ps1を用意。

```powershell
# ジョブの接続先を取得（再開後は読み直す）
$connection = Get-Content -Raw 'ジョブフォルダー\connection.json' | ConvertFrom-Json
& .\Tools\Send-ArtCommand.ps1 -PipeName $connection.pipeName -Command status
$arguments = @{ jobId = $connection.jobId } | ConvertTo-Json -Compress
& .\Tools\Send-ArtCommand.ps1 -PipeName $connection.pipeName -Command import -ArgsJson $arguments
```

クラウドAPIは呼び出さない。生成用PNGと結果JSONの形式は[工程13](アプリ実装_AI画像指示交換.md)を参照。

## 検証

- アプリ：Win64 Debug／Release Rebuild成功、警告0・エラー0。直下のAIArtToPSD.exeはRelease版。
- Stage14Smoke：両構成110項目合格。実パイプの状態・書出し・進捗・失敗・中止・取込・重複拒否、Undo／Redo・16操作上限・分岐・選択・未保存状態、別プロセスでの再開・取込・PSD保存、指示／ID／階層復元、不正要求／スナップショットの拒否、中止の永続化。接続待ち・受信待ち・応答未読の待ち状態で終了する試験も合格。
- 実PSDコピーの再開試験：両構成7項目合格。元の描画・ID・階層を復元し、Undo／Redoと再保存を確認。verify_stage14_real.pyは両構成各306項目合格（元画像・PSDレイヤーID・付加情報・リソースと独立合成の照合）。
- PowerShell送信スクリプト：別アプリプロセスへstatus／export／cancelを送り成功応答を確認。通常終了も確認。
- ExchangeSmoke 65項目、ExchangeUiSmoke 23項目、UiSmoke 181項目を両構成で確認。既存UI試験はリポジトリ内の保存済みPSDコピーを利用。
- verify_stage14.py：両構成の復帰後PSD2件について各18項目合格。psd-toolsで階層・レイヤー名・RGBA・合成画素を独立照合。
- 外部回帰照合：工程13 34項目、工程12 536項目、工程11 545項目、実PSD属性690項目合格。画面画像stage14_ui.bmpで操作欄の配置を確認。

旧PSD原本との再照合、実マスクPSDが必要なPsdRoundTrip全実行、実AIワーカー・実ホスト、高DPI・長時間・大規模文書の実操作は未確認。

次は工程9の未対応合成を進め、工程12の特殊表示と工程15の実ホスト確認へつなげる。ダイアログ配色の保留は維持する。
