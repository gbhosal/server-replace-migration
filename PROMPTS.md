# Migration Prompts — Intent, When to Use, and Step-by-Step Flow

Reusable prompts for AI-assisted IDE sessions (with SSH MCP) during **replace-style Linux server migrations**. Illustrated with AL2 → AL2023; adapt placeholders for your host.

**Repository:** https://github.com/gbhosal/server-replace-migration

**Operational rule:** Wrap every SSH command in `timeout` (e.g. `timeout 30 bash -c '...'`) so hung LDAP/NFS lookups do not block the session.

**SSH MCP:** Prompts that touch live servers start with **Using SSH MCP**. Prompts 2 and 4 are repo/doc work only — no SSH session required.

**SSH MCP server (reference):** We use [SSH MCP Server](https://mcpservers.org/servers/giuliolibrando/ssh-mcp-server) ([GitHub](https://github.com/giuliolibrando/ssh-mcp-server)) in Cursor. It exposes remote command execution over SSH via MCP tools (`execute_command`, file read/list, service status, etc.). Configure one host per session or switch `SSH_HOST` between source and target. Any SSH-capable MCP server works; adapt tool names if yours differ.

| Prompt | SSH MCP? | Hosts |
|--------|----------|-------|
| 1 Source discovery | Yes | Source |
| 2 Scaffold playbook | No | — |
| 3 Runtime analysis | Yes | Source (target if reachable) |
| 4 Scope exclusions | No | — |
| 5 Target precheck | Yes | Target |
| Check-mode review | Yes | Target |
| 6 Post-apply validation | Yes | Source + target |
| 7 Package parity | Yes | Source + target |
| 8 Breakage report | Yes (revalidate) | Target (+ source to compare) |
| 9 App feedback loop | Yes (revalidate) | Target (+ source to compare) |

**Adapt, don't copy verbatim.** These prompts are a starting scaffold. Every host differs — mounts, runtimes, agents, and job types vary or may not exist at all. Before each session:

- Add discovery items your source actually has (web stacks, message queues, custom agents, etc.)
- Drop sections that don't apply (no Java? remove JVM checks from Prompt 3 and 6)
- Extend **Out of playbook** and **APP-TURNOVER-GUIDANCE.md** with whatever Prompt 3 finds on *your* server
- Keep the two-party split: **DevOps/Linux Admin** = platform; **App team** = workload on the box

---

## Validation timeline (don't skip)

Replace migrations use **distinct checkpoints**. They answer different questions:

| Step | When | Question |
|------|------|----------|
| **Precheck (Prompt 5)** | Before any apply | Is the blank target ready? |
| **Check-mode review** | After dry run, before merge to main | Will the playbook do the right thing? |
| **Post-apply validation (Prompt 6)** | After full apply | Did migration succeed? |
| **Breakage report (Prompt 8)** | After Prompt 6 | What's fixed, open, and who owns it? |
| **App feedback loop (Prompt 9)** | After App smoke tests report platform issues | Playbook updated, re-applied, re-validated |

**Breakage report is not a pre-apply step.** Check mode surfaces risky tasks early; mounts, copies, and packages only prove out after **full apply**.

**App feedback loop:** When smoke tests surface **platform-owned** gaps (missing package, mount, uid, mail relay), DevOps/Linux Admin incorporates fixes into the playbook (Prompt 9), re-runs check mode → full apply, and re-validates. App team re-runs smoke tests until sign-off. Workload-owned items stay with the App team — not every smoke failure becomes a playbook change.

---

## When to use which prompt

| Step | Phase | Prompt | You are here when… |
|------|-------|--------|-------------------|
| 0 | Plan | — | Migration approved; source host identified; target AMI chosen |
| 1 | Discover | **Prompt 1** | No `var/<hostname>.yaml` yet; need inventory from source |
| 2 | Build | **Prompt 2** | Discovery done; need playbook, CI, and doc scaffold |
| 3 | Analyze | **Prompt 3** | Playbook draft exists; need runtime/script dependency matrix |
| 4 | Scope | **Prompt 4** | Playbook includes app-owned items that must be removed |
| 5 | Precheck | **Prompt 5** | Target provisioned; **before any** playbook apply |
| 6 | Check mode | — | Feature branch / `ansible-playbook --check` — dry run only |
| 6b | Review | **Check-mode review** | Using SSH MCP on target; **gate before merge to main** |
| 7 | Full apply | — | Merge to main / full apply |
| 8 | Validate | **Prompt 6** | **After full apply** — source vs target diff |
| 9 | Packages | **Prompt 7** | Validation found missing OS tools (optional) |
| 10 | Document | **Prompt 8** | **After Prompt 6** — breakage report for cutover / turnover |
| 11 | Turnover | — | Share **APP-TURNOVER-GUIDANCE.md** with App team |
| 12 | Smoke tests | — | App team runs smoke test matrix on `(NEW)` host |
| 13 | Fix loop | **Prompt 9** | App reported **platform** issues — update playbook, re-apply, re-test |
| 14 | Sign-off | — | App confirms workloads OK; no open platform blockers |
| 15 | Cleanup | — | `enable_migration_cleanup=true`; detach old root EBS |
| 16 | Cutover | — | DNS/LB/traffic switch; decommission source |

![Migration prompt step flow — when to use each prompt](diagrams/prompt-step-flow.png)

---

## Prompt 1 — Source discovery (SSH MCP)

**Intent:** Inventory everything needed to populate `var/<hostname>.yaml` before writing Ansible.

**When to use:** First SSH MCP session on the **source** server. Before any playbook YAML exists.

**Prerequisites:** SSH MCP access to source; read-only/sudo as needed.

```
Using SSH MCP, connect to source server <SOURCE_IP> (environment <ENV>, region <REGION>).
Use timeout on every command.

Discover and document:
1. App data mounts — mount points, filesystem UUIDs, LVM volume groups (vgchange needed?)
2. App/service users — names, uid/gid, home dirs, shells
3. Crontabs — /var/spool/cron/* (all users)
4. Services — sssd, chronyd, crond, sshd, postfix, autofs, agent/exporter services
5. Mail — /etc/mail.rc SMTP relay and from-address
6. Access control — netgroup rules, sudoers.d entries
7. Old source root volume filesystem UUID (for read-only /mnt/oldroot copy)
8. SSH host keys to copy (RSA + ECDSA; skip DSA if deprecated on target OS)

Output a summary table suitable for var/<hostname>.yaml.
List what lives on ROOT vs DATA volumes separately.
Do not commit unless asked.
```

**Example outcome (illustration):** 4 mounts, 9 service accounts, oldroot UUID documented, mail from-address captured.

---

## Prompt 2 — Scaffold playbook and CI (no SSH MCP)

**Intent:** Create migration directory, playbook structure, GitHub Actions workflow, and operator docs in one pass.

**When to use:** After Prompt 1 output exists. Before deep runtime analysis.

**Prerequisites:** Hostname, environment path, target tagging convention (e.g. `Name: <hostname> (NEW)`). No SSH MCP — work from Prompt 1 output and repo layout.

```
No SSH MCP for this step. Using Prompt 1 discovery output, replace-migrate <HOSTNAME> from source OS to target OS in <ANSIBLE_REPO>.

### Server context
- Hostname: <HOSTNAME>
- Environment: <ENV> / region <REGION>
- Source IP: <SOURCE_IP>
- Target IP: <TARGET_IP or TBD>
- Remote apply tag: <HOSTNAME> (NEW)
- Reference layout: hosts/batch-host01.example.corp in server-replace-migration repo

### Migration strategy
1. Reattach app data volumes by filesystem UUID (not cloud volume ID).
2. Attach old source root read-only at /mnt/oldroot for one-time copy; detach after validation.
3. Do NOT clone entire old root — copy only what playbook explicitly lists.

### Ansible scope (infra-owned only)
- server-migration.yaml (hosts: 127.0.0.1, remote apply via SSM or equivalent)
- Hostname, timezone, crond, OS packages (dnf/yum)
- /etc/mail.rc relay + from-address from discovery
- App users/groups with fixed uid/gid
- Netgroup + sudoers (visudo validate)
- Feature flags: enable_mounts, enable_copy_from_oldroot, oldroot_unmount_after_copy,
  enable_migration_cleanup (false until validated)

tasks/mount.yml, copy_from_oldroot.yml, cleanup_migration.yml
var/<hostname>.yaml from discovery

### Out of playbook (document for App team — customize APP-TURNOVER-GUIDANCE.md)
- Anything Prompt 3 classifies as App team-owned (runtimes, agents, venv, vendor tools)
- Workload start/stop and operational runbooks
- Application smoke tests

Add or remove bullets based on what discovery finds — not every server has the same components.

### CI/CD
- Path-filtered workflow
- feat/<host-short> → check mode only (no mutations)
- main → full apply

Produce: README.md, MIGRATION-ASSESSMENT.md, APP-TURNOVER-GUIDANCE.md template.
Follow repo conventions. Minimize scope. Do not commit unless asked.
```

---

## Prompt 3 — Runtime, script, and package analysis (SSH MCP)

**Intent:** Find application dependencies in scripts; classify remediation (reattach / copy / package install / app team).

**When to use:** After playbook scaffold. Before declaring infra scope final.

**Prerequisites:** SSH MCP to source; target optional if already provisioned. Paths to app volumes known (`/appl`, `/data`, etc.).

```
Using SSH MCP, connect to source <SOURCE_IP> (and target <TARGET_IP> if already provisioned).

For <HOSTNAME> (source <SOURCE_IP>, target <TARGET_IP or TBD>):

1. Scan shell scripts on app volumes for:
   - Shebangs and hardcoded paths (/usr/bin/ksh, java, perl, python, ftp, vendor CLIs)
   - Version pins (/usr/bin/python3.7, /opt/jdk*, custom install paths)

2. Compare deliberate OS packages on source vs target golden AMI:
   - Exclude base AMI and patch-only churn
   - Identify gaps requiring package manager install on target

3. Classify each dependency:
   | Strategy | Examples |
   |----------|----------|
   | Reattach EBS (no copy) | Application trees on data volumes |
   | Copy from oldroot | JVM trees, /etc/alternatives, legacy /opt installs |
   | Package manager install | ksh, mailx, CLI tools when binary not portable — ABI mismatch |
   | App team | Workload runtimes, agents, venv/pip, vendor install + config |
   | Blocked / workaround | Packages removed in new OS repos |

4. Prefer copy-first for pinned runtime layouts when scripts hardcode paths.

Update playbook vars/tasks and APP-TURNOVER-GUIDANCE.md with owners per item.
Improvise: add rows for components unique to this host (containers, middleware, etc.).
Use timeout on all SSH MCP commands.
Do not commit unless asked.
```

---

## Prompt 4 — Scope exclusions (no SSH MCP)

**Intent:** Remove app-owned components from Ansible; keep playbook infra-only.

**When to use:** After Prompt 3, when playbook draft includes App team-owned components that should not be in Ansible.

**Prerequisites:** Agreement with App team on ownership boundaries (from Prompt 3 output). No SSH MCP — edit playbook and docs only.

```
No SSH MCP for this step. Using Prompt 3 findings, for <HOSTNAME> playbook confirm and apply scope exclusions:

1. Remove any workload agents, runtime installs, or start/stop tasks from Ansible
2. Do not mount legacy data volumes unless App team explicitly requests
3. Document each excluded item in APP-TURNOVER-GUIDANCE.md with owner and verification steps

Improvise: use your Prompt 3 matrix — there is no fixed list of what to exclude.

Update README, vars, and APP-TURNOVER-GUIDANCE.md.
Do not commit unless asked.
```

---

## Prompt 5 — Target precheck (SSH MCP)

**Intent:** Validate vanilla target **before** first playbook apply; fix UUIDs and flags.

**When to use:** After `provision-target-from-source.sh` (or equivalent). Before any apply.

**Prerequisites:** Target instance running; disks attached per vars file. SSH MCP to target.

```
Using SSH MCP, connect to target server <TARGET_IP>. Source reference is <SOURCE_IP>.

Before first playbook execution, verify on <TARGET_IP>:
- OS version matches target generation (confirm IP roles — not validating wrong host)
- Base services: remote management agent, SSO, monitoring exporters
- Attached disks match var/<hostname>.yaml UUIDs (lsblk -f)
- Old source root volume attached if enable_copy_from_oldroot=true
- No stale /mnt/oldroot or wrong fstab entries from prior attempts

Fine-tune playbook and vars for findings. Use timeout on all SSH MCP commands.
Do not commit unless asked.
```

---

## Check-mode review (SSH MCP)

**Intent:** Review Ansible check-mode output on the target before merge to main. No mutations yet.

**When to use:** After CI/CD or local `ansible-playbook --check` on feature branch. Before merge to main / full apply.

**Prerequisites:** Check mode completed; SSH MCP to target.

```
Using SSH MCP, connect to target <TARGET_IP> (confirm NOT source <SOURCE_IP>).

Check-mode review — before full apply:
1. Read check-mode / SSM apply output: any unexpected changes, destructive tasks, or failed dry-run steps?
2. On target, confirm nothing was mutated (mounts not yet applied, users not yet created, etc.) unless check mode reported "changed" legitimately.
3. Compare planned changes against Prompt 1 / var/<hostname>.yaml intent.
4. STOP if check mode shows wrong host, wrong UUIDs, or risky tasks — fix playbook/vars and re-run check mode.

Use timeout on any live SSH MCP commands.
Do not merge to main until this review passes.
```

---

## Prompt 6 — Post-apply validation (SSH MCP)

**Intent:** Smoke-test target after playbook; diff against source; catch copy gaps.

**When to use:** Immediately after first **full** apply — **not** after check mode alone. Before App team turnover.

**Prerequisites:** Full apply completed; SSH MCP to source and target.

```
Using SSH MCP, connect to target <TARGET_IP> and source <SOURCE_IP>.
Confirm you are validating target <TARGET_IP>, NOT source <SOURCE_IP>.

Playbook was applied on target. Validate against source reference:
- Hostname, timezone, mounts (findmnt for each app path)
- Users — id for each app account; uid/gid match source
- Runtimes — paths scripts expect (java, python, vendor CLIs — only what discovery found)
- Mail — /etc/mail.rc relay and from-address
- Homes — app user dotfiles (.ssh, .aws, app config) copied from oldroot
- Cron — /var/spool/cron/* ; crond active
- SSH host key fingerprint (note duplicate-key risk while both hosts live)
- Monitoring endpoints if applicable
- Playbook-installed packages

Output PASS / FAIL / OPEN with owner (DevOps/Linux Admin / App team).
Use timeout on all SSH MCP commands.
Improvise: extend the checklist with items from your Prompt 3 matrix.
```

---

## Prompt 7 — Package parity update (SSH MCP)

**Intent:** RPM/package diff with deliberate-install filter; update vars package list.

**When to use:** When Prompt 6 finds missing CLI tools, or proactively after first apply.

**Prerequisites:** SSH MCP to source and target.

```
Using SSH MCP, connect to source <SOURCE_IP> and target <TARGET_IP>.

1. Compare installed package lists on both hosts
2. Exclude base AMI and patch-only packages
3. List deliberate source-only installs missing on target
4. Update packages in var/<hostname>.yaml
5. Note packages unavailable in target repos with workarounds in breakage report

Confirm all analysis used source <SOURCE_IP> and target <TARGET_IP> via SSH MCP — not the wrong host.
Use timeout on all SSH MCP commands.
Do not commit unless asked.
```

---

## Prompt 8 — Breakage report and assessment (SSH MCP to revalidate)

**Intent:** Produce/maintain breakage document and pre-cutover checklist for stakeholders.

**When to use:** After Prompt 6 post-apply validation — **not** before full apply. Re-run after each playbook fix.

**Prerequisites:** Validation results from Prompt 6. Use SSH MCP to confirm RESOLVED items on target.

```
Using SSH MCP on target <TARGET_IP> (and source <SOURCE_IP> when comparing), for <HOSTNAME> migration:

1. Create or update BREAKAGE-REPORT.md:
   - Severity: blocker / high / medium / low
   - Per item: symptom, cause, workaround, owner, verified status on target
   - Section: what does NOT break (playbook or volume reattach)

2. Create or update MIGRATION-ASSESSMENT.md:
   - Pre-cutover checklist with owners and dates
   - DevOps/Linux Admin complete vs App team open items

3. Cross-reference APP-TURNOVER-GUIDANCE.md for App team actions (customized per host).

Revalidate RESOLVED items on target via SSH MCP after each playbook fix.
Use timeout on all SSH MCP commands.
Do not commit unless asked.
```

---

## Prompt 9 — App feedback playbook iteration (SSH MCP to revalidate)

**Intent:** Triage App team smoke-test findings; incorporate **platform-owned** fixes into the playbook; re-apply and re-validate until App team sign-off.

**When to use:** After App team reports issues from smoke tests (or during turnover validation). When failures trace to mounts, packages, users, mail, sudoers, or other DevOps/Linux Admin scope — **not** for workload-only fixes the App team owns.

**Prerequisites:** Issue list with repro steps, expected vs actual, and run-as user; breakage report and APP-TURNOVER-GUIDANCE available.

```
App team reported issues on <HOSTNAME> target <TARGET_IP> after smoke tests.

Issue list:
<paste tickets, email, or table from App team>

For each item:
1. Classify owner:
   | Owner | Action |
   |-------|--------|
   | DevOps/Linux Admin | Update playbook, vars, or tasks |
   | App team | Update APP-TURNOVER-GUIDANCE / their runbook — no Ansible change |
   | Blocked | Document workaround in BREAKAGE-REPORT.md |

2. For DevOps/Linux Admin items only:
   - Update server-migration.yaml, tasks/, or var/<hostname>.yaml
   - Push feature branch → check mode → check-mode review (SSH MCP) → merge → full apply
   - Using SSH MCP on target <TARGET_IP>, re-run Prompt 6 checks for affected areas (or full diff if faster)
   - Update BREAKAGE-REPORT.md and MIGRATION-ASSESSMENT.md (Prompt 8)

3. Notify App team which items are fixed on target; ask them to re-run failed smoke tests.

4. Repeat until App team sign-off with no open platform blockers.

Use timeout on all SSH MCP commands. Do not expand Ansible into App team scope. Do not commit unless asked.
```

**Example platform fixes:** missing OS package, wrong mail from-address, uid mismatch, mount not in fstab, incomplete oldroot copy path.

**Not Prompt 9 scope:** application logic bugs, venv setup, vendor agent install — App team owns those per Prompt 4.

---

## Quick reference: decisions on every migration

| Decision | Rationale |
|----------|-----------|
| Mount by **filesystem UUID** | Persists across snapshot restore; cloud vol-id does not |
| **Fixed uid/gid** for app users | Ownership on reattached data volumes |
| **Copy runtimes** from oldroot when paths are hardcoded | Scripts break if layout changes |
| **Package manager** for CLI tools when binary not portable | OpenSSL/library ABI mismatch across OS generations |
| **SSH host keys** from oldroot | Avoids client trust churn at cutover (stop source before DNS swap) |
| **Workload components out of Ansible** | App team owns what runs on the box — list varies per host |
| **Confirm host IP** before validation | Easy to SSH to wrong host during parallel run |
| `enable_copy_from_oldroot=true` **once** | Disable for steady-state CI runs |
| `enable_migration_cleanup=true` **after app sign-off** | Then detach old root volume in cloud console |
| **Prompt 9 before cleanup** | Incorporate App platform issues into playbook; re-apply until smoke tests pass |

---

## Artifacts per migration

| File | Purpose | Created by step |
|------|---------|-----------------|
| `var/<hostname>.yaml` | Discovery → data | Prompt 1 |
| `server-migration.yaml` + tasks | Infra automation | Prompt 2 |
| `.github/workflows/*.yml` | CI/CD apply | Prompt 2 |
| `APP-TURNOVER-GUIDANCE.md` | App team functional turnover | Prompt 2–4, refined in 8 |
| `MIGRATION-ASSESSMENT.md` | Pre-cutover checklist | Prompt 8 |
| `BREAKAGE-REPORT.md` | Gaps, owners, workarounds | Prompt 6, 8, 9 |
| `PROMPTS.md` | This document | Reference |
