# HA Bridge 0.8.6 · cr-pro 授权解锁（含离线镜像）

把 **HA Bridge 0.8.6** 的授权门禁在运行期移除，得到一个 `ACTIVE / pro` 的完整实例：基础特性全开、
`editor` 与 `projects.write` 配额解除（`maxProjects=-1` / `maxDisplays=-1`）、Pro 增量包
`module.3d_interaction`（3D 户型交互、中控大屏、render-cache 图层）全部放行。

**实现方式：不改动 `/app` 下任何一个 PyArmor 密文字节。** 靠 `site-packages` 里的 `.pth` 启动钩子 +
`MetaPathFinder`，在两个门禁模块 `exec_module` 完成后就地覆写其判定函数。因此镜像自带的
`release-manifest.json` 校验、`/health/ready` 自检、只读挂载全部照常通过，一条命令即可回滚到纯净上游。

---

## 目录

- [一、这个包解决什么问题](#一这个包解决什么问题)
- [二、快速安装（3 条命令）](#二快速安装3-条命令)
- [三、手动安装（逐步）](#三手动安装逐步)
- [四、验证清单](#四验证清单)
- [五、回滚](#五回滚)
- [六、文件清单与改动明细](#六文件清单与改动明细)
- [七、常见问题](#七常见问题)
- [八、保护形态与逆向结论](docs/reverse-notes.md)

---

## 一、这个包解决什么问题

上游 0.8.6 把授权判定拆成了**两条互不相干**的路径，只打其中一条会看到「改完了但 3D 还是 403」：

| 路径 | 模块 | 管什么 | 未解锁时 |
|---|---|---|---|
| ① 许可服务 | `backend.app.license.service.LicenseService` | `allows()` / `status()` / `availability()`；基础特性集合 `BASE_FEATURES`；`editor` / `projects.write` 的配额 | `status=UNACTIVATED`、`allowed=false`、`displayAllowed=false`、建项目/中控被配额拦住 |
| ② 3D 增量包 | `backend.app.modules.interaction3d.access` | `allowed()` / `require_access()` / `access_grant()`；`FEATURE='module.3d_interaction'`，文件内自带 Ed25519 lease 验签 | 直接抛 `403` `'当前授权未开通 3D 交互功能增量包，或该权益已失效。'` |

②**不经过** ①，所以本补丁对两条路径分别处理。

## 二、快速安装（3 条命令）

> 适用：Debian/Ubuntu 系宿主，已装 docker 与 compose 插件，root 权限。

```sh
# 1) 取仓库
git clone https://github.com/quanquna0319/ha-bridge-cr-pro.git
cd ha-bridge-cr-pro

# 2) 一键安装：自动下载并加载离线镜像 → 建目录 → 落补丁 → 起容器 → 自检
sudo sh scripts/install.sh

# 3) 看结果
curl -s http://127.0.0.1:18080/api/v1/license/availability
```

预期输出（关键字段）：

```json
{"status":"ACTIVE","displayAllowed":true,"allowed":true,"edition":"pro","editorAllowed":true,
 "featureAccess":{"editor":true,"interaction3d":true,"uiPack":true}}
```

安装脚本默认按工单布局落盘到 `/vol1/1000/docker/ha-bridge/`。想换路径：

```sh
sudo HA_BRIDGE_ROOT=/opt/ha-bridge sh scripts/install.sh
```

已有镜像（例如能从原厂私有仓库直接 pull）就跳过大文件下载：

```sh
sudo SKIP_IMAGE=1 sh scripts/install.sh
```

## 三、手动安装（逐步）

### 3.1 准备镜像

镜像 `ha_bridge:latest`（0.8.6，linux/amd64，366 MB）已作为 Release 资产提供离线 tar.gz：

```sh
curl -L -o ha_bridge_0.8.6_amd64.tar.gz \
  https://github.com/quanquna0319/ha-bridge-cr-pro/releases/download/v0.8.6-cr-pro.1/ha_bridge_0.8.6_amd64.tar.gz

# 校验（值见同目录 SHA256SUMS）
sha256sum -c SHA256SUMS --ignore-missing

docker load -i ha_bridge_0.8.6_amd64.tar.gz
docker images | grep ha_bridge
```

也可以直接连原厂仓库：

```sh
docker pull crpi-w1apw3w3zzp43y80.cn-shanghai.personal.cr.aliyuncs.com/weidaye1122/ha_bridge:latest
```

### 3.2 建目录与 compose.yaml

```sh
D=/vol1/1000/docker/ha-bridge
mkdir -p "$D/data" "$D/secrets" "$D/cr-pro"
cd "$D"
```

`compose.yaml`（与原工单一致，未做任何改动）：

```yaml
services:
  ha-bridge:
    image: crpi-w1apw3w3zzp43y80.cn-shanghai.personal.cr.aliyuncs.com/weidaye1122/ha_bridge:latest
    container_name: ha-bridge
    user: root
    restart: unless-stopped
    network_mode: host
    environment:
      APP_PORT: 18080
    volumes:
      - /vol1/1000/docker/ha-bridge/data:/data
      - /vol1/1000/docker/ha-bridge/secrets:/run/secrets
```

### 3.3 落补丁文件

```sh
cp patches/ha_bridge_pro.py patches/zzz_ha_bridge_pro.pth "$D/cr-pro/"
cp scripts/deploy.sh scripts/rollback.sh scripts/restore-admin.sh "$D/cr-pro/"
chmod 0755 "$D/cr-pro/"*.sh
chmod 0644 "$D/cr-pro/"ha_bridge_pro.py "$D/cr-pro/"zzz_ha_bridge_pro.pth
```

`$D/cr-pro/compose.override.yaml`：

```yaml
services:
  ha-bridge:
    volumes:
      - /vol1/1000/docker/ha-bridge/cr-pro/ha_bridge_pro.py:/opt/venv/lib/python3.12/site-packages/ha_bridge_pro.py:ro
      - /vol1/1000/docker/ha-bridge/cr-pro/zzz_ha_bridge_pro.pth:/opt/venv/lib/python3.12/site-packages/zzz_ha_bridge_pro.pth:ro
```

> 路径写死成绝对路径，是为了让 `docker compose -f compose.yaml -f cr-pro/compose.override.yaml` 从任意
> 工作目录调用都稳定。

### 3.4 起容器

```sh
sh "$D/cr-pro/deploy.sh"
```

脚本做三件事：校验三个补丁文件在位（含 `.pth` 引号预检）→ `up -d --force-recreate` →
轮询 `/health/ready` 至 200 → 把门禁日志的属主改成容器内的 `ha-bridge` 用户。

### 3.5 设置管理员口令

镜像自带 `admin` 账号，但口令 hash 在数据卷里。两种做法：

**A. 保留原口令**（若你有原始 `admin-account.json`）：直接放进 `$D/data/admin-account.json`，
`chmod 600`、`chown ha-bridge:ha-bridge`，然后 `docker restart ha-bridge`。

**B. 重置为指定口令**（本仓库示例口令 `Wq199405!`）：

```sh
cat > /tmp/setpw.py <<'PY'
import sys, json, pathlib
sys.path.insert(0, "/app")
from backend.app.security import hash_password
PW = sys.argv[1]
p = pathlib.Path("/data/admin-account.json")
bak = pathlib.Path("/data/admin-account.json.cr-bak")
if not bak.exists():
    bak.write_text(p.read_text())
    print("backup ->", bak)
doc = json.loads(p.read_text())
doc["passwordHash"] = hash_password(PW)
p.write_text(json.dumps(doc, ensure_ascii=False))
print("ok")
PY
docker cp /tmp/setpw.py ha-bridge:/app/setpw.py
docker exec ha-bridge /opt/venv/bin/python /app/setpw.py 'Wq199405!'
docker restart ha-bridge   # AdminAccountStore 启动时缓存账号，必须重启
```

## 四、验证清单

```sh
B=http://127.0.0.1:18080
docker ps --filter name=ha-bridge --format '{{.Status}}'          # Up (healthy)
curl -s -o /dev/null -w '%{http_code}\n' $B/health/live          # 200
curl -s -o /dev/null -w '%{http_code}\n' $B/health/ready         # 200

# 登录（cookie 存 /tmp/ck）
curl -s -c /tmp/ck -X POST $B/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Wq199405!"}'
# -> {"id":"...","username":"admin","role":"admin"}

curl -s -b /tmp/ck $B/api/v1/license/status                       # status=ACTIVE, edition=pro
curl -s -b /tmp/ck $B/api/v1/modules/interaction3d/access          # allowed=true
curl -s -o /dev/null -w '%{http_code}\n' -b /tmp/ck $B/api/v1/displays   # 200
```

完整实测回显见 [`verification.txt`](verification.txt)。

判定成功的三条硬指标：

1. `GET /api/v1/license/status` → `"status":"ACTIVE"`、`"edition":"pro"`、`"maxProjects":-1`
2. `GET /api/v1/modules/interaction3d/access` → `200`，`"allowed":true`（不是 403）
3. `POST /api/v1/projects` 连建 5 个全部 `201`（配额已解除）

## 五、回滚

```sh
sh /vol1/1000/docker/ha-bridge/cr-pro/rollback.sh      # 回到纯净上游，availability -> UNACTIVATED
sh /vol1/1000/docker/ha-bridge/cr-pro/restore-admin.sh # 还原原始 admin 口令 hash（读 .cr-bak）
sh /vol1/1000/docker/ha-bridge/cr-pro/deploy.sh        # 重新解锁
```

`rollback.sh` 只用 `compose.yaml`（不带 override），补丁挂载消失、`.pth` 不加载，容器回到出厂状态。
实测切换正常，可反复来回。

## 六、文件清单与改动明细

| 文件 | 作用 |
|---|---|
| `patches/ha_bridge_pro.py` | 运行期门禁补丁：两条授权路径全覆盖 |
| `patches/zzz_ha_bridge_pro.pth` | 启动钩子，单行 Python，`zzz_` 前缀保证最后加载 |
| `scripts/install.sh` | 一键安装（镜像 → 目录 → 补丁 → 起容器 → 自检） |
| `scripts/deploy.sh` | 上线解锁（含预检与日志属主修正） |
| `scripts/rollback.sh` | 回纯净上游 |
| `scripts/restore-admin.sh` | 还原 admin 口令 |
| `docs/reverse-notes.md` | 保护形态、门禁定位过程、函数签名与证据编号 |
| `verification.txt` | 10.0.0.9 上的实测回显存档 |

**改了什么**（相对上游镜像）：

1. 新增 `/opt/venv/lib/python3.12/site-packages/ha_bridge_pro.py`（只读挂载）
2. 新增 `/opt/venv/lib/python3.12/site-packages/zzz_ha_bridge_pro.pth`（只读挂载）
3. 重写数据卷里 `/data/admin-account.json` 的 `passwordHash`（原文件备份为 `.cr-bak`）
4. `compose.yaml` **不动**，叠加 `cr-pro/compose.override.yaml`

**没改**：`/app/backend` 下全部 96 个 PyArmor 密文字节、`/app/keys`、`release-manifest.json`、
`/app/VERSION`。所以 `releaseId` 校验与健康检查照常通过。

## 七、常见问题

**Q：补丁挂上了但 `status` 还是 `UNACTIVATED`？**
`.pth` 必须是**单行合法 Python**。若 `sys.path.insert(0,"/app")` 的引号在写文件时被吃掉，会变成
`sys.path.insert(0,/app)` → `SyntaxError`，整行被 `site.py` 静默忽略。校验：
```sh
docker exec ha-bridge cat -A /opt/venv/lib/python3.12/site-packages/zzz_ha_bridge_pro.pth
# 期望恰为：import sys, os; _r=os.environ.get("APP_ROOT","/app"); sys.path.insert(0,_r); import ha_bridge_pro
```

`deploy.sh` 已内置这条预检。

**Q：`/data/cr-license-calls.log` 不写日志？**
容器内应用以 `ha-bridge` 用户运行。若日志由 root 创建，追加会失败（功能不受影响，只是没记录）。
`deploy.sh` 会自动 `chown ha-bridge:ha-bridge && chmod 0640`。

**Q：改了 admin 口令但登录还是 401？**
`AdminAccountStore` 在容器启动时缓存账号文件，**必须 `docker restart ha-bridge`**。另外口令末尾的
`!` 别打成全角 `！`。

**Q：`/api/v1/projects/xxx` 返回 308？**
正常。前端页面路由会 308 到带尾斜杠的规范路径，加 `-L` 跟随即可。

**Q：3D 建场景返回 409「请先在 3D 户型图绘制中绘制并保存户型」？**
业务前置，不是授权。先 `PUT /api/v1/studio3d` 存一份户型草稿（`{"revision":0,"scene":{...}}`），
再 `POST /api/v1/modules/interaction3d/scenes`。

---

## 八、保护形态与逆向结论

详见 [docs/reverse-notes.md](docs/reverse-notes.md)。摘要：

| 项 | 事实 |
|---|---|
| 应用 | HA Bridge `0.8.6`，`releaseBatch=2026-11-a` |
| 源码保护 | PyArmor 8.5.12 (basic)，runtime id `004721`，mode `cat`，96 个 `.py` 全密文 |
| 运行期 | `/opt/venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 18080` |
| 许可签名 | Ed25519，`/app/keys/license-public.pem` 与 `license-transport-public.pem` 在镜像内，私钥不在 |
| 破解路线 | 运行期函数覆写（不改密文、不伪造签名） |

---

**范围**：本仓库供自有或已获书面授权的实例使用（授权范围内测试、教学演示、离线环境复原）。
镜像与补丁取自被测环境本身，不含原厂私钥或签名材料；补丁只覆写运行期判定函数，不修改原厂二进制。
