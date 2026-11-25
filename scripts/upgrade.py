import sqlite3, pathlib, datetime, json, shutil, secrets

# 按实际安装目录修改
ROOT = pathlib.Path(r'D:\openlist')

backup = ROOT / 'backups' / datetime.datetime.now().strftime('pre-v4.2.6-%Y%m%d-%H%M%S')
backup.mkdir(parents=True, exist_ok=True)
c = sqlite3.connect(ROOT / 'data/data.db')
dest = sqlite3.connect(backup / 'data.db')
c.backup(dest)
dest.close()
shutil.copy2(ROOT / 'data/config.json', backup / 'config.json')

with c:
    updates = {
        'iframe_previews': json.dumps({'pdf': {'浏览器 PDF': '$url'}}, ensure_ascii=False),
        'video_autoplay': 'false',
        'audio_autoplay': 'false',
        'preview_archives_by_default': 'false',
        'site_title': '内网文件 · OpenList',
        'sign_all': 'true',
        'sign_expire': '1',
        'search_index': 'none',
    }
    for key, value in updates.items():
        c.execute('update x_setting_items set value=? where key=?', (value, key))
c.close()

cfg = json.loads((ROOT / 'data/config.json').read_text(encoding='utf-8-sig'))
cfg['jwt_secret'] = secrets.token_urlsafe(48)
cfg['token_expires_in'] = 24
(ROOT / 'data/config.json').write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding='utf-8')
downloaded_exe = ROOT / 'downloads/v4.2.6/openlist.exe'
if downloaded_exe.exists():
    shutil.copy2(downloaded_exe, ROOT / 'openlist.exe')
print('Security settings updated and JWT secret rotated; database snapshot saved.')
