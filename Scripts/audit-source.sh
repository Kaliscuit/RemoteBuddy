#!/bin/zsh
set -euo pipefail
RB_ROOT="${0:A:h:h}"
cd "$RB_ROOT"
"${PYTHON_FOR_TESTS:-python3}" - <<'PY'
import pathlib, re, subprocess
root = pathlib.Path.cwd()
raw = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'])
paths = sorted(set(filter(None, raw.decode().split('\0'))))
errors = []
synthetic_addresses = {'AA:BB:CC:DD:EE:FF', '11:22:33:44:55:66'}
for name in paths:
    path = root / name
    if path.is_symlink():
        errors.append(f'Symlink requires review: {name}')
        continue
    if not path.is_file():
        continue
    if path.suffix.lower() in {'.pkg', '.dmg', '.pklg', '.pcap', '.pcapng', '.log', '.pem', '.p12'} or '.app/' in name:
        errors.append(f'Non-source artifact: {name}')
    if name.startswith(('work/', 'dist/', '.build/', 'PrivateDependencies/')) or (name.startswith('Dependencies/') and name not in {'Dependencies/README.md', 'Dependencies/README.zh-CN.md'}):
        errors.append(f'Local artifact tracked: {name}')
    if path.suffix.lower() in {'.png', '.icns'}:
        continue
    text = path.read_text(errors='replace')
    if re.search(r'/Users/(?!demo\b|test\b)[\w.-]+', text):
        errors.append(f'Machine-specific home path: {name}')
    for address in re.findall(r'\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b', text):
        if address.upper() not in synthetic_addresses:
            errors.append(f'Unexpected device address in: {name}')
    if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', text):
        errors.append(f'Private key: {name}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'Source audit passed: {len(paths)} files, no private artifacts or machine-specific identities.')
PY
