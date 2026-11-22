"""Select publication only for trusted maintenance-image builds."""
import json
import os
from pathlib import Path
import re
import subprocess

REPOSITORY = "Railsimulatornet/UGREEN-NAS-Minecraft-Docker-Pack"
VERSION_FILE = Path("minecraft_server/MAINTENANCE_IMAGE_VERSION")
IMAGE_INPUTS = {"minecraft_server/Dockerfile.mc_maintenance", str(VERSION_FILE), "minecraft_server/health/maintenance_health.py"}


def validate_version(version):
    if not re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("Maintenance image version must use X.Y.Z format")
    return version


def publication_mode(event_name, repository, ref, changed=(), manual_mode="latest"):
    if repository != REPOSITORY or ref != "refs/heads/main":
        return "none"
    if event_name == "schedule":
        return "latest"
    if event_name == "workflow_dispatch":
        if manual_mode not in {"latest", "release"}:
            raise ValueError("Invalid publication mode")
        return manual_mode
    if event_name == "push" and str(VERSION_FILE) in changed:
        return "release"
    if event_name == "push" and any(path in IMAGE_INPUTS for path in changed):
        return "latest"
    return "none"


def main():
    version = validate_version(VERSION_FILE.read_text().strip())
    event_name = os.environ["GITHUB_EVENT_NAME"]
    changed = []
    if event_name == "push":
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        before, after = event.get("before", ""), os.environ["GITHUB_SHA"]
        if not all(re.fullmatch(r"[a-f0-9]{40}", value) for value in (before, after)):
            raise ValueError("Invalid push revisions")
        if before != "0" * 40:
            changed = subprocess.check_output(
                ["git", "diff", "--name-only", before, after], text=True
            ).splitlines()
    mode = publication_mode(
        event_name, os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_REF"], changed,
        os.environ.get("INPUT_PUBLICATION_MODE") or "latest"
    )
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"version={version}\npublication={mode}\n")


if __name__ == "__main__":
    main()
