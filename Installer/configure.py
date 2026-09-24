#!/usr/bin/env python3
"""Generate launchd/configuration files without writing to system locations.

Only install-system.sh installs these files. This module is also used in tests.
"""
import argparse
import json
import pathlib
import plistlib
import pwd
import re

LABEL = "local.codex.RemoteMic"
SERVICE = pathlib.Path("/Library/Application Support/RemoteMic")
PYTHON = "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3"


def address(value):
    if not re.fullmatch(r"[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5}", value):
        raise ValueError("Remote address must contain six colon-separated hexadecimal bytes")
    return value.upper()


def documents(uid, gid, home, remote, attribute=0x46, report_format="indexed"):
    if uid < 501 or gid < 0 or not str(home).startswith("/"):
        raise ValueError("Select a regular macOS user account with an absolute home directory")
    if not 1 <= attribute <= 0xFFFF:
        raise ValueError("ATT handle must be between 1 and 65535")
    if report_format not in ("indexed", "consumer16"):
        raise ValueError("Unsupported remote report format")
    config = dict(uid=uid, gid=gid, address=address(remote), attribute=attribute,
                  report_format=report_format,
                  socket=f"/var/run/{LABEL}.hci.sock", packetlogger=str(SERVICE / "PacketLogger.app/Contents/Resources/packetlogger"))
    daemon = dict(Label=LABEL + ".hci", ProgramArguments=[PYTHON, "-I", "-S", "-B", "-u", str(SERVICE / "hci_helper.py")],
                  RunAtLoad=True, KeepAlive=True, ThrottleInterval=5, ProcessType="Background",
                  WorkingDirectory=str(SERVICE), StandardOutPath="/var/log/RemoteBuddyHelper.log",
                  StandardErrorPath="/var/log/RemoteBuddyHelper.error.log")
    agent = dict(Label=LABEL, ProgramArguments=[str(pathlib.Path(home) / "Applications/RemoteBuddy.app/Contents/MacOS/RemoteBuddy")],
                 RunAtLoad=True, ProcessType="Interactive")
    return config, daemon, agent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", required=True)
    parser.add_argument("--address", required=True)
    parser.add_argument("--attribute", type=lambda value: int(value, 0), default=0x46)
    parser.add_argument("--report-format", choices=("indexed", "consumer16"), default="indexed")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    account = pwd.getpwnam(args.user)
    config, daemon, agent = documents(account.pw_uid, account.pw_gid, account.pw_dir, args.address, args.attribute, args.report_format)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "hci-config.json").write_text(json.dumps(config, indent=2) + "\n")
    (args.output / "daemon.plist").write_bytes(plistlib.dumps(daemon))
    (args.output / "agent.plist").write_bytes(plistlib.dumps(agent))


if __name__ == "__main__":
    main()
