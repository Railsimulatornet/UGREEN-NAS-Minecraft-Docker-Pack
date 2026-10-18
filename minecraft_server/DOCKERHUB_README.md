# Minecraft Maintenance

[![Maintenance Image + Security](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/actions/workflows/dockerhub-minecraft-maintenance.yml/badge.svg?branch=main)](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/actions/workflows/dockerhub-minecraft-maintenance.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/LICENSE)

[Deutsch](#deutsch) · [English](#english)

## Deutsch

Minecraft Maintenance stellt die Wartungsumgebung für das [UGREEN Minecraft Docker Pack](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack) bereit. Verwende das Image mit dem vollständigen Projektordner: Skripte, Cron-Konfiguration und Statusdateien werden zur Laufzeit aus diesem Ordner eingebunden.

### Funktionen

- Alpine Linux 3.24 als Basis
- Bash, Python, Git, curl, jq und rsync
- Docker CLI für die Kommunikation mit dem Docker-Host
- Lighttpd für die Status- und Metrikseite
- Werkzeuge für Watchdog, Backups und Addon-Updates
- Images für `linux/amd64` und `linux/arm64`
- Trivy-Prüfung beider Architekturen sowie SBOM- und Provenance-Attestierungen

### Schnellstart

1. Lade den vollständigen Projektordner `minecraft_server/` aus dem [Docker Pack](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/releases/latest) herunter.
2. Passe dessen `.env` an und behalte die Mounts aus der mitgelieferten Compose-Datei bei.
3. Stelle das Projekt über die UGOS-Docker-App oder Docker Compose bereit.

Die Maintenance-Service-Konfiguration verwendet diesen Image-Eintrag:

```yaml
image: railsimulatornet/minecraft-maintenance:1.0.3
```

Die vollständigen Startbefehle, Einstellungen und Voraussetzungen stehen in der [zweisprachigen Projektanleitung](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack#deutsch).

### Aktualisierung und Tags

| Tag | Bedeutung |
| --- | --- |
| `1.0.3` | Fester Maintenance-Release im aktuellen Docker Pack |
| `1.0` | Folgt neuen Releases der Reihe 1.0 |
| `latest` | Aktueller geprüfter Build einschließlich wöchentlicher Wartungsbuilds |

Wöchentliche Builds aktualisieren nur `latest`. Feste Versionstags bleiben erhalten. Beide Architekturen müssen die Prüfungen bestehen, bevor das geprüfte Image ohne weiteren Build veröffentlicht wird. Behebbare HIGH- oder CRITICAL-Funde und Scanfehler blockieren die Veröffentlichung.

Behalte bei Updates deine `.env`, Welten, Backups, Addons und Autoheal-Daten. Aktualisiere den bestehenden Docker-Stack nach der [Projektanleitung](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack#aktualisierung).

### Sicherheit und Dokumentation

Der Maintenance-Container verwendet den Docker-Socket und kann damit weitreichende Aktionen auf dem Host ausführen. Schütze das Image, die eingebundenen Skripte und den Docker-Zugriff vor unberechtigten Änderungen.

- [Vollständige Compose-Datei](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/minecraft_server/docker-compose.yaml)
- [Build-Quelle](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/minecraft_server/Dockerfile.mc_maintenance)
- [Installationshandbuch Deutsch/Englisch](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/UGREEN_Minecraft_Docker_Pack_Installation-DE-EN.pdf)

### Lizenz

[MIT License](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/LICENSE) · Copyright Roman Glos 2026.

## English

Minecraft Maintenance provides the maintenance environment for the [UGREEN Minecraft Docker Pack](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack). Use the image with the complete project directory: scripts, cron configuration and status files are mounted from that directory at runtime.

### Features

- Alpine Linux 3.24 base
- Bash, Python, Git, curl, jq and rsync
- Docker CLI for communication with the Docker host
- Lighttpd for the status and metrics page
- Tools for watchdog checks, backups and addon updates
- Images for `linux/amd64` and `linux/arm64`
- Trivy checks for both architectures, plus SBOM and provenance attestations

### Quick start

1. Download the complete `minecraft_server/` project directory from the [Docker Pack](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/releases/latest).
2. Adjust its `.env` and retain the mounts in the supplied Compose file.
3. Deploy the project through the UGOS Docker app or Docker Compose.

The maintenance service uses this image entry:

```yaml
image: railsimulatornet/minecraft-maintenance:1.0.3
```

Full startup commands, settings and requirements are in the [bilingual project guide](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack#english).

### Updating and tags

| Tag | Meaning |
| --- | --- |
| `1.0.3` | Fixed maintenance release in the current Docker Pack |
| `1.0` | Follows new releases in the 1.0 series |
| `latest` | Current verified build, including weekly maintenance builds |

Weekly builds update only `latest`. Fixed version tags are retained. Both architectures must pass the checks before the verified image is published without rebuilding. Fixable HIGH or CRITICAL findings and scan errors block publication.

Keep your `.env`, worlds, backups, addons and Autoheal data when updating. Update the existing Docker stack using the [project guide](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack#updating).

### Security and documentation

The maintenance container uses the Docker socket and can perform extensive actions on the host. Protect the image, mounted scripts and Docker access from unauthorized changes.

- [Complete Compose file](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/minecraft_server/docker-compose.yaml)
- [Build source](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/minecraft_server/Dockerfile.mc_maintenance)
- [German/English installation handbook](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/UGREEN_Minecraft_Docker_Pack_Installation-DE-EN.pdf)

### License

[MIT License](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack/blob/main/LICENSE) · Copyright Roman Glos 2026.
