import sys, json, urllib.request, urllib.parse, urllib.error, base64, pathlib, hashlib, ctypes
from PIL import Image, ImageDraw
from reportlab.pdfgen import canvas

# 按实际安装目录和监听 IP 修改
ROOT = pathlib.Path(r'D:\openlist')
BASE_URL = 'http://192.168.1.100:5244'

fixture = ROOT / 'maintenance' / 'test-files'
fixture.mkdir(exist_ok=True)
credentials = json.load(sys.stdin)
checks = []
local_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

def req(path, method='GET', data=None, token=None, headers=None):
    h = headers or {}
    if token:
        h['Authorization'] = token
    if isinstance(data, dict):
        data = json.dumps(data).encode()
        h['Content-Type'] = 'application/json'
    r = urllib.request.Request(BASE_URL + path, data=data, headers=h, method=method)
    try:
        with local_opener.open(r, timeout=15) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()

def api(path, data=None, token=None):
    status, headers, body = req(path, 'POST' if data is not None else 'GET', data, token)
    return json.loads(body)

def record(name, ok, detail=''):
    checks.append(dict(test=name, passed=bool(ok), detail=detail))
    print(name, ':', 'PASS' if ok else 'FAIL', detail, flush=True)

def login(name):
    r = api('/api/auth/login', dict(username=name, password=credentials[name]))
    if r.get('code') != 200:
        raise RuntimeError('Login failed for ' + name)
    return r['data']['token']

admin = login('admin')
reader = login('reader')
record('admin and reader login', True)

if 'setup' in sys.argv:
    im = Image.new('RGB', (640, 360), (225, 235, 245))
    ImageDraw.Draw(im).text((60, 160), 'OpenList LAN read-only preview test', fill=(0, 0, 0))
    im.save(fixture / '图片预览.png')
    pdf = canvas.Canvas(str(fixture / 'PDF预览.pdf'))
    pdf.drawString(80, 750, 'OpenList LAN PDF preview test')
    pdf.save()
    nested = fixture / '中文目录' / '第二层' / '第三层'
    nested.mkdir(parents=True, exist_ok=True)
    (nested / '中文文件名.txt').write_text('只读访问与下载测试\n', encoding='utf-8')
    (fixture / '下载校验.bin').write_bytes(bytes(range(256)) * 256)
    large = fixture / '大文件_5GiB_稀疏测试.bin'
    if not large.exists() or large.stat().st_size != 5 * 1024**3:
        with large.open('wb') as f:
            import msvcrt
            returned = ctypes.c_ulong()
            if not ctypes.windll.kernel32.DeviceIoControl(msvcrt.get_osfhandle(f.fileno()), 0x900C4, None, 0, None, 0, ctypes.byref(returned), None):
                raise RuntimeError('Sparse flag failed')
            f.write(b'OPENLIST-LARGE-FILE')
            f.seek(5 * 1024**3 - 16)
            f.write(b'END-LARGE-FILEOK')
    for mount, folder in [('/内网文件/连接测试', fixture), ('/内网文件/多目录测试', nested)]:
        result = api('/api/admin/storage/list?page=1&per_page=100', token=admin)
        if mount not in [x['mount_path'] for x in result['data']['content']]:
            storage = dict(
                mount_path=mount,
                driver='Local',
                cache_expiration=10,
                disabled=False,
                disable_index=True,
                enable_sign=True,
                web_proxy=True,
                webdav_policy='native_proxy',
                order_by='name',
                order_direction='asc',
                extract_folder='front',
                addition=json.dumps(dict(root_folder_path=str(folder), thumbnail=False, directory_size=False, show_hidden=False)),
                remark='仅新建验证文件；未共享用户磁盘',
            )
            r = api('/api/admin/storage/create', storage, admin)
            if r['code'] != 200:
                raise RuntimeError('Test storage creation failed: ' + r.get('message', ''))
    current = api('/api/admin/setting/list', token=admin)
    settings = current.get('data', [])
    if isinstance(settings, dict):
        settings = settings.get('content', [])
    (ROOT / 'maintenance' / 'settings-summary.json').write_text(
        json.dumps([{'key': x.get('key'), 'value': x.get('value')} for x in settings if x.get('key') in ['sign_all', 'sign_expire', 'iframe_previews', 'preview_archives', 'video_autoplay', 'search_index', 'site_title']], ensure_ascii=False, indent=2),
        encoding='utf-8',
    )

anonymous = api('/api/fs/list', {'path': '/', 'password': '', 'page': 1, 'per_page': 100})
record('anonymous listing denied', anonymous['code'] in (401, 403), str(anonymous['code']))

me = api('/api/me', token=reader)
record('reader minimal permissions', me['data']['permission'] == 256 and me['data']['base_path'] == '/内网文件')

listing = api('/api/fs/list', {'path': '/', 'password': '', 'page': 1, 'per_page': 100}, reader)
names = [x['name'] for x in listing.get('data', {}).get('content', []) or []]
record('multiple virtual directories', set(['连接测试', '多目录测试']).issubset(names), ', '.join(names))

deep = api('/api/fs/list', {'path': '/连接测试/中文目录/第二层/第三层', 'password': ''}, reader)
record('Chinese names and nested directories', any(x['name'] == '中文文件名.txt' for x in deep.get('data', {}).get('content', []) or []))

escape = api('/api/fs/list', {'path': '/../', 'password': ''}, reader)
record('reader confined to approved root', escape.get('code') != 200 or not any(x['name'] not in names for x in (escape.get('data') or {}).get('content', []) or []))

def download(path, local, range_=None):
    obj = api('/api/fs/get', {'path': path, 'password': ''}, reader)
    if obj['code'] != 200:
        return False, 'get failed'
    raw = obj['data']['raw_url']
    if obj['data'].get('sign') and 'sign=' not in raw:
        raw += ('&' if '?' in raw else '?') + 'sign=' + urllib.parse.quote(obj['data']['sign'])
    headers = {}
    if range_:
        headers['Range'] = range_
    try:
        with local_opener.open(urllib.request.Request(raw, headers=headers), timeout=20) as r:
            status = r.status
            h = r.headers
            b = r.read()
    except urllib.error.HTTPError as e:
        return False, str(e.code)
    if range_:
        return status == 206 and len(b) == 16 and b == b'END-LARGE-FILEOK', str(status) + ' ' + str(h.get('Content-Range'))
    return hashlib.sha256(b).digest() == hashlib.sha256(local.read_bytes()).digest(), str(status) + ' ' + str(h.get('Content-Type'))

for name in ['下载校验.bin', '图片预览.png', 'PDF预览.pdf']:
    if (fixture / name).exists():
        ok, detail = download('/连接测试/' + name, fixture / name)
        record('download ' + name, ok, detail)

if (fixture / '大文件_5GiB_稀疏测试.bin').exists():
    ok, detail = download('/连接测试/大文件_5GiB_稀疏测试.bin', fixture / '大文件_5GiB_稀疏测试.bin', f'bytes={5*1024**3-16}-{5*1024**3-1}')
    record('5 GiB range beyond 4 GiB', ok, detail)

unsigned = '/d/' + urllib.parse.quote('内网文件/连接测试/图片预览.png')
s, _, _ = req(unsigned)
record('unsigned direct download denied', s in (401, 403), str(s))

for endpoint, payload in [
    ('mkdir', {'path': '/连接测试/禁止创建'}),
    ('rename', {'path': '/连接测试/下载校验.bin', 'name': '禁止重命名.bin'}),
    ('remove', {'dir': '/连接测试', 'names': ['下载校验.bin']}),
    ('move', {'src_dir': '/连接测试', 'dst_dir': '/多目录测试', 'names': ['下载校验.bin']}),
    ('copy', {'src_dir': '/连接测试', 'dst_dir': '/多目录测试', 'names': ['下载校验.bin']}),
]:
    r = api('/api/fs/' + endpoint, payload, reader)
    record('reader ' + endpoint + ' denied', r['code'] in (401, 403), str(r['code']))

s, h, b = req('/api/fs/put', 'PUT', b'upload prohibited', reader, {'File-Path': urllib.parse.quote('/连接测试/禁止上传.txt'), 'Content-Type': 'application/octet-stream'})
try:
    code = json.loads(b)['code']
except Exception:
    code = s
record('reader upload denied', code in (401, 403), str(code))

davheaders = {'Authorization': 'Basic ' + base64.b64encode(('reader:' + credentials['reader']).encode()).decode()}
s, h, b = req('/dav/', 'PROPFIND', headers=dict(davheaders, Depth='1'))
record('WebDAV read list', s == 207, str(s))

path = '/dav/' + urllib.parse.quote('连接测试/下载校验.bin')
s, h, b = req(path, headers=davheaders)
record('WebDAV download', s == 200 and b == (fixture / '下载校验.bin').read_bytes(), str(s))

s, h, b = req('/dav/', 'PROPFIND', headers={'Depth': '1'})
record('anonymous WebDAV denied', s in (401, 403), str(s))

for method in ['PUT', 'DELETE', 'MOVE', 'COPY', 'MKCOL', 'PROPPATCH']:
    target = path if method in ['DELETE', 'MOVE', 'COPY', 'PROPPATCH'] else '/dav/' + urllib.parse.quote('连接测试/禁止WebDAV写入')
    hdr = dict(davheaders)
    if method in ['MOVE', 'COPY']:
        hdr['Destination'] = BASE_URL + '/dav/' + urllib.parse.quote('多目录测试/禁止写入.bin')
    s, h, b = req(target, method, b'prohibited' if method == 'PUT' else None, headers=hdr)
    record('WebDAV ' + method + ' denied', s in (401, 403, 405), str(s))

(ROOT / 'maintenance' / 'validation.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2), encoding='utf-8')
sys.exit(0 if all(x['passed'] for x in checks) else 1)
