# UGREEN Minecraft Docker Pack

## Deutsch

Community-Projekt für **UGREEN NAS / UGOS** mit einem oder zwei **Minecraft Bedrock**-Servern, automatischen **Bedrockifier**-Backups, einem **Maintenance**-Container, Addon-Update-Automatisierung, Watchdog-Prüfungen und **SMTP / Apprise**-Benachrichtigungen.

### Enthalten

- `minecraft_server/` als kompletter Projektordner für UGOS Docker
- zweisprachige `.env` mit deutschen und englischen Kommentaren
- optionale Creative- und Survival-Serverprofile
- Backup-Container mit konfigurierbaren Zielen und Intervallen
- Maintenance-Skripte für Benachrichtigungen, Watchdog und Addon-Updates
- relative Projektpfade für eine UGOS-freundliche Bereitstellung
- Installationshandbuch als PDF

### Ordnerstruktur

```text
minecraft_server/
├── .env
├── docker-compose.yaml
├── Dockerfile.mc_maintenance
├── addons_repo/
├── backup/
├── creative/
├── maintenance/
└── survival/
```

### Schnellstart

1. Repository oder Release herunterladen.
2. `minecraft_server/.env` anpassen.
3. Den kompletten Ordner `minecraft_server/` in die Docker-Freigabe der NAS kopieren.
4. In UGOS **Docker -> Projekt -> Erstellen** öffnen.
5. Den vorhandenen Ordner `minecraft_server` auswählen.
6. Die vorhandene `docker-compose.yaml` importieren.
7. Projekt bereitstellen und den ersten Start vollständig abwarten.

### Hinweise

- Dies ist ein **Community-Projekt**, kein offizielles UGREEN-Produkt.
- Verwendung auf eigene Verantwortung.
- Die ausführliche Schritt-für-Schritt-Anleitung befindet sich im mitgelieferten PDF-Handbuch.

### Copyright

Copyright Roman Glos 2026  
UGREEN NAS Community

---

## English

Community project for **UGREEN NAS / UGOS** with one or two **Minecraft Bedrock** servers, automatic **Bedrockifier** backups, a **Maintenance** container, addon update automation, watchdog checks and **SMTP / Apprise** notifications.

### Included

- `minecraft_server/` as the full project folder for UGOS Docker
- bilingual `.env` with German and English comments
- optional creative and survival server profiles
- backup container with configurable targets and intervals
- maintenance scripts for notifications, watchdog checks and addon updates
- relative project paths for UGOS-friendly deployment
- installation manual as PDF

### Directory layout

```text
minecraft_server/
├── .env
├── docker-compose.yaml
├── Dockerfile.mc_maintenance
├── addons_repo/
├── backup/
├── creative/
├── maintenance/
└── survival/
```

### Quick start

1. Download the repository or release.
2. Adjust `minecraft_server/.env`.
3. Copy the complete `minecraft_server/` folder into your NAS Docker share.
4. In UGOS, open **Docker -> Project -> Create**.
5. Select the existing `minecraft_server` folder.
6. Import the existing `docker-compose.yaml`.
7. Deploy the project and wait until the first startup is fully complete.

### Notes

- This is a **community project**, not an official UGREEN product.
- Use at your own risk.
- The detailed step-by-step guide is included in the PDF manual.

### Copyright

Copyright Roman Glos 2026  
UGREEN NAS Community
