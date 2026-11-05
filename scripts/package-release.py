"""Package BitBird GBA and matching source from a clean source commit.
SPDX-License-Identifier: GPL-3.0-only
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parent.parent
read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True, help='Fresh directory; never overwrites a prior bundle')
    p.add_argument('--repository-url', help='Approved source repository URL; omitted for local-only review')
    args = p.parse_args()
    out = args.output.resolve()
    require(not out.exists(), 'Output already exists; choose a fresh directory')
    require(not ROOT.is_relative_to(out), 'Output cannot contain the source repository')
    require(not out.is_relative_to(ROOT) or out.is_relative_to(ROOT / 'build'), 'In-repository output must be under build/')
    require(not git('status', '--porcelain'), 'Commit or separately preserve working changes before packaging')
    manifest = read(ROOT / 'docs/candidate-manifest.json')
    for row in manifest['files']:
        require(sha(ROOT / row['path']) == row['sha256'], 'Input hash changed: ' + row['path'])
    core = read(ROOT / 'pocket/Cores/BitBird.GBA/core.json')['core']
    require(core['metadata']['version'] == '0.1.0', 'Expected release version 0.1.0')
    require(core['metadata']['author'] == 'BitBird' and core['metadata']['shortname'] == 'GBA', 'Core identity differs')
    source_commit = git('rev-parse', 'HEAD')
    out.mkdir(parents=True)
    receipt = dict(status='PREPARING', version='0.1.0', source_commit=source_commit,
                   published=False, installed=False, new_hardware_test=False, image_changed=False,
                   release_approved=False, repository_url=args.repository_url)
    def save():
        (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    save()
    try:
        package = out / 'package'
        shutil.copytree(ROOT / 'pocket', package)
        (package / 'manifest.json').unlink()
        if args.repository_url:
            require(args.repository_url.startswith('https://github.com/'), 'Expected an approved HTTPS GitHub repository URL')
            metadata = read(package / 'Cores/BitBird.GBA/core.json')
            metadata['core']['metadata']['url'] = args.repository_url.rstrip('/')
            (package / 'Cores/BitBird.GBA/core.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        for name in ('LICENSE', 'LICENSE-SCOPE.md', 'THIRD_PARTY_NOTICES.md'):
            shutil.copyfile(ROOT / name, package / name)
        (package / 'docs').mkdir()
        for name in ('installation.md', 'known-issues.md', 'build.md',
                     'build-validation.md', 'build-validation-receipt.json',
                     'source-attribution-inventory.json'):
            shutil.copyfile(ROOT / 'docs' / name, package / 'docs' / name)
        shutil.copyfile(ROOT / 'docs/package-readme.md', package / 'README.md')
        credits = (ROOT / 'README.md').read_text(encoding='utf-8-sig').split('## Credits and acknowledgements', 1)[1].split('## License', 1)[0]
        (package / 'CREDITS.md').write_text('# Credits and acknowledgements\n' + credits, encoding='utf-8')
        (package / 'Assets/gba/common').mkdir(parents=True)
        source_name = 'BitBird.GBA_0.1.0-source.zip'
        source_description = f'''# Corresponding source

Version: 0.1.0
Source commit: {source_commit}
Source archive supplied beside this package: {source_name}

The archive is an export of that exact source commit, including build scripts,
constraints, third-party notices and installation/build documentation. See
docs/build.md. The standalone build reproduces the included FPGA image exactly.
'''
        source_description += ('\nSource repository: ' + args.repository_url + '\n') if args.repository_url else '\nNo source URL was supplied; use the matching source archive and recorded source commit.\n'
        (package / 'SOURCE.md').write_text(source_description, encoding='utf-8')
        image = package / 'Cores/BitBird.GBA/bitstream.rbf_r'
        require(sha(image) == manifest['image_sha256'], 'FPGA image changed')
        package_manifest = [{'path': f.relative_to(package).as_posix(), 'sha256': sha(f)}
                            for f in sorted(package.rglob('*')) if f.is_file()]
        (package / 'manifest.json').write_text(json.dumps(package_manifest, indent=2) + '\n', encoding='utf-8')
        archive = out / 'BitBird.GBA_0.1.0.zip'
        with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as z:
            z.writestr('Assets/gba/common/', b'')
            for f in sorted(package.rglob('*')):
                if f.is_file():
                    z.write(f, f.relative_to(package).as_posix())
        expected = {f.relative_to(package).as_posix(): sha(f) for f in package.rglob('*') if f.is_file()}
        with zipfile.ZipFile(archive) as z:
            entries = [i for i in z.infolist() if not i.is_dir()]
            require(len(entries) == len(expected), 'Archive entry count differs')
            require(len({i.filename for i in entries}) == len(entries), 'Duplicate archive entries')
            for i in entries:
                require(i.filename in expected and hashlib.sha256(z.read(i)).hexdigest() == expected[i.filename], 'ZIP readback differs: ' + i.filename)
        source = out / source_name
        subprocess.run(['git', '-C', str(ROOT), 'archive', '--format=zip', '--output', str(source), source_commit], check=True)
        with zipfile.ZipFile(source) as z:
            for row in manifest['files']:
                require(hashlib.sha256(z.read(row['path'])).hexdigest() == row['sha256'], 'Source export differs: ' + row['path'])
            for name in ('scripts/build.py', 'scripts/package-release.py', 'docs/build.md', 'docs/installation.md', 'LICENSE', 'LICENSE-SCOPE.md'):
                committed = subprocess.check_output(['git', '-C', str(ROOT), 'show', f'{source_commit}:{name}'])
                require(z.read(name) == committed, 'Source export missing required file: ' + name)
        sums = ''.join(sha(f) + '  ' + f.name + '\n' for f in (archive, source))
        (out / 'SHA256SUMS.txt').write_text(sums, encoding='utf-8')
        receipt.update(status='PASS', image_sha256=sha(image), verified_package_files=len(expected),
                       archive=dict(path=archive.name, sha256=sha(archive)),
                       corresponding_source=dict(path=source.name, sha256=sha(source)),
                       remaining_review=['Owner approval', 'Public repository creation and actual publication date', 'Final publication content review'])
        save()
        print(f'PASS: verified 0.1.0 package and matching source export, unchanged FPGA image; {out}', flush=True)
    except Exception as error:
        receipt.update(status='FAILED', error=str(error))
        save()
        raise


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('FAILED: ' + str(error), file=sys.stderr)
        sys.exit(1)
