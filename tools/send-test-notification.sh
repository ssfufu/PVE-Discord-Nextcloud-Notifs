#!/usr/bin/env bash
# Sends a fake Proxmox notification to the Jenkins job, to test the whole
# chain without running a backup.
#
# Usage:
#   JENKINS_URL=https://jenkins.example.com ./tools/send-test-notification.sh [STATE] [TYPE] [HOST] [LOG_FILE]
#
#   STATE     info, notice, warning, error or unknown (default: info)
#   TYPE      vzdump, package-updates, gc, prune, verify... (default: vzdump)
#   HOST      name shown in the message (default: pve-test)
#   LOG_FILE  file sent as the log (default: a one-line test message)
#
# The webhook token is read from JENKINS_TOKEN, or asked for when unset.
# Requires bash and curl.
set -euo pipefail

usage() {
    sed -n '2,14s/^# \{0,1\}//p' "$0"
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

# Prints a JSON string. Other control characters are removed.
json() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
    printf '"%s"' "$s"
}

if [[ -z ${JENKINS_URL:-} ]]; then
    usage >&2
    exit 1
fi
if [[ ${JENKINS_URL} != https://* ]]; then
    echo "Warning: ${JENKINS_URL} is not HTTPS, the token is sent in clear text." >&2
fi
if [[ -z ${JENKINS_TOKEN:-} ]]; then
    read -rsp 'Webhook token: ' JENKINS_TOKEN
    echo
fi

state=${1:-info}
type=${2:-vzdump}
host=${3:-pve-test}
log_file=${4:-}

if [[ -n $log_file ]]; then
    log=$(<"$log_file")
else
    log="Test notification sent on $(date -u '+%F %T') UTC."
fi

payload=$(mktemp)
trap 'rm -f "$payload"' EXIT

printf '{"X_STATE": %s, "X_TYPE": %s, "X_HOST": %s, "X_TITLE": %s, "X_TIMESTAMP": %s, "X_LOG_CONTENT": %s}\n' \
    "$(json "$state")" "$(json "$type")" "$(json "$host")" \
    "$(json "Test notification ($type, $state)")" "$(date +%s)" "$(json "$log")" >"$payload"

# The token is given to curl on stdin so it does not show in the process list.
token=${JENKINS_TOKEN//\\/\\\\}
token=${token//\"/\\\"}
printf 'header = "Authorization: Bearer %s"\n' "$token" |
    curl --config - --silent --show-error --fail-with-body \
        --connect-timeout 10 --max-time 60 \
        --header 'Content-Type: application/json' \
        --data-binary @"$payload" \
        "${JENKINS_URL%/}/generic-webhook-trigger/invoke"
echo
