# 多層の * 排他選択

2026-10-24。本体ソース修正済み、ユーザーによる `V:\DelphiProg\AIArtToPSD\AIArtToPSD.dpr` の再ビルド・起動待ち。こちらではコンパイル・起動・GUI操作を行っていない。既存PSDも変更していない。

## 修正内容

旧 `ArtParts.SelectExclusive` は選択した層と同じ親の兄弟だけを変え、祖先を選択しなかった。そのため、非表示の親にある子を選んでも見えず、親パターンを跨ぐ切替にも親の手動選択が必要だった。

新処理は文書内で選択層への経路をすべて解決してから、根から選択層まで順に処理する。

- 各階層で、その層が `*` 排他なら**同じ親の `*` 兄弟だけ**をOFFにする。
- 選択層と祖先をONにする。非排他の中間コンテナも表示する。
- 別の枝の同名層を検索・変更しない。左右手足の非排他コンテナ、固定層、`!` 層、選択経路外の表示フラグは保持する。
- 名前・RGBA・座標・順序・不透明度・文書revision自体は共通プリミティブで変更しない。従来どおりGUIやimport側がUndo/revisionを管理する。
- 文書外の層、深度超過は、可視状態を変える前に拒否する。曖昧な旧 `*!` / `**` prefixの扱いは変更しない。
- OFF操作は従来どおり対象のみをOFFにする。親だけを選んだときに子の段階を勝手に選ぶ処理は追加しない。

GUIの可視ON・パーツ選択と、パイプ一括importの `select_part` は同じ `ArtParts.SelectExclusive` を使用する。新しい通信口やプロトコル変更はない。Codex/dot両方で従来のexport/importを使う。

GUIのパーツ選択欄も、祖先が非表示なら子の保存フラグがONでも「選択中」にしない。同じ子を選び直したときに選択イベントが発生し、祖先を表示できるようにした。これは表示欄の判定だけで、保存済みフラグを書き換えない。

既存の `set_attributes` は指定値を一括編集する命令のまま維持する。競合する複数*をONにした結果は従来どおりimportの最終検査で拒否する。パイプで「選択」を行う場合は `select_part` を使う。`rename_layer` や宣言的な一括属性変更を勝手な選択操作へ変更しない。

## ビルド後の識別と検証

本人がメインプロジェクトを再ビルド・起動したら、現在PIDを取得し直す。`status.data.exclusiveSelectionVersion=2` が新処理の識別子。旧PIDを再使用しない。descriptorにこの項目がなくても、statusで確認する。

```powershell
Get-Process AIArtToPSD | Select-Object Id,Path,StartTime
.\Tools\Invoke-ArtRoute.ps1 -ProcessId 12345 -InputJson '{"command":"status","args":{}}'
```

既存命令の選択例（jobのID・文書ID・revisionと対象layerIdは直前の応答を使う）:

```json
{"command":"import","args":{"jobId":"<export.jobId>","result":{"schemaVersion":1,"requestId":"<export.jobId>","jobId":"<export.jobId>","documentId":"<export.documentId>","ifRevision":"<export.ifRevision>","assets":[],"operations":[{"op":"select_part","layerId":"<選択する子のlayerId>"}]}}}
```

これは表示を変える命令なので、本人の実PSDに検証目的で送らない。未保存文書を保持し、専用の空アプリだけで以下のテストを行う。

### 正規パイプだけのテスト

```powershell
.\Tools\Test-ArtMultilevelExclusive.ps1 -ProcessId 12345
```

helperはアプリを起動しない。version=2未満、既存文書あり、未保存あり、busyなら何も作成せず拒否する。専用の空アプリに4×4の合成テスト文書を作り、2×2の赤/青PNGだけを使う。非表示祖先、複数の*階層、非排他の中間コンテナ、パターン跨ぎ、IDLE往復、左右手足・同名別枝・固定層の保持を検査し、新規の `Tests/output/MultilevelExclusive/<GUID>/synthetic-selected.psd` へ保存して再読込を比較する。本人素材は使わない。

### Delphiの回帰テスト

`Tests/MultilevelExclusiveSmoke.dproj` / `.dpr` はコンソールテスト。新規の出力ディレクトリだけを受け付け、既存ディレクトリなら拒否する。

対象は共通処理、同名別枝、非表示祖先、根の排他、深度エラーの無変更、IDLE、他部位・固定層・旧prefix維持、ピクセル/位置/順序/不透明度維持、JSON import経由の候補作成と失敗時の元文書保護、PSD保存再読込。アプリGUIや通信サーバーは起動しない。

今回このテストはコンパイル・実行していない。実装とテストの静的確認、PowerShell構文・プロジェクトXML/参照・UTF-8 BOM・diff検査を行い、実行結果と混同しない。メイン本体と補助テストのコンパイル可否、新実装の実機動作は本人のビルド後に確認する。
