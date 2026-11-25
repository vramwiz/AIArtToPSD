"""Check saved folder channels and byte preservation independently of ArtPsd.

Usage: python verify_psd_compatibility.py OUTPUT_DIRECTORY ORIGINAL_PSD
Run PsdCompatibilitySmoke first. Only the standard library is required.
"""
import struct
import sys
from pathlib import Path


def parse(path):
    data = Path(path).read_bytes()

    def u32(offset):
        return struct.unpack_from('>I', data, offset)[0]

    pos = 26
    for _ in range(2):
        pos += 4 + u32(pos)
    prefix = data[:pos]
    layer_mask_end = pos + 4 + u32(pos)
    info_end = pos + 8 + u32(pos + 4)
    count = struct.unpack_from('>h', data, pos + 8)[0]
    pos += 10
    records = []
    for _ in range(abs(count)):
        start = pos
        channels = struct.unpack_from('>H', data, pos + 16)[0]
        entries = [struct.unpack_from('>hI', data, pos + 18 + i * 6)
                   for i in range(channels)]
        pos += 18 + channels * 6 + 12
        header = data[start:pos]
        extra = data[pos + 4:pos + 4 + u32(pos)]
        pos += 4 + len(extra)
        cursor = 0
        for _ in range(2):
            cursor += 4 + struct.unpack_from('>I', extra, cursor)[0]
        cursor += (extra[cursor] + 4) // 4 * 4
        kind = 0
        while len(extra) - cursor >= 12:
            key = extra[cursor + 4:cursor + 8]
            size = struct.unpack_from('>I', extra, cursor + 8)[0]
            if key in (b'lsct', b'lsdk'):
                kind = struct.unpack_from('>I', extra, cursor + 12)[0]
            cursor += 12 + size
        records.append(dict(header=header, extra=extra, kind=kind, entries=entries))
    for record in records:
        size = sum(length for _, length in record['entries'])
        record['pixels'] = data[pos:pos + size]
        pos += size
    assert pos <= info_end and not any(data[pos:info_end]), 'Layer info boundary/padding'
    return dict(prefix=prefix, count=count, records=records,
                tail=data[info_end:layer_mask_end], merged=data[layer_mask_end:])


def verify(folder, source):
    files = list(Path(folder).glob('*.psd'))
    assert len(files) == 9, 'Expected all nine smoke-test outputs'
    groups = 0
    for path in files:
        for record in parse(path)['records']:
            if record['kind'] in (1, 2, 3):
                assert record['entries'] == [(-1, 2), (0, 2), (1, 2), (2, 2)], path
                assert record['pixels'] == bytes(8), path
                groups += 1
    before = parse(source)
    after = parse(Path(folder) / 'legacy_unchanged.psd')
    for key in ('prefix', 'count', 'tail', 'merged'):
        assert before[key] == after[key], f'Changed archive {key}'
    assert len(before['records']) == len(after['records'])
    for old, new in zip(before['records'], after['records']):
        assert old['extra'] == new['extra'], 'Changed names, IDs, masks or additional metadata'
        if old['kind'] in (1, 2, 3) and not old['entries']:
            assert old['header'][:16] == new['header'][:16], 'Changed group bounds'
            assert old['header'][18:] == new['header'][42:], 'Changed group attributes'
        else:
            assert old['header'] == new['header'], 'Changed existing channel/header records'
            assert old['pixels'] == new['pixels'], 'Changed compressed channel bytes'
    assert (Path(folder) / 'new_1.psd').read_bytes() == (Path(folder) / 'unchanged.psd').read_bytes()
    print(f'PASS: {len(files)} PSDs, {groups} folder/divider records; original metadata and image bytes preserved')


if __name__ == '__main__':
    verify(sys.argv[1], sys.argv[2])
