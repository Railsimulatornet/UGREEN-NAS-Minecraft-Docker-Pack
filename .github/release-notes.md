## Deutsch

UGREEN Minecraft Docker Pack 1.1.5

### Änderungen

- Das feste Maintenance-Image wurde von `railsimulatornet/minecraft-maintenance:1.0.2` auf `railsimulatornet/minecraft-maintenance:1.0.3` aktualisiert.
- Das Maintenance-Image wird weiterhin frisch aus Alpine 3.24 für `linux/amd64` und `linux/arm64` gebaut.
- Der zuvor von Trivy gemeldete behebbare HIGH-Fund in `libexpat` ist im neu gebauten Maintenance-Image nicht mehr vorhanden.
- Vor der Veröffentlichung blockiert der bestehende Trivy-Security-Gate weiterhin bei behebbaren HIGH- oder CRITICAL-Funden.
- Der Docker-Pack-Release bleibt reproduzierbar auf den festen Maintenance-Tag `1.0.3` gepinnt.
- Der bewegliche Tag `latest` kann unabhängig davon durch den wöchentlichen Security-Workflow frisch gebaut werden, ohne veröffentlichte Versionstags zu verändern.

### Hinweis für bestehende Installationen

Die eigene produktive `.env` nicht überschreiben. Für dieses Update genügt die neue `docker-compose.yaml` beziehungsweise die Änderung des Maintenance-Image-Tags von `1.0.2` auf `1.0.3`.

## English

UGREEN Minecraft Docker Pack 1.1.5

### Changes

- The pinned maintenance image was updated from `railsimulatornet/minecraft-maintenance:1.0.2` to `railsimulatornet/minecraft-maintenance:1.0.3`.
- The maintenance image continues to be built fresh from Alpine 3.24 for `linux/amd64` and `linux/arm64`.
- The previously reported fixable HIGH finding in `libexpat` is no longer present in the rebuilt maintenance image.
- The existing Trivy security gate continues to block publication when fixable HIGH or CRITICAL findings are present.
- The Docker Pack remains reproducibly pinned to the immutable maintenance tag `1.0.3`.
- The moving `latest` tag can be refreshed independently by the weekly security workflow without modifying published version tags.

### Note for existing installations

Do not overwrite your customized production `.env`. For this update, use the new `docker-compose.yaml` or change only the maintenance image tag from `1.0.2` to `1.0.3`.
