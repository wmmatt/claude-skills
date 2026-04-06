#!/bin/bash
# secure-claw install script
# Downloads SKILL.md and hook scripts, merges hook config into ~/.claude/settings.json
# Safe to run multiple times -- idempotent

set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/wmmatt/claude-skills/main/skills/secure-claw"
SKILL_DIR="$HOME/.claude/skills/secure-claw"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[secure-claw]${NC} $1"; }
warn()    { echo -e "${YELLOW}[secure-claw]${NC} $1"; }
err()     { echo -e "${RED}[secure-claw]${NC} $1" >&2; }

# ---- Detect JSON tool ----
JSON_TOOL=""
if command -v python3 >/dev/null 2>&1; then
  JSON_TOOL="python3"
elif command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
else
  err "Neither python3 nor jq found. One is required to merge settings.json."
  err "Install python3 (https://python.org) or jq (https://stedolan.github.io/jq/) and retry."
  exit 1
fi
info "Using $JSON_TOOL for JSON merging"

# ---- Create directories ----
mkdir -p "$SKILL_DIR"
mkdir -p "$HOOKS_DIR"
info "Directories ready"

# ---- Download SKILL.md ----
info "Downloading SKILL.md..."
if curl -fsSL "${BASE_URL}/SKILL.md" -o "${SKILL_DIR}/SKILL.md"; then
  info "  -> ${SKILL_DIR}/SKILL.md"
else
  err "Failed to download SKILL.md"
  exit 1
fi

# ---- Download hook scripts ----
HOOKS=(
  "secure-claw-intercept.sh"
  "secure-claw-session-start.sh"
  "secure-claw-session-end.sh"
)

info "Downloading hook scripts..."
for HOOK in "${HOOKS[@]}"; do
  if curl -fsSL "${BASE_URL}/hooks/${HOOK}" -o "${HOOKS_DIR}/${HOOK}"; then
    chmod +x "${HOOKS_DIR}/${HOOK}"
    info "  -> ${HOOKS_DIR}/${HOOK}"
  else
    err "Failed to download ${HOOK}"
    exit 1
  fi
done

# ---- Merge settings.json ----
info "Merging hook config into ${SETTINGS}..."

# The three hook entries we need -- keyed by a unique identity for idempotency checks
# PreToolUse / Bash matcher / secure-claw-intercept.sh
# SessionStart / secure-claw-session-start.sh
# Stop (SessionEnd) / secure-claw-session-end.sh

INTERCEPT_CMD="${HOOKS_DIR}/secure-claw-intercept.sh"
SESSION_START_CMD="${HOOKS_DIR}/secure-claw-session-start.sh"
SESSION_END_CMD="${HOOKS_DIR}/secure-claw-session-end.sh"

if [ "$JSON_TOOL" = "python3" ]; then
  python3 - "$SETTINGS" "$INTERCEPT_CMD" "$SESSION_START_CMD" "$SESSION_END_CMD" <<'PYEOF'
import sys, json, os

settings_path = sys.argv[1]
intercept_cmd = sys.argv[2]
session_start_cmd = sys.argv[3]
session_end_cmd = sys.argv[4]

# Load existing settings or start fresh
if os.path.exists(settings_path):
  try:
    with open(settings_path) as f:
      settings = json.load(f)
  except (json.JSONDecodeError, IOError):
    settings = {}
else:
  settings = {}

if "hooks" not in settings or not isinstance(settings["hooks"], dict):
  settings["hooks"] = {}

hooks = settings["hooks"]

# Helper: remove all existing secure-claw entries from a hook list
def remove_secure_claw(hook_list):
  return [
    h for h in hook_list
    if not any("secure-claw" in str(v) for v in (h.get("hooks") or []) + [h.get("command", "")])
    and not any("secure-claw" in str(entry.get("command", "")) for entry in (h.get("hooks") or []))
  ]

# ---- PreToolUse: Bash matcher -> intercept ----
pretooluse = hooks.get("PreToolUse", [])
if not isinstance(pretooluse, list):
  pretooluse = []

pretooluse = remove_secure_claw(pretooluse)
pretooluse.append({
  "matcher": "Bash",
  "hooks": [
    {"type": "command", "command": intercept_cmd}
  ]
})
hooks["PreToolUse"] = pretooluse

# ---- SessionStart ----
session_start = hooks.get("SessionStart", [])
if not isinstance(session_start, list):
  session_start = []

session_start = remove_secure_claw(session_start)
session_start.append({
  "hooks": [
    {"type": "command", "command": session_start_cmd}
  ]
})
hooks["SessionStart"] = session_start

# ---- Stop (session end) ----
stop = hooks.get("Stop", [])
if not isinstance(stop, list):
  stop = []

stop = remove_secure_claw(stop)
stop.append({
  "hooks": [
    {"type": "command", "command": session_end_cmd}
  ]
})
hooks["Stop"] = stop

# Write back
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
  json.dump(settings, f, indent=2)
  f.write("\n")

print("settings.json updated")
PYEOF

elif [ "$JSON_TOOL" = "jq" ]; then
  # Create settings.json if it doesn't exist
  if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
  fi

  TMPFILE=$(mktemp)

  jq \
    --arg intercept "$INTERCEPT_CMD" \
    --arg session_start "$SESSION_START_CMD" \
    --arg session_end "$SESSION_END_CMD" \
    '
    # Remove existing secure-claw entries from a hook list
    def remove_secure_claw:
      map(
        select(
          ((.hooks // []) | map(.command // "") | any(test("secure-claw"))) | not
        )
      );

    # Ensure hooks key exists
    .hooks //= {} |

    # PreToolUse: remove old secure-claw entry, add new one with Bash matcher
    .hooks.PreToolUse //= [] |
    .hooks.PreToolUse |= remove_secure_claw |
    .hooks.PreToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": $intercept}]}] |

    # SessionStart: remove old, add new
    .hooks.SessionStart //= [] |
    .hooks.SessionStart |= remove_secure_claw |
    .hooks.SessionStart += [{"hooks": [{"type": "command", "command": $session_start}]}] |

    # Stop: remove old, add new
    .hooks.Stop //= [] |
    .hooks.Stop |= remove_secure_claw |
    .hooks.Stop += [{"hooks": [{"type": "command", "command": $session_end}]}]
    ' "$SETTINGS" > "$TMPFILE" && mv "$TMPFILE" "$SETTINGS"

  info "settings.json updated"
fi

# ---- Summary ----
echo ""
echo "  secure-claw installed successfully"
echo ""
echo "  Files:"
echo "    ${SKILL_DIR}/SKILL.md"
echo "    ${HOOKS_DIR}/secure-claw-intercept.sh"
echo "    ${HOOKS_DIR}/secure-claw-session-start.sh"
echo "    ${HOOKS_DIR}/secure-claw-session-end.sh"
echo ""
echo "  Hooks registered in ${SETTINGS}:"
echo "    PreToolUse (Bash) -> secure-claw-intercept.sh"
echo "    SessionStart      -> secure-claw-session-start.sh"
echo "    Stop              -> secure-claw-session-end.sh"
echo ""
echo "  Optional: install Socket.dev CLI for deeper supply chain scanning:"
echo "    npm install -g @socketsecurity/cli"
echo ""
