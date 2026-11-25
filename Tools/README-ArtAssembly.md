# 新規キャンバスから複数差分を PSD に組み立てる API

2026-10-24追加: [パイプによるPSD読込と明示的上書き保存](README-PipeFileOperations.md)。`open` と `save overwrite:true / expectedFileSha256` はユーザーが再ビルド・起動した本体で13PSDの再保存と内容照合を完了。以下の新規保存の既定動作は維持する。

2026-10-23。メイン `AIArtToPSD.dpr` / `AIArtToPSD.dproj` 内の既存 unit へ実装。今回追加した組み立て機能は **未ビルド・未起動・実機未検証**。ビルドと起動はユーザーが行う。素材を今取り込む手順ではなく、ビルド後の受入・操作仕様。

更新：その後ユーザーがメインをビルド・起動し、バイオリン4PNGの新規文書→分割受信→一括登録→プレビュー→新規PSD保存・再読込を実機で確認した。[実試験記録](README-ViolinTrial.md)を参照。元RGBAと独立合成は完全一致。以下の未検証表記は実装時点の記録であり、この4PNG経路については実証済み。11画像ケース、再送キャッシュ、異常系全体、再起動復帰、長時間負荷の実機検証は別途必要。

## 通常起動との接続

承認付きの正式な通常ユーザー実行で、ユーザー起動の PID 6252 / `V:\DelphiProg\AIArtToPSD\AIArtToPSD.exe` に状態要求を送り、dot / Codex / 旧形式が成功した（2026-10-23 09:45:22 UTC）。要求IDは `dot:native-dot-check`、`codex:native-codex-check`、旧形式 `904a7d9c-d459-4b19-bab7-116e72194d52`。両クライアントの seen=true と受信履歴を確認した。これは **呼出元対応版の状態取得** の実測であり、この後追加した組み立て命令の実測ではない。

隔離側は同じユーザー SID でも低整合性、通常実行側は中整合性で、LOCALAPPDATA とプロセスの可視範囲が異なった。隔離側からのパイプ Connect はアクセス拒否、正式な通常ユーザー実行では成功。ACL は変更していない。実際の ACL 読取りの前にアプリが終了したため、パイプの実行時セキュリティ記述子は未取得。低整合性、AppContainer の制約、実際の ACL のどれが拒否の直接条件だったかは個別には断定していない。

本体は既存 CreateNamedPipe のセキュリティ属性 nil を維持する。nil は Windows の既定記述子を使う指定であり、無制限アクセスを付ける指定ではない。[Microsoft の名前付きパイプの説明](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights)を参照。Everyone / 特定 SID の追加許可、整合性ラベル変更、永続アクセス付与、外部ポート公開はしていない。

dot から通常起動アプリへ接続するには、その PC 実行タスクの **プラットフォームが承認した通常ユーザー実行経路**を使う。今回利用できたツール設定は sandbox_permissions=require_escalated。アプリ自身が隔離外実行を承認したり、ACL を緩めてこの境界を解消したりする実装ではない。レビュー拒否時に別プロセス、サービス等で迂回しない。

補助 CLI は隔離 LOCALAPPDATA と現在ユーザーの通常プロファイルの接続情報を探索し、生存プロセス照合を維持する。照合できない記述子だけの場合は、古い記述子または実行範囲の問題を明示して停止する。新本体の接続情報と status には実 EXE パス、status には processId も出す。AI 欄のヒントには実際の接続情報ファイルを表示する。

## 命令の棚卸し

| 必要な処理 | 利用する本体 API |
| --- | --- |
| 幅・高さ指定の新規文書 | **追加** new-document。最初は画像0枚の透明キャンバス。ダミーレイヤーなし |
| PNG 受領 | 既存 image-begin / image-chunk / image-status / image-commit / image-abort。バイト列の base64 分割受信 |
| グループ、レイヤー、階層、重ね順、座標、表示、不透明度 | 既存 export / import の add_group / add_layer / replace_layer / rename_layer / set_attributes / select_part を共用 |
| 複数差分の一括登録 | 既存 import の候補文書への一括適用。**追加** args.result に結果 JSON を渡せるため、PC 上で result.json を手書きしなくてよい |
| 状態・レイヤー一覧 | 既存 status / document。status に assemblyVersion=1 を追加 |
| 透明 PNG プレビュー取得 | **追加** preview / preview-read。PNG バイト列を分割取得し SHA256 照合可能 |
| 新規名 PSD 保存 | 既存 save。**強化** 一時名へ保存後、既存ファイルを置換しないアトミック確定 |
| 要求再送 | **追加** 成功した変更要求を直近64件、呼出元+requestId ごとに記憶。同じ構造の JSON は応答再送、違う内容は拒否 |

## PC 実行で呼ぶ方法

ユーザーが新本体をビルド・起動した後、正式な許可済み経路の PowerShell 7 で PID を取り直す。過去の6252を再利用しない。

```powershell
Get-Process AIArtToPSD | Select-Object Id,Path
.\Tools\Test-ArtClientStatus.ps1 -ProcessId 12345
.\Tools\Invoke-ArtRoute.ps1 -ProcessId 12345 -InputJson '{"command":"status","args":{},"requestId":"assembly-status"}'
```

status.data の assemblyVersion=1 と commands に new-document / preview / preview-read があることを確認する。以下は Invoke-ArtRoute に渡す入力 JSON の例。CLI は client=dot、schemaVersion=1 を付ける。識別子・ハッシュはその場の応答を使う。

## 新規作成と画像受信

文書未読込の場合：

```json
{"command":"new-document","requestId":"create-unique-id","args":{"width":1024,"height":1536,"documentId":"","ifRevision":"0"}}
```

既存文書が開いている場合は、確認した documentId / revision を指定する。未保存文書は必ず拒否し、破棄を自動代行しない。幅・高さは1～30,000、面積は既存16,000,000画素制限。成功応答は document と同じ ID / revision / サイズ / レイヤー情報。作成直後は modified=true、画像0枚。空キャンバスのまま PSD 保存する用途には対応せず、1枚以上登録してから保存する。

```json
{"command":"export","args":{"prompt":"原RGBAと1024x1536座標を維持して演奏差分を登録"}}
```

空キャンバスでも export できる。空の場合は recovery.json に emptyCanvas=true を記録し、ハッシュ済み request.json のキャンバスから復帰する。空の snapshot.psd やダミーレイヤーを生成しない。非空の既存 export は従来の snapshot.psd を維持。

PNG の受信例：

```json
{"command":"image-begin","args":{"jobId":"今回のjobId","transferId":"{今回の転送GUID}","fileName":"R1.png","sizeBytes":123456,"sha256":"実PNGファイルの64桁SHA256","width":1024,"height":1536}}
```

```json
{"command":"image-chunk","args":{"transferId":"{今回の転送GUID}","offset":0,"dataBase64":"PNGバイト列を最大12288バイトずつbase64化した値"}}
```

```json
{"command":"image-commit","args":{"transferId":"{今回の転送GUID}"}}
```

chunk は既存オフセット・同一内容再送検査を利用する。PNG の SHA256、ファイルサイズ、実寸法、デコードメモリ、alpha を扱う既存 RGBA 読込経路で検査する。1PNG32MiB、未完転送合計64MiB、同時16転送、アイドル15分を維持。既存のファイルは上書きしない。

PC 上の PNG がある場合は Send-ArtImage.ps1 -Client dot を使える。クラウド側にしかない PNG は、この PC 実行経路へバイト列を運んでから同じ chunk 形式で送る。**クラウドからの画像取得と、アプリがバイト列を受信する処理は別**。クラウドのファイルパスを Windows で開けるとは仮定しない。この実装で Library 等からの自動ダウンロードが完成したとは扱わない。

## 一括登録

export の応答にある jobId / documentId / ifRevision をそのまま使い、manifest の requestId は jobId とする。パイプの requestId とは別。

```json
{
  "command":"import",
  "requestId":"import-unique-id",
  "args":{
    "jobId":"今回のjobId",
    "result":{
      "schemaVersion":1,
      "requestId":"今回のjobId",
      "jobId":"今回のjobId",
      "documentId":"今回のdocumentId",
      "ifRevision":"今回の文字列revision",
      "assets":[{"assetId":"R1","path":"images/R1.png","sha256":"実PNGのSHA256","width":1024,"height":1536,"pixelFormat":"RGBA8","colorSpace":"sRGB"}],
      "operations":[
        {"op":"add_group","layerId":"{新規グループGUID}","name":"右手","parentId":"","beforeLayerId":"","visible":true,"opacity":255},
        {"op":"add_layer","layerId":"{新規画像GUID}","name":"*R1","parentId":"{新規グループGUID}","beforeLayerId":"","visible":true,"opacity":255,"assetId":"R1","bounds":{"left":0,"top":0,"right":1024,"bottom":1536}}
      ]
    }
  }
}
```

beforeLayerId は同じ親のどの要素より前（上）へ挿入するか。空文字は末尾。ルート親は空文字。operations は先頭から順に評価する。PNG の bounds は入力寸法と一致させ、resample / sourceBounds / trimTransparent を付けなければ再生成・拡縮・切抜き・移動補正を行わない。透明 RGB / alpha を含む元 RGBA を保持する。opacity は0～255。グループの255未満の不透明度は既存レンダラーで扱える通常グループ合成として処理する。

同じ親の * 差分は最終的に最大1枚ON。最終候補が競合していればバッチ全体を拒否する。複数部位はそれぞれの親へ select_part を同じバッチに並べてもよい。

全 PNG・操作を候補文書へ適用・検証し、成功してから現在文書を一度入れ替える。不正な後続操作でも先行レイヤーだけを残さず、文書・revision・Undo・完了状態を保持する。失敗した result.json は診断用にジョブ内へ残ることがあり、別の結果への上書きは拒否する。その場合は新しい export を使う。従来の args={jobId} とローカル result.json の import も維持。

入力 RGBA の合計上限128MiBを維持し、入力+登録後画像の合計を192MiBにした。11枚の1024×1536 RGBA は合計138,412,032バイトで範囲内。これは静的計算であり、実機のメモリ負荷は未検証。

## プレビューと保存

```json
{"command":"preview","args":{"documentId":"確認したID","ifRevision":"確認したrevision"}}
```

previewId、documentId、revision、width、height、sizeBytes、PNG の sha256、合成 RGBA の pixelSha256 を返す。

```json
{"command":"preview-read","args":{"previewId":"{返ったID}","offset":0,"count":12288}}
```

返った dataBase64 を連結し、count ずつ offset を進める。最後は eof=true。snapshot は保持時点の画像で、後の編集へ自動追従しない。1PNG32MiB、合計64MiB、8件、アイドル15分。呼出元別で、文書リセット・保存・終了時に破棄する。

PC へファイルとして受け取る補助：

```powershell
.\Tools\Receive-ArtPreview.ps1 -PipeName '現在のパイプ' -DocumentId '現在のID' -Revision '現在のrevision' -OutputPng 'V:\制作資料\新規プレビュー.png' -Client dot
```

既存出力は拒否し、分割取得・SHA256確認後に新規確定する。画像をクラウドへ戻す場合もこの同じバイト列を使える。

```json
{"command":"save","args":{"documentId":"現在のID","ifRevision":"現在のrevision","fileName":"V:\\制作資料\\新しい演奏PSD.psd"}}
```

親フォルダーは事前に存在する必要がある。PSD を一時名へ書出し・既存の検証後、置換フラグなしで指定先へ確定する。保存先が途中で出現しても上書きしない。保存後は再読込して新しい文書ID・レイヤーIDとなる。書出し後の再読込だけ失敗した場合は、エラーに保存済みのパスを含める。状態とファイルを確認し、無条件に別名保存を重ねない。

## 再送・競合

変更命令の成功応答は client+requestId 単位で直近64件、アプリのメモリに保存する。同じID・同じJSON構造なら再実行せず同じ応答を返す。オブジェクトのキー順・空白の差は許すが、配列順・値の変更は拒否する。キャッシュは再起動・64件超過で失効するため、一般的な永続トランザクションキーではない。失効後は documentId/revision、ジョブの結果ハッシュ、保存先の新規名制限等で判断する。import 自身の同一結果二重適用防止は従来どおり維持。status / document / preview / preview-read / image-status はこの成功再送キャッシュの対象外。

dot の undo / redo / recover も確認した documentId / ifRevision を渡す。文書未読込時の recover は空IDと revision="0"。旧 Codex の形式は維持する。別担当のジョブを変更せず、自分のジョブでも古い revision は適用しない。呼出元は認証境界ではなく自己申告なので、同一Windowsユーザー内での制作担当の調整は引き続き必要。

## ビルド後の受入ケース

Test-ArtAssembly.ps1 を用意した。ユーザーが **文書を開いていない専用の新本体** を起動してPIDを指定した場合だけ、合成PNGで試験する。スクリプトはアプリを起動・終了・再起動しない。既存文書があると開始前に拒否する。

```powershell
.\Tools\Test-ArtAssembly.ps1 -ProcessId 12345
```

1024×1536、背景1 + R0/R1/R2 + B0/B1/B2/C0/C1/C2 + belt1 の11画像と左右2グループを作り、背景・R1・B1・beltだけを表示する。不正バッチのロールバック、要求再送、全画像RGBAと座標、分割プレビュー取得、新規PSD保存・再読込を検査する。**実際の採用済みアコーディオン素材は使わず、今回このスクリプトも実行していない。**

今回の到達点は実装と静的確認。追加命令のコンパイル、実機処理、再起動復帰、長時間負荷はユーザーのビルド後に確認する。
