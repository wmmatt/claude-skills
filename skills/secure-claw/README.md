# secure-claw

A Claude Code skill that scans your project against 17 defined security categories, intercepts unsafe package installs, and generates data flow diagrams with weaknesses highlighted.

## Quick install

```bash
# Per-project
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/SKILL.md \
  -o .claude/skills/secure-claw/SKILL.md --create-dirs

# Global (all projects)
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/SKILL.md \
  -o ~/.claude/skills/secure-claw/SKILL.md --create-dirs
```

## Update

Re-run the install command above to pull the latest SKILL.md. If you installed hooks, also update them:

```bash
# Update hooks
for hook in secure-claw-intercept.sh secure-claw-session-start.sh secure-claw-session-end.sh; do
  curl -sL "https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/hooks/${hook}" \
    -o ~/.claude/hooks/${hook} && chmod +x ~/.claude/hooks/${hook}
done
```

Check the [CHANGELOG](CHANGELOG.md) for what's new. Current version:

```bash
curl -s https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/VERSION
```

## What it does

On first encounter with a project, the skill:

1. **Profiles your app** -- reads your codebase to determine stack, data stores, auth method, payment integrations, and data sensitivity. Asks targeted questions only for what it can't figure out from the code.
2. **Determines your tier** -- not every app needs every check. A static HTML site gets 2 categories. A full-stack app with sensitive data gets 15. A multi-tenant SaaS gets all 17.
3. **Scans against a defined checklist** -- not ad-hoc "let me find something wrong." A fixed list of standards, checked consistently every time.
4. **Generates data flow and auth flow diagrams** -- with weaknesses highlighted in red so you can see where the gaps are.
5. **Stores a profile** in `.securecode/profile.json` so subsequent sessions are fast.

On every session after that:

- **Session start:** loads the profile, runs applicable checks, reports findings
- **Install interception:** catches `npm install` / `pip install` / `cargo add` / `curl | bash` before execution, checks packages against Socket.dev + GitHub Advisory Database
- **Session end:** re-scans for changes introduced during the session

## The 17 categories

| # | Category | Applies to |
|---|----------|------------|
| 1 | Dependency Tiering | Frontend SPA+ |
| 2 | Install Gatekeeper | Frontend SPA+ |
| 3 | License Compliance | All |
| 4 | Container Isolation | Frontend SPA+ |
| 5 | Environment Parity | Frontend SPA+ |
| 6 | Git Hygiene | All |
| 7 | Input Validation / Injection | Full-stack+ |
| 8 | Authentication & Authorization | Full-stack+ |
| 9 | Client-Side Security | Frontend SPA+ |
| 10 | CORS & API Hardening | Full-stack+ |
| 11 | Secrets Management | Full-stack+ |
| 12 | Data Encryption | Sensitive data+ |
| 13 | Data Sensitivity Profiling | Sensitive data+ |
| 14 | Multi-Tenant Isolation | Multi-tenant only |
| 15 | Serverless Preference | Sensitive data+ |
| 16 | CI/CD Pipeline Security | Full-stack+ |
| 17 | AI Config Hygiene + Access Control | Full-stack+ |

## Application tiers

The skill only activates the categories relevant to your project:

- **Static site** (flat HTML, docs) -- categories 3, 6
- **Frontend SPA** (React/Vue, no backend) -- categories 1-6, 9
- **Full-stack, no sensitive data** (internal tools, blogs) -- categories 1-10, 16, 17
- **Full-stack, sensitive data** (PII, PHI, financial) -- categories 1-13, 15-17
- **Multi-tenant, sensitive data** (SaaS with customer isolation) -- all 17

## Install interception

The intercept hook catches these patterns:

| Pattern | Action |
|---------|--------|
| `npm/pip/cargo/go/gem/composer install` | Scan packages |
| `brew install` / `apt-get install` | Scan packages |
| `curl \| bash` / `wget \| sh` | Hard block always |
| `curl -o && chmod +x` | Hard block always |
| `npx/bunx/pnpx <package>` | Scan the package |
| `make install` | Warn, ask to verify |

Packages are checked against:
1. Hardcoded blocklist (known compromised packages)
2. Socket.dev API (supply chain attacks, typosquatting, malware)
3. GitHub Advisory Database (known CVEs)
4. Project allowlist (`.securecode/allowlist.json`)

## OWASP Top 10:2025 coverage

| OWASP | Vulnerability | Covered by |
|-------|---------------|------------|
| A01 | Broken Access Control | 8, 14, 17 |
| A02 | Security Misconfiguration | 4, 5, 9, 10, 15 |
| A03 | Supply Chain Failures | 1, 2, 3 |
| A04 | Cryptographic Failures | 11, 12 |
| A05 | Injection | 7 |
| A06 | Insecure Design | 13, 14, 15 |
| A07 | Auth Failures | 8 |
| A08 | Integrity Failures | 1, 2, 6, 16 |
| A09 | Logging Failures | 10 |
| A10 | Exception Handling | 7 |

## Hooks (optional auto-enforcement)

See the [root README](../../README.md#with-hooks-auto-enforcement) for hook installation instructions. The hooks automate:

- **Session start** -- auto-profile or auto-scan on every new Claude Code session
- **Install interception** -- block/warn before any package install command runs
- **Session end** -- re-scan for changes made during the session
