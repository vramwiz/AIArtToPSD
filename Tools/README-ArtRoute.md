# Codex / dot 本体通信対応

2026-10-23。本体対応版。`AIArtToPSD.dpr` が参照する既存の通信・交換・MainForm unit を改良した。外部 CLI は PC 実行経路の補助であり、本体で呼出元の受理・表示・ジョブ担当元の検証を行う。共通の名前付きパイプを維持し、MCP、HTTP サーバー、外部公開ポートは追加していない。

**今回の本体変更は静的確認まで。ユーザーの最新方針により、ビルド・アプリ起動・再起動はユーザーが担当する。旧 EXE での以前の成功記録は、今回の本体実装の実行確認ではない。**

追記：この呼出元対応版はユーザーのビルド後、正式な承認付き通常ユーザー実行で状態取得に成功した。その後の新規キャンバス・一括JSON登録・プレビュー等の追加と現在の検証範囲は [PSD組み立てAPI](README-ArtAssembly.md) を優先する。追加命令は改めてユーザービルド待ち。

## ユーザーによるメインのビルドと確認

1. Delphi でメイン `AIArtToPSD.dpr` / `AIArtToPSD.dproj` を Win64 Debug / Release でビルドする。通信 unit は既にメインの uses に登録済みなので、別アプリや補助 CLI のビルドに置き換えない。
2. 生成された `Win64/<Config>/AIArtToPSD.exe` をユーザーが起動する。プロジェクト直下の旧 EXE と取り違えない。
3. 画面の AI 欄に「Codex / dot 受付中」、両者の「未受信」が表示されることを確認する。
4. PowerShell 7 でプロジェクト直下から次を実行する。これは起動済みアプリだけへ状態要求を送る。起動・ビルド・文書編集は行わない。

```powershell
Get-Process AIArtToPSD | Select-Object Id,Path
# 12345 は上でユーザーが起動した新 EXE の PID。
.\Tools\Test-ArtClientStatus.ps1 -ProcessId 12345
```

成功時は `passed=true`、`readOnly=true`、dot / Codex / 旧形式それぞれの requestId と clients を返す。画面にも各呼出元の最終受信時刻と結果が表示される。ラベルのヒントにはパイプと最終 requestId を表示する。これは受信履歴であり、常時接続・クラウドのログイン状態を示さない。

PNG / 編集対応 PSD を開かなくても status は利用可能。レイヤー登録には `canEdit=true` の対象文書が必要。既存の未保存文書を自動で置き換えない。

個別の状態確認：

```powershell
.\Tools\Invoke-ArtRoute.ps1 -ProcessId 12345 -Client dot -InputJson '{"command":"status","args":{},"requestId":"dot-check-001"}'
.\Tools\Invoke-ArtRoute.ps1 -ProcessId 12345 -Client codex -InputJson '{"command":"status","args":{},"requestId":"codex-check-001"}'
.\Tools\Invoke-ArtRoute.ps1 -ProcessId 12345 -Client dot -InputJson '{"command":"document","args":{"offset":0,"limit":32,"includePixelHashes":true}}'
```

## 本体の変更

| unit | 変更内容 |
| --- | --- |
| ArtPipeProtocol | schemaVersion=1 に任意 client を追加。codex / dot を受理、省略は codex。不正値を拒否。応答にも client を返す。呼出元別に最終 UTC 時刻、requestId、command、処理状態を保持し、再入要求で現在の文脈が上書きされることを防ぐ |
| ArtPipeBridge | 起動時の接続 JSON に clientRoutingVersion=1 と supportedClients を発行 |
| ArtExchange | ジョブに client を持たせ、request.json / connection.json へ保存。復帰時も維持し、旧ジョブの省略は codex。別 client のジョブ更新を拒否する照合処理 |
| ArtPipeImages | begin / chunk / status / commit / abort にジョブ担当元の照合を適用。既存のハッシュ・寸法・新規名検証を維持 |
| AIArtToPSDMainForm | Codex / dot の受信表示、指示元を区別した AI 記録とジョブ状態表示、呼出元別の最新ジョブ。import / progress / cancel / recover に担当元検査。dot の undo / redo に documentId / ifRevision を必須化 |

メイン .dpr 自体へ通信処理を詰め込む変更は不要だった。既存の uses から上記 unit をビルドすることで本体へ組み込まれる。

## JSON プロトコルと互換性

アプリが `AIArtToPSD.<PID>.{GUID}` を待ち受け、PC 実行タスクのクライアントが `\\.\pipe\<name>` に接続する。起動時の接続情報は同じユーザーの `%LOCALAPPDATA%\AIArtToPSD\pipes\*.json`。UI スレッドで命令を処理し、ワーカーへイベントで応答を戻す。MaxInstances=1 の既存直列処理を維持する。

新しい要求：

```json
{"schemaVersion":1,"requestId":"dot:probe-001","client":"dot","command":"status","args":{}}
```

client なしの旧 Codex 要求もそのまま受理する。requestId の接頭辞を本体の呼出元判定に使わない。パイプ requestId は応答照合に使う。現在は成功した変更要求の直近64件に再送キャッシュを追加しており、詳細はPSD組み立てAPIを参照。

期待応答例（未実行の書式例。data の一部）：

```json
{"schemaVersion":1,"ok":true,"client":"dot","requestId":"dot:probe-001","data":{"clientRoutingVersion":1,"supportedClients":["codex","dot"],"clients":[{"client":"codex","seen":false},{"client":"dot","seen":true,"requestId":"dot:probe-001","command":"status","state":"processing","lastSeenUtc":"2026-10-23T00:00:00.000Z"}]}}
```

status 自身の処理中にスナップショットを作るため、要求元の state は processing となる。要求終了後、画面と次の要求には succeeded / failed を記録する。status の jobId を省略した場合はその client の最新ジョブを返す。明示した jobId の読み取り状態照会は他 client 分も可能。

メッセージモード UTF-8 JSON、一要求・一応答。長さプレフィックスや改行終端なし。要求は 60,000 バイトかつ Delphi 30,000 文字以下。requestId は 128 文字以下。既存バッファは 65,536 バイト、document は最大64層のページと約58,000バイト制限。CLI の接続・書込・読取はそれぞれ既定5秒、最大60秒。サーバーへ渡される Timeout=1000 は共通実装の I/O 制限には使われておらず、UI 待ちや接続・読書きはブロッキング。FBusy 中の命令は status も含め拒否される。

## 補助 CLI

Invoke-ArtRoute の入力は command / args / 任意 requestId。`-Client dot` が既定で、codex も指定できる。CLI が client を要求の独立フィールドに入れ、requestId にも同じ接頭辞を付ける。要求ID指定は ASCII 英数字と `._:-` の1～120文字。dot の場合、接続情報に本体対応の広告がなければ旧 EXE へ送信せず拒否する。

```powershell
.\Tools\Invoke-ArtRoute.ps1 -ProcessId 12345 -InputFile .\request.json -TimeoutMs 60000
```

```json
{"command":"status","args":{},"requestId":"probe-001"}
```

status / document / image-status 以外は明示した ProcessId が必要。候補が一つなら読み取りは PID を省略できる。複数候補は拒否する。EndpointDirectory は隔離試験用で、通常は既定 LOCALAPPDATA を使う。失敗も stdout に一つの JSON、終了コードは成功0・失敗1。route_failed は CLI エラー、command_failed は本体の拒否。タイムアウトは実行失敗の確定ではなく、状態を照合してから判断する。

Send-ArtCommand は任意の `-Client codex|dot` を追加したが、省略時の旧 envelope と GUID 発行・エラー例外の挙動を維持する。Send-ArtImage も任意 Client を全画像コマンドに伝える。

## レイヤー登録と競合

既存の [パイプ操作ルール](../パイプ操作ルール.md) の export→PNG→result.json→import→新規名saveを共用する。

1. 対象 documentId / revision を確認し、同じ Client で export する。
2. 返ったジョブの images 内へ新規名 PNG を用意する。Send-ArtImage で送る場合、dot ジョブには `-Client dot` を付ける。
3. request.json の requestId / jobId / documentId / ifRevision を保ち、PNG の相対パス、SHA256、寸法と add_group / add_layer 等を result.json に記述する。result.json の requestId はジョブIDであり、パイプIDとは別。
4. 同じ Client から import し、completed、階層、画素ハッシュを照合して、新規名に save する。

PNG 分割受信は従来どおり最大12,288バイトの base64 chunk、1 PNG32MiB、合計64MiB、16転送、アイドル15分。画像はジョブフォルダーで受け渡す。アプリから Codex / dot を起動する非公開 API は追加していない。アプリ→AI は request.json 等の書出し、AI→アプリは既存パイプの命令という区別を維持する。

別 client のジョブに対する import / progress / cancel / recover / image-* は拒否する。復帰時も担当元を保ち、現在文書を入れ替える前に照合する。双方が自分のジョブを同じ revision で作った場合、先に適用された編集だけが成立し、後の古い結果は既存 revision 検証で拒否される。同じ結果の再 import は二重適用しない。save は引き続き documentId / ifRevision と存在しない保存先を検証する。

dot undo / redo は次のように直前の文書状態を渡す。旧 Codex の空 args の互換は保持し、Codex でもこれらを指定した場合は検証する。

```json
{"command":"undo","args":{"documentId":"今回確認したID","ifRevision":"今回確認した文字列revision"}}
```

client は自己申告であり認証境界ではない。同じ client 内の複数セッションの所有権分離はない。グローバルな保存・履歴操作は同じ文書へ作用するため、制作担当の調整は必要。パイプの ACL、ファイアウォール、権限、外部公開設定は変更しない。低レベルの共通 PipeServerTThread も無変更。

## 検証範囲と過去の証跡

本体変更後は静的確認のみ。PowerShell 構文、Pascal の宣言・呼出箇所、メインからの unit 参照、UTF-8 BOM、git diff --check を確認する。新しい本体のコンパイル、UI目視、通信、画像登録、再起動復帰はユーザーのビルド後に検証が必要。

Test-ArtRoute.ps1 を本体対応用に更新した。client応答、本体対応広告、担当元別status、他担当のcancel/画像操作拒否、PNG受信・登録、競合拒否、revision付きUndo/Redo、保存の試験を用意した。専用アプリを起動する補助のため、ユーザーが実行する場合だけ使用する。こちらでは実行していない。Tests/ClientProtocolSmoke.dpr は旧形式・dot・不正client・失敗・再入拒否の試験ソースで、未ビルド・未実行。

本体変更前、旧 EXE と外部 CLI のみで各35チェックが成功した証跡は以下に保持する。**本体対応版の検証結果として扱わない。**

- Tests/output/ArtRoute/83b4bf91b41f4b0687070e68a4660648/verification.json（旧 Release）
- Tests/output/ArtRoute/a6c92448addc416babc5b62031ddee61/verification.json（旧ルートEXE）
- Tests/output/ArtRoute/parent-check-20261023-0916/parent-check.json（旧実装、09:17:02 UTC、dot:dot-parent-check-20261023-0916 の往復）

本体変更前の Win64 Debug ビルド試行は BRCC32 タスク初期化の Borland.Globalization.ResourceStringManager によるレジストリアクセスで SecurityException / MSB4061 / MSB4060。権限回避は行っていない。以後はユーザー方針に従ってビルド・起動を行わない。クラウド画像受領、長時間負荷、GUI目視、最新本体の実動作は未検証。

初期の既存変更 Sample/LayerSplitTrial/README.md の削除は保持。ユーザーの PSD・画像・未保存文書を変更していない。
