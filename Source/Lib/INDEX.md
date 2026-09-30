# 登録ライブラリ

| 部品 | コピー元 | 用途・状態 |
| --- | --- | --- |
| [PipeServerTThread](Pipe/README.md) | Aul2MIRAI/Source/Lib/Pipe | 名前付きパイプの共通スレッド。コピー・ビルド登録済み、AIArtToPSDの通信接続は未実施 |

| [VerticalScrollBarControl](UI/VerticalScrollBar/README.md) | SYNC_ScreenLayout/Lib/VerticalScrollBar | 無変更コピー。独自レイヤー一覧のスクロール |
| [HorizontalTrackBar](UI/HorizontalTrackBar/README.md) | DelphiVclAppTemplate/Source/Lib/UI/HorizontalTrackBar | Control・Rendererを無変更コピー。レイヤー行の不透明度 |

必要なUI等のライブラリはDelphiVclAppTemplateから積極的にコピーして利用する。レイヤー一覧は独自描画とし、指定されたSYNC_ScreenLayoutのスクロール部品を再利用する。
