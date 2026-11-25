#!/usr/bin/env python3
"""Package the official standalone ESP flasher with a desktop Meshgram build."""

import hashlib
import os
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

VERSION = "v5.7.0"
DIGESTS = {
    "linux-aarch64": "fdfca2b662987d76c0c22acee8ef0f07cb57e2e3a54d374cf17409bc14778e07",
    "linux-amd64": "f35ac7ab299b1fcdcf2a583ef447705dcc2409c48ecf34178bb30587253b042b",
    "macos-amd64": "a4774eb68d458e8159e3035fd0c4a18542b7fca5bd06482cf258b33f587a77a9",
    "macos-arm64": "91ed98320f1f591ba9c2895bf3b85bdda1a64542447fc314547dbd67cd43623c",
    "windows-amd64": "c97911246149141eab535b3a6dd5367cd3c16ba17098bce27ac6af780708c9e9",
}
CACHE = Path(__file__).resolve().parents[1] / "build" / "esptool-cache"


def matches(path, digest):
    if not path.is_file():
        return False
    with path.open("rb") as source:
        checksum = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest() == digest


def archive_for(platform):
    zipped = platform.startswith("windows")
    extension = "zip" if zipped else "tar.gz"
    filename = f"esptool-{VERSION}-{platform}.{extension}"
    destination = CACHE / filename
    expected = DIGESTS[platform]
    if not matches(destination, expected):
        url = f"https://github.com/espressif/esptool/releases/download/{VERSION}/{filename}"
        CACHE.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=CACHE) as temporary:
            pending = Path(temporary) / filename
            request = urllib.request.Request(url, headers={"User-Agent": "Meshgram build"})
            with urllib.request.urlopen(request, timeout=45) as response, pending.open("wb") as output:
                shutil.copyfileobj(response, output)
            if not matches(pending, expected):
                raise ValueError(f"Invalid SHA-256 for {filename}")
            os.replace(pending, destination)
    return destination


def copy_member(archive, member, destination):
    try:
        source = archive.open(member) if isinstance(archive, zipfile.ZipFile) else archive.extractfile(member)
    except KeyError:
        # Some Espressif Windows archives have no directory prefix.
        basename = member.rsplit("/", 1)[-1]
        source = archive.open(basename)
    if source is None:
        raise ValueError(f"Missing file: {member}")
    with source, destination.open("wb") as output:
        shutil.copyfileobj(source, output)


def install(destination, platform):
    package = archive_for(platform)
    output = destination / platform
    output.mkdir(parents=True, exist_ok=True)
    zipped = platform.startswith("windows")
    name = "esptool.exe" if zipped else "esptool"
    with tempfile.TemporaryDirectory(dir=output) as temporary:
        staging = Path(temporary)
        with (zipfile.ZipFile(package) if zipped else tarfile.open(package)) as archive:
            for member in (name, "LICENSE"):
                copy_member(archive, f"esptool-{platform}/{member}", staging / member)
        (staging / name).chmod(0o755)
        for member in (name, "LICENSE"):
            os.replace(staging / member, output / member)


if __name__ == "__main__":
    for build_platform in sys.argv[2:]:
        install(Path(sys.argv[1]), build_platform)
