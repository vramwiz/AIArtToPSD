"""Create reproducible inspection reports and independently check small merged images."""
import collections
import hashlib
import json
import struct
import sys
from pathlib import Path

from PIL import Image

sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
out = Path(__file__).parent / 'results'
samples = json.loads((out / 'samples.json').read_text(encoding='utf-8'))
ok = [s for s in samples if s['status'] == 'ok']
layers = [(s, l) for s in ok for l in s['layers']]
channels = [(s, l, c) for s, l in layers for c in l['channels']]

def counter(items):
    return dict(collections.Counter(items))

summary = dict(
    candidates=len(samples), parsed=len(ok), total_bytes=sum(s['size'] for s in samples),
    unique_psd_sha256=len(set(s['sha256'] for s in ok)),
    headers=counter(str(s['header']) for s in ok),
    layer_records=len(layers), channels=len(channels),
    layer_compression=counter(str(c.get('compression', 'none')) for _, _, c in channels),
    channel_validation=counter(c['validation'] for _, _, c in channels),
    merged_compression=counter(str(s['merged']['compression']) for s in ok),
    negative_layer_count=sum(s.get('signed_layer_count', 0) < 0 for s in ok),
    no_layer_info=sum(not s['layers'] for s in ok),
    section_types=counter(str(l['section_type']) for _, l in layers),
    blend_modes=counter(l['blend'] for _, l in layers),
    layer_tags=counter(t['key'] for _, l in layers for t in l['tags']),
    global_tags=counter(t['key'] for s in ok for t in s.get('global_tags', [])),
    resource_ids=counter(str(t['id']) for s in ok for t in s['resources']),
    channel_ids=counter(str(c['id']) for _, _, c in channels),
    negative_rect=sum(any(n < 0 for n in l['rect']) for _, l in layers),
    opacity_non255=sum(l['opacity'] != 255 for _, l in layers),
    clipping_nonzero=sum(l['clipping'] != 0 for _, l in layers),
    mask_records=sum(l['mask']['length'] != 0 for _, l in layers),
    odd_layer_tag_lengths=sum(t['length'] % 2 != 0 for _, l in layers for t in l['tags']),
    markers=counter(l['name'][0] for _, l in layers if l['name'] and l['name'][0] in '*!+'),
    warnings=[dict(path=s['relative_path'], warnings=s['warnings']) for s in ok if s['warnings']],
    excluded=[s for s in samples if s['status'] != 'ok'],
)
duplicates = collections.defaultdict(list)
for s in ok:
    duplicates[s['sha256']].append(s['relative_path'])
summary['duplicate_groups'] = {h: paths for h, paths in duplicates.items() if len(paths) > 1}

checks = []
for s in ok:
    if s['size'] > 100_000:
        continue
    check = dict(path=s['relative_path'])
    try:
        # Pillow's PSD decoder independently reads the original merged image.
        with Image.open(s['path']) as im:
            im.load()
            check.update(size=list(im.size), mode=im.mode,
                         rgb_sha256=hashlib.sha256(im.convert('RGB').tobytes()).hexdigest())
            preview_path = s['merged'].get('preview')
            if preview_path:
                with Image.open(preview_path) as preview:
                    check['matches_inspector_rgb'] = im.convert('RGB').tobytes() == preview.convert('RGB').tobytes()
                    check['matches_inspector_rgba'] = im.convert('RGBA').tobytes() == preview.convert('RGBA').tobytes()
    except Exception as exc:
        check['error'] = str(exc)
    checks.append(check)
summary['pillow_merged_checks'] = checks

# Additional evidence for files whose merged row lengths do not end at EOF.
for s in ok:
    expected = s['merged'].get('expected_end')
    if expected is not None and expected != s['size']:
        with open(s['path'], 'rb') as f:
            if expected <= s['size']:
                f.seek(expected)
                tail = f.read()
                s['merged']['tail_evidence'] = dict(length=len(tail), all_zero=not any(tail),
                                                    first64_hex=tail[:64].hex(), sha256=hashlib.sha256(tail).hexdigest())
        if s['merged']['compression'] == 1 and s['header']['depth'] == 8:
            from inspect_psd import Reader, unpack_bits
            h = s['header']
            with open(s['path'], 'rb') as f:
                f.seek(s['merged']['offset'] + 2)
                rr = Reader(f, s['size'])
                counts = [rr.number('H') for _ in range(h['height'] * h['channels'])]
                raw = b''.join(unpack_bits(rr.read(n), h['width']) for n in counts)
            plane_size = h['width'] * h['height']
            planes = [Image.frombytes('L', (h['width'], h['height']), raw[i * plane_size:(i + 1) * plane_size]) for i in range(3)]
            with Image.open(s['path']) as im:
                im.load()
                matches = im.convert('RGB').tobytes() == Image.merge('RGB', planes).tobytes()
            s['merged']['warning_check'] = dict(declared_rows_decode=True, rgb_matches_pillow=matches,
                                                trailing_data_unexplained=True)
            summary.setdefault('warning_checks', []).append(dict(path=s['relative_path'], **s['merged']['warning_check']))

(out / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
(out / 'samples.json').write_text(json.dumps(samples, ensure_ascii=False, indent=2), encoding='utf-8')

report = ['# PSDサンプル解析：ファイル別一覧', '',
          '2026-09-30。原本は変更せず解析。詳細のオフセット・名前・チャンネル情報は[samples.json](samples.json)、集計は[summary.json](summary.json)を参照。', '',
          '同じSHA-256のPSDは重複として集計できる。下表のレコード数はグループ境界を含み、画像レイヤー数とは異なる。', '',
          '| 相対パス | bytes | サイズ | レコード | signed count | 圧縮 | マスク | 警告 | SHA-256 |',
          '| --- | ---: | --- | ---: | ---: | --- | ---: | --- | --- |']
for s in samples:
    if s['status'] != 'ok':
        report.append(f"| {s['relative_path']} | {s['size']} | 対象外 | — | — | — | — | {s['error']} | {s['sha256']} |")
        continue
    h = s['header']
    compression = sorted(set(c.get('compression', -1) for l in s['layers'] for c in l['channels']))
    report.append(f"| {s['relative_path']} | {s['size']} | {h['width']}×{h['height']} | {len(s['layers'])} | {s.get('signed_layer_count', 0)} | {compression} / 合成{s['merged']['compression']} | {sum(l['mask']['length'] > 0 for l in s['layers'])} | {'; '.join(s['warnings'])} | {s['sha256']} |")
report += ['', '## 小さいサンプルのレコード順', '', '下表はファイル内の記録順。通常レイヤー0、グループ1/2、境界3。', '']
for s in ok:
    if s['size'] >= 100_000:
        continue
    report += [f"### {s['relative_path']}", '',
               f"領域：`{json.dumps(s['sections'], ensure_ascii=False)}`", '',
               '| index | 名前 | type | 矩形(top,left,bottom,right) | 表示 | 不透明度 | チャンネルID |',
               '| ---: | --- | ---: | --- | --- | ---: | --- |']
    for l in s['layers']:
        report.append(f"| {l['index']} | {l['name']} | {l['section_type']} | {l['rect']} | {l['visible']} | {l['opacity']} | {[c['id'] for c in l['channels']]} |")
    if not s['layers']:
        report.append('| — | レイヤー情報なし | — | — | — | — | — |')
    report.append('')
(out / 'PSD解析_ファイル別一覧.md').write_text('\n'.join(report) + '\n', encoding='utf-8-sig')
print(json.dumps({k: v for k, v in summary.items() if k not in ('headers', 'excluded', 'duplicate_groups', 'resource_ids')}, ensure_ascii=False, indent=2))
