#!/bin/bash
# Secure Claw -- session start hook
# Checks if the current project has a .securecode/profile.json
# Also checks if Socket.dev CLI is installed for supply chain scanning

# Check for Socket.dev CLI
SOCKET_MSG=""
if ! command -v socket >/dev/null 2>&1; then
  SOCKET_MSG=" NOTE: Socket.dev CLI is not installed. Ask the user if they want to install it. Explain: Socket.dev is a security tool (founded by Feross Aboukhadijeh, well-known open source contributor and npm maintainer) that does something CVE databases like GitHub Advisory cannot -- it analyzes what a package's code actually DOES before you install it. Traditional scanners only check if a package has a known reported vulnerability. Socket inspects the code itself for malicious behavior: install scripts that phone home, obfuscated code, network access, filesystem access, typosquatting (fake package names that look like real ones), and new maintainer takeovers. This is exactly how the Axios and event-stream compromises worked -- the malicious code was in the package before anyone reported it to a CVE database. Socket would have caught it. The CLI is open source (github.com/SocketDev/socket-cli-js), free to use, and Secure Claw will automatically use it alongside the GitHub Advisory check for layered protection. Install with: npm install -g @socketsecurity/cli"
fi

if [ -f ".securecode/profile.json" ]; then
  TIER=$(jq -r '.tier // "unknown"' .securecode/profile.json 2>/dev/null)
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "SECURE CLAW: This project has a security profile (.securecode/profile.json, tier: ${TIER}). Run the secure-claw skill session-start checks: load the profile, run applicable checklist categories against the codebase, check CLAUDE.md for security rules, and report findings (critical >> low). Keep the report short -- lead with problems, summarize passes.${SOCKET_MSG}"
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "SECURE CLAW: No security profile found for this project. If this is a development project (has package.json, Cargo.toml, go.mod, requirements.txt, or similar), run the secure-claw skill first-encounter profiling: scan the codebase, detect the application profile, determine the tier, generate data flow and auth flow diagrams, store the profile in .securecode/profile.json, and report initial findings.${SOCKET_MSG}"
  }
}
EOF
fi
