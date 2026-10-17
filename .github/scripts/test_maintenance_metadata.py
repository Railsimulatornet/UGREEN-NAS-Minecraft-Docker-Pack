"""Publication decisions for maintenance builds, without network access."""
import unittest

from maintenance_metadata import IMAGE_INPUTS, REPOSITORY, publication_mode, validate_version


class MetadataTests(unittest.TestCase):
    def mode(self, event, changed=(), repository=REPOSITORY, ref="refs/heads/main"):
        return publication_mode(event, repository, ref, changed)

    def test_pull_request_cannot_publish(self):
        self.assertEqual(self.mode("pull_request", IMAGE_INPUTS), "none")

    def test_only_image_source_pushes_publish_release(self):
        for path in IMAGE_INPUTS:
            self.assertEqual(self.mode("push", [path]), "release")
        for path in ("README.md", ".github/workflows/dockerhub-minecraft-maintenance.yml",
                     ".github/scripts/maintenance_metadata.py"):
            self.assertEqual(self.mode("push", [path]), "none")

    def test_weekly_build_updates_only_latest(self):
        self.assertEqual(self.mode("schedule"), "latest")

    def test_manual_main_build_checks_release(self):
        self.assertEqual(self.mode("workflow_dispatch"), "release")

    def test_other_repository_or_branch_cannot_publish(self):
        for event in ("push", "schedule", "workflow_dispatch"):
            self.assertEqual(self.mode(event, IMAGE_INPUTS, repository="someone/fork"), "none")
            self.assertEqual(self.mode(event, IMAGE_INPUTS, ref="refs/heads/test"), "none")

    def test_full_version_format(self):
        self.assertEqual(validate_version("1.0.3"), "1.0.3")
        for version in ("latest", "1.0", "01.0.3", "1.0.3\npublication=release", "１.0.3"):
            with self.assertRaises(ValueError):
                validate_version(version)


if __name__ == "__main__":
    unittest.main()
