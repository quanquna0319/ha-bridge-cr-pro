# images/

离线镜像不放在 git 仓库里（366 MB 会撑爆 packfile），放在 Release 的 **8 个 20 MiB 分卷**里：

```
https://github.com/quanquna0319/ha-bridge-cr-pro/releases/download/v0.8.6-cr-pro.1/ha_bridge_0.8.6_amd64.tar.gz.part00
...                                                                                       .part07
```

`scripts/install.sh` 会自动按序下载、合并、校验整包 sha256 再 `docker load`。手动取：

```sh
TAG=v0.8.6-cr-pro.1
BASE=https://github.com/quanquna0319/ha-bridge-cr-pro/releases/download/$TAG
mkdir -p /tmp/hb && cd /tmp/hb

for i in 0 1 2 3 4 5 6 7; do
  N=$(printf '%02d' $i)
  curl -fL --retry 5 -C - -o ha_bridge_0.8.6_amd64.tar.gz.part$N \
    "$BASE/ha_bridge_0.8.6_amd64.tar.gz.part$N"
done

cat ha_bridge_0.8.6_amd64.tar.gz.part* > ha_bridge_0.8.6_amd64.tar.gz
sha256sum ha_bridge_0.8.6_amd64.tar.gz
# 89f32fb5a1edcc9aba8ebb7d71dc24642d3b9dbe7d440006edd8eded7709565a

docker load -i ha_bridge_0.8.6_amd64.tar.gz
```

镜像身份：

| 项 | 值 |
|---|---|
| Image ID | `sha256:3fe56aec4ea4610ac3bacf29c368c83def0abc8e94838aa725106d3240c4187b` |
| 平台 | linux/amd64 |
| 大小 | 365988122 字节（解包）/ 165981569 字节（tar.gz） |
| tag | `crpi-w1apw3w3zzp43y80.cn-shanghai.personal.cr.aliyuncs.com/weidaye1122/ha_bridge:latest` |
| GHCR | `ghcr.io/quanquna0319/ha-bridge-cr-pro:0.8.6-cr-pro`（私有包，需 `docker login`） |

GHCR 那份 manifest digest 为 `sha256:71023062a7be17420c8fa47080a30e39a0d35f16fc3617374b4914a0395ae63b`，
与离线包内容一致，只是 registry 侧重新封装了 manifest。
