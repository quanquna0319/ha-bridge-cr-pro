# 逆向记录：HA Bridge 0.8.6 授权门禁

所有结论标注证据编号 E1…E12。样本来自 10.0.0.9 上运行的容器 `ha-bridge`，镜像摘要见 E1。

## 1. 目标识别

| 项 | 值 | 证据 |
|---|---|---|
| 镜像 | `crpi-w1apw3w3zzp43y80.cn-shanghai.personal.cr.aliyuncs.com/weidaye1122/ha_bridge:latest` | E1 |
| Image ID | `sha256:3fe56aec4ea4610ac3bacf29c368c83def0abc8e94838aa725106d3240c4187b` | E1 |
| 平台 | linux/amd64，365 988 122 B | E1 |
| 版本 | `VERSION` = `0.8.6`，releaseBatch `2026-11-a` | E2 |
| releaseId | `dec95f09cb5d527a76ee067b3119ad14` | E2 |
| 运行时 | `/opt/venv/bin/python /opt/venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 18080` | E3 |
| 容器用户 | `ha-bridge`（compose 里 `user: root` 只影响直接 exec） | E4 |

## 2. 查壳：PyArmor 8.5.12 basic

`/app/backend` 下 96 个 `.py` 全部是同一形态（E5）：

```text
# Pyarmor 8.5.12 (basic), 004721, cat
__pyarmor__(__name__, __file__, b'PY004721......')
```

判定依据：

1. 末行固定 `# Pyarmor <ver> (<mode>), <runtime_id>, <suffix>` 注释 —— 结构特征，非猜测；
2. `loaders/pyarmor_runtime_004721/` 在容器内存在，含 `pyarmor_runtime.so`（linux_x86_64）；
3. `mode=cat` 表示密文的最后一段是**运行时解密的字节码**，不是可静态还原的 pyc；
4. 熵：密文段接近随机，无 Python 常量表可读，无明文 `import` 语句。

**结论**：静态脱壳不可行（basic 模式的密文每份都绑 `__file__` 与模块名，且运行期 patch 了 `importlib`）。
本方案改走运行期函数覆写 —— 不改密文，因此不受 PyArmor 的自校验约束。

## 3. 定位门禁（动态）

在容器内把两个模块 dump 出来做 attr 枚举（E6），得到判定面：

### 3.1 `backend.app.license.service` —— 主许可

| 成员 | 签名 | 作用 |
|---|---|---|
| `LicenseService.allows` | `(self, feature=None, *, database=None) -> bool` | 全部特性开关的**唯一入口** |
| `LicenseService.status` | `(self) -> dict` | `/api/v1/license/status` 的载荷 |
| `LicenseService.availability` | `(self) -> dict` | `/api/v1/license/availability` |
| `LicenseService._verified_access` | `(self, ...) -> bool` | 内部二次校验 |
| `LicenseService.activate` / `heartbeat` / `recover` / `retry_now` | `async` | 联网激活与心跳 |
| `BASE_FEATURES` | `tuple[str, ...]` | 未授权时也可用的基础集合 |

关键返回值（未激活时，E7）：

```json
{"status":"UNACTIVATED","allowed":false,"displayAllowed":false,"edition":"free",
 "maxProjects":3,"maxDisplays":1,"leaseExpiresAt":null,"errorCode":"NOT_ACTIVATED"}
```

### 3.2 `backend.app.modules.interaction3d.access` —— 3D 增量包

| 成员 | 签名 | 行为 |
|---|---|---|
| `allowed` | `(request, *, database=None) -> bool` | 判定 |
| `require_access` | `(request, *, database=None) -> None` | 失败抛 `403` |
| `access_grant` | `(request) -> dict` | 现场验 Ed25519 lease，失败抛 `403` |
| `require_document_changes` | `(request, document, previous=None, *, database=None) -> None` | 文档级校验 |
| `FEATURE` | `str` = `'module.3d_interaction'` | 权益标识 |
| `MAX_GRANT_SECONDS` | `float` = `60` | 授权窗口 |

**这是独立路径**：模块自带 verifier 与公钥，不调用 `LicenseService.allows`（E8）。只打 ① 会得到
「许可显示 pro，但 `POST /api/v1/modules/interaction3d/scenes` 仍 403」。这是本补丁必须分两处处理的原因。

## 4. 签名材料

| 文件 | 内容 | 私钥 |
|---|---|---|
| `/app/keys/license-public.pem` | Ed25519 `MCowBQYDK2VwAyEAIFCJD0g4dQ5pCmHNCB+gZm3VxtqIK4o5bsoopA/P2DY=` | 不在镜像内 |
| `/app/keys/license-transport-public.pem` | Ed25519 `MCowBQYDK2VuAyEAs+086lQaAzVArVpubfjNsSDF0fB+zAsuc/W2J17Fglo=` | 不在镜像内 |

→ **无法伪造 lease**。任何声称「生成注册码」的做法都需要原厂私钥，本方案因此不走签名字面，
而是让判定函数直接返回成功，绕开验签。

## 5. 补丁机制

### 5.1 加载链

```text
python 启动
  └─ site.py 扫描 site-packages/*.pth
       └─ zzz_ha_bridge_pro.pth  (单行，行首 import)
            └─ import ha_bridge_pro
                 └─ install()  把 _PatchFinder 插到 sys.meta_path[0]
app 冷启动
  └─ import backend.app.license.service
       └─ _PatchFinder.find_spec 命中 → 用 _LoaderProxy 包住真实 loader
            └─ exec_module: 先执行 PyArmor 密文，再 _apply(mod) 覆写函数
  └─ import backend.app.modules.interaction3d.access   (同上, _apply_3d)
两个都命中后 finder 从 sys.meta_path 自我摘除
```


### 5.2 `.pth` 内容（98 B，单行）

```python
import sys, os; _r=os.environ.get("APP_ROOT","/app"); sys.path.insert(0,_r); import ha_bridge_pro
```


> **坑**：这行必须是一行合法 Python。早期版本用 shell heredoc 写入时反引号/引号被吃掉，变成
> `sys.path.insert(0,/app)` → `SyntaxError`，整个 `.pth` 被 `site.py` **静默跳过**，
> 表现为「文件挂上了但毫无效果」。校验命令见 README 第七节。

### 5.3 覆写了什么

| 模块 | 原函数 | 覆写为 |
|---|---|---|
| license.service | `LicenseService.allows` | `lambda self, feature=None, *, database=None: True` |
| license.service | `LicenseService.status` | 返回 `ACTIVE/pro/maxProjects=-1` 的静态载荷 |
| license.service | `LicenseService.availability` | 同上（`displayAllowed=True`） |
| license.service | `activate/heartbeat/recover/retry_now` | `async` 返回静态载荷（不联网） |
| license.service | `start/stop` | `async` no-op（心跳线程不启动） |
| license.service | `_verified_access` | `-> True` |
| license.service | `_validate_saved_state` | 透传 |
| license.service | `_mark_failure/_mark_revoked` | no-op |
| interaction3d.access | `allowed` | `-> True` |
| interaction3d.access | `require_access` | `-> None`（不抛 403） |
| interaction3d.access | `access_grant` | 合成 grant 字典（`allowed=True`，含 `entitlements`） |
| interaction3d.access | `require_document_changes` | `-> None` |

## 6. 部署与证据

| 编号 | 内容 | 取法 |
|---|---|---|
| E1 | 镜像摘要与平台 | `docker image inspect` |
| E2 | `VERSION` / `release-manifest.json` | `docker exec ha-bridge cat /app/VERSION` |
| E3 | PID1 命令行 | `docker exec ha-bridge cat /proc/1/cmdline` |
| E4 | 应用运行用户 | `docker exec ha-bridge ps -o user,cmd -p 1` |
| E5 | PyArmor 文件头 | `head -1 /app/backend/app/main.py` |
| E6 | 模块 attr 枚举 | 容器内 `dir(module)` dump |
| E7 | 未激活载荷 | `GET /api/v1/license/status`（打补丁前） |
| E8 | 3D 路径独立 | 打 ① 后 `interaction3d/access` 仍 403 |
| E9 | 解锁后 status | `GET /api/v1/license/status` → `ACTIVE` |
| E10 | 解锁后 3D | `GET /api/v1/modules/interaction3d/access` → 200 |
| E11 | 配额解除 | 连建 5 个项目全 201 |
| E12 | 回滚 | `rollback.sh` → `UNACTIVATED` 复现 |

实测回显存于仓库根 `verification.txt`。
