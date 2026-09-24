import importlib.util
import json
import pathlib
import plistlib
import unittest
import hashlib
import shlex
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("configure", ROOT / "Installer/configure.py")
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)


class ConfigurationTests(unittest.TestCase):
    def test_different_accounts_and_remote_addresses_round_trip(self):
        for uid, home, address in [(501, "/Users/demo", "aa:bb:cc:dd:ee:ff"),
                                   (1007, "/Users/test & space", "11:22:33:44:55:66")]:
            config, daemon, agent = configure.documents(uid, 20, home, address)
            self.assertEqual(json.loads(json.dumps(config))["uid"], uid)
            self.assertEqual(config["address"], address.upper())
            decoded = plistlib.loads(plistlib.dumps(agent))
            self.assertEqual(decoded["ProgramArguments"], [home + "/Applications/RemoteBuddy.app/Contents/MacOS/RemoteBuddy"])
            self.assertNotIn("/usr/bin/python3", daemon["ProgramArguments"])
            self.assertIn("-I", daemon["ProgramArguments"])
            self.assertIn("-S", daemon["ProgramArguments"])
            self.assertEqual(config["attribute"], 0x46)

    def test_rejects_root_invalid_address_and_out_of_range_handles(self):
        for uid, home, address, attribute in [(0, "/var/root", "AA:BB:CC:DD:EE:FF", 0x46),
                (501, "relative", "AA:BB:CC:DD:EE:FF", 0x46),
                (501, "/Users/demo", "AA:BB:CC:DD:EE:FF\n", 0x46),
                (501, "/Users/demo", "arbitrary text", 0x46),
                (501, "/Users/demo", "AA:BB:CC:DD:EE:FF", 0),
                (501, "/Users/demo", "AA:BB:CC:DD:EE:FF", 65536)]:
            with self.assertRaises(ValueError):
                configure.documents(uid, 20, home, address, attribute)

    def test_consumer_remote_configuration_and_unknown_format(self):
        config, _, _ = configure.documents(501, 20, "/Users/demo", "AA:BB:CC:DD:EE:FF", 0x2b, "consumer16")
        self.assertEqual(config["attribute"], 0x2b)
        self.assertEqual(config["report_format"], "consumer16")
        with self.assertRaises(ValueError):
            configure.documents(501, 20, "/Users/demo", "AA:BB:CC:DD:EE:FF", 0x2b, "unknown")

    def test_dependency_verification_fails_even_when_later_files_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = pathlib.Path(temporary)
            (base / "Installer").mkdir()
            (base / "Dependencies").mkdir()
            (base / "Dependencies/last.pkg").write_bytes(b"good")
            digest = hashlib.sha256(b"good").hexdigest()
            (base / "Installer/dependencies.tsv").write_text(
                f"missing.pkg\t{digest}\thttps://example.invalid/first\n"
                f"last.pkg\t{digest}\thttps://example.invalid/last\n")
            script = "RB_ROOT=" + shlex.quote(str(base)) + "\nsource " + shlex.quote(str(ROOT / "Installer/common.sh"))
            script += "\nif rb_verify_dependencies; then exit 0; else exit 1; fi\n"
            result = subprocess.run(["/bin/zsh"], input=script, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Missing regular file", result.stderr)

    def test_manifest_only_contains_pinned_https_artifacts(self):
        rows = [line.split("\t") for line in (ROOT / "Installer/dependencies.tsv").read_text().splitlines() if not line.startswith("#")]
        self.assertEqual(len(rows), 4)
        for filename, checksum, url in rows:
            self.assertEqual(pathlib.Path(filename).name, filename)
            self.assertRegex(checksum, r"^[a-f0-9]{64}$")
            self.assertTrue(url.startswith("https://"))
            self.assertNotIn("PacketLogger", filename)


if __name__ == "__main__":
    unittest.main()
