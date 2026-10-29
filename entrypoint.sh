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

# Restore defaults only when the mounted configuration is uninitialized.
if [[ ! -f /etc/cups/cupsd.conf ]]; then
    cp -rpn /etc/cups-bak/. /etc/cups/
fi

# An explicitly empty model disables the Brother installer.
if [[ -n "${CUPSBRPRINTER:-}" ]]; then
    printf 'y\ny\ny\ny\nn\nn\nn\n' | bash /root/linux-brprinter-installer-2.2.4-1 "$CUPSBRPRINTER"
fi

# The Brother installer (and its packages) can start a background scheduler.
# Stop it before launching the container's scheduler so TCP and the Unix socket
# use the same process and the same local authentication certificates.
/etc/init.d/cups stop

exec /usr/sbin/cupsd -f
