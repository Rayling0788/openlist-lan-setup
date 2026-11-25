# OpenList Windows 原生局域网只读部署指南

这是一套在 Windows 上**原生部署 OpenList（v4.2.6，不使用 Docker）**并限制为**仅限局域网只读访问**的配置说明与运维脚本模板，适合将本机或外接硬盘中的媒体、电子书、文档安全共享给同一局域网内的手机、平板和电脑。

> [!WARNING]
> 本仓库仅包含**教程文档与脱敏后的脚本模板**。实际部署后生成的 `data/`、`backups/`、`accounts.dpapi.xml` 等文件包含密码哈希、JWT 密钥、网盘凭据及本机信息，**切勿提交或上传到公开仓库**（仓库已自带 `.gitignore` 防护）。

---

## 1. 方案特点与安全设计

- **严格监听绑定**：仅监听指定的本机以太网 IPv4 地址（本文以示例地址 `192.168.1.100:5244` 说明），不监听代理虚拟网卡、Hyper-V 等虚拟网卡或 IPv6。
- **双层防火墙限制**：仅允许同一局域网网段（示例 `192.168.1.0/24`）通过指定以太网接口访问 TCP `5244`，并显式阻断该程序来自网段外的 IPv4 入站连接。
- **账号权限最小化**：
  - 停用匿名/游客访问（`role=1`）。
  - `admin` 仅用于后台配置。
  - `reader` 仅用于日常浏览、预览与 WebDAV 只读读取，挂载根目录限制在 `/内网文件`，禁止上传、新建目录、删除、重命名、移动、复制及管理存储。
  - 全站开启下载签名校验（`sign_all=true`、`enable_sign=1`），未签名直链拒绝访问。
  - 关闭 S3、FTP、SFTP、MCP 等非必要协议端口。
- **本机凭据保护**：自动生成高强度随机密码并使用 **Windows DPAPI** 加密保存为 `accounts.dpapi.xml`（仅当前 Windows 用户可解密，并限制 NTFS 权限），脚本与日志不落盘明文密码。
- **隐私友好预览**：替换外部在线预览服务，避免将内网文件地址泄露给第三方服务器；PDF 使用浏览器内置或本地预览，默认关闭整盘缩略图生成、目录大小递归统计与搜索索引。
- **可靠自启动与防多开**：通过 Windows 任务计划程序 `OpenList-LAN`（开机延迟 30 秒，以当前用户 `S4U` 非交互、Limited 权限运行，无需保存 Windows 登录密码），配合文件锁（`launcher.lock`）和 Windows 作业对象（Job Object），确保单实例运行且停止任务时无残留子进程；若批准的以太网 IP 未就绪则自动退出（Fail-Closed），不飘移到其他网卡。

---

## 2. 效果预览

![部署验证](assets/deploy-preview.png)

---

## 3. 仓库结构与实际部署目录

```text
openlist-lan-setup/
├── README.md          # 本使用与部署说明
├── .gitignore         # 屏蔽可执行文件、数据库、日志、密钥与备份
├── assets/
│   └── deploy-preview.png
└── scripts/           # 脱敏后的部署与日常维护脚本（需复制到安装目录的 maintenance/）
```

实际部署时（本文以 `D:\openlist` 为示例安装目录），目录结构如下：

```text
D:\openlist\
├── openlist.exe               # 官方 v4.2.6 可执行文件（自行下载并校验 SHA-256）
├── start_alist_v3.vbs         # （可选）静默启动入口
├── stop_alist_v3.vbs          # （可选）静默停止入口
├── data\                      # 运行时配置 config.json、SQLite 数据库 data.db、日志 log\（切勿外传）
├── downloads\                 # 官方压缩包下载与校验目录
├── backups\                   # 升级前快照与手动备份目录（切勿外传）
└── maintenance\               # 将本仓库 scripts\ 中的脚本放到此目录使用
```

---

## 4. 从零部署步骤

### 第一步：规划目录与局域网 IP（建议先设 DHCP 保留）

1. 在路由器管理后台（例如 `192.168.1.1`）的 **DHCP 地址保留 / 静态租约** 中，将部署电脑的以太网网卡 MAC（`<你的以太网网卡MAC地址>`）绑定到一个固定局域网 IP（本文示例为 `192.168.1.100`）。
   - 保存前确认该地址属于本机且未与其他设备冲突。
   - **只建议设路由器 DHCP 保留**，不随意修改 Windows 本机静态 IP。
2. 新建部署目录（示例 `D:\openlist`），将本仓库 `scripts\` 目录下的全部脚本复制到 `D:\openlist\maintenance\`（`.vbs` 可放在 `D:\openlist\` 根目录）。
3. **修改脚本中的环境参数**：在执行前，请全局检查并按需修改以下占位默认值：
   - 安装目录：`D:\openlist` → 你的实际部署目录
   - 本机局域网 IP：`192.168.1.100` → 你的实际以太网 IPv4 地址
   - 网卡名称：`以太网` → 你的实际 Windows 网络适配器名称（可在 `Get-NetAdapter` 中确认）
   - 局域网网段：`192.168.1.0/24` → 若网段不同，需同步调整 `配置防火墙与开机启动.ps1` 中的 `$lanSubnet` 与外网阻断 CIDR 列表 `$outside`
   - Python 命令：脚本默认调用 `python`，请确保 Python 3 已加入系统 `PATH`（验证脚本还依赖 `Pillow` 和 `reportlab`）。

### 第二步：下载并校验官方程序

1. 前往 [OpenList v4.2.6 Release](https://github.com/OpenListTeam/OpenList/releases/tag/v4.2.6) 下载 `openlist-windows-amd64.zip`（或运行 `maintenance\download.py` 自动断点续传下载并校验）。
2. 校验压缩包 SHA-256 是否与官方发布一致：
   ```text
   10d24913f86843e347eefac219c61224628bbd5d3c7443b2ee119c168a8cb3b9
   ```
3. 解压出 `openlist.exe` 放到 `D:\openlist\openlist.exe`，并先手动启动一次以初始化 `data\config.json` 与 `data\data.db`，随后停止进程。

### 第三步：初始化安全配置与账号

1. 停止 `openlist.exe` 后，依次运行配置准备脚本：
   ```powershell
   python D:\openlist\maintenance\prepare.py
   python D:\openlist\maintenance\upgrade.py
   ```
   - `prepare.py` 会备份初始文件、停用游客账号、限制仅监听指定 IPv4 和端口 `5244`、禁用 S3/FTP/SFTP/MCP 并设置日志轮转（单份上限 10 MB、最多 5 份、保留 14 天）。
   - `upgrade.py` 会重置高强度随机 `jwt_secret`、关闭外链预览服务与自动播放/归档默认预览、关闭全局搜索索引并开启全站签名。
2. 生成随机密码并写入数据库（使用 Windows DPAPI 加密保存）：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File D:\openlist\maintenance\accounts.ps1
   ```
   - 完成后双击 `maintenance\查看账号.cmd` 在本机弹窗查看 `admin` 与 `reader` 的随机密码，并保存到你的密码管理器。
   - 凭据文件仅当前 Windows 用户可解密；换电脑或重装系统后无法直接解密，届时需重新运行账号配置重置。

### 第四步：配置防火墙与开机自启动

- 右键 **`maintenance\完成系统配置.cmd`** → **以管理员身份运行**。
- 脚本将自动完成：
  1. 导出原有相关防火墙规则到 `backups\original-firewall.xml` 并禁用宽泛规则。
  2. 新建严格入站规则 `OpenList-LAN-ReadOnly`（仅允许来自指定局域网网段访问指定以太网 IP 的 TCP `5244`）与 `OpenList-Block-Outside-LAN`（阻断网段外来源）。
  3. 注册开机自启动任务 `OpenList-LAN`（延迟 30 秒，S4U Limited 权限）。
  4. 如有旧的开机启动快捷方式，自动迁移备份。

### 第五步：启动服务并运行自动化验收

1. 双击 `maintenance\启动服务.cmd` 启动服务，稍等几秒后双击 `maintenance\查看状态.cmd` 确认正在监听 `192.168.1.100:5244`。
2. 运行自动化验收脚本（会生成临时验证目录与测试文件并检验读写权限隔离、签名校验、Range 断点续传与 WebDAV 只读限制）：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File D:\openlist\maintenance\验证.ps1 setup
   ```
3. 验收全部通过后，登录 `admin` 后台添加实际要共享的目录：
   - 驱动选择：**本机存储（Local）**
   - 挂载路径：统一放在 `/内网文件/分类/名称`（例如 `/内网文件/媒体/示例目录`），这样 `reader` 账号才能看到。
   - 根文件夹路径：填写具体目标文件夹，**不要填写整盘根目录、系统目录或用户个人目录**。
   - 开启 **启用签名（enable_sign）**，关闭 **缩略图**、**目录大小统计** 与 **索引**。

---

## 5. 日常维护与备份恢复

在 `maintenance\` 目录双击对应脚本即可：

| 入口文件 | 作用 |
| --- | --- |
| `启动服务.cmd` | 启动 `OpenList-LAN` 计划任务（重复启动会被任务和进程锁阻止） |
| `停止服务.cmd` | 停止当前服务（不影响下次开机自启动） |
| `查看状态.cmd` | 查看运行实例数、监听地址端口、任务状态及最近运行结果 |
| `查看账号.cmd` | 本机弹窗解密查看 `admin` / `reader` 密码 |
| `备份配置.cmd` | 短暂停止服务后备份 `data`、`accounts.dpapi.xml` 与 `启动.ps1` 到 `backups\manual-日期时间` 并恢复运行（不复制原始共享硬盘资料） |
| `取消自启动.cmd` | 右键 **以管理员身份运行**，禁用开机任务并停止服务（恢复时在任务计划程序中重新启用 `OpenList-LAN`） |

### 备份与恢复注意事项
- 备份至少保留完整 `data\` 与 `maintenance\` 入口；**数据库、配置及备份包含账号哈希与密钥，请妥善私下保管**。
- 恢复时先停止服务，将同一份备份中的 `config.json` 与 `data.db` 恢复回 `data\` 再启动；跨版本恢复需同时恢复对应版本的 `openlist.exe`。
- 外接硬盘暂时断开时，**保留存储配置即可**，恢复连接且盘符一致后在后台重新加载存储，切勿随意删配置或改动原文件。

---

## 6. 手机 / 平板访问与常见排查

### 客户端访问方式
1. 手机/平板连接同一路由器的普通 Wi-Fi（关闭蜂窝数据和手机 VPN，勿连访客 Wi-Fi）。
2. **浏览器访问**：打开 `http://192.168.1.100:5244`，使用 `reader` 账号登录。
3. **WebDAV 客户端访问**：
   - 协议：`HTTP`
   - 主机：`192.168.1.100`
   - 端口：`5244`
   - 路径：`/dav/`
   - 账号：`reader`（密码在本机 `查看账号.cmd` 获取）

### 视频与电子书阅读说明
- **视频播放**：MP4（H.264 + AAC）在手机浏览器中兼容性较好；MKV 封装或 H.265/HEVC、AV1、10-bit/HDR、AC3/DTS 音轨及 ASS/PGS 外挂/内封字幕在浏览器中可能无声、黑屏或缺少字幕。遇到此类情况可下载后用本地播放器播放，或直接使用支持 WebDAV 的播放器（如 VLC、nPlayer、PotPlayer、mpv 等）挂载 `/dav/` 串流。
- **电子书与漫画**：EPUB、CBZ/CBR、ZIP 建议直接下载后用专业阅读器打开，或使用支持 WebDAV 的阅读客户端访问。

### 连接失败排查顺序
1. 电脑是否处于开机唤醒状态（睡眠/休眠时服务不可用）、外接硬盘是否在线。
2. 运行 `查看状态.cmd` 确认存在 1 个监听实例，且监听在预期的以太网 IPv4 地址上。
3. 检查手机是否连接同一路由器且获取到同网段 IP（如 `192.168.1.x`），未开启 VPN 或访客隔离 / AP 隔离。
4. 检查本机以太网 IP 是否因 DHCP 租约过期而变化（变化时启动器会主动拒绝启动以防止暴露到未授权网络），或 Windows 防火墙规则是否被更改。
5. 更换路由器或网段时，需同步更新 `config.json`、`启动.ps1`、`管理.ps1` 与防火墙规则中的 IP 和网段，切勿直接改为 `0.0.0.0` 全网卡监听。

---

## 7. 官方参考来源

- [OpenList v4.2.6 发布页](https://github.com/OpenListTeam/OpenList/releases/tag/v4.2.6)
- [OpenList 用户权限说明](https://doc.oplist.org/guide/advanced/user)
- [OpenList 本机存储配置](https://doc.oplist.org/guide/drivers/local)
- [OpenList 预览配置](https://doc.oplist.org/configuration/preview)
- [MDN 媒体容器与编码兼容参考](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Containers)
