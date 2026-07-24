# Minecraft Maintenance

Multi-architecture maintenance image for the **UGREEN Minecraft Docker Pack**.

> This image is part of the complete Docker Pack and is normally used through its supplied `docker-compose.yaml`. The maintenance scripts, cron configuration and web files are mounted from the project directory at runtime.

## Deutsch

Das Image stellt die Wartungsumgebung für das UGREEN Minecraft Docker Pack bereit. Es enthält unter anderem:

- Alpine Linux 3.24
- Bash, Python, Git, curl, jq und rsync
- Docker CLI für die Kommunikation mit dem Docker-Host
- Lighttpd für die integrierte Status- und Metrikseite
- Cron und Werkzeuge für Watchdog, Backups und Addon-Aktualisierungen
- Multi-Arch-Unterstützung für `linux/amd64` und `linux/arm64`
- SBOM- und Provenance-Attestierungen bei der Veröffentlichung

### Empfohlene Verwendung

```yaml
minecraftserver_maintenance:
  image: railsimulatornet/minecraft-maintenance:1.0.0
```

Die vollständige Compose-Konfiguration, Skripte und Installationsanleitung befinden sich im GitHub-Projekt:

**[UGREEN NAS Minecraft Docker Pack auf GitHub](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack)**

## English

This image provides the maintenance environment for the UGREEN Minecraft Docker Pack. It includes:

- Alpine Linux 3.24
- Bash, Python, Git, curl, jq and rsync
- Docker CLI for communication with the Docker host
- Lighttpd for the integrated status and metrics page
- Cron and utilities for watchdog checks, backups and addon updates
- Multi-architecture support for `linux/amd64` and `linux/arm64`
- SBOM and provenance attestations on published images

### Recommended usage

```yaml
minecraftserver_maintenance:
  image: railsimulatornet/minecraft-maintenance:1.0.0
```

The complete Compose configuration, scripts and installation guide are available in the GitHub project:

**[UGREEN NAS Minecraft Docker Pack on GitHub](https://github.com/Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack)**

## Image tags

- `1.0.0` – fixed release
- `1.0` – newest patch release in the 1.0 series
- `latest` – current stable release

## License

MIT License. Copyright Roman Glos 2026.
