# netbird-iac

用 Ansible 把 **自托管 NetBird 服务端**部署到公网 Debian 系 VPS：当前合并版
`Management + Signal + Relay + STUN` 容器、NetBird Dashboard，以及内置 Traefik
反向代理（自动签发 Let's Encrypt 证书）。目录结构与官方
[`getting-started.sh`](https://docs.netbird.io/selfhosted/selfhosted-quickstart)
一键脚本一致，但改为幂等、可版本控制的 IaC。

## 部署内容

- **内置 Dex IdP**（NetBird ≥ 0.62）：开箱即用本地用户，无需外部 IdP；外部
  OIDC 提供方可事后在 Dashboard 里追加。
- **server 镜像已固定版本**（Renovate 跟踪）；dashboard 上游只发布滚动 tag，故跟随
  `latest`。

## 依赖

- 一台 Linux VM（≥ 1 CPU / 2 GB），公网可达 **TCP 80/443** 与 **UDP 3478**。
- 一个 **公网域名**，A 记录指向该 VM。
- Docker Engine + Compose v2 插件；缺失时自动从 Docker 官方源安装（Debian 系）；
  设 `install_docker: false` 可改为要求预装。
- 控制端：`mise` 或 `asdf`、`openssl`，以及对主机的 SSH 访问。

## 快速开始

```bash
make ans-deps-tools          # 安装固定版本工具链
make ans-deps                # 工具链 + Galaxy collections

make host-init HOST=netbird-1
#   编辑 inventory/hosts.yml
#   编辑 inventory/host_vars/netbird-1/main.yml    （域名、ACME 邮箱）
#   编辑 inventory/host_vars/netbird-1/vault.yml   （IP、SSH 凭据、owner）
ansible-vault encrypt inventory/host_vars/netbird-1/vault.yml

make ans-lint && make ans-check && make ans-site
```

部署以**非 root 服务账号**执行（`site.yml` 默认拒绝 root，除非
`host_allow_root_login=true`）。首次以 root 创建一次：

```bash
make host-bootstrap      # 创建 ansible 账号 + sudo
# 然后在 vault.yml 指向它：
#   vault_ansible_user: ansible
#   vault_ansible_ssh_privkey_file: ~/.ssh/...   （或 vault_ansible_password）
```

`host-bootstrap` 会按 `ansible → admin → root` 顺序探测，用第一个能登录的身份；若非
ansible，则创建该服务账号，并确保 Docker Engine + Compose v2 已安装（缺失时安装 Docker
CE）。对每个设置了 `vault_<id>_ssh_pubkey_file` 的身份，会把该路径的
公钥写入被控机对应账号（`ansible` / `admin` / `root`）；留空则忽略（不会自动生成密钥）。
ansible 身份未给公钥时才设密码（自动生成并写入加密 vault）。当 `admin` 身份被配置（提供
密码和/或公钥）时，会自动创建该账号、设置密码并授权公钥。对应的私钥路径由
`vault_<id>_ssh_privkey_file` 显式指定（与公钥路径同处 vault.yml，仅接受路径，不接受
内联公钥字符串）。镜像源也在这里配置（见下）。

vault 里填了 `owner_email` 时会通过 `/api/setup` 自动创建首个 owner；
`owner_password` 留空则由角色生成并写入加密的 `vault_managed.yml`。
该首次部署还会创建一个 `admin` service user、为它签发 Personal Access Token，
存入 `vault_admin_service_user_access_token`（供 tenant 阶段使用），然后删除一次性的
owner token。不填 email 时，浏览器打开 `https://<域名>/setup` 手动创建（该页仅在实例无任何
账号时可用；只填密码而不填 email 不会生效，只会打印警告）。

Tag：`netbird`、`netbird_preflight`、`netbird_config`、`netbird_deploy`、
`netbird_owner`，可用 `make ans-tags TAGS=netbird_config` 单独执行。

## 关于 IdP（常见问题）

**官方一键脚本默认装 Zitadel 吗？** 不再装了。NetBird 0.62 起，服务端内置 **Dex**
做本地用户管理，Zitadel 只是旧版 quickstart 的历史默认项。本项目与官方现状一致，
**默认本地用户**。

**能自定义其他 IdP（如 Authentik）吗？** 可以。任何 **OIDC 兼容**的 IdP 都能作为
*外部* IdP 接入（Google / Entra / Okta / Zitadel / Keycloak / **Authentik** /
Pocket ID，或通用 OIDC），且能与本地用户并存：Dashboard → **Settings → Identity
Providers**，或 `POST /api/identity-providers`。这是运行时的租户配置，不属于服务端
部署 role。

**已有自托管 Authentik 能直接用吗？** 可以。在 Authentik 建 **confidential
OAuth2/OpenID** provider → 把 NetBird 的 redirect URL 填进去 → 在 NetBird 加
*Generic OIDC*，issuer 用 `https://authentik.example.com/application/o/netbird/`。
面向**远程公网用户**时注意：

- 用户浏览器**和** NetBird 服务端都要能访问该 issuer（discovery、JWKS、token，以及
  登录/同意页面），且证书必须是有效的公网 TLS。
- 若 Authentik 前面有只放行内网/CGNAT 的 IP 白名单，公网浏览器与公网 NetBird
  服务端都会被拒——需先公开 OIDC/登录路径，或把相关来源 IP 加白名单。
- 组同步：Authentik 的 `profile` scope 自带 `groups`，在 NetBird 开启 *JWT group
  sync* 用 `groups` claim 即可（Zitadel 用的是 *roles*，还需写 Action 转成扁平数组）。

**官方文档里的 Ansible 是管 server 还是 client？** 两者都不是纯「部署」。它指的是
`community.ansible_netbird` collection，对**已存在 tenant 的 REST API**做声明式配置
（users/groups/setup keys/policies/networks/DNS/IdP）——**不装 client，也不装
server**。它属于服务端侧的「配置即代码」，本项目已接入（见下节）。

## 租户 / ACL 配置即代码（community.ansible_netbird）

`netbird_config/` 下版本化的 YAML 就是期望状态，用 collection 的 Config-as-Code
工作流声明式应用，支持纯名称→ID 解析、按依赖顺序应用：

```bash
make netbird-plan          # 只读 diff（安全默认）
make netbird-apply         # 应用期望状态
make netbird-apply-strict  # 应用 + 删除未纳管资源
```

需要 `vault_admin_service_user_access_token`（全新部署会自动创建；否则在
Team → Service Users 建 `admin` service user 及其 access token）。
可代码化范围：

| 资源 | 可否代码化 | 说明 |
|---|---|---|
| 组、Policies(ACL)、Posture checks | 可以 | `access_control/*.yml`，按名称引用 |
| Networks(路由器/资源)、DNS(nameservers/zones/settings) | 可以 | `networks.yml`、`dns/*.yml` |
| 账户设置（Dashboard settings） | 可以 | `settings.yml` |
| 用户 / 服务用户 | 可以* | 对象/角色/组可管；内置 IdP 密码是一次性 |
| Setup keys | 可以* | 密钥值仅创建时返回一次 |
| 外部 IdP | 可以* | client secret 需存 vault |
| **Peer（设备）** | **不可以** | 是入网设备，只能管其设置；设备用 setup key 重新入网 |
| 审计/事件 | 不可以 | 只读 |

`*` = 声明可代码化，但一次性密钥不可复现，需另存密码管理器。

## 备份与恢复

```bash
make netbird-backup                              # -> backup/<host>/<stamp>/
make netbird-restore FROM=backup/<host>/<stamp>  # 成对恢复
```

备份会停容器做一致的 SQLite 快照、打包 `netbird_data` 卷，并把
`vault_managed.yml`（加密密钥）一并存放。**数据与密钥必须来自同一份备份**，否则
加密字段解不开。`backup/` 已 gitignore；请另存异地副本。

## 区域受限主机的镜像源（可选）

`make host-bootstrap`（可选，**不**在 `ans-site` 内）可把主机指向替代软件源——适合中国
VPS。变量未设置时是 no-op，且不动部署基线：

```yaml
# inventory/host_vars/<host>/main.yml
host_apt_mirror: "https://mirrors.tuna.tsinghua.edu.cn/debian"
docker_registry_mirrors:
  - "https://docker.1ms.run"
```

## 目录

```
inventory/           # hosts.yml(.example)、group_vars/netbird、host_vars/example
playbooks/site.yml   # server preflight + netbird_server role
playbooks/tenant.yml # 租户 config-as-code（community.ansible_netbird）
netbird_config/      # 声明式租户期望状态（版本化 YAML）
roles/netbird_server # defaults（镜像版本）、tasks、templates/
roles/helpers/       # 共享的 vault 密钥生成
```

## 密钥

切勿提交 vault。用户密钥放在加密的
`inventory/host_vars/<host>/vault.yml`；role 首次部署时把加密材料生成进加密的
`vault_managed.yml`（后续运行保留原值）。**务必备份 `vault_managed.yml`**：丢失
`vault_datastore_encryption_key` 会导致加密的用户数据不可恢复。

## 许可证

见 `LICENSE`。
