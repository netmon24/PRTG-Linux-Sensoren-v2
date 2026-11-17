# PRTG-Linux-Sensoren-v2

Vier Skripte für den PRTG-Sensor **SSH Script v2**, mit denen sich Linux-Server um Messwerte erweitern lassen, die die Standardsensoren nicht liefern: Systemzustand, Ende des Herstellersupports und Docker. Von netmon24, frei nutzbar unter der Apache-Lizenz 2.0.

Die Skripte lesen nur. Sie ändern nichts auf dem überwachten System und brauchen, bis auf die Docker-Abfragen, keine Root-Rechte.

## Die Skripte

| Skript | Zweck | Kanäle |
|---|---|---|
| `linux_health_v2.sh` | Sammelwerte eines Linux-Servers | Angemeldete Benutzer, Prozesse, Zombie-Prozesse, Load (1, 5, 15 Minuten und je Kern), Speicher, Swap, vollster Mountpoint, TCP-Verbindungen, Laufzeit |
| `os_lifecycle_v2.sh` | Lebenszyklus des Betriebssystems | Tage bis zum Ende des Herstellersupports, ausstehende Updates, davon Sicherheitsupdates, Neustart erforderlich |
| `docker_health_v2.sh` | Docker-Host im Überblick | Container gesamt, laufend, beendet, in Neustartschleife, pausiert, ohne gesunden Healthcheck, Images, ungenutzte Images, Plattenbedarf |
| `docker_container_v2.sh <Name>` | Ein einzelner Container | Status, Exit-Code, Neustarts, Laufzeit, CPU, Speicher, Prozesse, Netzwerk, Plattenzugriffe |

Alle vier liefern das JSON-Schema **Version 3** des SSH Script v2 Sensors, samt Grenzwerten und Statusmeldung im Klartext. Die Grenzwerte lassen sich im Sensor in PRTG überschreiben.

### Kurzbeschreibung der Bewertung

- **Linux Health:** Warnung ab 85 % Plattenbelegung, Fehler ab 95 %. Warnung bei Speicher ab 90 %, Swap ab 50 %, Load je Kern ab 200 %, bei Zombie-Prozessen und wenn mehr als die erlaubte Zahl an Benutzern angemeldet ist (Parameter, Standard 5).
- **OS Lifecycle:** Warnung unter 180 Tagen bis zum Ende des Supports, Fehler ab dem Ende. Die Termine stehen in einer Tabelle am Anfang des Skripts und gelten für Debian, Ubuntu (Standardsupport) sowie RHEL, AlmaLinux und Rocky. Bei neuen Versionen müssen Sie die Tabelle selbst ergänzen. Eine unbekannte Version meldet das Skript als Warnung.
- **Docker Health:** Fehler bei Containern mit Healthcheck „unhealthy“, Warnung bei Containern in der Neustartschleife und bei mehr als 5 ungenutzten Images.
- **Docker Container:** Fehler, wenn der Container nicht läuft oder „unhealthy“ ist, Warnung beim Start des Healthchecks und ab 90 % Speicher.

## Voraussetzungen

- PRTG mit dem Sensor **SSH Script v2**, getestet mit PRTG 26.4.126.
- SSH-Zugang vom PRTG-Server zum Linux-Rechner. Der Sensor erwartet einen **RSA-Schlüssel im PEM-Format ohne Passphrase**.
- Die Skripte liegen auf dem Linux-Rechner in `/opt/paessler/share/scripts` und sind ausführbar.
- Für die Docker-Skripte eine eng gefasste sudo-Regel (siehe unten).

## Einrichten

### 1. Benutzer, Schlüssel und Skriptordner anlegen

Auf dem Linux-Rechner als root ausführen. Das Skript `einrichten-prtg-user.sh` legt den Benutzer `prtg` an, hinterlegt den öffentlichen Schlüssel und erstellt den Skriptordner:

```bash
sudo ./einrichten-prtg-user.sh "ssh-rsa AAAA... prtg-monitoring"
```

Für Docker-Rechner als zweites Argument `docker` angeben. Dann legt das Skript zusätzlich eine sudo-Regel an, die dem Benutzer `prtg` nur lesende Docker-Befehle erlaubt (`docker ps`, `images`, `system df`, `stats`, `inspect`):

```bash
sudo ./einrichten-prtg-user.sh "ssh-rsa AAAA... prtg-monitoring" docker
```

Den Schlüssel erzeugen Sie vorher auf dem PRTG-Server oder einem Verwaltungsrechner:

```bash
ssh-keygen -t rsa -b 4096 -m PEM -N "" -f prtg_linux -C prtg-monitoring
```

Der private Schlüssel `prtg_linux` bleibt geheim und gehört nur in die Zugangsdaten in PRTG. Der Inhalt von `prtg_linux.pub` ist das Argument für das Skript.

### 2. Skripte kopieren

```bash
scp skripte/*.sh benutzer@server:/tmp/
ssh -t benutzer@server 'sudo install -m 755 /tmp/*_v2.sh /opt/paessler/share/scripts/'
```

### 3. Zugangsdaten in PRTG

Am Gerät (oder an einer Gruppe) unter „Zugangsdaten für Linux-Systeme“: Benutzer `prtg`, Anmeldung mit privatem Schlüssel, **Rechteerhöhung „Keine“**. Steht dort noch eine Gruppe mit anderem Benutzer und Rechteerhöhung, legen Sie die Zugangsdaten am Gerät neu fest, sonst meldet PRTG einen Fehler zum Wert `elevation_method`.

### 4. Sensoren anlegen

Am Gerät **Sensor hinzufügen → SSH Script v2** und das Skript auswählen. Beim Docker-Container-Sensor tragen Sie den Containernamen im Feld **Parameter** ein, ohne Parameter meldet das Skript „Containername als Parameter fehlt“. Pro Container ein Sensor.

Der Parameter von `linux_health_v2.sh` ist optional: die Zahl der angemeldeten Benutzer, ab der der Sensor warnt.

## Testen auf dem Linux-Rechner

PRTG führt die Skripte mit einem minimalen Pfad aus. Wenn Sie auf der Kommandozeile mit dem gleichen Umfeld prüfen, vermeiden Sie böse Überraschungen:

```bash
sudo -u prtg env -i /bin/bash --noprofile --norc -c '/opt/paessler/share/scripts/linux_health_v2.sh'
```

Die Ausgabe ist JSON mit `"version": 3`, Status, Meldung und der Kanalliste. Kommt stattdessen eine Fehlermeldung oder nichts, liegt es am Pfad, an den Rechten oder (bei Docker) an der sudo-Regel. Bei `docker_container_v2.sh` hängen Sie den Containernamen an.

## Sicherheit

Die Skripte lesen nur, aber die sudo-Regel für Docker hat eine Folge, die Sie kennen sollten:

- Sie erlaubt dem Benutzer `prtg` `docker ps`, `images`, `system df`, `stats` und `inspect` jeweils mit beliebigen Zusätzen. Damit lässt sich kein Container starten und kein Zugriff auf das Dateisystem erlangen.
- **`docker inspect` zeigt auch die Umgebungsvariablen eines Containers.** Dort stehen oft Kennwörter und Schlüssel. Wer den privaten SSH-Schlüssel des Benutzers `prtg` besitzt, kann sie lesen.
- Schützen Sie den Schlüssel deshalb wie ein Kennwort: nur in den Zugangsdaten in PRTG ablegen, nicht weitergeben, nicht auf mehreren Rechnern verteilen. Prüfen Sie, ob auf dem Host Container mit sensiblen Umgebungsvariablen laufen, bevor Sie die Docker-Regel einrichten.
- Der Benutzer `prtg` gehört **nicht** in die Gruppe `docker`. Das wäre faktisch Root-Zugriff.
- Wer die Regel enger fassen möchte, kann statt der Platzhalter ein Hilfsskript unter Root-Rechten einsetzen, das den Containernamen prüft und nur die nötigen Felder ausgibt, und die sudo-Regel auf dieses Skript beschränken.

## Grenzen

- Die Docker-Skripte rufen `sudo -n /usr/bin/docker` auf. Liegt Docker woanders, passen Sie den Pfad am Anfang der Skripte und in der sudo-Regel an.
- `os_lifecycle_v2.sh` ermittelt Updates über `apt-get -s` (Debian, Ubuntu) oder `dnf` (RHEL-Familie) ohne Root. Der `dnf`-Zweig ist bisher nicht in der Praxis getestet.
- Die Supporttermine sind Stand September 2026 und gehören zu den Herstellerangaben. Prüfen Sie sie vor dem produktiven Einsatz.

## Lizenz

Apache-Lizenz 2.0, siehe [LICENSE](LICENSE). Verwendung auf eigene Verantwortung, ohne Gewährleistung.

Fragen und Ergänzungen als Issue oder Pull Request.
