# secure-claw

**Intercepts and blocks malicious package installs before they execute. Then audits your entire codebase against a 17-category security checklist.**

---

## Install

```bash
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/install.sh | bash
```

That's it. The script downloads SKILL.md, installs the three hook scripts, and merges the hook configuration into `~/.claude/settings.json` without touching your existing settings. Safe to run multiple times.

---

## The killer feature: install interception

When Claude tries to run `npm install`, `pip install`, `cargo add`, or any other package install, secure-claw intercepts it first-- before anything hits your filesystem.

It checks every package against:
1. A hardcoded blocklist of known-compromised packages (including `litellm`, `event-stream`, `ua-parser-js`, and others)
2. Socket.dev API -- catches supply chain attacks, typosquatting, and malicious install scripts
3. GitHub Advisory Database -- catches known CVEs

If anything looks wrong, it blocks the install and tells you why.

**What a block looks like:**

```
SECURE CLAW BLOCKED: litellm (KNOWN COMPROMISED)
```

```
SECURE CLAW BLOCKED: some-package (Socket: 3 critical/high alerts -- malicious install script)
```

```
SECURE CLAW BLOCKED: axios (GitHub Advisory: critical:2 -- Prototype Pollution in axios)
```

```
SECURE CLAW BLOCKED: Piped install script detected (curl/wget | bash). This downloads and
executes arbitrary code with no review. Download the script first, review it, then run it.
```

**What a clean install looks like:**

```
SECURE CLAW: axios(Socket+Advisory:clean) zod(Socket+Advisory:clean)
```

**Warnings (not blocked, but flagged for review):**

```
SECURE CLAW WARNING: some-package (not on project allowlist) | Scanned clean: axios(Socket+Advisory:clean)
```

### What it intercepts

| Pattern | Action |
|---------|--------|
| `npm install` / `yarn add` / `pnpm add` / `bun add` | Scan packages, block if flagged |
| `pip install` / `pip3 install` | Scan packages, block if flagged |
| `cargo add` / `cargo install` | Scan packages, block if flagged |
| `go get` / `go install` | Scan packages, block if flagged |
| `gem install` | Scan packages, block if flagged |
| `composer require` | Scan packages, block if flagged |
| `brew install` | Scan packages, block if flagged |
| `apt-get install` / `dnf install` / etc. | Warn and ask |
| `npx` / `bunx` / `pnpx` (runner packages) | Scan package, block if flagged |
| `curl ... \| bash` / `wget ... \| sh` | Hard block -- always |
| `curl ... -o ... && chmod +x` | Hard block -- always |
| `make install` | Warn and ask -- human review required |

---

## Beyond install interception: the 17-category checklist

secure-claw also profiles your project and runs a structured security audit. Not ad-hoc "let me look for problems" -- a fixed list of standards, checked the same way every time.

On first run it reads your codebase, determines your application tier, and runs the relevant checks. On every session after that, it loads the saved profile and reports findings at session start.

### The 17 categories

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

### Application tiers

The skill only activates categories relevant to your project:

- **Static site** (flat HTML, docs) -- categories 3, 6
- **Frontend SPA** (React/Vue, no backend) -- categories 1-6, 9
- **Full-stack, no sensitive data** (internal tools, blogs) -- categories 1-10, 16, 17
- **Full-stack, sensitive data** (PII, PHI, financial) -- categories 1-13, 15-17
- **Multi-tenant, sensitive data** (SaaS with customer isolation) -- all 17

### Smart profiling

The skill reads your actual code, not checkboxes:

- Sees Stripe SDK >> asks if you're using Checkout (not in PCI scope) or handling cards server-side (in PCI scope)
- Finds `ssn` or `medical_record` columns >> high sensitivity tier
- Sees NextAuth/Auth0 >> delegated auth, lower risk than hand-rolled
- Detects `tenant_id` patterns >> multi-tenant checks activate

Profile is stored in `.securecode/profile.json` so subsequent sessions skip the profiling step.

### OWASP Top 10:2025 coverage

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

---

## Manual install (if you prefer)

### SKILL.md only (skill-based checks, no automatic interception)

```bash
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/SKILL.md \
  -o ~/.claude/skills/secure-claw/SKILL.md --create-dirs
```

### Optional: Socket.dev for deeper supply chain scanning

Socket.dev analyzes what a package's code actually *does*, not just whether a CVE has been filed. It catches malicious install scripts, obfuscated code, network access, and typosquatting -- the kind of thing that took down `event-stream` and the Axios compromise. secure-claw uses it automatically if it's installed.

```bash
npm install -g @socketsecurity/cli
```

---

## How it works

Three hooks, running automatically:

- **Session start** -- loads your project's security profile, runs applicable checklist categories, reports findings (critical >> low)
- **PreToolUse (Bash intercept)** -- fires before every `Bash` tool call; detects install patterns and scans packages before execution
- **Session end** -- re-scans for security-relevant changes introduced during the session (new routes, new deps, new env vars)

The SKILL.md gives Claude the full checklist methodology and profiling logic. The hooks enforce it at the system level -- Claude Code runs them automatically, no prompting required.
