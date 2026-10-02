# 前髪1パーツの分離再試験（2026-10-01）

この記録内のPSD・PNG・中間データ・作業スクリプトはローカル資料で、GitHubへの同期対象外。[資料の管理方針](../README.md)を参照。

確認対象は `front_hair_trial_v3.psd` と `comparison.png`。元画像は `../character_neutral.png`。元画像・既存PSD原本は変更していない。

## 現在の結果

元画像の座標と画素を使って、前髪候補11,632画素を分離した。キャンバスは1024×1536のまま。PSDの上から「前髪（可視部・試験）」「残り（未分離・補完なし）」「元画像（比較用・非表示）」の3レイヤー。通常表示は上の2枚で再合成する。

Python/Pillowの再合成、アプリのCoreでの合成、アプリのPSD保存・再読込後の合成で、元画像の可視RGBAと透明度の差は0。前髪のみ表示したPNGも切り抜きPNGの可視RGBAと一致。別実装の `Analysis/inspect_psd.py` でPSD構造・3レイヤーを確認し、警告なし。詳細は `verification.json` と `psd_inspection/structure.json`。

この一致は画素の分配と再合成の確認であり、前髪の意味的な境界が完全に正しいという判定ではない。全身の自動レイヤー分離は未達。

## 方法と残る制約

内蔵image_genで前髪の透明切り抜きを試したが、髪が拡大され、背景光が残ったため不採用。白黒マスク生成も試し、構造の参考にした。指示全文は `imagegen_prompts.json`、生成結果は `generated_fringe_rejected.png` と `generated_mask_reference.png`。

ユーザーの指示によりPythonの元画素切り抜きへ移行。元画像の拡大表示で前髪と後髪の分岐を判断し、専用の輪郭と寒色条件を `front_hair_mask.json` に記述。毛先には肌色が混ざっているため、寒色条件だけで短くなった毛先を輪郭指定で補正した。孤立した混入画素は連結成分で除外。前髪候補と残りへ排他的に画素を割り当て、重複する半透明画素による合成変化を避けた。

マスクはこの画像に対して手作業で調整した近似で、他画像への自動適用には使えない。細い毛束・毛先の境界はユーザーによる拡大確認が必要。毛先には元画像で既に混ざっている肌色や眉の線が含まれ、元画素維持と、肌色を含まない独立した髪の復元は別課題。前髪を隠すと透明な穴が開く。額・肌の補完は未実施。残りの画像には元の背景光も残る。

## 確認手順

AIArtToPSD.exeで `front_hair_trial_v3.psd` を開く。「残り」を非表示にすると前髪候補のみを確認できる。前髪と残りを非表示にし「元画像」を表示すると比較できる。位置を動かす必要はない。

次は毛先・こめかみ・前髪と後髪の境界を確認し、その後に額の補完を別工程として試す。目・口・衣装・手足への分離拡大は、この1パーツの品質確認後に進める。

## 再現と検証

`Tools/split_visible_part.py` はPillowとNumPyを使う。元画像のSHA-256と寸法を検査してから出力し、別画像のマスクの誤適用を拒否する。

```powershell
python Tools/split_visible_part.py Sample/character_neutral.png Sample/separation_trial_20261001/front_hair_mask.json Sample/separation_trial_20261001
```

`Tools/BuildVisiblePartPsd.dpr` はアプリのCore・PNG・PSDユニットを直接使う試験用CLI。PNG3枚からPSDを作成・再読込し、元画像と合成を照合する。既存の出力PSDへの上書きは拒否する。

```powershell
# Delphi環境を設定し、BuildVisiblePartPsd.dprojをWin64でビルドする。
Tools/Win64/Release/BuildVisiblePartPsd.exe Sample/character_neutral.png Sample/separation_trial_20261001/front_hair.png Sample/separation_trial_20261001/remainder.png Sample/separation_trial_20261001/new_trial.psd
```

アプリと試験CLIのWin64 Debug／Release Rebuildは警告0・エラー0。両構成でPSD保存・再読込後の可視画素・透明度の一致を確認。アプリ本体のロジックは変更していない。実画面での目視操作、PSDToolKit実ホスト、過去の全回帰試験はこの再試験では未実施。
