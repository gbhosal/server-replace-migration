# App Team Functional Turnover — Replace Migration

**Purpose:** What the **App team** verifies and completes after **DevOps/Linux Admin** delivers the replacement host. DevOps/Linux Admin owns the platform; the App team owns workload behavior on the server.

**Customize this document** after Prompt 3 (runtime analysis). Remove sections that don't apply. Add rows for components your host actually runs — not every server has the same runtimes, agents, or job types.

**Server (example):** `batch-host01.example.corp`  
**Source (old):** `<SOURCE_IP>` — decommission after cutover  
**Target (new):** `<TARGET_IP>` — tag `batch-host01.example.corp (NEW)`  
**App data mounts:** `/appl`, `/data` (reattached — not copied)  
**Primary run-as users:** `appadmin`, `batchsvc`

**Repo reference:** https://github.com/gbhosal/server-replace-migration

---

## When you receive this document

| Milestone | DevOps/Linux Admin status | App team action |
|-----------|---------------------------|-----------------|
| **Turnover issued** | Playbook applied on target; breakage report attached | Review sections below; schedule validation window |
| **Smoke tests** | Platform items PASS in breakage report | Run smoke tests in §4; log PASS or defects |
| **Platform issues found** | DevOps/Linux Admin runs **Prompt 9** — playbook fix, re-apply, re-validate | Re-run failed smoke tests after fixes land on target |
| **Sign-off** | No open **platform** blockers; App confirms workloads OK | DevOps/Linux Admin runs oldroot cleanup; cutover scheduled |
| **Cutover** | DNS/LB/traffic pointed to target | Monitor first production cycle; source decommissioned |

Do **not** wait for cutover to run smoke tests. Validate on the `(NEW)` host while source still runs (where parallel operation is allowed).

---

## What DevOps/Linux Admin already delivered (don't redo)

| Item | How it was done |
|------|-----------------|
| Hostname, timezone | Ansible |
| App data volume mounts | Reattached EBS + fstab by UUID |
| Service accounts (uid/gid) | Ansible — matches source |
| User home directories, dotfiles | Copied from read-only old root |
| SSH host keys | Copied from old root (same fingerprint as source until cutover) |
| User crontabs | Copied from old root |
| OS CLI tools (ksh, mailx, curl, etc.) | Package manager via Ansible |
| Mail relay + from-address | Ansible `/etc/mail.rc` |
| Access control (netgroup, sudoers) | Ansible |

---

## What the App team owns (customize from discovery)

These are **intentionally outside** the Ansible playbook. Complete before cutover sign-off.

| Item | Why not in Ansible |
|------|-------------------|
| Workload runtimes (Java, Python, Node, etc.) | Version pins and install layout — varies per host |
| Vendor agents or middleware | Fresh install or config on new OS may be required |
| Language venv / pip packages | App repos and pins — not platform package list |
| Job-specific env vars / secrets | May live in dotfiles (copied) but must be validated |
| Application smoke tests | Only App team knows correct job output |
| Cron enable/disable vs external triggers | Crontab copied; entries may be commented intentionally |

**Add rows** from your Prompt 3 dependency matrix. **Delete rows** that don't apply to this server.

---

## Runtime verification checklist (examples — adapt per host)

Use only the subsections that match what Prompt 3 found on source. Add new subsections for anything else (containers, app servers, message clients, etc.).

### Example A: Language runtime (e.g. Java)

DevOps/Linux Admin may have **copied** runtime trees from old root. Verify — do not reinstall unless broken.

```bash
readlink -f /usr/bin/java    # omit if Java not used
/usr/bin/java -version

su - batchsvc
java -jar /appl/batch/bin/example-job.jar --help   # adjust path
```

**If runtime fails:** Document in breakage ticket. Confirm with App team before changing paths scripts expect.

### Example B: Python / pip (if scripts use hardcoded interpreter)

```bash
/usr/bin/python3.7 --version   # adjust version if discovery found a pin

# App team: create venv on app volume if needed
cd /appl/your-app
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Document interpreter path in app repo for the next OS migration.

### Example C: Vendor CLI on data volume

If discovery found binaries on a data mount and DevOps/Linux Admin created a symlink only:

```bash
findmnt /appl    # adjust mount
ls -la /path/to/vendor/bin/your-cli

su - appuser
/path/to/vendor/bin/your-cli --version
```

**App team** validates the tool works and any dependent services are started per your runbook.

### Example D: Mail from batch jobs

```bash
grep -E '^set (smtp|from)=' /etc/mail.rc
echo "Test" | mailx -s "Migration smoke test" your-team@example.com
```

### Example E: Cron entries

Crontabs were **copied** from source. Entries may be **commented** if jobs are triggered elsewhere.

```bash
sudo cat /var/spool/cron/batchsvc
```

**App team** confirms whether entries should be active on the new host.

---

## Smoke test matrix (fill in for your application)

| # | Job / script | Run-as user | Command (abbreviated) | Pass? | Notes |
|---|--------------|-------------|---------------------|-------|-------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

Run at least **one representative job per runtime or integration type** your workloads use.

---

## Reporting platform issues to DevOps/Linux Admin

When smoke tests fail due to **platform** gaps (not application logic), report them so DevOps/Linux Admin can run **Prompt 9** — incorporate fixes into the playbook, re-apply, and ask you to re-test.

| Report | Include |
|--------|---------|
| Symptom | What failed (error message, exit code) |
| Repro | Exact command, script path, run-as user |
| Expected | What source server did |
| Actual | What target `(NEW)` host did |
| Owner guess | Platform vs workload — DevOps will confirm |

**Platform-owned examples:** mount missing, wrong uid, mail relay rejected, OS package missing, sudo denied, incomplete home copy.

**Workload-owned (App team fixes):** application bug, venv/pip, vendor agent not installed, job data issue.

Use tickets or the open-items block in the sign-off template below. DevOps/Linux Admin will reply with which items were fixed on target and which remain App team-owned.

---

## Sign-off template

Copy into email or ticket when validation is complete.

```
Functional turnover sign-off — batch-host01.example.corp

Target: <TARGET_IP> (NEW)
Validated by: <name / team>
Date: <YYYY-MM-DD>

Smoke tests:
  [ ] <workload type 1> — PASS
  [ ] <workload type 2> — PASS
  [ ] Mail notification — PASS (if used)
  [ ] Representative scheduled/manual job — PASS

Open items (if any):
  - <ticket> — <description> — owner (DevOps / App) — ETA

Platform issues pending Prompt 9 fix: YES / NO
Approved for oldroot cleanup: YES / NO
Approved for cutover: YES / NO
```

---

## After sign-off — DevOps/Linux Admin actions

1. Run playbook with `enable_migration_cleanup=true`, `enable_copy_from_oldroot=false`
2. Detach old source root volume in cloud console
3. Schedule DNS / load balancer / traffic cutover
4. **Stop source instance** before cutover if SSH host keys were copied (duplicate key risk)
5. Steady-state: CI/CD on main branch only (no oldroot copy)

---

## Contact matrix (customize per organization)

| Area | Party | Validates |
|------|-------|-----------|
| Platform / mounts / users | DevOps/Linux Admin | MIGRATION-ASSESSMENT.md, BREAKAGE-REPORT.md |
| Workloads / scripts / smoke tests | App team | This document §4 |
| Cutover window | Change management | Sign-off + CAB if required |

---

*Obfuscated example. Replace hostnames, paths, and contacts with your environment. Improvise sections based on Prompt 3 output — do not assume every host matches this template.*
