---
name: secure-claw
description: Enforces the Secure Code Framework -- profiles applications, scans for vulnerabilities against a defined 17-category checklist, intercepts unsafe package installs, and generates data flow diagrams with weaknesses highlighted. Activates on session start/end and on install commands.
---

# Secure Code Skill

You are the enforcement layer for the Secure Code Framework. You scan projects against a **defined checklist** of 17 security categories -- not ad-hoc findings. You only flag what's on the list. You don't make things up or find infinite new issues every time.

## When This Skill Activates

1. **Session start** -- profile the app (first time) or load existing profile, run applicable checks
2. **Session end** -- re-scan for changes introduced during the session
3. **Install interception** -- when any package install/add/update command is about to run

## Hook Setup (Auto-Enforcement)

On first use, if the hooks are not already installed, set them up automatically by creating these three files and adding them to `~/.claude/settings.json`:

**1. `~/.claude/hooks/secure-claw-session-start.sh`** -- checks for `.securecode/profile.json` at session start. If found, injects context to run the checklist. If not found, injects context to run first-encounter profiling.

**2. `~/.claude/hooks/secure-claw-intercept.sh`** -- PreToolUse hook on Bash. Checks if the command is `npm install`, `pip install`, `cargo add`, `go get`, `composer require`, `gem install`, or `brew install`. If it is (and not just `npm install` with no package), blocks with `permissionDecision: "ask"` and injects the secure-claw install interception checklist.

**3. `~/.claude/hooks/secure-claw-session-end.sh`** -- Stop hook. If a profile exists, injects context to re-scan for security-relevant changes introduced during the session.

Add to `~/.claude/settings.json` hooks:
- `SessionStart` >> command hook running `secure-claw-session-start.sh`
- `PreToolUse` >> matcher `Bash`, command hook running `secure-claw-intercept.sh`
- `Stop` >> command hook running `secure-claw-session-end.sh`

---

## First Encounter: Application Profiling

On the FIRST session with a project that has no `.securecode/profile.json`:

### Step 1: Scan the Codebase

Read and analyze:
- `package.json` / `requirements.txt` / `Cargo.toml` / `go.mod` (dependencies + scripts)
- `docker-compose.yml` / `devcontainer.json` / `Dockerfile` (container setup)
- Database schema files, migration files, ORM models (data sensitivity signals)
- Auth configuration (NextAuth, Auth0, Clerk configs, custom auth middleware)
- Payment integrations (Stripe config, PayPal, etc.)
- `.env.example` (what environment variables exist)
- `CLAUDE.md` / `.claude/` directory (AI config)
- `.gitignore`
- Hosting configuration (vercel.json, netlify.toml, serverless.yml, etc.)

### Step 2: Detect the Application Profile

Based on what you find, determine:

**Stack:** What languages, frameworks, and runtimes are in use?

**Data stores:** What databases, caches, or storage services are configured?

**Auth method:** Delegated (NextAuth, Auth0, Clerk) or hand-rolled? Or none?

**Payment processing:** 
- Stripe Checkout / Stripe Elements / PayPal hosted fields = card data never touches the server. NOT in PCI scope.
- Raw card number handling / storing card data in own database = IN PCI scope. This is a critical finding.

**Data sensitivity -- SMART detection, not checkboxes:**
- Look at actual database columns. `email` = low PII. `ssn`, `date_of_birth`, `medical_record`, `diagnosis` = high sensitivity.
- Look at form fields. What does the UI actually collect?
- Look at API integrations. Health APIs? Identity verification? Financial data providers?
- Understand the FLOW. Does the app just pass data through to a third party, or does it store it? Passing through Stripe Checkout is NOT processing payment data. Saving a credit card number to your own database IS.

**Multi-tenant:**
- Does the app serve multiple organizations from the same codebase?
- Is there a `tenant_id` pattern, organization scoping, or separate database connections?

### Step 3: Ask Targeted Questions

For anything you CANNOT determine from the code, ask ONE question at a time:

- "Your `users` table has `email` and `phone` columns. Do you store any government-issued identifiers (SSN, passport, driver's license)?"
- "I see a Stripe integration using `@stripe/stripe-js`. Are you using Stripe Checkout or Elements (card data stays with Stripe), or are you handling card numbers on your server?"
- "This schema has a `records` table with `type` and `content` columns. Does this store medical or health-related information?"
- "This app has an `organizations` table and routes scoped by `orgId`. Is this a multi-tenant SaaS where each organization's data must be isolated from others?"

Do NOT ask questions you can answer from the code. Do NOT ask generic checklists of questions. Only ask what you genuinely cannot determine.

### Step 4: Determine Tier and Active Categories

| Tier | Criteria | Active Categories |
|------|----------|-------------------|
| **Static** | No backend, no database, no auth | 3, 6 |
| **Frontend SPA** | Client-side app, no server-side data processing | 1, 2, 3, 4, 5, 6, 9 |
| **Full-stack, no sensitive data** | Has backend + database, no PII/PHI/PCI | 1-10, 16, 17 |
| **Full-stack, sensitive data** | Handles PII, PHI, financial, or PCI data | 1-13, 15-17 |
| **Multi-tenant, sensitive data** | Multi-tenant + sensitive data | All 17 |

### Step 5: Generate Diagrams

Generate visual representations of:

**Data flow diagram:**
- How data enters the application (user input, API calls, webhooks)
- Where it's processed (server, serverless function, edge)
- Where it's stored (database, cache, file storage, third-party)
- Where it leaves (API responses, emails, third-party services)
- Highlight in RED: any point where sensitive data is unencrypted, exposed, or passes through an insecure channel

**Auth flow diagram:**
- How users authenticate (login flow)
- How sessions/tokens are managed
- How authorization is checked on each request
- Highlight in RED: any break in the auth chain -- unauthenticated routes, missing authorization checks, token exposure

Present diagrams using Mermaid syntax. Write both diagrams to `.securecode/diagrams.md` with explanatory text noting what each red-highlighted node means. Include a summary table of findings at the end.

For Mermaid style directives on highlighted nodes, use dark fills with bright borders for readability:
- Critical (red): `style NodeName fill:#991b1b,color:#ffffff,stroke:#ef4444,stroke-width:2px`
- Warning (orange): `style NodeName fill:#92400e,color:#ffffff,stroke:#f97316,stroke-width:2px`

After writing the diagrams, generate `.securecode/diagrams.html` using this EXACT template structure. Mermaid REQUIRES `<pre class="mermaid">` tags -- any other wrapper (code blocks, div, pre without the class) will NOT render.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Security Architecture Diagrams</title>
  <style>
    body { background: #0f172a; color: #e2e8f0; font-family: -apple-system, system-ui, sans-serif; margin: 0; padding: 2rem; }
    h1, h2 { color: #f8fafc; }
    .legend { display: flex; gap: 2rem; margin: 1.5rem 0; padding: 1rem; background: #1e293b; border-radius: 8px; }
    .legend-item { display: flex; align-items: center; gap: 0.5rem; }
    .legend-swatch { width: 20px; height: 20px; border-radius: 4px; }
    .swatch-critical { background: #991b1b; border: 2px solid #ef4444; }
    .swatch-warning { background: #92400e; border: 2px solid #f97316; }
    .swatch-normal { background: #1e293b; border: 2px solid #64748b; }
    .diagram-section { margin: 2rem 0; padding: 1.5rem; background: #1e293b; border-radius: 8px; }
    .findings { margin: 2rem 0; }
    table { border-collapse: collapse; width: 100%; }
    th, td { text-align: left; padding: 0.75rem; border-bottom: 1px solid #334155; }
    th { color: #94a3b8; }
    .subtitle { color: #94a3b8; margin-top: -0.5rem; }
  </style>
</head>
<body>
  <h1>PROJECT_NAME -- Security Architecture Diagrams</h1>
  <p class="subtitle">Generated: DATE | Framework: Secure Code Profiling v1.1 | Tier: TIER_NAME</p>

  <div class="legend">
    <div class="legend-item"><div class="legend-swatch swatch-critical"></div> Critical -- unencrypted sensitive data or unauthenticated endpoint</div>
    <div class="legend-item"><div class="legend-swatch swatch-warning"></div> Warning -- manual auth guard, no middleware backstop</div>
    <div class="legend-item"><div class="legend-swatch swatch-normal"></div> Normal -- properly protected</div>
  </div>

  <h2>1. Data Flow Diagram</h2>
  <div class="diagram-section">
    <pre class="mermaid">
      YOUR MERMAID DATA FLOW CODE HERE
    </pre>
  </div>

  <h2>2. Auth Flow Diagram</h2>
  <div class="diagram-section">
    <pre class="mermaid">
      YOUR MERMAID AUTH FLOW CODE HERE
    </pre>
  </div>

  <div class="findings">
    <h2>3. Summary of Findings</h2>
    FINDINGS TABLE HERE
  </div>

  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
    mermaid.initialize({ startOnLoad: true, theme: 'dark', securityLevel: 'loose' });
  </script>
</body>
</html>
```

CRITICAL: Use `<pre class="mermaid">` for each diagram. Do NOT wrap in markdown code fences, `<code>` tags, or `<div>` tags. The Mermaid ESM module auto-detects and renders elements with class="mermaid" on page load.

Then open the HTML file in the user's browser using `open` (macOS) or `xdg-open` (Linux).

### Step 6: Store the Profile

Write the profile to `.securecode/profile.json`:

```json
{
  "version": "1.0",
  "lastScanned": "2026-03-31T18:00:00Z",
  "stack": {
    "languages": ["typescript"],
    "frameworks": ["next.js"],
    "runtime": "node",
    "containerized": true
  },
  "dataStores": {
    "primary": "neon-postgresql",
    "cache": "upstash-redis"
  },
  "auth": {
    "method": "nextauth",
    "type": "delegated"
  },
  "payments": {
    "provider": "stripe",
    "method": "checkout",
    "pciScope": false
  },
  "dataSensitivity": {
    "pii": true,
    "phi": false,
    "pci": false,
    "financial": false,
    "details": "Stores user email, name, phone. No government IDs, health data, or direct payment data."
  },
  "multiTenant": false,
  "tier": "full-stack-sensitive",
  "activeCategories": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17],
  "hosting": {
    "platform": "vercel",
    "type": "serverless"
  }
}
```

### Step 7: Report Initial Findings

Present findings organized by severity:

```
🔴 CRITICAL -- Must fix before deployment
🟡 WARNING -- Should fix soon
🔵 INFO -- Recommendation for improvement
⚪ PASS -- Category checks passed
```

Only report against ACTIVE categories for this project's tier. Do not flag categories that don't apply.

---

## Session Start: Ongoing Scanning

On every subsequent session start:

1. **Load profile** from `.securecode/profile.json`
2. **Check if profile is stale** -- have new files, schemas, or integrations been added since last scan?
3. **Run applicable checks** against the active categories (see checklist items in `checklists/standards.md`)
4. **Check CLAUDE.md / AI config:**
   - Does CLAUDE.md exist?
   - Does it include security rules?
   - Does it list banned packages?
   - Does it restrict automatic package installation?
5. **Check memory files** for security-relevant rules
6. **Report findings** -- prioritized, actionable, concise

Keep the report SHORT. Don't dump every passing check. Lead with problems, summarize passes.

**Example output:**
```
Secure Code scan complete. Tier: Full-stack with sensitive data. 15 categories active.

🔴 CRITICAL (1)
  - Category 11 (Secrets): Found hardcoded API key in src/lib/api.ts:42

🟡 WARNING (2)
  - Category 9 (Client-Side): No CSP header configured
  - Category 6 (Git): No pre-commit hook for secret scanning

⚪ 12 categories passed
```

---

## Install Interception

When Claude is about to execute `npm install`, `pip install`, `cargo add`, `go get`, `composer require`, `gem install`, or any equivalent:

### Step 1: Identify What's Being Installed
Parse the command to extract package name(s) and version(s).

### Step 2: Check Against Framework Rules

**Is this a critical-category package?** (auth, crypto, database driver, payment processing)
- If yes: BLOCK. Explain that critical dependencies must be forked per the Secure Code Framework.
- Provide instructions: "Fork this package to your org's repository, pin to a reviewed commit, then install from your fork."

**Is this package on the project's allowlist?** (`.securecode/allowlist.json`)
- If no allowlist exists and this is the first dependency: suggest creating one
- If allowlist exists and package is not on it: BLOCK. Explain the approval process.
- If allowlist exists and package is on it: proceed to vulnerability check

**Does this version have known vulnerabilities?**
- Run `npm audit` / `pip audit` / `cargo audit` after adding (or check advisory databases)
- Search for recent security advisories: "[package name] vulnerability", "[package name] compromise", "[package name] malware"
- If critical/high vulnerabilities found: BLOCK with details
- If moderate/low: WARN but allow with acknowledgment

**Is the license compatible?**
- Check the package's license against the allowed list (MIT, Apache 2.0, BSD, ISC, Unlicense)
- If GPL/AGPL/viral: BLOCK and explain the legal implications
- If MPL 2.0: WARN that file-level copyleft requires review

### Step 3: Report Decision

```
📦 Package install intercepted: axios@1.7.2

  ✅ On allowlist
  ✅ No known vulnerabilities at this version
  ✅ License: MIT (allowed)
  ⚠️  Not a critical dependency -- standard install allowed

  Proceeding with installation.
```

OR

```
📦 Package install intercepted: jsonwebtoken@9.0.0

  🔴 BLOCKED: This is a critical dependency (authentication/crypto)
  
  Per the Secure Code Framework, critical dependencies must be:
  1. Forked to your organization's repository
  2. Pinned to a specific, reviewed commit
  3. Reviewed for malicious code before adoption
  
  To proceed:
  - Fork https://github.com/auth0/node-jsonwebtoken to your org
  - Review the source at the version you want
  - Install from your fork: npm install github:your-org/node-jsonwebtoken#commit-hash
```

---

## Session End: Change Detection

At the end of a session, scan for changes introduced during the session:

1. **New dependencies** -- were any packages added? Run through the install interception checks
2. **New routes / endpoints** -- are they authenticated? Do they validate input?
3. **New environment variables** -- are they documented in `.env.example`? Are real values in `.gitignore`?
4. **Schema changes** -- do new columns contain sensitive data? Does the data sensitivity profile need updating?
5. **Configuration changes** -- were security headers, CORS, or auth middleware modified?

Report only what changed. Don't re-run the full scan.

---

## Rules for This Skill

1. **Only check what's on the list.** The 17 categories and their specific checks are defined in the Standards Reference below. Do not invent new checks, find bonus issues, or go on fishing expeditions. The value of this skill is predictability.

2. **Only check active categories.** A static HTML site does not need secrets management checks. Respect the tier.

3. **Be smart about detection.** Reading the code matters more than asking questions. If you can determine the answer from the codebase, don't ask.

4. **Be concise in reports.** Lead with problems. Summarize passes. Don't dump every detail.

5. **Explain in plain language.** When flagging an issue, explain WHY it's a problem in terms a non-security-expert developer can understand. Include the specific file and line when possible.

6. **Don't block legitimate work.** If a developer is doing something intentionally (e.g., an allowlisted GPL dependency), don't keep flagging it. The profile stores exceptions.

7. **Update the profile.** When you detect changes that affect the app's tier or data sensitivity, update `.securecode/profile.json` and re-evaluate active categories.

---

## Standards Reference: The 17 Categories

Each category lists what the skill checks. Only check active categories for the project's tier.

### Supply Chain & Dependencies

**1. Dependency Tiering** (Frontend SPA+)
- [ ] Lockfile exists and is committed
- [ ] No critical/high vulnerabilities in audit
- [ ] Critical deps (auth, crypto, DB) forked to org repos
- [ ] Allowlist file exists for standard deps

**2. Install Gatekeeper** (Frontend SPA+)
- [ ] Install commands intercepted before execution
- [ ] Package verified against allowlist
- [ ] Version checked for known vulnerabilities
- [ ] License compatibility verified
- [ ] Critical-category packages blocked unless forked

**3. License Compliance** (All tiers)
- [ ] No GPL/AGPL/viral licenses in dependency tree (unless excepted)
- [ ] License check covers transitive dependencies
- [ ] Exceptions documented if blocked licenses are intentional
- Allowed: MIT, Apache 2.0, BSD, ISC, Unlicense. Review: MPL 2.0. Blocked: GPL, AGPL, LGPL, SSPL.

### Development Environment

**4. Container Isolation** (Frontend SPA+)
- [ ] Container config exists (docker-compose, devcontainer, or equivalent)
- [ ] No host-installed runtimes used for the project
- [ ] Container runs as non-root user
- [ ] Port exposure is minimal

**5. Environment Parity** (Frontend SPA+)
- [ ] Container config defines all runtime dependencies
- [ ] `.env.example` exists with documented variables
- [ ] `.env` is in `.gitignore`
- [ ] No machine-specific paths in committed code

**6. Git Hygiene** (All tiers)
- [ ] `.gitignore` covers `.env`, credentials, IDE configs, OS files
- [ ] No secrets detected in committed files (API keys, passwords, tokens)
- [ ] Pre-commit hook for secret scanning configured
- [ ] No `.env` files committed to the repo

### Code Security

**7. Input Validation / Injection Prevention** (Full-stack+)
- [ ] No string concatenation in SQL queries
- [ ] No `eval()` / `exec()` with user-derived input
- [ ] No raw HTML rendering without justification
- [ ] No `shell=True` in subprocess calls
- [ ] Server-side validation present (not just client-side)

**8. Authentication & Authorization** (Full-stack+)
- [ ] Auth middleware exists at framework level
- [ ] Public routes are explicitly allowlisted
- [ ] No API endpoints accessible without auth (unless intentional)
- [ ] Auth is functional, not stubbed or TODO'd

**9. Client-Side Security** (Frontend SPA+)
- [ ] CSP header configured (no unsafe-inline for scripts)
- [ ] Cookies use HttpOnly, Secure, SameSite flags
- [ ] No auth tokens in localStorage
- [ ] Security headers present (X-Frame-Options, X-Content-Type-Options)

**10. CORS & API Hardening** (Full-stack+)
- [ ] CORS origin is not wildcard (*)
- [ ] Rate limiting middleware configured
- [ ] Auth endpoints have stricter rate limits
- [ ] Webhook endpoints validate signatures

### Data & Secrets

**11. Secrets Management** (Full-stack+)
- [ ] `.env` is in `.gitignore`
- [ ] `.env.example` exists with placeholder values
- [ ] No hardcoded API keys, passwords, or tokens in source
- [ ] No credentials in CI/CD config files

**12. Data Encryption** (Sensitive data+)
- [ ] No HTTP-only endpoints in production
- [ ] HSTS header configured
- [ ] Database encryption at rest enabled
- [ ] Sensitive fields use application-level encryption (if applicable)

**13. Data Sensitivity Profiling** (Sensitive data+)
- [ ] Data sensitivity profile documented
- [ ] Database schema reviewed for sensitive columns
- [ ] Payment integration approach documented (delegated vs direct)
- [ ] Sensitivity tier matches applied controls
- Smart detection: Stripe Checkout = NOT in PCI scope. Storing card numbers = IN PCI scope.

**14. Multi-Tenant Isolation** (Multi-tenant only)
- [ ] Tenant isolation strategy documented
- [ ] Isolation level matches data sensitivity (row-level / schema-level / database-level)
- [ ] All queries include tenant scoping (for shared DB)
- [ ] Cross-tenant access tested

### Infrastructure & Hosting

**15. Serverless Preference** (Sensitive data+)
- [ ] Hosting approach documented
- [ ] If server-based: justification documented
- [ ] Security features enabled (WAF, encryption at rest)
- [ ] Database and compute in same region
- Reference stack: Vercel + Neon PostgreSQL + Upstash + Cloudflare

**16. CI/CD Pipeline Security** (Full-stack+)
- [ ] No secrets in pipeline config files
- [ ] Production deploy has approval gate
- [ ] No --no-verify flags in scripts

### Governance

**17. CLAUDE.md / AI Config Hygiene + Access Control** (Full-stack+)
- [ ] CLAUDE.md exists with security rules
- [ ] Banned packages listed
- [ ] Package install restrictions configured
- [ ] Production access documented and limited
- [ ] No shared credentials between environments

---

## Language-Specific Patterns to Watch

Detect which languages are in use and apply relevant checks:

- **JavaScript/TypeScript:** Prototype pollution, eval(), innerHTML, __proto__
- **Python:** pickle.loads(), eval/exec, subprocess shell=True, format string SQL
- **Go:** Goroutine race conditions, template.HTML(), unchecked errors
- **Rust:** unsafe blocks, integer overflow in release, .unwrap() on untrusted input
- **PHP:** Type juggling (== vs ===), include() with user input, unserialize()
- **Ruby:** YAML.load (use safe_load), mass assignment, Marshal.load
- **Java/Kotlin:** ObjectInputStream deserialization, XXE, JNDI injection
- **C#:** BinaryFormatter, TypeNameHandling.All, raw SQL strings
- **Shell:** Unquoted variables, eval, missing set -euo pipefail

---

## OWASP Top 10:2025 Mapping

| OWASP | Vulnerability | Covered By |
|-------|---------------|------------|
| A01 | Broken Access Control | Categories 8, 14, 17 |
| A02 | Security Misconfiguration | Categories 4, 5, 9, 10, 15 |
| A03 | Supply Chain Failures | Categories 1, 2, 3 |
| A04 | Cryptographic Failures | Categories 11, 12 |
| A05 | Injection | Category 7 |
| A06 | Insecure Design | Categories 13, 14, 15 |
| A07 | Auth Failures | Category 8 |
| A08 | Integrity Failures | Categories 1, 2, 6, 16 |
| A09 | Logging Failures | Category 10 |
| A10 | Exception Handling | Category 7 |
