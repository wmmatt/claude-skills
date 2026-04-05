#!/bin/bash
# Secure Claw -- install interception hook
# Catches ANY attempt to install software/packages/dependencies on the machine
# Uses Socket.dev API (primary) + GitHub Advisory Database (supplement) for package checks
#
# Detection modes:
#   1. Package managers (npm, pip, cargo, go, gem, composer, brew, apt-get, dnf, yum, pacman, snap)
#      -> Extract package name -> check blocklist, Socket API, GitHub Advisory, allowlist
#   2. Runner commands (npx, bunx, pnpx)
#      -> Extract package name -> same checks as package managers
#   3. Piped executors (curl|bash, wget|sh)
#      -> Hard block always -- no way to verify what's being executed
#   4. Download + execute (curl -o + chmod +x patterns)
#      -> Hard block always -- downloading executables is high risk
#   5. make install
#      -> Warn and ask -- compiling from source needs human review
#
# Scanners (run in order, both run when available):
#   - Socket.dev API (primary) -- catches supply chain attacks, typosquatting, malware
#   - GitHub Advisory Database API (supplement) -- catches known CVEs

CMD=$(jq -r '.tool_input.command // ""' 2>/dev/null)

# ---- Detect install intent ----
# Rather than a static list, catch patterns that indicate "putting new software on this machine"

IS_INSTALL=0
INSTALL_TYPE=""
RAW_PACKAGES=""

# Package managers with explicit install commands
if echo "$CMD" | grep -qiE '(npm|npx|yarn|pnpm|bun)[[:space:]]+(install|add|i)[[:space:]]+[^-]'; then
  IS_INSTALL=1; INSTALL_TYPE="npm"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*(npm|npx|yarn|pnpm|bun)[[:space:]]+(install|add|i)[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'pip3?[[:space:]]+install[[:space:]]+'; then
  IS_INSTALL=1; INSTALL_TYPE="pip"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*pip3?[[:space:]]+install[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'cargo[[:space:]]+(add|install)[[:space:]]+'; then
  IS_INSTALL=1; INSTALL_TYPE="cargo"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*cargo[[:space:]]+(add|install)[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'go[[:space:]]+(get|install)[[:space:]]+'; then
  IS_INSTALL=1; INSTALL_TYPE="go"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*go[[:space:]]+(get|install)[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'composer[[:space:]]+require[[:space:]]+'; then
  IS_INSTALL=1; INSTALL_TYPE="composer"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*composer[[:space:]]+require[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'gem[[:space:]]+install[[:space:]]+'; then
  IS_INSTALL=1; INSTALL_TYPE="gem"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*gem[[:space:]]+install[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'brew[[:space:]]+(install|cask[[:space:]]+install)[[:space:]]+'; then
  IS_INSTALL=1; INSTALL_TYPE="brew"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*brew[[:space:]]+(install|cask[[:space:]]+install)[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'apt-get[[:space:]]+install|apt[[:space:]]+install|dnf[[:space:]]+install|yum[[:space:]]+install|pacman[[:space:]]+-S|snap[[:space:]]+install'; then
  IS_INSTALL=1; INSTALL_TYPE="system"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*(apt-get|apt|dnf|yum|snap)[[:space:]]+install[[:space:]]+//' | sed -E 's/^.*pacman[[:space:]]+-S[[:space:]]+//')

elif echo "$CMD" | grep -qiE 'make[[:space:]]+install'; then
  IS_INSTALL=1; INSTALL_TYPE="make"

# Piped install scripts -- curl/wget piped to sh/bash
elif echo "$CMD" | grep -qiE '(curl|wget)[[:space:]].*\|[[:space:]]*(bash|sh|zsh|dash|python|python3|perl|ruby|node|sudo[[:space:]]+bash|sudo[[:space:]]+sh)'; then
  IS_INSTALL=1; INSTALL_TYPE="piped-script"

# Direct download + execute patterns
elif echo "$CMD" | grep -qiE '(curl|wget)[[:space:]].*-o[[:space:]]+.*&&.*chmod[[:space:]]+\+x'; then
  IS_INSTALL=1; INSTALL_TYPE="download-execute"

# npx/bunx/pnpx running a package (downloads and executes)
elif echo "$CMD" | grep -qiE '(npx|bunx|pnpx)[[:space:]]+[^-]' && ! echo "$CMD" | grep -qiE '(npx|bunx|pnpx)[[:space:]]+(--help|-h)'; then
  IS_INSTALL=1; INSTALL_TYPE="exec-package"
  RAW_PACKAGES=$(echo "$CMD" | sed -E 's/^.*(npx|bunx|pnpx)[[:space:]]+//' | awk '{print $1}')

fi

# Not an install -- pass through
if [ "$IS_INSTALL" -eq 0 ]; then
  exit 0
fi

# ---- Special cases: block without scanning ----

# Piped scripts and download+execute are always dangerous
if [ "$INSTALL_TYPE" = "piped-script" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "SECURE CLAW BLOCKED: Piped install script detected (curl/wget | bash). This downloads and executes arbitrary code with no review. Download the script first, review it, then run it."
  }
}
EOF
  exit 0
fi

if [ "$INSTALL_TYPE" = "download-execute" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "SECURE CLAW BLOCKED: Download and execute pattern detected. This downloads a binary/script and makes it executable without review. Download it first, verify what it is, then proceed."
  }
}
EOF
  exit 0
fi

if [ "$INSTALL_TYPE" = "make" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "SECURE CLAW: make install detected. This will install compiled software to the system. Verify: what is being installed, where it will be placed, and whether it should be containerized instead."
  }
}
EOF
  exit 0
fi

# ---- Extract and check packages ----

# Strip flags, split into package names
PACKAGES=$(echo "$RAW_PACKAGES" | tr ' ' '\n' | grep -v '^-' | grep -v '^$')

# If no packages extracted (e.g., system package manager), warn generically
if [ -z "$PACKAGES" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "SECURE CLAW: ${INSTALL_TYPE} install detected. Review what is being installed before proceeding."
  }
}
EOF
  exit 0
fi

# Known compromised packages (hardcoded blocklist)
KNOWN_BAD="litellm event-stream ua-parser-js coa rc colors faker flatmap-stream plain-crypto-js"

# Determine ecosystem for API calls
ECOSYSTEM="npm"
case "$INSTALL_TYPE" in
  pip) ECOSYSTEM="pip" ;;
  cargo) ECOSYSTEM="crates.io" ;;
  go) ECOSYSTEM="go" ;;
  composer) ECOSYSTEM="packagist" ;;
  gem) ECOSYSTEM="rubygems" ;;
esac

BLOCKED=""
WARNED=""
CHECKED=""

for PKG in $PACKAGES; do
  # Extract version from specifier before stripping (axios@1.7.2 -> 1.7.2, package>=1.0 -> 1.0)
  CMD_VER=""
  if echo "$PKG" | grep -q '@[0-9]'; then
    CMD_VER=$(echo "$PKG" | sed 's/.*@//')
  elif echo "$PKG" | grep -q '[><=][0-9]'; then
    CMD_VER=$(echo "$PKG" | sed 's/.*[><=]//')
  fi

  # Strip version specifier (axios@1.7.2 -> axios, package>=1.0 -> package, github.com/foo/bar -> bar)
  PKG_NAME=$(echo "$PKG" | sed 's/@.*//' | sed 's/[<>=].*//' | sed 's#.*/##')

  [ -z "$PKG_NAME" ] && continue

  # --- Check 1: Hardcoded blocklist ---
  if echo "$KNOWN_BAD" | grep -qw "$PKG_NAME"; then
    BLOCKED="$BLOCKED $PKG_NAME (KNOWN COMPROMISED -- this package has a documented history of supply chain compromise or malicious code. Do not install under any circumstances.)"
    continue
  fi

  # --- Check 2: Socket.dev API (primary scanner) ---
  SOCKET_CHECKED=0
  if [ -n "$SOCKET_API_KEY" ]; then
    SOCKET_RESP=$(curl -s --max-time 10 \
      -H "Authorization: Bearer $SOCKET_API_KEY" \
      "https://api.socket.dev/v0/npm/${PKG_NAME}/score" 2>/dev/null)
    SOCKET_EXIT=$?

    if [ $SOCKET_EXIT -eq 0 ] && echo "$SOCKET_RESP" | jq -e '.score' >/dev/null 2>&1; then
      SOCKET_CHECKED=1

      # Check for critical alerts
      HAS_CRITICAL=$(echo "$SOCKET_RESP" | jq -r '
        .alerts // [] | map(select(.severity == "critical" or .severity == "high")) | length
      ' 2>/dev/null)

      if [ "${HAS_CRITICAL:-0}" -gt 0 ]; then
        ALERT_TYPES=$(echo "$SOCKET_RESP" | jq -r '
          .alerts // [] | map(select(.severity == "critical" or .severity == "high")) | map(.type // "unknown") | unique | join(", ")
        ' 2>/dev/null)
        BLOCKED="$BLOCKED $PKG_NAME (Socket: ${HAS_CRITICAL} critical/high alerts -- types: ${ALERT_TYPES}. Socket.dev flagged this package for supply chain risk. Review at https://socket.dev/npm/package/${PKG_NAME} before installing.)"
        continue
      fi
    fi
  elif command -v socket >/dev/null 2>&1; then
    # Fallback to Socket CLI if installed
    SOCKET_OUT=$(socket package score "$PKG_NAME" 2>/dev/null)
    if [ $? -eq 0 ]; then
      SOCKET_CHECKED=1
      if echo "$SOCKET_OUT" | grep -qiE 'critical|malware|typosquat|install[[:space:]]*script|trojan|compromised'; then
        RISK_LINE=$(echo "$SOCKET_OUT" | grep -iE 'critical|malware|typosquat|install[[:space:]]*script|trojan|compromised' | head -1 | head -c 120)
        BLOCKED="$BLOCKED $PKG_NAME (Socket: $RISK_LINE)"
        continue
      elif echo "$SOCKET_OUT" | grep -qiE 'high|suspicious|obfuscated|network[[:space:]]*access'; then
        RISK_LINE=$(echo "$SOCKET_OUT" | grep -iE 'high|suspicious|obfuscated|network[[:space:]]*access' | head -1 | head -c 120)
        WARNED="$WARNED $PKG_NAME (Socket: $RISK_LINE)"
      fi
    fi
  fi

  # --- Check 3: GitHub Advisory Database (always runs as supplement) ---
  # Resolve target version for accurate filtering
  # Priority: 1) already installed, 2) version from command, 3) registry latest
  INSTALLED_VER=""
  if [ -f "node_modules/${PKG_NAME}/package.json" ]; then
    INSTALLED_VER=$(jq -r '.version // empty' "node_modules/${PKG_NAME}/package.json" 2>/dev/null)
  fi
  if [ -z "$INSTALLED_VER" ] && [ -n "$CMD_VER" ]; then
    INSTALLED_VER="$CMD_VER"
  fi
  if [ -z "$INSTALLED_VER" ] && [ "$ECOSYSTEM" = "npm" ]; then
    INSTALLED_VER=$(npm view "$PKG_NAME" version 2>/dev/null)
  fi

  HAS_VULN=0
  VULN_DETAIL=""
  ADV_DETAIL=""
  for SEV in critical high; do
    RESP=$(curl -s --max-time 10 -H "Accept: application/vnd.github+json" \
      "https://api.github.com/advisories?ecosystem=${ECOSYSTEM}&affects=${PKG_NAME}&severity=${SEV}&per_page=5" 2>/dev/null)
    if echo "$RESP" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
      if [ -n "$INSTALLED_VER" ]; then
        # Filter: only count advisories where installed version is still vulnerable
        # An advisory applies if installed version is in the vulnerable range AND
        # either there's no patch yet, or the installed version is below the patched version
        FILTERED=$(echo "$RESP" | jq --arg ver "$INSTALLED_VER" '
          [.[] | select(
            any(.vulnerabilities[]?;
              # Check if first_patched_version exists
              (.first_patched_version.identifier // null) as $patched |
              if $patched == null then
                # No patch available -- still vulnerable
                true
              else
                # Compare installed version against patched version
                # Split versions into arrays of numbers for comparison
                ($ver | split(".") | map(tonumber? // 0)) as $inst |
                ($patched | split(".") | map(tonumber? // 0)) as $patch |
                # Installed is vulnerable if it is less than the patched version
                if ($inst[0] < $patch[0]) then true
                elif ($inst[0] == $patch[0] and $inst[1] < $patch[1]) then true
                elif ($inst[0] == $patch[0] and $inst[1] == $patch[1] and $inst[2] < $patch[2]) then true
                else false
                end
              end
            )
          )]
        ' 2>/dev/null)
        COUNT=$(echo "$FILTERED" | jq 'length' 2>/dev/null)
        if [ "${COUNT:-0}" -gt 0 ]; then
          SUMMARY=$(echo "$FILTERED" | jq -r '.[0].summary // "Unknown"' | head -c 120)
          GHSA_ID=$(echo "$FILTERED" | jq -r '.[0].ghsa_id // "unknown"' 2>/dev/null)
          VULN_RANGE=$(echo "$FILTERED" | jq -r '[.[0].vulnerabilities[]? | .vulnerable_version_range // empty] | join(", ")' 2>/dev/null)
          PATCHED_AT=$(echo "$FILTERED" | jq -r '[.[0].vulnerabilities[]? | .first_patched_version.identifier // empty] | join(", ")' 2>/dev/null)
          VULN_DETAIL="$VULN_DETAIL ${SEV}:${COUNT}"
          ADV_DETAIL="${ADV_DETAIL}${SEV} [${GHSA_ID}]: ${SUMMARY}. Affected: ${VULN_RANGE}. Patched in: ${PATCHED_AT:-no patch available}. Installed: ${INSTALLED_VER}. "
          HAS_VULN=1
        fi
      else
        # No installed version found -- block conservatively
        COUNT=$(echo "$RESP" | jq 'length')
        SUMMARY=$(echo "$RESP" | jq -r '.[0].summary // "Unknown"' | head -c 120)
        GHSA_ID=$(echo "$RESP" | jq -r '.[0].ghsa_id // "unknown"' 2>/dev/null)
        VULN_RANGE=$(echo "$RESP" | jq -r '[.[0].vulnerabilities[]? | .vulnerable_version_range // empty] | join(", ")' 2>/dev/null)
        PATCHED_AT=$(echo "$RESP" | jq -r '[.[0].vulnerabilities[]? | .first_patched_version.identifier // empty] | join(", ")' 2>/dev/null)
        VULN_DETAIL="$VULN_DETAIL ${SEV}:${COUNT}"
        ADV_DETAIL="${ADV_DETAIL}${SEV} [${GHSA_ID}]: ${SUMMARY}. Affected: ${VULN_RANGE}. Patched in: ${PATCHED_AT:-no patch available}. Version could not be resolved -- blocking conservatively. "
        HAS_VULN=1
      fi
    fi
  done

  if [ "$HAS_VULN" -eq 1 ]; then
    BLOCKED="$BLOCKED $PKG_NAME (GitHub Advisory:$VULN_DETAIL -- $ADV_DETAIL)"
    continue
  fi

  # --- Check 4: Allowlist (informational, after security scans pass) ---
  if [ -f ".securecode/allowlist.json" ]; then
    if ! jq -e --arg pkg "$PKG_NAME" '.packages[] | select(. == $pkg)' .securecode/allowlist.json >/dev/null 2>&1; then
      WARNED="$WARNED $PKG_NAME (not on project allowlist)"
      continue
    fi
  fi

  # All checks passed
  SCANNER_LABEL=""
  [ "$SOCKET_CHECKED" -eq 1 ] && SCANNER_LABEL="Socket+"
  CHECKED="$CHECKED $PKG_NAME(${SCANNER_LABEL}Advisory:clean)"
done

# ---- Build response ----
if [ -n "$BLOCKED" ]; then
  REASON="SECURE CLAW BLOCKED:$BLOCKED"
  if [ -n "$WARNED" ]; then
    REASON="$REASON | Warnings:$WARNED"
  fi
  if [ -n "$CHECKED" ]; then
    REASON="$REASON | Safe:$CHECKED"
  fi
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$REASON"
  }
}
EOF
elif [ -n "$WARNED" ]; then
  REASON="SECURE CLAW WARNING:$WARNED"
  if [ -n "$CHECKED" ]; then
    REASON="$REASON | Scanned clean:$CHECKED"
  fi
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "$REASON"
  }
}
EOF
else
  SAFE_LIST=$(echo "$CHECKED" | xargs)
  cat <<EOF
{
  "systemMessage": "SECURE CLAW: $SAFE_LIST"
}
EOF
fi
