# バイオリン4枚の新規PSD試験：実行準備

**2026-10-23 実試験完了。** ユーザーのローカル保存確認後、Downloads の violin_4png.zip から4PNGを検査し、通常起動中の空文書状態のアプリへパイプで新規PSDを作成した。下記は再利用できる試験手順であり、再実行の指示ではない。[受入ケース](../Tests/fixtures/violin_assembly_case.json)。署名付きLibrary受領情報を渡す経路は再開していない。

## 固定する受入条件

- 1024×1536、PNGは全て左上0,0・原寸。不透明度255。拡縮、切抜き、透明余白除去、画像生成を行わない。
- ルートの上から Arm、Fixed。Arm の上から *ARM_0、*ARM_1、*ARM_2。Fixed の子は BODY。
- 新規試験の初期条件は Fixed/BODY と Arm/*ARM_1 だけを表示。グループ自身は両方表示。*ARM_0 / *ARM_2 は非表示。既存試験文書の名前だけを直す場合は、その時点のユーザーの表示選択を保持する。
- 指定された名前をそのまま使い、差分3層だけを *ARM_0 / *ARM_1 / *ARM_2 とする。BODY・グループ・PNGファイル名は変更しない。APIでの自動付与は行わず、登録manifestで明示する。Arm内で表示する画像が1枚だけであることを確認する。
- 画像4枚＋グループ2個＝6ノード。既存PSDは開き直して再保存しない。
- 元PNGファイルSHA256は受入ケースの4値に固定。ファイルSHA256と、デコードしたRGBAのSHA256は別物として照合する。

## 保存通知後の前提確認

1. 本人が保存したZIPの実パスを確定する。通知前に探索しない。
2. 明示されたローカルZIPを読み取りで開く。必要なBODY.png / ARM_0.png / ARM_1.png / ARM_2.pngがそれぞれ一意に存在することを確認する。PSDエントリはアプリへ渡さない。
3. 元ZIPを保持し、新規 `Tests/output/ArtRoute/violin_<UTC時刻>_<GUID>/input/` へ4PNGだけをコピーする。エントリパスを出力パスとして使わず、上記固定ファイル名で新規作成する。重複・寸法違い・SHA256不一致ならここで停止する。
4. PNGを独立したデコーダー（親側のPillow等）で原寸RGBAへ読み、各RGBA SHA256とBODY＋ARM_1の初期合成を記録する。元PNGバイト列は変更しない。
5. 正式承認付きの通常ユーザー実行で、現在のAIArtToPSDのPID・実行パスを再取得する。過去の7356等を固定して使わない。
6. statusでassemblyVersion=1と追加命令を確認する。documentIdがあれば、この試験では既存文書を自動置換せず停止する。未保存作業を閉じない。アプリの追加起動・ビルド・再起動もしない。

## 必要な識別子

| 値 | 取得・発行する場所 |
| --- | --- |
| appId / pipeName | その時点のプロセス一覧とstatus |
| runId | 試験ごとの新しいGUID |
| パイプrequestId | 各論理操作に `violin-<runId>-<phase>`。再送だけ同じID・同じ内容を使う |
| documentId / revision | new-document応答。その後は変更ごとにdocumentから取り直す |
| jobId / ifRevision | export応答。result.requestIdもこのjobId |
| transferId | PNGごとに新しいGUID。同じPNGの転送再開時だけ維持 |
| Arm / Fixed / 各画像のlayerId | 一括登録前に発行する6個の新しいGUID |
| previewId | preview応答。保存・文書リセットで失効するため、保存前に受信を完了 |
| 保存後の文書・レイヤーID | save後のdocument。以前のIDを使い回さない |

## PCで使う既存補助

以降の例は保存通知後に値を埋めて実行するための準備。現在は実行しない。

```powershell
Get-Process AIArtToPSD | Select-Object Id,Path
.\Tools\Invoke-ArtRoute.ps1 -ProcessId <現在のPID> -Client dot -InputJson '<入力JSON>' -TimeoutMs 60000
```

### 1. 状態取得

```json
{"command":"status","requestId":"violin-RUN-status","args":{}}
```

文書未読込であることを確認した場合だけ、新規作成する。

### 2. 新規文書

```json
{"command":"new-document","requestId":"violin-RUN-new","args":{"width":1024,"height":1536,"documentId":"","ifRevision":"0"}}
```

返った文書IDを記録し、width=1024、height=1536、layerCount=0を検査する。未保存文書がある場合の拒否を、破棄やrecoverで回避しない。

### 3. 受信用ジョブ

```json
{"command":"export","requestId":"violin-RUN-export","args":{"prompt":"採用済みバイオリン4PNGの新規PSD試験。原RGBA・1024x1536座標を保持。生成・変形なし。"}}
```

### 4. PNGを分割送信

4枚それぞれに実行し、committed、SHA256、寸法、返ったimages内の相対パスを記録する。

```powershell
.\Tools\Send-ArtImage.ps1 -PipeName $pipeName -JobId $jobId -InputPng $bodyPng -FileName 'BODY.png' -TransferId $bodyTransferId -Client dot
# 同様に ARM_0.png / ARM_1.png / ARM_2.png。各々独立したTransferId。
```

この補助は既存 image-begin → image-chunk → image-commit を使用する。ジョブID、PNGファイルSHA256、実寸法を検査する。

### 5. 一括import

resultはローカルresult.jsonへの依存を避け、args.resultで渡す。下記の大文字識別子・ハッシュ・パスは応答と受入ケースで置き換える。operationsはこの順に一つのバッチへ含める。

```json
{
  "command":"import","requestId":"violin-RUN-import",
  "args":{"jobId":"JOB_ID","result":{
    "schemaVersion":1,"requestId":"JOB_ID","jobId":"JOB_ID","documentId":"DOCUMENT_ID","ifRevision":"REVISION_STRING",
    "assets":[
      {"assetId":"BODY","path":"images/BODY.png","sha256":"BODY_FILE_SHA256","width":1024,"height":1536,"pixelFormat":"RGBA8","colorSpace":"sRGB"},
      {"assetId":"ARM_0","path":"images/ARM_0.png","sha256":"ARM_0_FILE_SHA256","width":1024,"height":1536,"pixelFormat":"RGBA8","colorSpace":"sRGB"},
      {"assetId":"ARM_1","path":"images/ARM_1.png","sha256":"ARM_1_FILE_SHA256","width":1024,"height":1536,"pixelFormat":"RGBA8","colorSpace":"sRGB"},
      {"assetId":"ARM_2","path":"images/ARM_2.png","sha256":"ARM_2_FILE_SHA256","width":1024,"height":1536,"pixelFormat":"RGBA8","colorSpace":"sRGB"}
    ],
    "operations":[
      {"op":"add_group","layerId":"ARM_GROUP_ID","name":"Arm","parentId":"","beforeLayerId":"","visible":true,"opacity":255},
      {"op":"add_group","layerId":"FIXED_GROUP_ID","name":"Fixed","parentId":"","beforeLayerId":"","visible":true,"opacity":255},
      {"op":"add_layer","layerId":"BODY_ID","name":"BODY","parentId":"FIXED_GROUP_ID","beforeLayerId":"","visible":true,"opacity":255,"assetId":"BODY","bounds":{"left":0,"top":0,"right":1024,"bottom":1536}},
      {"op":"add_layer","layerId":"ARM_0_ID","name":"*ARM_0","parentId":"ARM_GROUP_ID","beforeLayerId":"","visible":false,"opacity":255,"assetId":"ARM_0","bounds":{"left":0,"top":0,"right":1024,"bottom":1536}},
      {"op":"add_layer","layerId":"ARM_1_ID","name":"*ARM_1","parentId":"ARM_GROUP_ID","beforeLayerId":"","visible":true,"opacity":255,"assetId":"ARM_1","bounds":{"left":0,"top":0,"right":1024,"bottom":1536}},
      {"op":"add_layer","layerId":"ARM_2_ID","name":"*ARM_2","parentId":"ARM_GROUP_ID","beforeLayerId":"","visible":false,"opacity":255,"assetId":"ARM_2","bounds":{"left":0,"top":0,"right":1024,"bottom":1536}}
    ]
  }}
}
```

成功はstate=completedで判定する。失敗・タイムアウト時はstatus/documentとジョブを確認し、別内容で無条件再送しない。部分的な登録がないことを確認する。

### 6. 登録後の層と初期合成

```json
{"command":"document","requestId":"violin-RUN-layers-before-save","args":{"offset":0,"limit":32,"includePixelHashes":true}}
```

6ノード、親ID、親内index、4画像のbounds・visible・opacity、独立デコードした4RGBA SHA256との完全一致を検査する。

```powershell
.\Tools\Receive-ArtPreview.ps1 -PipeName $pipeName -DocumentId $documentId -Revision $revision -OutputPng $newPreviewBeforePath -Client dot
```

PNGの受信SHA256を検査し、BODY＋ARM_1の参照合成と照合する。合成差があれば最大差・不一致画素数・alpha差を記録し、無条件に成功としない。

### 7. 独立した新規PSD保存

保存直前にdocumentId/revisionを取得し直す。保存先は新規試験フォルダー内の `violin_from_png.psd`。既存ファイルがあれば別の新規試験フォルダーを使う。

```json
{"command":"save","requestId":"violin-RUN-save","args":{"documentId":"CURRENT_DOCUMENT_ID","ifRevision":"CURRENT_REVISION_STRING","fileName":"ABSOLUTE_NEW_TEST_DIRECTORY\\violin_from_png.psd"}}
```

### 8. 終了条件

save成功後の新しいIDでdocumentを再取得し、6ノード・全属性・4元PNGのRGBA SHA256を再照合する。保存後previewを新規名で受信し、保存前previewとデコードRGBAが一致することを確認する。

終了記録は、元PNGファイルSHA256、元RGBA SHA256、保存前後のdocument JSON、preview PNGと照合値、新規PSDのパスとSHA256、実requestId、全判定を含むverification.json。**層とPNG画素の照合を終えるまで試験成功とは報告しない。**

## 実行結果

出力：`Tests/output/ArtRoute/violin_20261023T104439Z_7c9f66a1/violin_from_png.psd`。

- 起動済みPID7356のメインEXEを、正式な承認付き通常ユーザー実行で操作。開始時の文書未読込を再確認した。新規アプリ起動・ビルド・再起動は行っていない。
- ユーザー保存の軽量ZIPに4PNGだけがあり、指定ファイルSHA256は全一致。元ZIPを保持し、別試験フォルダーへ展開。
- new-document→export→4PNGのimage-begin/chunk/commit→inline import→preview→save→document/preview確認を実施。比較用の既存PSDは入力に使っていない。
- API側53項目と、既存Analysis/inspect_psd.pyによる保存ファイル自体の独立40項目が成功。4層のRGBAは元PNGと完全一致。画像4＋グループ2、全属性・階層・順序を確認。
- 初期合成は独立したBODY＋ARM_1の計算と完全一致（最大差0）。保存前後のPNGプレビューのファイルSHA256とRGBAが一致。PSDに格納された白マットRGB・alphaも独立照合で一致。
- psd_toolsは未導入だったためインストールせず、既存の標準ライブラリ製PSDデコーダーと利用可能なPillow/NumPyで検証した。

同フォルダーのverification.jsonが最終判定。inputs.json、転送受領情報、実requestId付き応答、import-manifest.json、保存前後document JSON、期待合成、保存前後preview、independent/psd-structure.jsonを保持する。新規PSDのSHA256は `26d8bd18401a40f8658a2d574c2dc33c62175bcb0b635d489c9f92d8ddd70fc5`。

## 差分名の訂正

ユーザー指示に合わせ、既存一括importのrename_layerを3件だけ明示し、*ARM_0 / *ARM_1 / *ARM_2へ訂正した。BODYとArm/Fixedは改名していない。PNGの再送・再描画・置換は不要で、API側の自動prefix処理は追加しない。

訂正前は同じ試験文書のrevision=8、modified=trueで、ユーザーがARM_2だけを表示していた。元の保存状態へ戻すことはせず、他の全属性と元画素を照合したうえで、現在の表示を保持した3件の名前変更を適用した。指定と異なる文書・画素・階層だった場合は停止する条件を入れていた。

修正版：`Tests/output/ArtRoute/violin_20261023T104439Z_7c9f66a1/violin_from_png_exclusive.psd`。前のviolin_from_png.psdはSHA256を含め不変。修正版は*ARM_2とBODYを表示し、*ARM_0/*ARM_1を非表示に保つ。6ノード、元PNG RGBA、座標、順序、不透明度を保持し、訂正前後の合成差は0。

API87項目＋独立PSD33項目が成功。証跡は同フォルダーexclusive-verification.json。修正版SHA256は `5520cea5a5bbf34056326d13e85be320c2f16de040f9921cfee512e9aac59958`。将来の新規登録manifestとfixturesにも差分だけの*付き期待名を反映した。
