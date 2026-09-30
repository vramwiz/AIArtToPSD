# PipeServerTThread

2026-09-30、ユーザー指定によりAul2MIRAIで使用中の共通パイプユニットを無変更でコピーした。

- コピー元：`D:\DelphiProg\test\Aul2MIRAI\Source\Lib\Pipe\PipeServerTThread.pas`
- コピー先：`Source/Lib/Pipe/PipeServerTThread.pas`
- SHA-256：`1CFB4F01CB3444465115134A8D6716617DB066CC5488946630094B2CC6C4B932`
- 依存：Winapi.Windows、Winapi.Messages、System.Classes、System.SysUtils。
- アプリのdpr／dprojに登録し、Win64 Debug／Releaseで警告0・エラー0。

元プロジェクトの`Aul2MIRAIPipeServer.pas`は接続・終了処理の参照先。これはAviUtl固有のCommand／Protocol／Viewに依存するので、今回はコピーしていない。

通信は`PIPE_TYPE_MESSAGE`／UTF-8文字列。`WM_PIPE_NOTIFY`を受けてUIスレッドから`ProcessMainThread`を呼び、終了時は`Terminate`、`ReleaseWait`、接続待ち解除、`WaitFor`を組み合わせる。元プロジェクトのバッファ設定は65,536バイト。大きい画像はファイル参照で交換する。

新しい低レベル通信を一から作らず、この部品へAIArtToPSDの命令処理を接続する。長さプレフィックス方式を独自に追加しない。今回サーバーは起動しておらず、通信・終了・上限・切断の試験は連携工程で行う。
