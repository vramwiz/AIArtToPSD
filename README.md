# AIArtToPSD（AI立ち絵メーカー）

多層*排他の祖先選択修正（本人再ビルド待ち）: [仕様・回帰テスト・パイプ確認手順](Tools/README-MultilevelExclusive.md)。新本体のstatusでexclusiveSelectionVersion=2を確認する。

PSD読込と明示上書きの追加パイプ仕様: [README-PipeFileOperations.md](Tools/README-PipeFileOperations.md)。2026-10-24追加分はユーザーが再ビルド・起動し、13PSDのパイプ再保存・再読込・内容照合を完了。

Delphi製のPSD編集アプリ。PSDの読み書き、レイヤー表示、PNG取込と配置、表情切替、名前付きパイプによるAI画像作成との連携を扱う。

現在の実装・制作方針は[note.md](note.md)、再開手順は[作業引継ぎ](作業引継ぎ.md)、制作の再利用手順は[Codex再利用ガイド](Codex再利用ガイド.md)を参照。

メインアプリに Codex / dot の呼出元識別・受信表示・ジョブ担当元の照合を実装した。[本体通信対応とユーザーのビルド後確認手順](Tools/README-ArtRoute.md)を参照。既存パイプを共用し、新しい常駐サーバーや公開ポートは不要。本体変更後のビルド・起動確認はユーザー担当。

新規キャンバス、PNG分割受信、一括JSON登録、プレビュー取得、新規PSD保存の手順は[PSD組み立てAPI](Tools/README-ArtAssembly.md)。通常起動への承認付き状態取得は確認済みだが、その後追加した組み立て命令はビルド待ち。

## ビルド

WindowsとDelphi 37を使用する。Delphiのコマンドプロンプトで、プロジェクト直下から実行する。

```bat
msbuild AIArtToPSD.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:minimal /nologo
```

`AIArtToPSD.res` はアプリと画面テストが使用するため、リポジトリに保持する。`Source/` はアプリソース、`Tools/` は共通補助ツール、`Tests/` はテストのソースと検証スクリプト。

## GitHubへ同期するファイル

ソース、プロジェクト、必要なアプリリソース、設計・作業文書を管理する。`Sample/` では `README.md`、`learning_record.json`、名前に `prompt` を含むJSON、`verification.json` だけを管理する。

次のデータは[.gitignore](.gitignore)で同期対象から除外する。

- `PSD/` と `Sample/` のPSD・PNG・作業用スクリプト・セッション応答・中間データ。
- `Exchange/` の画像交換ジョブと復帰用スナップショット。
- `Tests/output/` と `Analysis/results/` の生成結果。
- Delphiのビルド生成物、IDEのローカル設定、Pythonキャッシュ、一時ファイル。

文書中のPSD・画像・中間ファイルへのリンクは手元の作業資料を参照する。GitHubからcloneしただけでは画像資料は揃わない。同じ素材を別PCで使う場合は、必要なPSD・PNGを別途同じ相対配置で渡す。[Sampleの管理方針](Sample/README.md)も参照。

解析出力は[Analysisの手順](Analysis/README.md)で再生成する。テスト出力もテスト実行で作成する。`Tests/ViewerSmoke.dpr` は事前に `Tests/output/preserved_aiueo.psd` を生成する必要があるため、[PSD往復テストの手順](PSD実装_最小読み書き.md)を先に実行する。

2026-10-02の整理では、既に追跡されていた作業資料もGitの管理対象から外した。完成PSD・元画像・制作素材は手元に保持する。Gitの過去のコミット履歴は保持する。

## ローカル作業ファイルの削除

[Tools/Clean-WorkFiles.ps1](Tools/Clean-WorkFiles.ps1)をPowerShell 7で実行する。既定では候補と容量を表示するだけで、`-Apply` を指定した場合に削除する。

```powershell
.\Tools\Clean-WorkFiles.ps1
.\Tools\Clean-WorkFiles.ps1 -Apply
```

対象は再生成できるテスト出力・ビルド出力・Pythonキャッシュ・大容量解析出力と、キャンセル済みの交換ジョブ。`Sample/` の制作素材、`PSD/`、メインの実行ファイル、アプリリソース、IDEの個人設定は保持する。`-Apply -WhatIf` でも事前確認できる。
