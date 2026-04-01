#!/bin/bash
# Secure Claw -- session end hook
# Reminds Claude to re-scan for changes introduced during the session

if [ -f ".securecode/profile.json" ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "SECURE CLAW session end: Re-scan for security-relevant changes introduced during this session. Check for: new dependencies added, new API routes (are they authenticated?), new environment variables (documented in .env.example?), schema changes (sensitive data?), security header or auth middleware modifications. Report only what changed -- don't re-run the full scan."
  }
}
EOF
else
  exit 0
fi
