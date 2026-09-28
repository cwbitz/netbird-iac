# netbird-iac

Ansible IaC that deploys the **self-hosted NetBird server** onto a public
Debian-family VPS: the combined `Management + Signal + Relay + STUN` container,
the NetBird dashboard, and a built-in Traefik reverse proxy that issues Let's
Encrypt certificates automatically. It reproduces the layout of the official
[`getting-started.sh`](https://docs.netbird.io/selfhosted/selfhosted-quickstart)
quickstart, but idempotently and version-controlled.

## What it deploys

```
┌───────────────────────────── public VPS ─────────────────────────────┐
│  TCP 80/443                         UDP 3478                          │
│      │                                  │                             │
│   netbird-traefik ──────────────────────┼──── netbird-server           │
│   (Let's Encrypt, TLS-ALPN)             │     (Management + Signal +   │
│      │            │                     │      Relay + STUN + Dex)      │
│  netbird-dashboard                  (STUN)                            │
└───────────────────────────────────────────────────────────────────────┘
```

- **Embedded Dex IdP** (NetBird ≥ 0.62): local users out of the box, no external
  IdP required. External OIDC providers can be added later from the Dashboard.
- **Pinned server image** (Renovate-tracked); the dashboard only ships moving
  tags upstream, so it follows `latest`.

## Requirements

- A Linux VM with at least 1 CPU / 2 GB RAM, publicly reachable on **TCP 80 and
  443** and **UDP 3478**.
- A **public domain** whose A record points at the VM.
- Docker Engine + the Compose v2 plugin **preinstalled** (this project never
  installs Docker).
- On the control node: `mise` or `asdf`, `openssl`, and SSH access to the host.

## Quickstart

```bash
# 1. Toolchain + collections
make ans-deps-tools
make ans-deps

# 2. Create a host from the committed template
make host-init HOST=netbird-1
#    - edit inventory/hosts.yml            (hostname)
#    - edit inventory/host_vars/netbird-1/main.yml   (domain, ACME email)
#    - edit inventory/host_vars/netbird-1/vault.yml  (IP, SSH creds, owner)
#    - then encrypt the vault:
ansible-vault encrypt inventory/host_vars/netbird-1/vault.yml

# 3. Validate, dry-run, deploy
make ans-lint
make ans-check
make ans-site
```

Deploys run as a **non-root service account** (`playbooks/site.yml` refuses root
unless `host_allow_root_login=true`). Create it once, as root:

```bash
# once, before the first deploy (creates the 'ansible' account + sudo):
make host-bootstrap
# then point the connection at it in vault.yml:
#   vault_ansible_user: ansible
#   vault_ansible_ssh_privkey_file: ~/.ssh/...   (or vault_ansible_password)
```

`make host-bootstrap` probes `ansible → admin → root` and uses the first that
works; when it is not `ansible` it creates the account. For each identity whose
`vault_<id>_ssh_pubkey_file` is set, the public key at that path is authorized
for the matching account (`ansible`, `admin` or `root`); an unset path is ignored
(keys are never generated). For `ansible`, when no public key is given a password
is set instead (generated into the encrypted vault). The matching private key
path is `vault_<id>_ssh_privkey_file` (set explicitly next to the public key
path; only paths are accepted, never raw key strings). It is also where region
mirrors are configured (see below).

When `owner_email` is set in the vault, the play creates the first owner
automatically through `/api/setup`; if `owner_password` is empty, one is
generated into the encrypted `vault_managed.yml`. On that first setup the play
also creates an `admin` service user, mints a Personal Access Token for it,
stores it as `vault_admin_service_user_access_token` (used by the tenant phase),
and deletes the one-time owner token again. With no email, open
`https://<domain>/setup` in a browser and create the owner there — that page only
works while the instance has no accounts (a password set without an email is
ignored and logs a warning).

Tags: `netbird`, `netbird_preflight`, `netbird_config`, `netbird_deploy`,
`netbird_owner`. Use `make ans-tags TAGS=netbird_config`.

## Identity providers (IdP)

The quickstart script **no longer installs Zitadel**. Since NetBird 0.62 the
server ships an **embedded Dex** IdP, and the dashboard manages local users
directly. This project mirrors that behaviour: **local users are the default**.

Any **OIDC-compliant** provider can additionally be attached as an *external*
IdP — Google, Microsoft Entra, Okta, Zitadel, Keycloak, **Authentik**, Pocket ID,
or a generic OIDC provider. Add it in **Settings → Identity Providers** (or via
`POST /api/identity-providers`); multiple providers can run alongside local
users. This is intentionally a **runtime/tenant configuration step**, not part
of the server-deploy role.

### Using an existing self-hosted Authentik

Yes, Authentik works. Register a **confidential OAuth2/OpenID** provider in
Authentik, copy the NetBird redirect URL into it, then add a *Generic OIDC* IdP
in NetBird with the issuer `https://authentik.example.com/application/o/netbird/`.
Caveats for a **remote-access** deployment:

- Both the user's browser **and** the NetBird server must be able to reach the
  Authentik issuer URL (discovery, JWKS, token, and the login/consent pages),
  over a **valid public TLS** certificate.
- If Authentik sits behind an IP allowlist that only permits LAN/CGNAT sources,
  public browsers and the public NetBird server will be rejected. Expose the
  OIDC/login paths publicly or allowlist the required source IPs first.
- JWT group sync: Authentik's `profile` scope includes `groups`; enable *JWT
  group sync* in NetBird and use the `groups` claim. (Zitadel instead exposes
  *roles* and needs an Action to flatten them into a flat `groups` array.)

## Managing tenants/ACLs with Ansible (config-as-code)

The `community.ansible_netbird` collection manages **tenant resources** against
the running server's REST API. This repo uses its Config-as-Code workflow:
versioned YAML in `netbird_config/` is applied declaratively, with plain names
resolved to IDs and resources applied in dependency order.

```bash
make netbird-plan          # read-only diff (safe default)
make netbird-apply         # apply the desired state
make netbird-apply-strict  # apply + remove unmanaged resources
```

Requires `vault_admin_service_user_access_token` (provisioned automatically on a
fresh deploy; otherwise create an `admin` service user + token under
Team → Service Users). What you can and cannot codify:

| Resource | Codifiable? | Notes |
|---|---|---|
| Groups, Policies (ACL), Posture checks | Yes | `access_control/*.yml`, name-based |
| Networks (routers/resources), DNS (nameservers/zones/settings) | Yes | `networks.yml`, `dns/*.yml` |
| Account settings (Dashboard settings) | Yes | `settings.yml` |
| Users / service users | Yes* | objects/roles/groups; embedded-IdP passwords are one-time |
| Setup keys | Yes* | secret value returned only at creation |
| Identity providers (external IdP) | Yes* | client secret must be stored in vault |
| **Peers** | **No** | enrolled devices: only settings are managed; devices re-enroll with setup keys |
| Audit / events | No | read-only |

`*` = the *declaration* is code, but a one-time secret is not reproducible; store
it in a secret manager.

## Backup & restore

```bash
make netbird-backup                              # -> backup/<host>/<stamp>/
make netbird-restore FROM=backup/<host>/<stamp>  # paired restore
```

The backup stops the container for a consistent SQLite copy, archives the
`netbird_data` volume, and saves `vault_managed.yml` (the encryption key)
alongside it. **Data and key must come from the same backup** or encrypted fields
cannot be decrypted. `backup/` is gitignored; keep a copy off-host.

## Mirrors for region-restricted hosts (optional)

`make host-bootstrap` (opt-in, not part of `ans-site`) can point a host at
alternative package mirrors — useful for China-based VPS. It is a no-op unless
the variables are set, and touches nothing in the deploy baseline:

```yaml
# inventory/host_vars/<host>/main.yml
host_apt_mirror: "https://mirrors.tuna.tsinghua.edu.cn/debian"
docker_registry_mirrors:
  - "https://docker.1ms.run"
```

## Layout

```
inventory/           # hosts.yml(.example), group_vars/netbird, host_vars/example
playbooks/site.yml   # server preflight + netbird_server role
playbooks/tenant.yml # tenant config-as-code (community.ansible_netbird)
netbird_config/      # declarative tenant desired state (versioned YAML)
roles/netbird_server # defaults (image pins), tasks, templates/
roles/helpers/       # shared vault-secret provisioning
```

## Secrets

Never commit vaults. User secrets live in the encrypted
`inventory/host_vars/<host>/vault.yml`; the role generates the crypto material
into the encrypted `vault_managed.yml` on first deploy (values are preserved
on later runs). **Back up `vault_managed.yml`** — losing
`vault_datastore_encryption_key` makes encrypted user data
unrecoverable.

## License

See `LICENSE`.
