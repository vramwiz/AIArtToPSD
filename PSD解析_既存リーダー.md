# PSD解析：既存リーダーの構成

調査日：2026-09-30。第一段階「リーダーの構成把握」の静的調査記録。
コードを読んで確認した内容であり、サンプルPSDの解析・実行確認・公式仕様との照合はまだ行っていない。以下の行番号は調査時点のもの。

## 参照元

入口：`D:\DelphiProg\AviUtl2Plugin\Syncroh2\Syncroh2_Filter_PSDDraw.dpr`

読み込み本体：`D:\DelphiProg\AviUtl2Plugin\AviUtl2PluginLib\Lib\PSDImage`

DPRはAviUtl2のフィルタープラグインDLL。GetFilterPluginTableと初期化・終了処理を持ち、PSDのバイナリ解析本体は共有ライブラリへ分離されている。既存リーダーは参照用であり、AIArtToPSDにはコピーしていない。

## 責務と主な参照位置

以下のユニット名は、特記しない限り上記PSDImageディレクトリからの相対パス。

| ユニット | 担当・参照位置 |
| --- | --- |
| PsdImage.pas | TPSDImage。全体情報、Layers、Trees、Resource、Bitmapを保持。LoadFromFile:390、ヘッダー:453、レイヤー情報:470、ツリー構築:494/587、Render:939 |
| PsdImageFileStreamBuf.pas | TFileStreamBuf。ファイル全体をメモリへ読み込む:59。ビッグエンディアン整数:118、リトルエンディアン整数:137、文字列・位置移動・範囲検査 |
| PsdImageLayer.pas | TPsdFileLayer/TPsdFileLayers。矩形・チャンネル・名前・表示・ブレンド等。画像展開:556/571、追加情報:597、矩形とチャンネル:647、lsct:671、luni:695、基本属性:701、VCL描画:296、AviUtl描画:392 |
| PsdImageChannel.pas | TPsdFileChannel。チャンネルID・データ長・画像位置・Byteの二次元画像。ID分類:304、圧縮分岐:326、無圧縮:342、RLE:355、チャンネルレコード:396 |
| PsdImageTree.pas | TPsdFileTree/Trees。親経路・子階層・表示状態・表示連動ルール。先頭!の判定:316、先頭*による選択判定:335、表示制御:390 |
| PsdImageDefine.pas | チャンネル・ブレンド種別、BGRAのTFourth等の共通型 |
| PsdImageBlend.pas | レイヤーのブレンド範囲情報。画像合成の関数登録とは別の役割 |
| PsdImageResource.pas | TPsdFileResource。リソース領域の走査:42。$040Cサムネイルを解析し、その他を読み飛ばす |
| PsdImageThumbnail.pas | リソース内サムネイルの読み込み |
| PSDImageAnmPath.pas | AssignPSDImageAnmPaths。レイヤーからANM用経路情報を作る。バイナリ解析後の付加情報 |
| PsdImageBitmap.pas | ビットマップ関連の派生層。詳細調査は次段階 |
| AviUtl2/PSDImageAviUtl2Filter.pas | TPsdImageBitmapの派生。乗算等の合成関数を登録。passは通常描画として扱い、グループ合成未対応と明記 |
| AviUtl2/PSDImageAviUtl2.pas | TPSDImageAviUtl2。LoadFromFile:302、立ち絵種類判定・独自補正・要素分類、画像事前展開の切替、描画バッファと差分キャッシュ、RenderAviUtlFilter:689 |
| PSDImageCacheFile.pas | GetOrCreate。ファイル名でPSDインスタンスを再利用。186〜194で生成・遅延展開設定・ロード |
| PSDImageCacheRender.pas | 描画結果のキャッシュ。PSDの保存処理とは別 |
| PSDImageElementList.pas、Kind/、Custom/ | 表情等の分類、立ち絵種類の判定、作者・キャラクターごとのマーカーや表示補正。PSD標準構造と分けて理解する |

プラグイン側の呼び出し元：

- `D:\DelphiProg\AviUtl2Plugin\Syncroh2\Plugin_Filter\PSD\PluginFilterPSDDraw.pas`:148〜149で描画・ファイルキャッシュを生成。
- 同ディレクトリの`PluginFilterPSDDrawIn.pas`:74でGPSDImageCacheFiles.GetOrCreate(FN)を呼び、GCtx.Psdへ設定。
- 同ディレクトリの`PluginFilterPSDDrawOut.pas`:122で描画キャッシュ取得、135でGCtx.Psd.RenderAviUtlFilter、148で描画結果を登録。

## 読み込みから描画まで

1. プラグイン入力側からファイルキャッシュのGetOrCreateを呼ぶ。
2. キャッシュ未登録ならTPSDImageAviUtl2を生成し、LoadFromFileを実行する。
3. 基底のTPSDImage.LoadFromFileがヘッダー、カラーモード領域、画像リソース、レイヤーレコードを順に読む。
4. レイヤーレコード直後の位置から、各チャンネルのImageLengthを足してImageAdrを割り当てる。この時点では画像の展開を行わない。
5. ANM経路、階層ツリー、平坦なツリー参照リストを構築する。レイヤー配列を末尾から走査し、LayerType 1/2をフォルダー、3を終了として再帰処理する。実ファイルにない仮想ルート!v1を追加する。
6. 派生層が立ち絵種類を判定し、Customによるマーカー・初期表示・排他連動・分類補正を適用する。*が無い場合は仮想マーカー*、ある場合は+の補正経路へ進む。
7. 描画時に表示中のレイヤーのチャンネルを展開し、画像バッファへ合成する。FImageLoadedにより展開済み画像を再利用する。基底Renderは元PSDを再読込し、派生層はFRenderFileStreamを保持する。

構造情報のロードとチャンネル展開は分かれているが、TFileStreamBuf自体は元ファイル全体をメモリに保持する。ファイルから完全に独立した編集用画像データをロード時に必ず作る設計ではない。

## コードから確認できた対応範囲と限界

- ヘッダーの8BPS、版、チャンネル数、幅・高さ、ビット深度、カラーモードを読み取る。ただし版・深度・モードの対応可否を検証しているとは言えない。LoadFromFileは各Boolean戻り値を検査していない。
- チャンネル展開の分岐は無圧縮0とRLE1のみ。ZIP2/3の展開分岐はない。画像はByte単位で、RGBとアルファを要求する描画処理がある。16/32bitやRGB以外の対応は確認できない。
- レイヤー名は従来名とluniのUnicode名、階層はlsctを読む。未知の追加情報は長さ分読み飛ばす。lspfも保持せず読み飛ばす。
- 画像リソースは$040Cサムネイル以外を読み飛ばすため、ICC等をそのまま再保存する材料はこのクラスからは得られない。
- レイヤーマスクの読み取りコードはあるが、FChannels[4]を前提とする部分がある。全マスク形式への対応や描画再現性は未確認。
- チャンネル位置・長さ等はInteger主体。PSBや大容量ファイルの対応は未確認。PSB対応とは扱わない。
- 基底RenderSubは末尾のレイヤーをスキップする条件がある。理由とサンプルへの影響は次段階で確認する。
- 合成画像領域を直接読み込む処理は、調査した基底LoadFromFileには見当たらず、レイヤーから再合成する。
- コアPsdImage*.pas群の検索ではSaveToFile/SaveToStream/WriteBufferが見当たらない。PSD書き出しを提供する構成としては確認できない。

以上は既存実装についての確認であり、PSD形式そのものの仕様・制約を示すものではない。

## 新しい読み書き設計へ引き継ぐ注意点

元PSDの生情報、PSDToolKit向け解釈、Customによる補正、描画キャッシュを別の情報として扱う必要がある。仮想ルートや補正した名前を元ファイル由来の情報として保存しない。
未知リソース・追加情報を保持する必要性、符号付き座標、境界・長さ・パディング、未対応圧縮の明示的な扱いを次段階で調べる。内部データ形式やGoogle API連携形式はまだ決めない。

参照実装のDestructorや未定義ブレンド関数には再検証を要する箇所があるが、既存プロジェクトの修正は本調査の対象外とする。既存コード全体の品質を保証した記録ではない。

## 第二段階への参照

2026-09-30にPSD仕様との照合を実施。第一段階時点の未確認項目に対する続きは[PSD解析_構造とサンプル.md](PSD解析_構造とサンプル.md)を参照する。末尾レイヤー除外は派生描画にも存在すること、不透明度・クリッピング・マスクを調査した描画処理が適用していないこと、ctAlphaコメントと実コードの極性が逆であることも同ファイルへ記録した。
