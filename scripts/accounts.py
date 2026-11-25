import sys, json, sqlite3, secrets, hashlib, time
from pathlib import Path

# 按实际安装目录修改
ROOT = Path(r'D:\openlist')

c = sqlite3.connect(ROOT / 'data' / 'data.db')
credentials = json.load(sys.stdin)

def hashes(password):
    salt = secrets.token_hex(8)
    static = hashlib.sha256((password + '-https://github.com/alist-org/alist').encode()).hexdigest()
    return salt, hashlib.sha256((static + '-' + salt).encode()).hexdigest()

with c:
    for name, password in credentials.items():
        salt, h = hashes(password)
        ts = int(time.time())
        if name == 'admin':
            c.execute("update x_users set pwd_hash=?,salt=?,pwd_ts=?,password='',disabled=0 where username=? and role=2", (h, salt, ts, name))
        else:
            c.execute("insert into x_users(username,pwd_hash,salt,pwd_ts,password,base_path,role,disabled,permission,otp_secret,sso_id,authn) values(?,?,?,?,?,?,0,0,256,'','','[]')", (name, h, salt, ts, '', '/内网文件'))
    c.execute('update x_users set disabled=1,permission=0 where role=1')
    # All downloads require expiring signatures, including existing storage.
    c.execute('update x_storages set enable_sign=1')
c.close()
