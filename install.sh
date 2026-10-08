#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR='/etc/ssh-login-notify'
CONF="$APP_DIR/telegram.conf"
HOOK='/usr/local/sbin/ssh-login-telegram.sh'
PAM_SSH='/etc/pam.d/sshd'
PAM_RULE="session optional pam_exec.so quiet type=open_session $HOOK"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

[[ $EUID -eq 0 ]] || fail 'Run this installer as root: sudo bash install.sh'
[[ -r /etc/os-release ]] || fail 'Cannot detect the operating system.'
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] || fail 'This installer supports Debian 13 only.'
[[ -f $PAM_SSH ]] || fail 'Missing /etc/pam.d/sshd.'

has_rule() { grep -Fxq -- "$PAM_RULE" "$1"; }

# Do not reinstall or overwrite an existing complete installation.
if [[ -f $CONF && -f $HOOK ]] && has_rule "$PAM_SSH"; then
    info 'SSH Login Notifier is already installed. Skipping installation.'
    if [[ -f /etc/pam.d/login ]] && grep -Fq -- "$HOOK" /etc/pam.d/login; then
        info 'Note: a legacy PAM hook still exists in /etc/pam.d/login.'
        info 'This installer does not modify an existing installation or remove legacy hooks.'
    fi
    exit 0
fi

# Avoid overwriting pre-existing files or creating duplicate hooks.
if [[ -e $APP_DIR || -L $APP_DIR || -e $HOOK || -L $HOOK ]] \
    || grep -Fq -- "$HOOK" "$PAM_SSH"; then
    fail 'Existing files or a partial installation were found. Inspect them before retrying.'
fi

[[ -r /dev/tty && -w /dev/tty ]] || fail 'An interactive terminal is required.'

info '=== Debian 13 SSH Login Telegram Notifier ==='
printf 'Telegram Bot Token (hidden): ' > /dev/tty
IFS= read -rs BOT_TOKEN < /dev/tty
printf '\n' > /dev/tty
[[ $BOT_TOKEN =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || fail 'Invalid Bot Token format.'

printf 'Telegram Chat ID (numeric): ' > /dev/tty
IFS= read -r CHAT_ID < /dev/tty
[[ $CHAT_ID =~ ^-?[0-9]+$ ]] || fail 'Chat ID must be a number.'

printf 'Server label (press Enter to use the hostname): ' > /dev/tty
IFS= read -r SERVER_REMARK < /dev/tty
SERVER_REMARK=${SERVER_REMARK:-$(/usr/bin/hostname)}

if [[ ! -x /usr/bin/curl ]]; then
    info 'Installing curl with apt ...'
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl
fi
[[ -x /usr/bin/curl ]] || fail 'curl is required but was not found.'

if [[ -x /usr/sbin/sshd ]]; then
    SSH_PAM=$(/usr/sbin/sshd -T 2>/dev/null | awk 'tolower($1)=="usepam" {print tolower($2);exit}')
    [[ $SSH_PAM == yes ]] || fail 'SSH does not appear to have UsePAM enabled.'
fi

TMP_DIR=$(mktemp -d)
BACKUP_DIR=$(mktemp -d /var/backups/ssh-login-notify.XXXXXXXX)
STARTED=0

cleanup() {
    result=$?
    trap - EXIT
    if (( result != 0 && STARTED == 1 )); then
        cp -a "$BACKUP_DIR/sshd" "$PAM_SSH" || true
        rm -f -- "$HOOK" "$CONF"
        rmdir -- "$APP_DIR" 2>/dev/null || true
        printf 'Installation failed; attempted to restore PAM. Backup: %s\n' "$BACKUP_DIR" >&2
    fi
    rm -rf -- "$TMP_DIR"
    exit "$result"
}
trap cleanup EXIT

cp -a "$PAM_SSH" "$BACKUP_DIR/sshd"

# Shell-escape user input before storing it in a root-only config file.
printf 'BOT_TOKEN=%q\nCHAT_ID=%q\nSERVER_REMARK=%q\n' \
    "$BOT_TOKEN" "$CHAT_ID" "$SERVER_REMARK" > "$TMP_DIR/telegram.conf"

cat > "$TMP_DIR/notify.sh" <<'NOTIFY'
#!/bin/bash

# Only SSH session creation events should trigger a notification.
[[ "${PAM_SERVICE:-}" == 'sshd' ]] || exit 0
[[ "${PAM_TYPE:-}" == 'open_session' ]] || exit 0

CONFIG='/etc/ssh-login-notify/telegram.conf'
[[ -r "$CONFIG" ]] || exit 0
source "$CONFIG"
[[ -n "${BOT_TOKEN:-}" && -n "${CHAT_ID:-}" ]] || exit 0

HOST=$(/usr/bin/hostname)
USER_NAME="${PAM_USER:-unknown}"
REMOTE="${PAM_RHOST:-unknown}"
TIME=$(/usr/bin/date '+%Y-%m-%d %H:%M:%S %Z')
SERVER_REMARK="${SERVER_REMARK:-$HOST}"

MESSAGE=$(printf '🔐 SSH login successful\n\n🏷 Server label: %s\n🖥 Hostname: %s\n👤 User: %s\n🌐 Source: %s\n🕒 Time: %s' \
    "$SERVER_REMARK" "$HOST" "$USER_NAME" "$REMOTE" "$TIME")

(
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$BOT_TOKEN" |
        /usr/bin/curl --config - --fail --silent --show-error \
            --connect-timeout 3 --max-time 8 --output /dev/null \
            --data-urlencode "chat_id=${CHAT_ID}" \
            --data-urlencode "text=${MESSAGE}" \
        || /usr/bin/logger -t ssh-telegram 'Telegram notification failed'
) </dev/null >/dev/null 2>&1 &

exit 0
NOTIFY

/bin/bash -n "$TMP_DIR/notify.sh"

STARTED=1
install -d -o root -g root -m 700 "$APP_DIR"
install -o root -g root -m 600 "$TMP_DIR/telegram.conf" "$CONF"
install -o root -g root -m 700 "$TMP_DIR/notify.sh" "$HOOK"

# Only modify sshd; leave /etc/pam.d/login untouched.
printf '\n# ssh-login-notify: SSH login notification\n%s\n' "$PAM_RULE" >> "$PAM_SSH"

info 'Installation completed successfully.'
info 'SSH login notifications are now enabled.'
info "PAM backup: $BACKUP_DIR"
info 'No sshd restart is required. Open a new SSH session to test.'
