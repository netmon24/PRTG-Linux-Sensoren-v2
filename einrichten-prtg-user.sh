#!/bin/bash
# Richtet auf einem Linux-Host den Monitoring-Benutzer fuer PRTG ein.
# Aufruf als root:  ./einrichten-prtg-user.sh "ssh-rsa AAAA... prtg-monitoring" [docker]
# Zweites Argument "docker" legt zusaetzlich die enge sudoers-Regel fuer Docker an.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Bitte als root ausfuehren (sudo)." >&2; exit 1; }
PUBKEY="${1:-}"
[ -n "$PUBKEY" ] || { echo "Aufruf: $0 \"<oeffentlicher Schluessel>\" [docker]" >&2; exit 1; }

id prtg >/dev/null 2>&1 || useradd -m -s /bin/bash prtg
install -d -m 700 -o prtg -g prtg /home/prtg/.ssh
printf '%s\n' "$PUBKEY" > /home/prtg/.ssh/authorized_keys
chmod 600 /home/prtg/.ssh/authorized_keys
chown prtg:prtg /home/prtg/.ssh/authorized_keys

# Skriptordner fuer den SSH Script v2 Sensor
install -d -m 755 /opt/paessler/share/scripts

if [ "${2:-}" = "docker" ]; then
  cat > /etc/sudoers.d/prtg-docker <<'EOF'
Cmnd_Alias DOCKER_RO = /usr/bin/docker ps, /usr/bin/docker ps *, /usr/bin/docker images, /usr/bin/docker images *, /usr/bin/docker system df, /usr/bin/docker system df *, /usr/bin/docker stats *, /usr/bin/docker inspect *
Defaults:prtg !requiretty
prtg ALL=(root) NOPASSWD: DOCKER_RO
EOF
  chmod 440 /etc/sudoers.d/prtg-docker
  visudo -cf /etc/sudoers.d/prtg-docker
fi
echo "Fertig: Benutzer prtg, Schluessel und /opt/paessler/share/scripts eingerichtet."
