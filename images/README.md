# images/

离线镜像不放在 git 仓库里（366 MB 会撑爆 packfile），放在 Release：

```
https://github.com/quanquna0319/ha-bridge-cr-pro/releases/download/v0.8.6-cr-pro.1/ha_bridge_0.8.6_amd64.tar.gz
```

`scripts/install.sh` 会自动下载并校验。手动取：

```sh
curl -L -O https://github.com/quanquna0319/ha-bridge-cr-pro/releases/download/v0.8.6-cr-pro.1/ha_bridge_0.8.6_amd64.tar.gz
curl -L -O https://github.com/quanquna0319/ha-bridge-cr-pro/releases/download/v0.8.6-cr-pro.1/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
docker load -i ha_bridge_0.8.6_amd64.tar.gz
```

镜像身份：`sha256:3fe56aec4ea4610ac3bacf29c368c83def0abc8e94838aa725106d3240c4187b`，linux/amd64。
