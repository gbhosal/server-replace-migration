# Server Replace Migration — Example Repository

**Repository:** https://github.com/gbhosal/server-replace-migration

Obfuscated, educational example of a **lift-and-replace server migration** workflow:

- Ansible playbook (narrow infra scope, feature flags)
- Bash script to provision a target instance from a source
- GitHub Actions workflow (feature branch = check mode, main = apply)

**Illustrated with:** Amazon Linux 2 → Amazon Linux 2023 on AWS EC2 + SSM.  
**Applicable to:** any migration where in-place upgrade isn't viable (OS generation changes, golden AMI swaps, hardware refresh with data volume reattach).

**SSH MCP (optional):** Prompts assume an IDE with [SSH MCP Server](https://mcpservers.org/servers/giuliolibrando/ssh-mcp-server) ([GitHub](https://github.com/giuliolibrando/ssh-mcp-server)). See [PROMPTS.md](PROMPTS.md) for setup notes and copy-paste prompts.

All hostnames, account IDs, ARNs, and UUIDs are fictional.

---

## Documentation map

| Document | Audience | Purpose |
|----------|----------|---------|
| [PROMPTS.md](PROMPTS.md) | DevOps/Linux Admin + AI IDE | **When** to run each prompt; adapt copy per host |
| [APP-TURNOVER-GUIDANCE.md](APP-TURNOVER-GUIDANCE.md) | App team | **Customizable functional turnover** after platform apply |
| `hosts/.../var/*.yaml` | Infra | Discovery output → Ansible data |

---

## Repository layout

```
server-replace-migration/
├── README.md                          ← start here
├── PROMPTS.md                         ← AI prompts: intent, when to use, step order
├── APP-TURNOVER-GUIDANCE.md           ← customize and share with App team
├── LICENSE
├── .gitignore
├── .github/workflows/
│   └── batch-host01.yml
└── hosts/batch-host01.example.corp/
    ├── server-migration.yaml
    ├── helper.sh
    ├── var/batch-host01.yaml
    ├── tasks/
    └── scripts/provision-target-from-source.sh
```

---

## What's in this repo

| Path | Purpose |
|------|---------|
| `README.md` | Repo overview |
| `.gitignore` | Ignore local secrets and generated migration docs |
| `PROMPTS.md` | Adaptable AI prompts with intent + when-to-use step table |
| `APP-TURNOVER-GUIDANCE.md` | Customizable functional turnover template for App team |
| `LICENSE` | MIT license |
| `.github/workflows/batch-host01.yml` | CI/CD pattern |
| `hosts/batch-host01.example.corp/server-migration.yaml` | Main playbook |
| `hosts/.../var/batch-host01.yaml` | Example vars from discovery |
| `hosts/.../tasks/*.yml` | Mount, oldroot copy, cleanup |
| `hosts/.../scripts/provision-target-from-source.sh` | Target provisioning |
| `hosts/.../helper.sh` | Stub pre-zip script |

---

## Customization before use

1. Replace `123456789012` IAM account ID and role ARNs in the workflow.
2. Replace S3 bucket name and SSM document name if not using AWS defaults.
3. Update `var/batch-host01.yaml` from **your** source server discovery (UUIDs, uids, packages).
4. Adjust `target_name_suffix` in the provision script to match your SSM/automation tag convention.
5. Set `enable_copy_from_oldroot: false` after first successful migration.

---

## Step-by-step approach (with prompts)

| Step | Action | Reference |
|------|--------|-----------|
| 1 | Discover source server | [PROMPTS.md § Prompt 1](PROMPTS.md#prompt-1--source-discovery-ssh) |
| 2 | Scaffold playbook + CI | [PROMPTS.md § Prompt 2](PROMPTS.md#prompt-2--scaffold-playbook-and-ci) |
| 3 | Runtime / script analysis | [PROMPTS.md § Prompt 3](PROMPTS.md#prompt-3--runtime-script-and-package-analysis) |
| 4 | Remove app-owned scope from Ansible | [PROMPTS.md § Prompt 4](PROMPTS.md#prompt-4--scope-exclusions) |
| 5 | Provision target instance | `scripts/provision-target-from-source.sh` |
| 6 | Precheck target (**before any apply**) | [PROMPTS.md § Prompt 5](PROMPTS.md#prompt-5--target-precheck) |
| 7a | Check mode apply (feature branch) | CI/CD dry run |
| 7b | MCP review planned changes (**before merge**) | Gate — approve before full apply |
| 7c | Full apply (merge to main) | CI/CD production apply |
| 8 | Post-apply validation (**after full apply**) | [PROMPTS.md § Prompt 6](PROMPTS.md#prompt-6--post-apply-validation) |
| 9 | Package parity (if needed) | [PROMPTS.md § Prompt 7](PROMPTS.md#prompt-7--package-parity-update) |
| 10 | Breakage report (**after Prompt 6**) | [PROMPTS.md § Prompt 8](PROMPTS.md#prompt-8--breakage-report-and-assessment) |
| 11 | **Functional turnover to App team** | [APP-TURNOVER-GUIDANCE.md](APP-TURNOVER-GUIDANCE.md) |
| 12 | App smoke tests | APP-TURNOVER-GUIDANCE.md § Smoke test matrix |
| 13 | **App feedback → playbook fix loop** | [PROMPTS.md § Prompt 9](PROMPTS.md#prompt-9--app-feedback-playbook-iteration) |
| 14 | App sign-off | APP-TURNOVER-GUIDANCE.md § Sign-off template |
| 15 | Cleanup oldroot + cutover | `enable_migration_cleanup=true`; decommission source |

Full workflow: [PROMPTS.md — Validation timeline](PROMPTS.md#validation-timeline-dont-skip).

---

## Phased execution (recommended)

```bash
# Steps 1–4: Use PROMPTS.md (discovery → scaffold → analysis → scope)
#   Output: var/batch-host01.yaml + reviewed playbook

# Step 5: Provision target (dry run first)
./scripts/provision-target-from-source.sh \
  --source-instance-id i-0source1234567890 \
  --target-ami-id ami-0TARGET0000000000 \
  --dry-run

# Step 6: PROMPTS.md Prompt 5 — target precheck (before ANY apply)

# Step 7a: Feature branch → check mode only (dry run)
# Step 7b: MCP review planned changes — gate before merge to main
# Step 7c: Merge to main → full apply

# Steps 8–10: PROMPTS.md Prompts 6–8 — AFTER full apply only

# Step 11: Customize and share APP-TURNOVER-GUIDANCE.md with App team

# Step 12: App smoke tests — App team reports platform issues per APP-TURNOVER-GUIDANCE

# Step 13: PROMPTS.md Prompt 9 — incorporate platform fixes, re-apply, re-validate; loop until sign-off

# Step 14–15: Cleanup oldroot + cutover after App sign-off
#   -e "enable_migration_cleanup=true enable_copy_from_oldroot=false"

# Steady state: CI/CD on main branch only (no oldroot copy)
```

---

## License

MIT — use freely for learning and adaptation. No warranty; review before production use.
