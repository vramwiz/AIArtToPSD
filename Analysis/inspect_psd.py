"""Read-only PSD structure inspection. No application code or PSD is modified.

Usage: python Analysis/inspect_psd.py SOURCE_DIRECTORY OUTPUT_DIRECTORY
Standard library only; Pillow is optional for small merged-image PNG previews.
"""
import collections
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path


class Reader:
    def __init__(self, f, end):
        self.f, self.end = f, end

    @property
    def pos(self):
        return self.f.tell()

    def read(self, n):
        if n < 0 or self.pos + n > self.end:
            raise ValueError(f"boundary exceeded: {self.pos}+{n}>{self.end}")
        b = self.f.read(n)
        if len(b) != n:
            raise ValueError("short read")
        return b

    def number(self, fmt):
        return struct.unpack('>' + fmt, self.read(struct.calcsize('>' + fmt)))[0]

    def skip(self, n):
        if n < 0 or self.pos + n > self.end:
            raise ValueError("skip boundary exceeded")
        self.f.seek(n, 1)


def text4(b):
    return b.decode('ascii', errors='backslashreplace')


def pascal(r, padding):
    n = r.number('B')
    b = r.read(n)
    r.skip(-(n + 1) % padding)
    return b


def tagged(r, padding):
    result = []
    while r.pos < r.end:
        start = r.pos
        if r.end - start < 12:
            tail = r.read(r.end - start)
            if any(tail):
                raise ValueError(f"nonzero tagged tail at {start}: {tail.hex()}")
            break
        sig, key = r.read(4), r.read(4)
        if sig not in (b'8BIM', b'8B64'):
            raise ValueError(f"tag signature at {start}: {sig!r}")
        n = r.number('I')  # PSD v1 only; PSB is explicitly rejected.
        data_start = r.pos
        data = r.read(n)
        item = dict(offset=start, signature=text4(sig), key=text4(key), length=n)
        if key == b'luni' and n >= 4:
            count = struct.unpack('>I', data[:4])[0]
            if count * 2 + 4 > n:
                raise ValueError("Unicode name length exceeds block")
            item['name'] = data[4:4 + count * 2].decode('utf-16-be')
        if key in (b'lsct', b'lsdk') and n >= 4:
            item['section_type'] = struct.unpack('>I', data[:4])[0]
        if key == b'lyid' and n >= 4:
            item['layer_id'] = struct.unpack('>I', data[:4])[0]
        r.skip(-n % padding)
        item['end'] = r.pos
        result.append(item)
    return result


def unpack_bits(data, expected):
    out = bytearray()
    i = 0
    while i < len(data):
        n = data[i]
        i += 1
        if n < 128:
            count = n + 1
            if i + count > len(data):
                raise ValueError("PackBits literal truncated")
            out.extend(data[i:i + count])
            i += count
        elif n > 128:
            if i == len(data):
                raise ValueError("PackBits repeat truncated")
            out.extend(bytes([data[i]]) * (257 - n))
            i += 1
        if len(out) > expected:
            raise ValueError("PackBits output exceeds row width")
    if len(out) != expected:
        raise ValueError(f"PackBits row size {len(out)} != {expected}")
    return bytes(out)


def channel(r, w, h, depth, decode):
    start = r.pos
    compression = r.number('H')
    result = dict(offset=start, end=r.end, compression=compression)
    row_bytes = (w * depth + 7) // 8
    if not decode:
        if w < 0 or h < 0:
            raise ValueError('negative channel dimensions')
        if compression == 0:
            result['expected_end'] = r.pos + row_bytes * h
            if result['expected_end'] != r.end:
                raise ValueError('Raw channel length mismatch')
            result['validation'] = 'raw-size-checked'
        elif compression == 1:
            sizes = [r.number('H') for _ in range(h)]
            result['row_lengths_sum'] = sum(sizes)
            if r.pos + sum(sizes) != r.end:
                raise ValueError('RLE channel length table mismatch')
            result['validation'] = 'rle-length-table-checked'
        else:
            result['validation'] = 'structure-only'
        r.skip(r.end - r.pos)
        return result, None
    raw = None
    if compression == 0:
        raw = r.read(row_bytes * h)
    elif compression == 1:
        sizes = [r.number('H') for _ in range(h)]
        raw = b''.join(unpack_bits(r.read(n), row_bytes) for n in sizes)
        result['row_lengths_sum'] = sum(sizes)
    elif compression in (2, 3):
        compressed = r.read(r.end - r.pos)
        inflater = zlib.decompressobj()
        raw = inflater.decompress(compressed) + inflater.flush()
        if not inflater.eof or inflater.unused_data:
            raise ValueError("ZIP stream incomplete or trailing data")
        if len(raw) != row_bytes * h:
            raise ValueError("ZIP expanded size mismatch")
        # Prediction reversal only for the 8-bit inspection target.
        if compression == 3 and depth == 8:
            raw = bytearray(raw)
            for y in range(h):
                for x in range(1, row_bytes):
                    p = y * row_bytes + x
                    raw[p] = (raw[p] + raw[p - 1]) & 255
            raw = bytes(raw)
        elif compression == 3:
            result['prediction'] = 'not reversed (non-8bit)'
    else:
        raise ValueError(f"unsupported compression {compression}")
    trailing = r.end - r.pos
    if trailing:
        tail = r.read(trailing)
        result['trailing_bytes'] = trailing
        if any(tail):
            raise ValueError("nonzero channel trailing bytes")
    result.update(validation='decoded-size-checked', expanded_bytes=len(raw),
                  expanded_sha256=hashlib.sha256(raw).hexdigest())
    return result, raw


def inspect(path, root, out):
    size = path.stat().st_size
    with path.open('rb') as f:
        digest = hashlib.file_digest(f, 'sha256').hexdigest()
    result = dict(path=str(path), relative_path=str(path.relative_to(root)), size=size,
                  sha256=digest, status='ok', warnings=[])
    # Decode bounded small files; all files receive full structural inspection.
    decode = size <= 5_000_000
    with path.open('rb') as f:
        r = Reader(f, size)
        if r.read(4) != b'8BPS':
            raise ValueError("not a PSD")
        version = r.number('H')
        if version != 1:
            raise ValueError(f"unsupported version {version}")
        reserved = r.read(6)
        channels, height, width, depth, mode = [r.number(k) for k in ('H', 'I', 'I', 'H', 'H')]
        result['header'] = dict(version=version, channels=channels, width=width,
                                height=height, depth=depth, color_mode=mode,
                                reserved_zero=not any(reserved))
        decode = decode and depth == 8 and mode == 3 and width * height <= 16_000_000
        sections = result['sections'] = []
        layers = result['layers'] = []
        resources = result['resources'] = []
        for section in ('color_mode', 'resources', 'layer_mask'):
            offset = r.pos
            length = r.number('I')
            start, end = r.pos, r.pos + length
            if end > size:
                raise ValueError(f"{section} outside file")
            sections.append(dict(kind=section, offset=offset, payload_start=start,
                                 end=end, length=length))
            sub = Reader(f, end)
            if section == 'resources':
                while sub.pos < end:
                    off = sub.pos
                    sig = sub.read(4)
                    if sig != b'8BIM':
                        raise ValueError(f"resource signature {sig!r} at {off}")
                    rid = sub.number('H')
                    name = pascal(sub, 2)
                    n = sub.number('I')
                    data_start = sub.pos
                    sub.skip(n)
                    sub.skip(-n % 2)
                    resources.append(dict(offset=off, id=rid, name_hex=name.hex(),
                                          data_start=data_start, length=n, end=sub.pos))
            elif section == 'layer_mask' and length:
                info_offset = sub.pos
                n = sub.number('I')
                info_start, info_end = sub.pos, sub.pos + n
                if info_end > end:
                    raise ValueError("layer info outside layer-mask")
                result['layer_info'] = dict(offset=info_offset, payload_start=info_start,
                                            end=info_end, length=n)
                if n:
                    lr = Reader(f, info_end)
                    signed_count = lr.number('h')
                    result['signed_layer_count'] = signed_count
                    for index in range(abs(signed_count)):
                        rec_start = lr.pos
                        rect = [lr.number('i') for _ in range(4)]
                        nc = lr.number('H')
                        cs = [dict(id=lr.number('h'), length=lr.number('I')) for _ in range(nc)]
                        if lr.read(4) != b'8BIM':
                            raise ValueError("blend signature")
                        blend = text4(lr.read(4))
                        opacity, clipping, flags, filler = [lr.number('B') for _ in range(4)]
                        extra_len = lr.number('I')
                        extra_end = lr.pos + extra_len
                        if extra_end > info_end:
                            raise ValueError("extra outside layer info")
                        er = Reader(f, extra_end)
                        mn = er.number('I')
                        mask_bytes = er.read(mn)
                        mask = dict(length=mn)
                        if mn >= 18:
                            mask.update(rect=list(struct.unpack('>4i', mask_bytes[:16])),
                                        default_color=mask_bytes[16], flags=mask_bytes[17])
                        bn = er.number('I')
                        er.skip(bn)
                        legacy = pascal(er, 4)
                        tags = tagged(er, 1)
                        name = next((t['name'] for t in tags if 'name' in t), None)
                        if name is None:
                            name = legacy.decode('cp932', errors='replace')
                        typ = next((t['section_type'] for t in tags if 'section_type' in t), 0)
                        layers.append(dict(index=index, offset=rec_start, end=lr.pos, rect=rect,
                                           name=name, legacy_hex=legacy.hex(), section_type=typ,
                                           blend=blend, opacity=opacity, clipping=clipping,
                                           flags=flags, visible=not bool(flags & 2), mask=mask,
                                           blending_ranges_length=bn, channels=cs, tags=tags))
                    for layer in layers:
                        top, left, bottom, right = layer['rect']
                        for c in layer['channels']:
                            cr_end = lr.pos + c['length']
                            if cr_end > info_end:
                                raise ValueError("channel outside layer info")
                            rect = layer['mask'].get('rect', layer['rect']) if c['id'] == -2 else layer['rect']
                            t, l, b, rr = rect
                            if c['id'] == -3:
                                c.update(offset=lr.pos, end=cr_end, validation='real-mask-structure-only')
                                lr.skip(c['length'])
                                continue
                            if c['length'] < 2:
                                c.update(offset=lr.pos, end=cr_end, validation='empty-no-compression')
                                lr.skip(c['length'])
                                continue
                            meta, _ = channel(Reader(f, cr_end), rr - l, b - t, depth, decode)
                            c.update(meta)
                    leftover = lr.read(info_end - lr.pos)
                    result['layer_info']['trailing_bytes'] = len(leftover)
                    result['layer_info']['trailing_zero'] = not any(leftover)
                    if any(leftover):
                        result['warnings'].append('nonzero layer-info trailing bytes')
                f.seek(info_end)
                if end - f.tell() >= 4:
                    glen = sub.number('I')
                    result['global_mask_length'] = glen
                    sub.skip(glen)
                result['global_tags'] = tagged(sub, 4)
            f.seek(end)
        # Structure of merged image. Do not confuse this with layer image data.
        merged_start = r.pos
        compression = r.number('H')
        result['merged'] = dict(offset=merged_start, end=size, compression=compression)
        if compression == 1:
            counts = [r.number('H') for _ in range(height * channels)]
            result['merged'].update(row_count=len(counts), encoded_bytes=sum(counts),
                                    payload_start=r.pos, expected_end=r.pos + sum(counts))
            if r.pos + sum(counts) != size:
                result['warnings'].append('merged RLE lengths do not end at EOF')
            if decode:
                raw = b''.join(unpack_bits(r.read(n), width) for n in counts)
            else:
                raw = None
        elif compression == 0:
            expected = ((width * depth + 7) // 8) * height * channels
            result['merged']['expected_end'] = r.pos + expected
            if r.pos + expected != size:
                result['warnings'].append('merged Raw size does not end at EOF')
            raw = r.read(expected) if decode else None
        else:
            raw = None
            result['merged']['validation'] = 'ZIP-structure-only'
        if raw is not None:
            result['merged'].update(validation='decoded-size-checked', expanded_bytes=len(raw),
                                    expanded_sha256=hashlib.sha256(raw).hexdigest())
            if mode == 3 and channels in (3, 4):
                try:
                    from PIL import Image
                    plane_size = width * height
                    planes = [Image.frombytes('L', (width, height), raw[i * plane_size:(i + 1) * plane_size]) for i in range(channels)]
                    img = Image.merge('RGBA' if channels == 4 else 'RGB', planes)
                    if max(img.size) > 1600:
                        img.thumbnail((1600, 1600))
                    preview = out / 'previews' / (digest[:16] + '.png')
                    preview.parent.mkdir(exist_ok=True)
                    img.save(preview)
                    result['merged']['preview'] = str(preview)
                    result['merged']['preview_note'] = 'raw planes; no ICC transform; fourth plane treated as alpha provisionally'
                except ImportError:
                    pass
        # Derive hierarchy in stored order; group order is recorded without rewriting.
        stack = []
        for layer in layers:
            if layer['section_type'] == 3:
                stack.append(layer['index'])
                layer['depth'] = len(stack) - 1
            elif layer['section_type'] in (1, 2):
                layer['depth'] = max(0, len(stack) - 1)
                if stack:
                    layer['group_boundary_index'] = stack.pop()
                else:
                    result['warnings'].append('group closing without boundary')
            else:
                layer['depth'] = len(stack)
        if stack:
            result['warnings'].append('unclosed group boundaries')
        result['decode_selected'] = decode
    return result


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='backslashreplace')
    root, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    paths = sorted(root.rglob('*.psd'), key=lambda p: (p.stat().st_size, str(p)))
    results = []
    for index, path in enumerate(paths):
        try:
            result = inspect(path, root, out)
        except Exception as exc:
            result = dict(path=str(path), relative_path=str(path.relative_to(root)),
                          size=path.stat().st_size, status='error', error=str(exc))
            with path.open('rb') as f:
                result['sha256'] = hashlib.file_digest(f, 'sha256').hexdigest()
        results.append(result)
        if (index + 1) % 10 == 0 or index + 1 == len(paths):
            (out / 'samples.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f"{index + 1}/{len(paths)} {result['status']} {path.name}", flush=True)
    print(json.dumps(dict(total=len(results), ok=sum(r['status'] == 'ok' for r in results),
                          errors=[(r['relative_path'], r['error']) for r in results if r['status'] != 'ok']), ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
