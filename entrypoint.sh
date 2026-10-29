#!/bin/bash
set -euo pipefail

: "${CUPSADMIN:?Set CUPSADMIN}"
: "${CUPSPASSWORD:?Set CUPSPASSWORD}"
: "${TZ:?Set TZ}"

# chpasswd uses colon-delimited records; reject extra records or fields.
if [[ "$CUPSADMIN" == *:* || "$CUPSADMIN" == *$'\n'* ||
      "$CUPSPASSWORD" == *$'\n'* ]]; then
    echo "Admin credentials must not contain newlines or a colon in the username" >&2
    exit 1
fi
if [[ "$TZ" == /* || "$TZ" == *..* || ! -f "/usr/share/zoneinfo/$TZ" ]]; then
    echo "Invalid timezone: $TZ" >&2
    exit 1
fi

if ! id -u "$CUPSADMIN" >/dev/null 2>&1; then
    useradd -r -G lpadmin -M "$CUPSADMIN"
fi
usermod -aG lpadmin "$CUPSADMIN"
# Apply changes on every start, without logging the password.
printf '%s:%s\n' "$CUPSADMIN" "$CUPSPASSWORD" | chpasswd
ln -fs "/usr/share/zoneinfo/$TZ" /etc/localtime
printf '%s\n' "$TZ" > /etc/timezone

# Migrate daemon settings once, including existing bind-mounted configurations.
# Printer queues, PPDs, certificates, and other persistent files stay in place.
config_version=/etc/cups/.container-config-v2
if [[ ! -f "$config_version" ]]; then
    if [[ -f /etc/cups/cupsd.conf ]]; then
        backup_dir=$(mktemp -d /etc/cups/.before-config-v2.XXXXXX)
        for config in cupsd.conf cups-files.conf; do
            if [[ -f "/etc/cups/$config" ]]; then
                cp -p "/etc/cups/$config" "$backup_dir/"
            fi
        done
        echo "Previous CUPS daemon settings saved in $backup_dir"
    else
        for default in /etc/cups-bak/*; do
            if [[ ! -e "/etc/cups/${default##*/}" ]]; then
                cp -rp "$default" /etc/cups/
            fi
        done
    fi
    cp -p /etc/cups-bak/cupsd.conf /etc/cups/cupsd.conf
    cp -p /etc/cups-bak/cups-files.conf /etc/cups/cups-files.conf
    /usr/sbin/cupsd -t
    touch "$config_version"
fi

# An explicitly empty model disables the Brother installer.
if [[ -n "${CUPSBRPRINTER:-}" ]]; then
    printf 'y\ny\ny\ny\nn\nn\nn\n' | bash /root/linux-brprinter-installer-2.2.4-1 "$CUPSBRPRINTER"
fi

# The Brother installer (and its packages) can start a background scheduler.
# Stop it before launching the container's scheduler so TCP and the Unix socket
# use the same process and the same local authentication certificates.
/etc/init.d/cups stop
# Fail rather than serve TCP and the Unix socket from different schedulers.
if pgrep -x cupsd >/dev/null; then
    echo "A CUPS scheduler is still running after setup; refusing to start a second one" >&2
    exit 1
fi
/usr/sbin/cupsd -t

exec "$@"
