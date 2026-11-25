import urllib.request, concurrent.futures, hashlib, time, zipfile
from pathlib import Path

# 按实际安装目录修改
ROOT = Path(r'D:\openlist\downloads')
ROOT.mkdir(parents=True, exist_ok=True)

url = 'https://github.com/OpenListTeam/OpenList/releases/download/v4.2.6/openlist-windows-amd64.zip'
expected = '10d24913f86843e347eefac219c61224628bbd5d3c7443b2ee119c168a8cb3b9'

with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=25) as r:
    size = int(r.headers['Content-Length'])
    final = r.url
print('Official download size:', size, flush=True)

chunk = 2 * 1024 * 1024

def fetch(i):
    start = i * chunk
    end = min(size - 1, start + chunk - 1)
    part = ROOT / f'v4.2.6.part{i}'
    if part.exists() and part.stat().st_size == end - start + 1:
        return part
    for attempt in range(8):
        try:
            req = urllib.request.Request(final, headers={'Range': f'bytes={start}-{end}'})
            with urllib.request.urlopen(req, timeout=30) as r:
                if r.status != 206:
                    raise ValueError('Range unsupported')
                data = r.read()
            if len(data) != end - start + 1:
                raise ValueError('Incomplete range')
            part.write_bytes(data)
            print('Downloaded chunk', i + 1, flush=True)
            return part
        except Exception:
            if attempt == 7:
                raise RuntimeError('Official download range failed') from None
            time.sleep(2)

count = (size + chunk - 1) // chunk
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    parts = list(pool.map(fetch, range(count)))

out = ROOT / 'openlist-v4.2.6-verified.zip'
with out.open('wb') as f:
    for p in parts:
        f.write(p.read_bytes())

actual = hashlib.sha256(out.read_bytes()).hexdigest()
if actual != expected:
    raise RuntimeError('Official SHA256 mismatch')

with zipfile.ZipFile(out) as z:
    z.extractall(ROOT / 'v4.2.6')
print('Official SHA256 verified:', actual, flush=True)
