import json, sqlite3, shutil, pathlib, datetime

# 按实际安装目录和监听 IP 修改
ROOT = pathlib.Path(r'D:\openlist')
LAN_IP = '192.168.1.100'

backup = ROOT / 'backups' / datetime.datetime.now().strftime('before-lan-%Y%m%d-%H%M%S')
backup.mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / 'openlist.exe', backup / 'openlist.exe')
shutil.copy2(ROOT / 'data/config.json', backup / 'config.json')
src = sqlite3.connect(ROOT / 'data/data.db')
dst = sqlite3.connect(backup / 'data.db')
src.backup(dst)
dst.close()
src.execute('update x_users set disabled=1, permission=0 where role=1')
src.commit()
src.close()

cfg = json.loads((ROOT / 'data/config.json').read_text(encoding='utf-8-sig'))
cfg['force'] = True
cfg['scheme']['address'] = LAN_IP
cfg['scheme']['http_port'] = 5244
cfg['site_url'] = f'http://{LAN_IP}:5244'
cfg['log'].update(max_size=10, max_backups=5, max_age=14)
for key in ['s3', 'ftp', 'sftp', 'mcp']:
    if key in cfg:
        cfg[key]['enable'] = False
(ROOT / 'data/config.json').write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding='utf-8')
print('Backup saved:', str(backup))
print('Anonymous disabled; listener restricted to Ethernet IPv4.')
