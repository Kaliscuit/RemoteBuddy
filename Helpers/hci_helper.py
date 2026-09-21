#!/usr/bin/env python3
"""Root capture service. No commands from clients; only one allowed user's socket.

The Apple-signed PacketLogger writes binary records into a private FIFO. Raw
traffic stays in memory. Only the configured remote's HID notifications leave
this process. This does not change Apple's HID logging/privacy flags.
"""
import argparse
import ctypes
import json
import os
import pathlib
import selectors
import signal
import socket
import stat
import struct
import subprocess
import tempfile
import time


class Frames:
    def __init__(self):
        self.buffer = bytearray()
        self.endian = None

    def feed(self, data):
        self.buffer.extend(data)
        if len(self.buffer) > 1024 * 1024:
            raise ValueError("capture input overflow")
        while len(self.buffer) >= 12:
            if self.endian is None:
                candidates = [e for e in (">", "<") if
                              8 <= struct.unpack_from(e + "III", self.buffer)[0] < 65536 and
                              struct.unpack_from(e + "III", self.buffer)[2] < 1_000_000]
                if len(candidates) != 1:
                    raise ValueError("invalid capture framing")
                self.endian = candidates[0]
            size, seconds, micros = struct.unpack_from(self.endian + "III", self.buffer)
            if not 8 <= size < 65536 or micros >= 1_000_000:
                raise ValueError("invalid capture record")
            if len(self.buffer) < size + 4:
                return
            body = bytes(self.buffer[12:size + 4])
            del self.buffer[:size + 4]
            if body:
                yield seconds + micros / 1_000_000, body[0], body[1:]


class RemoteReports:
    def __init__(self, address, attribute):
        self.address = bytes.fromhex(address.replace(":", ""))[::-1]
        self.attribute = attribute
        self.connections = set()
        self.fragments = {}

    def accept(self, kind, data):
        if kind == 0xfd and len(data) >= 4 and data[0] == 1:
            connection = struct.unpack_from("<H", data, 1)[0]
            offset = 4 + data[3]
            if len(data) >= offset + 6:
                if data[offset:offset + 6] == self.address:
                    self.connections.add(connection)
                else:
                    self.connections.discard(connection)
            return None
        if kind == 1:
            if len(data) >= 14 and data[0] == 0x3e and data[2] in (1, 0x0a) and data[3] == 0:
                connection = struct.unpack_from("<H", data, 4)[0]
                if data[8:14] == self.address:
                    self.connections.add(connection)
                else:
                    self.connections.discard(connection)
            elif len(data) >= 6 and data[0] == 5:
                connection = struct.unpack_from("<H", data, 3)[0]
                known = connection in self.connections
                self.connections.discard(connection)
                self.fragments.pop(connection, None)
                if known:
                    return []
            return None
        if kind != 3 or len(data) < 4:
            return None
        flags, length = struct.unpack_from("<HH", data)
        connection = flags & 0xfff
        if connection not in self.connections or length != len(data) - 4:
            return None
        if (flags >> 12) & 3 == 1:
            if connection not in self.fragments:
                return None
            self.fragments[connection].extend(data[4:])
        else:
            self.fragments[connection] = bytearray(data[4:])
        packet = self.fragments[connection]
        if len(packet) < 4:
            return None
        size, cid = struct.unpack_from("<HH", packet)
        if len(packet) < size + 4:
            return None
        del self.fragments[connection]
        if len(packet) != size + 4 or cid != 4:
            return None
        att = packet[4:]
        if len(att) < 3 or att[0] not in (0x1b, 0x1d) or struct.unpack_from("<H", att, 1)[0] != self.attribute:
            return None
        payload = list(att[3:])
        return payload if 1 <= len(payload) <= 2 and all(value <= 17 for value in payload) else None


class Capture:
    def __init__(self, tool):
        self.directory = tempfile.TemporaryDirectory(prefix="remotemic-hci-", dir="/private/var/run")
        self.path = pathlib.Path(self.directory.name) / "stream.pklg"
        os.mkfifo(self.path, 0o600)
        self.fd = os.open(self.path, os.O_RDWR | os.O_NONBLOCK)
        self.frames = Frames()
        self.count = 0
        try:
            self.process = subprocess.Popen([tool, "convert", "--output", str(self.path)],
                                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL, close_fds=True)
        except Exception:
            os.close(self.fd)
            self.directory.cleanup()
            raise

    def read(self):
        if not stat.S_ISFIFO(self.path.stat().st_mode):
            raise RuntimeError("PacketLogger did not preserve the private FIFO")
        data = os.read(self.fd, 65536)
        for timestamp, kind, body in self.frames.feed(data):
            self.count += 1
            # PacketLogger mixes cached metadata timestamps and live controller
            # timestamps. Do not calibrate all reports from the first record.
            # This FIFO is live-only (no --bufferedPackets); IPC messages carry
            # a fresh Unix receive timestamp, which the app uses for expiry.
            yield timestamp, kind, body

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        os.close(self.fd)
        self.directory.cleanup()


def peer_uid(connection):
    library = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    uid, gid = ctypes.c_uint32(), ctypes.c_uint32()
    if library.getpeereid(connection.fileno(), ctypes.byref(uid), ctypes.byref(gid)) != 0:
        raise OSError(ctypes.get_errno(), "getpeereid")
    return uid.value


def session(connection, config):
    capture = Capture(config["packetlogger"])
    decoder = RemoteReports(config["address"], config["attribute"])
    selector = selectors.DefaultSelector()
    selector.register(connection, selectors.EVENT_READ, "client")
    selector.register(capture.fd, selectors.EVENT_READ, "capture")
    connection.settimeout(1)
    last_heartbeat = 0
    started = time.monotonic()
    reports_seen = 0

    def send(kind, **fields):
        message = {"type": kind, "address": config["address"], "received_at": time.time(), **fields}
        connection.sendall(json.dumps(message, separators=(",", ":")).encode() + b"\n")

    try:
        send("connected")
        while True:
            for key, _ in selector.select(timeout=0.5):
                if key.data == "client":
                    # EOF closes capture; any client command is rejected.
                    connection.recv(256)
                    return
                for timestamp, kind, body in capture.read():
                    payload = decoder.accept(kind, body)
                    if payload is None:
                        continue
                    reports_seen += 1
                    send("report", bytes=payload or [0])
            now = time.monotonic()
            if now - last_heartbeat >= 1:
                send("heartbeat", ready=capture.count > 0, remote_connected=bool(decoder.connections), reports_seen=reports_seen)
                last_heartbeat = now
            if capture.process.poll() is not None:
                raise RuntimeError("capture process exited")
            if capture.count == 0 and now - started > 15:
                raise RuntimeError("no HCI data; check capture configuration")
    finally:
        selector.close()
        capture.close()


def self_test(tool, address, attribute):
    capture = Capture(tool)
    decoder = RemoteReports(address, attribute)
    selector = selectors.DefaultSelector()
    selector.register(capture.fd, selectors.EVENT_READ)
    deadline = time.monotonic() + 8
    try:
        while time.monotonic() < deadline:
            for _, _ in selector.select(timeout=0.25):
                for timestamp, kind, body in capture.read():
                    decoder.accept(kind, body)
        print(json.dumps({"records": capture.count, "remote_identified": bool(decoder.connections),
                          "fifo": stat.S_ISFIFO(capture.path.stat().st_mode)}))
    finally:
        selector.close()
        capture.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="/Library/Application Support/RemoteMic/hci-config.json")
    parser.add_argument("--self-test-stream")
    parser.add_argument("--address")
    parser.add_argument("--attribute", type=lambda v: int(v, 0), default=0x46)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Administrator privileges are required")
    def terminate(*_):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, terminate)
    if args.self_test_stream:
        if not args.address:
            parser.error("--self-test-stream requires --address")
        self_test(args.self_test_stream, args.address, args.attribute)
        return
    config_path = pathlib.Path(args.config)
    info = config_path.stat()
    if info.st_uid != 0 or info.st_mode & 0o022:
        raise SystemExit("Helper configuration must be root-owned and not writable by other users")
    config = json.loads(config_path.read_text())
    path = config["socket"]
    if os.path.lexists(path):
        if not stat.S_ISSOCK(os.lstat(path).st_mode):
            raise SystemExit("Unexpected existing socket path")
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    os.umask(0o077)
    server.bind(path)
    os.chown(path, config["uid"], config["gid"])
    os.chmod(path, 0o600)
    server.listen(2)
    print("RemoteMic HCI helper ready", flush=True)
    try:
        while True:
            connection, _ = server.accept()
            try:
                if peer_uid(connection) == config["uid"]:
                    session(connection, config)
            except (OSError, RuntimeError, ValueError) as error:
                print(f"Session ended: {error}", flush=True)
                time.sleep(1)
            finally:
                connection.close()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()
        os.unlink(path)


if __name__ == "__main__":
    main()
