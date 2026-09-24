import importlib.util
import json
import os
import pathlib
import socket
import stat
import tempfile
import threading
import types
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("helper", ROOT / "Helpers/hci_helper.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RemoteConfigurationTests(unittest.TestCase):
    def request(self, **changes):
        return {"type": "configure", "address": "aa:bb:cc:dd:ee:ff", "attribute": 43,
                "report_format": "consumer16", "auto_detect": True,
                "peripheral_id": "11111111-2222-3333-4444-555555555555", **changes}

    def config(self):
        return dict(uid=501, gid=20, address="11:22:33:44:55:66", attribute=70,
                    report_format="indexed", socket="/var/run/test.sock", packetlogger="/fixed/tool",
                    peripheral_id="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")

    def test_selection_is_canonical_and_cannot_change_privileged_fields(self):
        result = helper.remote_selection(self.request())
        self.assertEqual(result["address"], "AA:BB:CC:DD:EE:FF")
        self.assertNotIn("type", result)
        for changes in [{"uid": 0}, {"gid": 0}, {"socket": "/tmp/other"}, {"packetlogger": "/tmp/command"},
                        {"path": "/tmp/config"}, {"type": "execute"}, {"attribute": True}, {"attribute": 0},
                        {"attribute": 65536}, {"attribute": "43"}, {"address": "AA:BB:CC:DD:EE:FF\n"},
                        {"address": "$(command)"}, {"report_format": "other"}, {"auto_detect": 1},
                        {"peripheral_id": "bad"}, {"peripheral_id": 7}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                helper.remote_selection(self.request(**changes))
        for request in [[], None, {}, "configure"]:
            with self.assertRaises(ValueError):
                helper.remote_selection(request)

    def test_atomic_save_preserves_service_fields_and_clears_old_voice_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "config.json"
            original = self.config()
            path.write_text(json.dumps(original))
            selection = helper.remote_selection(self.request(peripheral_id=None))
            with mock.patch.object(helper, "read_configuration", return_value=original):
                updated = helper.save_selection(path, original, selection)
            self.assertEqual(json.loads(path.read_text()), updated)
            for field in ["uid", "gid", "socket", "packetlogger"]:
                self.assertEqual(updated[field], original[field])
            self.assertNotIn("peripheral_id", updated)
            self.assertEqual(updated["attribute"], 43)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_failed_or_stale_save_leaves_original_configuration_intact(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "config.json"
            original = self.config()
            wire = json.dumps(original)
            path.write_text(wire)
            selection = helper.remote_selection(self.request())
            with mock.patch.object(helper, "read_configuration", return_value=original), \
                    mock.patch.object(helper.os, "replace", side_effect=OSError("failed")):
                with self.assertRaises(OSError):
                    helper.save_selection(path, original, selection)
            self.assertEqual(path.read_text(), wire)
            self.assertEqual(list(path.parent.iterdir()), [path])
            with mock.patch.object(helper, "read_configuration", return_value={**original, "attribute": 99}):
                with self.assertRaises(ValueError):
                    helper.save_selection(path, original, selection)
            self.assertEqual(path.read_text(), wire)

    def test_config_rejects_links_non_root_owner_and_group_writable_files(self):
        for mode, owner in [(stat.S_IFLNK | 0o777, 0), (stat.S_IFREG | 0o644, 501),
                            (stat.S_IFREG | 0o664, 0), (stat.S_IFDIR | 0o755, 0)]:
            path = mock.Mock()
            path.lstat.return_value = types.SimpleNamespace(st_mode=mode, st_uid=owner)
            with self.assertRaises(ValueError):
                helper.read_configuration(path)
            path.read_text.assert_not_called()

    def test_socket_protocol_applies_one_selection_and_closes_capture(self):
        class Capture:
            def __init__(self, tool):
                self.fd, self.writer = os.pipe()
                self.count = 1
                self.process = types.SimpleNamespace(poll=lambda: None)

            def close(self):
                os.close(self.fd)
                os.close(self.writer)

        for wire, expected_type in [
            (json.dumps(self.request()).encode() + b"\n", "configured"),
            (json.dumps(self.request(uid=0)).encode() + b"\n", "configuration_error"),
            (b"x" * 4097, "configuration_error"),
            (b'{}\n{}\n', "configuration_error"),
        ]:
            with self.subTest(expected=expected_type), tempfile.TemporaryDirectory() as directory:
                path = pathlib.Path(directory) / "config.json"
                original = self.config()
                path.write_text(json.dumps(original))
                server, client = socket.socketpair()
                client.settimeout(3)
                failures = []

                def run():
                    try:
                        helper.session(server, original, path)
                    except Exception as error:
                        failures.append(error)
                    finally:
                        server.close()

                with mock.patch.object(helper, "Capture", Capture), \
                        mock.patch.object(helper, "read_configuration", side_effect=lambda p: json.loads(p.read_text())):
                    thread = threading.Thread(target=run, daemon=True)
                    thread.start()
                    stream = client.makefile("rb")
                    self.assertEqual(json.loads(stream.readline())["protocol_version"], 2)
                    client.sendall(wire)
                    messages = [json.loads(line) for line in stream]
                    thread.join(timeout=3)
                    stream.close()
                    client.close()
                self.assertFalse(thread.is_alive())
                self.assertEqual(failures, [])
                self.assertEqual(messages[-1]["type"], expected_type)
                updated = json.loads(path.read_text())
                self.assertEqual(updated["address"], "AA:BB:CC:DD:EE:FF" if expected_type == "configured" else original["address"])
                self.assertEqual(updated["uid"], 501)


if __name__ == "__main__":
    unittest.main()
