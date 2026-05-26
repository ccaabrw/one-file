#!/usr/bin/env bash
# download-one-file.sh — Download a single file from a GitHub repository.
#
# Authentication is by username/password (or personal access token) using
# the GitHub API over HTTPS, or by SSH private key using git-archive.
# Only the requested file is transferred; the repository is never cloned.
#
# Dependencies:
#   Username/password mode: curl, and one of: python3 | python | (jq + base64)
#   SSH key mode          : git, ssh, tar

set -euo pipefail

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download a single file from a GitHub repository without cloning the full repo.

Authentication (choose one):
  -u USERNAME    GitHub username
  -p PASSWORD    GitHub password or personal access token
  -k KEY_PATH    Path to SSH private key

Required:
  -r OWNER/REPO  Repository (e.g. octocat/Hello-World)
  -f FILE_PATH   Path to the target file inside the repository

Optional:
  -b REF         Branch, tag, or commit SHA (default: HEAD)
  -o OUTPUT      Local destination path (default: basename of FILE_PATH)
  -h             Show this help message and exit

Examples:
  # HTTPS — username + token
  $(basename "$0") -u myuser -p ghp_mytoken -r octocat/Hello-World -f README.md

  # HTTPS — with explicit branch and output path
  $(basename "$0") -u myuser -p ghp_mytoken -r octocat/Hello-World \\
      -f src/main.py -b develop -o ./downloaded_main.py

  # SSH key
  $(basename "$0") -k ~/.ssh/id_rsa -r octocat/Hello-World -f README.md

  # SSH key — with explicit branch and output path
  $(basename "$0") -k ~/.ssh/id_rsa -r octocat/Hello-World \\
      -f src/main.py -b develop -o ./downloaded_main.py
EOF
}

# ---------------------------------------------------------------------------
# parse arguments
# ---------------------------------------------------------------------------
USERNAME=""
PASSWORD=""
SSH_KEY=""
REPO=""
FILE_PATH=""
BRANCH="HEAD"
OUTPUT=""

while getopts "u:p:k:r:f:b:o:h" opt; do
    case "$opt" in
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        k) SSH_KEY="$OPTARG" ;;
        r) REPO="$OPTARG" ;;
        f) FILE_PATH="$OPTARG" ;;
        b) BRANCH="$OPTARG" ;;
        o) OUTPUT="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# validate required arguments
# ---------------------------------------------------------------------------
if [ -z "$REPO" ]; then
    echo "Error: repository (-r) is required." >&2
    usage >&2
    exit 1
fi

if [ -z "$FILE_PATH" ]; then
    echo "Error: file path (-f) is required." >&2
    usage >&2
    exit 1
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="$(basename "$FILE_PATH")"
fi

# ---------------------------------------------------------------------------
# helper: decode base64 content returned by the GitHub API
# The API embeds newlines inside the encoded string; strip them first.
# ---------------------------------------------------------------------------
decode_github_base64() {
    local encoded="$1"
    local clean
    clean="$(printf '%s' "$encoded" | tr -d '\n')"

    if command -v python3 &>/dev/null; then
        python3 -c "import base64,sys; sys.stdout.buffer.write(base64.b64decode('$clean'))"
    elif command -v python &>/dev/null; then
        python -c "import base64,sys; sys.stdout.write(base64.b64decode('$clean'))"
    elif command -v base64 &>/dev/null; then
        printf '%s' "$clean" | base64 --decode 2>/dev/null || \
        printf '%s' "$clean" | base64 -d
    else
        echo "Error: python3, python, or base64 is required to decode the API response." >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# SSH key mode — uses git-archive which transfers only the requested path
# ---------------------------------------------------------------------------
if [ -n "$SSH_KEY" ]; then
    if ! command -v git &>/dev/null; then
        echo "Error: git is required for SSH key authentication." >&2
        exit 1
    fi

    if [ ! -f "$SSH_KEY" ]; then
        echo "Error: SSH key file not found: $SSH_KEY" >&2
        exit 1
    fi

    echo "Downloading '${FILE_PATH}' from '${REPO}' via SSH key..."

    export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"

    git archive \
        --remote="git@github.com:${REPO}.git" \
        "$BRANCH" \
        "$FILE_PATH" \
        | tar --extract --to-stdout "$FILE_PATH" \
        > "$OUTPUT"

    echo "Saved to: ${OUTPUT}"
    exit 0
fi

# ---------------------------------------------------------------------------
# HTTPS mode — username + password/token via GitHub API
# ---------------------------------------------------------------------------
if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
    if ! command -v curl &>/dev/null; then
        echo "Error: curl is required for username/password authentication." >&2
        exit 1
    fi

    echo "Downloading '${FILE_PATH}' from '${REPO}' via HTTPS..."

    TMPFILE="$(mktemp)"
    trap 'rm -f "$TMPFILE"' EXIT

    API_URL="https://api.github.com/repos/${REPO}/contents/${FILE_PATH}?ref=${BRANCH}"

    HTTP_CODE="$(curl \
        --silent \
        --output "$TMPFILE" \
        --write-out "%{http_code}" \
        --header "Accept: application/vnd.github.v3+json" \
        --user "${USERNAME}:${PASSWORD}" \
        "$API_URL")"

    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "Error: GitHub API returned HTTP ${HTTP_CODE}." >&2
        cat "$TMPFILE" >&2
        exit 1
    fi

    # Extract the base64-encoded content field from the JSON response.
    if command -v python3 &>/dev/null; then
        python3 - "$TMPFILE" "$OUTPUT" <<'PYEOF'
import json, base64, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
with open(sys.argv[2], "wb") as out:
    out.write(base64.b64decode(data["content"]))
PYEOF
    elif command -v python &>/dev/null; then
        python - "$TMPFILE" "$OUTPUT" <<'PYEOF'
import json, base64, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
with open(sys.argv[2], "wb") as out:
    out.write(base64.b64decode(data["content"]))
PYEOF
    elif command -v jq &>/dev/null && command -v base64 &>/dev/null; then
        jq -r '.content' "$TMPFILE" \
            | tr -d '\n' \
            | base64 --decode 2>/dev/null > "$OUTPUT" \
        || jq -r '.content' "$TMPFILE" \
            | tr -d '\n' \
            | base64 -d > "$OUTPUT"
    else
        echo "Error: python3, python, or (jq + base64) is required to decode the response." >&2
        exit 1
    fi

    echo "Saved to: ${OUTPUT}"
    exit 0
fi

# ---------------------------------------------------------------------------
# no valid auth combination provided
# ---------------------------------------------------------------------------
echo "Error: provide either an SSH key (-k) or both a username (-u) and password/token (-p)." >&2
usage >&2
exit 1
