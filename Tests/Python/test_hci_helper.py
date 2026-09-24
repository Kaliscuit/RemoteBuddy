import importlib.util
import pathlib
import struct
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("helper", ROOT / "Helpers/hci_helper.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


def configuration(address="aabbccddeeff", connection=0x4c):
    name = b"Chromecast Remote"
    return b"\x01" + struct.pack("<H", connection) + bytes([len(name)]) + name + bytes.fromhex(address)[::-1]


def notification(payload, connection=0x4c, attribute=0x46):
    att = b"\x1b" + struct.pack("<H", attribute) + bytes(payload)
    l2cap = struct.pack("<HH", len(att), 4) + att
    return struct.pack("<HH", connection | 0x2000, len(l2cap)) + l2cap


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.decoder = helper.RemoteReports("AA:BB:CC:DD:EE:FF", 0x46)

    def test_requires_remote_identity_before_forwarding(self):
        self.assertIsNone(self.decoder.accept(3, notification([3])))
        self.decoder.accept(0xfd, configuration(address="112233445566"))
        self.assertIsNone(self.decoder.accept(3, notification([3])))
        self.decoder.accept(0xfd, configuration())
        self.assertEqual(self.decoder.accept(3, notification([3])), [3])

    def test_real_single_and_dual_report_sequence(self):
        self.decoder.accept(0xfd, configuration())
        reports = [[3], [0], [4], [0], [5], [0], [6], [0], [7], [0], [3], [0], [5], [7, 5], [0], [0]]
        self.assertEqual([self.decoder.accept(3, notification(p)) for p in reports], reports)

    def test_unrelated_connection_attribute_and_bad_payload_are_rejected(self):
        self.decoder.accept(0xfd, configuration())
        for packet in (notification([3], connection=0x4d), notification([3], attribute=0x47),
                       notification([99]), notification([3, 4, 5]), notification([])):
            self.assertIsNone(self.decoder.accept(3, packet))

    def test_disconnect_releases_and_invalidates_reused_handle(self):
        self.decoder.accept(0xfd, configuration())
        self.assertEqual(self.decoder.accept(1, bytes.fromhex("0504004c0013")), [])
        self.assertIsNone(self.decoder.accept(3, notification([3])))

    def test_acl_fragments_reassemble_without_partial_key_output(self):
        self.decoder.accept(0xfd, configuration())
        full = notification([7, 5])[4:]
        first = struct.pack("<HH", 0x204c, 5) + full[:5]
        second = struct.pack("<HH", 0x104c, len(full) - 5) + full[5:]
        self.assertIsNone(self.decoder.accept(3, first))
        self.assertEqual(self.decoder.accept(3, second), [7, 5])

    def test_consumer_remote_preserves_existing_button_mapping_ids(self):
        decoder = helper.RemoteReports("AA:BB:CC:DD:EE:FF", 0x2b, "consumer16")
        decoder.accept(0xfd, configuration())
        # Up, down, left, right, select, back, home, volume +/-, mute,
        # YouTube, Netflix, power, input. Each press is followed by release.
        usages = [0x42, 0x43, 0x44, 0x45, 0x41, 0x224, 0x223,
                  0xe9, 0xea, 0xe2, 0x77, 0x78, 0x19e, 0x189]
        buttons = [3, 4, 5, 6, 7, 11, 10, 12, 13, 8, 14, 15, 1, 17]
        for usage, button in zip(usages, buttons):
            report = notification(struct.pack("<H", usage), attribute=0x2b)
            self.assertEqual(decoder.accept(3, report), [button])
            self.assertEqual(decoder.accept(3, notification([0, 0], attribute=0x2b)), [0])

    def test_consumer_reports_still_require_matching_identity_attribute_and_format(self):
        decoder = helper.RemoteReports("AA:BB:CC:DD:EE:FF", 0x2b, "consumer16")
        self.assertIsNone(decoder.accept(3, notification([0x42, 0], attribute=0x2b)))
        decoder.accept(0xfd, configuration())
        for packet in (notification([0x42, 0]),
                       notification([0x42, 0], connection=0x4d, attribute=0x2b),
                       notification([0x42], attribute=0x2b),
                       notification([0x42, 0, 0], attribute=0x2b),
                       notification([0xff, 0xff], attribute=0x2b)):
            self.assertIsNone(decoder.accept(3, packet))
        # The original format must not mistake a Consumer usage for two keys.
        self.decoder.accept(0xfd, configuration())
        self.assertIsNone(self.decoder.accept(3, notification([0x42, 0])))
        with self.assertRaises(ValueError):
            helper.RemoteReports("AA:BB:CC:DD:EE:FF", 0x2b, "unknown")

    def test_streaming_frames_across_arbitrary_reads(self):
        expected = [(0xfd, configuration()), (3, notification([3])), (3, notification([0]))]
        for endian in (">", "<"):
            wire = b"".join(struct.pack(endian + "III", len(body) + 9, 1789950000, 123000)
                            + bytes([kind]) + body for kind, body in expected)
            frames = helper.Frames()
            received = []
            for byte in wire:
                received.extend(frames.feed(bytes([byte])))
            self.assertEqual([(kind, body) for _, kind, body in received], expected)


if __name__ == "__main__":
    unittest.main()
