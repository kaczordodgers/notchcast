#!/usr/bin/env python3
"""Generated archive fixtures and byte-for-byte checks for the Swift fallback harness."""

import bz2
import gzip
import io
import json
import lzma
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import unicodedata
import zipfile


class WindowsZipInfo(zipfile.ZipInfo):
    def _encodeFilenameFlags(self):
        return self.filename.encode('cp852'), self.flag_bits & ~0x800


def generate(root):
    source = root / 'source' / 'Folder'
    source.mkdir(parents=True, exist_ok=True)
    (source / 'hello.txt').write_bytes(b'Archive fallback contents\n')
    (source / 'notes link to self.txt').write_bytes(b'Ordinary filename\n')
    (source / 'zażółć gęślą jaźń.txt').write_bytes(b'Polish CP852 filename\n')
    (source / 'pchnąć w tę łódź jeża lub ośm skrzyń fig.txt').write_bytes(b'Encoding detection sample\n')
    for suffix, mode in [('tar.xz', 'w:xz'), ('tar.bz2', 'w:bz2'), ('tar', 'w')]:
        with tarfile.open(root / f'sample.{suffix}', mode) as archive:
            archive.add(source, arcname='Folder')
    payload = b'Plain stream contents\x00\xff\n'
    subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(source),
                    str(root / 'mac-polish.zip')], check=True)
    (root / 'plain-source').write_bytes(payload)
    for suffix, compress in [('gz', gzip.compress), ('xz', lzma.compress), ('bz2', bz2.compress)]:
        (root / f'plain.txt.{suffix}').write_bytes(compress(payload))
        (root / f'empty.txt.{suffix}').write_bytes(compress(b''))
    zstd = shutil.which('zstd') or '/opt/homebrew/bin/zstd'
    for name, source_file in [('plain.txt.zst', root / 'plain-source'), ('sample.tar.zst', root / 'sample.tar')]:
        subprocess.run([zstd, '-q', '-f', str(source_file), '-o', str(root / name)], check=True)
    subprocess.run(['/usr/bin/hdiutil', 'makehybrid', '-ov', '-iso', '-joliet', '-o', str(root / 'sample.iso'),
                    str(source.parent)], check=True)
    for name, encoding in [('windows.zip', 'cp852'), ('windows-1250.zip', 'cp1250')]:
        class EncodedZipInfo(WindowsZipInfo):
            def _encodeFilenameFlags(self):
                return self.filename.encode(encoding), self.flag_bits & ~0x800

        with zipfile.ZipFile(root / name, 'w') as archive:
            for path in source.iterdir():
                info = EncodedZipInfo('Folder/' + path.name)
                info.create_system = 0
                archive.writestr(info, path.read_bytes())
    for name, paths in [
        ('unsafe.tar.xz', ['../escaped.txt']),
        ('absolute.tar.bz2', ['/escaped.txt']),
        ('collision.tar.xz', ['A.txt', 'a.txt']),
        ('ancestor.tar.xz', ['link/child', 'link']),
    ]:
        with tarfile.open(root / name, 'w:bz2' if name.endswith('bz2') else 'w:xz') as archive:
            for path in paths:
                info = tarfile.TarInfo(path)
                if path == 'link':
                    info.type = tarfile.SYMTYPE
                    info.linkname = 'target'
                    archive.addfile(info)
                else:
                    info.size = 6
                    archive.addfile(info, io.BytesIO(b'unsafe'))
    with zipfile.ZipFile(root / 'unsafe-windows.zip', 'w') as archive:
        archive.writestr(WindowsZipInfo('../żółć.txt'), b'unsafe')
    with tarfile.open(root / 'unsafe.tar', 'w') as archive:
        info = tarfile.TarInfo('../escaped.txt')
        info.size = 6
        archive.addfile(info, io.BytesIO(b'unsafe'))
    subprocess.run([zstd, '-q', '-f', str(root / 'unsafe.tar'), '-o', str(root / 'unsafe.tar.zst')], check=True)
    print('PASS: generated tar.xz, tar.bz2, gz/xz/bz2, zst, tar.zst, ISO (hdiutil), raw CP852 ZIP and unsafe fixtures')


def contents(path):
    if path.is_file():
        return {'': path.read_bytes()}
    return {unicodedata.normalize('NFC', str(item.relative_to(path))): item.read_bytes()
            for item in path.rglob('*') if item.is_file()}


def verify(root):
    outputs = json.loads((root / 'outputs.json').read_text())
    for name, output in outputs.items():
        if name.startswith('empty.'):
            expected = {'': b''}
        elif name.startswith('plain.'):
            expected = contents(root / 'plain-source')
        else:
            expected = contents(root / 'source' / 'Folder')
        actual = contents(Path(output))
        assert actual == expected, f'{name}: different names or bytes: {actual.keys()} != {expected.keys()}'
        print(f'PASS: diff {name} vs source: identical names and bytes')
    print('PASS: CP852 Polish names preserved: zażółć gęślą jaźń.txt')


if __name__ == '__main__':
    sys.stderr = sys.stdout
    operation, directory = sys.argv[1:]
    root = Path(directory)
    if operation == 'generate':
        generate(root)
    elif operation == 'verify':
        verify(root)
    else:
        raise SystemExit('Expected generate or verify')
