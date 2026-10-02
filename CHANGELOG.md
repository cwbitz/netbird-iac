# Changelog

## [1.1.0](https://github.com/cwbitz/netbird-iac/compare/v1.0.0...v1.1.0) (2026-10-02)


### Features

* verify GitHub App release automation end to end ([f877949](https://github.com/cwbitz/netbird-iac/commit/f87794900a8cd45a27f1c1f4953656b919936530))

## 1.0.0 (2026-10-02)


### ⚠ BREAKING CHANGES

* **tenant:** fold apply-strict into apply via tenant_strict
* **secrets:** vault_managed.yml no longer holds control-generated keys. Run `make vault-migrate` once per existing host to move them into vault.yml.
* **make:** make targets were renamed/removed. Use install, lint, dry-run, deploy, print, ping, plan, apply, apply-strict, backup, restore.
* **tenant:** the committed netbird_config/ directory is removed; tenant resources must be declared as per-host variables and playbooks/tenant.yml no longer reads netbird_config/.
* **vars:** host_vars overrides must use the new names (host_ssh_*, domain_name, letsencrypt_email, owner_*, disable_geolite_update), and `-e tenant_commit=true` / `-e restore_from=...` replace the netbird_-prefixed extra vars.
* **netbird:** vault_pat is renamed to vault_admin_service_user_access_token (an empty/absent value on a fresh deploy is filled automatically), and the netbird_setup_pat_enabled / netbird_owner_create_pat variables are removed.
* **host-vars:** update any host_vars overrides to the new host_* names.
* **vault:** existing hosts must rename inventory/host_vars/<host>/vault_generated.yml to vault_managed.yml before the next deploy, otherwise the store/session encryption keys are regenerated and already-encrypted data becomes unrecoverable.

### Features

* **bootstrap:** authorize per-identity SSH public keys ([a2a75ef](https://github.com/cwbitz/netbird-iac/commit/a2a75ef755cf52176b28a6af67cc4f064548d2ee))
* **bootstrap:** provision a configured admin account ([15472a0](https://github.com/cwbitz/netbird-iac/commit/15472a016402d8b1702cfaf806b2f61963f3b391))
* **docker:** install Docker CE via the official get.docker.com script ([f87bc30](https://github.com/cwbitz/netbird-iac/commit/f87bc3029a383d1ffc5859fffd33ba5443a2f31b))
* **docker:** install Docker CE when it is missing ([88a6d07](https://github.com/cwbitz/netbird-iac/commit/88a6d073eaeee35db1599e155860d88c34e77172))
* **make:** apply the tenant state in deploy ([c8d699c](https://github.com/cwbitz/netbird-iac/commit/c8d699c4c4f3d8000e035f2db7ea091bd711eb2a))
* **make:** auto-install sshpass via check-deps ([5b2d764](https://github.com/cwbitz/netbird-iac/commit/5b2d764c55d1ae48a5b7eacdfcda970ea0267a7f))
* **make:** run host-bootstrap first in deploy and make tenant_strict strictly opt-in ([f503462](https://github.com/cwbitz/netbird-iac/commit/f503462f264620b511b81e28d19167b6101308b1))
* **netbird:** bootstrap the admin service-user access token ([1498ef9](https://github.com/cwbitz/netbird-iac/commit/1498ef9f17b9272700a7c1d6ec7bc40574cb33fb))
* **netbird:** generate the first-owner password ([4a834d4](https://github.com/cwbitz/netbird-iac/commit/4a834d46cc4f2375384628844b6597ff0cc98993))
* **tenant:** auto-converge routed networks on gateway enrollment ([0ccddbe](https://github.com/cwbitz/netbird-iac/commit/0ccddbe8a6a3b44d6deb91fdd2fd0e1f5482f5e9))
* **tenant:** persist newly created setup key secrets ([bde1b07](https://github.com/cwbitz/netbird-iac/commit/bde1b07cfb7bb79b3bb4bedf040bcbc6ec8f656e))


### Bug Fixes

* **bootstrap:** apply the probed SSH identity as play vars ([d8e4eb3](https://github.com/cwbitz/netbird-iac/commit/d8e4eb33248f6dfa4586bbd47ba483247a9badd9))
* **bootstrap:** avoid dynamic-only group and undefined-var lint warnings ([22bc3ed](https://github.com/cwbitz/netbird-iac/commit/22bc3ed0f0b3410935a164f9be8ba8b72a1d82c1))
* **example:** hardcode the root SSH user and drop vault_root_user ([71a9e6a](https://github.com/cwbitz/netbird-iac/commit/71a9e6a4ee6845a9ec620d4dfba64155c90666a9))
* **host-init:** scaffold an encrypted vault with safe permissions ([0ca5dc4](https://github.com/cwbitz/netbird-iac/commit/0ca5dc43c1b20326f6d6ca941e39c43d09457d61))
* **netbird:** make the check-mode dry-run work on a fresh host ([ff2f770](https://github.com/cwbitz/netbird-iac/commit/ff2f770680bf7b745c6c854869c8be5e75de2d76))
* **tenant:** drop the deprecated vault_pat fallback ([efe7561](https://github.com/cwbitz/netbird-iac/commit/efe75616c6cd17d6f7b337420855cab62afaccfa))
* **tenant:** resolve netbird_user auto_groups names to IDs ([6acb2d4](https://github.com/cwbitz/netbird-iac/commit/6acb2d4ce948fd6f6b3a23eb9744c5f2ac531985))


### Code Refactoring

* **host-vars:** rename netbird_* host knobs to host_* ([cf264d9](https://github.com/cwbitz/netbird-iac/commit/cf264d958b26f873fdd65ca8b6049730fdf56843))
* **make:** flatten and rename targets, drop ans-/netbird- prefixes ([84444f5](https://github.com/cwbitz/netbird-iac/commit/84444f5697ea0d53b8f184b4c6c9e7cf613b71e8))
* **secrets:** split vault.yml (control-authoritative) from vault_managed.yml (host-authoritative) ([42f8ef6](https://github.com/cwbitz/netbird-iac/commit/42f8ef68b52688b64c9a59c17ceef3c6cad24ee4))
* **tenant:** drive tenant config-as-code from per-host vars ([1b6f46c](https://github.com/cwbitz/netbird-iac/commit/1b6f46c34946200bfb9655b588a2e6f9bdb79073))
* **tenant:** fold apply-strict into apply via tenant_strict ([a7ffc1c](https://github.com/cwbitz/netbird-iac/commit/a7ffc1c64a82c059df4812f9112f492c4d17cbc6))
* **vars:** drop the netbird_ prefix from project-owned variables ([132b1c2](https://github.com/cwbitz/netbird-iac/commit/132b1c2916eb800e6fae192a9e465f66d56d298a))
* **vault:** rename vault_generated.yml to vault_managed.yml ([db8fba6](https://github.com/cwbitz/netbird-iac/commit/db8fba627ce66cc530462b3a9afc9155873dda78))
