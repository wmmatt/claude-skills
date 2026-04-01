# Claude Skills

A collection of skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## Skills

### [secure-claw](skills/secure-claw/)

Security enforcement skill that profiles your app, scans against 17 defined security categories, intercepts unsafe package installs, and generates data flow diagrams with weaknesses highlighted.

- Tiered scanning -- only checks categories relevant to your project (static site gets 2, multi-tenant SaaS gets all 17)
- Smart profiling -- reads your actual code to determine stack, auth, payments, data sensitivity
- Install interception -- catches `npm install`, `pip install`, `cargo add`, `curl | bash`, etc. before execution
- Session start/end scanning -- checks for new vulnerabilities and changes introduced during your session
- OWASP Top 10:2025 coverage across all 17 categories

**[Full details >>](skills/secure-claw/)**

## Install

Each skill can be installed per-project or globally.

### Per-project (recommended)

```bash
# Install secure-claw for the current project
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/SKILL.md \
  -o .claude/skills/secure-claw/SKILL.md --create-dirs
```

### Global (all projects)

```bash
# Install secure-claw for all projects
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/SKILL.md \
  -o ~/.claude/skills/secure-claw/SKILL.md --create-dirs
```

### With hooks (auto-enforcement)

The skill includes optional hooks that automate session-start scanning, install interception, and session-end re-scanning. To install the hooks:

```bash
# Download the hook scripts
mkdir -p ~/.claude/hooks
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/hooks/secure-claw-session-start.sh \
  -o ~/.claude/hooks/secure-claw-session-start.sh
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/hooks/secure-claw-intercept.sh \
  -o ~/.claude/hooks/secure-claw-intercept.sh
curl -sL https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw/hooks/secure-claw-session-end.sh \
  -o ~/.claude/hooks/secure-claw-session-end.sh
chmod +x ~/.claude/hooks/secure-claw-*.sh
```

Then add the hooks to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "~/.claude/hooks/secure-claw-session-start.sh"
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "type": "command",
        "command": "~/.claude/hooks/secure-claw-intercept.sh"
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "~/.claude/hooks/secure-claw-session-end.sh"
      }
    ]
  }
}
```

## What are Claude Code skills?

Skills are markdown files that give Claude Code specialized capabilities. Drop a `SKILL.md` file into `.claude/skills/` (per-project) or `~/.claude/skills/` (global) and Claude picks it up automatically. No config, no plugins -- just a markdown file with instructions.

## License

MIT
