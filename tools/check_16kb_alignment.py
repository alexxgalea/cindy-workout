#!/usr/bin/env python3
"""
Checks that every native library in an APK or App Bundle loads on a 16 KB page-size device.

Google Play refuses app updates whose 64-bit native code is not 16 KB aligned, and a 16 KB phone
refuses to load such a library at all: for this app that would be the pose model's runtime, and
the first sign would be "Pose model failed to load" on a stranger's phone. Nothing in the Gradle
build fails when an AAR brings in a 4 KB-aligned library, so this script is the check.

Two things must hold, and both are read straight from the bytes:
  * ELF: every PT_LOAD segment of a 64-bit library (arm64-v8a, x86_64) is aligned to >= 16 KB.
    32-bit libraries are reported but never fail; 16 KB pages are a 64-bit-only thing.
  * Zip (APK only): an uncompressed library starts at a 16 KB boundary inside the APK, so it can
    be mapped in place. In a bundle, Play does this when it builds the APKs.

Standard library only, so it runs on a CI runner with no Android SDK.

    python3 tools/check_16kb_alignment.py app/build/outputs/bundle/release/app-release.aab
"""

import struct
import sys
import zipfile

PAGE = 16 * 1024
SIXTY_FOUR_BIT = {"arm64-v8a", "x86_64"}
PT_LOAD = 1


def load_alignments(elf: bytes):
    """The p_align of every PT_LOAD segment, or None if this is not an ELF file."""
    if elf[:4] != b"\x7fELF":
        return None
    is64 = elf[4] == 2
    endian = "<" if elf[5] == 1 else ">"
    if is64:
        phoff = struct.unpack_from(endian + "Q", elf, 0x20)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", elf, 0x36)
    else:
        phoff = struct.unpack_from(endian + "I", elf, 0x1C)[0]
        phentsize, phnum = struct.unpack_from(endian + "HH", elf, 0x2A)
    aligns = []
    for i in range(phnum):
        at = phoff + i * phentsize
        if struct.unpack_from(endian + "I", elf, at)[0] != PT_LOAD:
            continue
        if is64:
            aligns.append(struct.unpack_from(endian + "Q", elf, at + 48)[0])
        else:
            aligns.append(struct.unpack_from(endian + "I", elf, at + 28)[0])
    return aligns


def data_offset(archive: zipfile.ZipFile, info: zipfile.ZipInfo) -> int:
    """Where an entry's bytes start: past its local header, whose extra field can differ."""
    archive.fp.seek(info.header_offset)
    header = archive.fp.read(30)
    name_len, extra_len = struct.unpack_from("<HH", header, 26)
    return info.header_offset + 30 + name_len + extra_len


def check(path: str) -> bool:
    ok = True
    is_apk = path.endswith(".apk")
    seen = 0
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            name = info.filename
            if not name.endswith(".so") or "/lib/" not in "/" + name:
                continue
            parts = name.split("/")
            abi = parts[-2]
            aligns = load_alignments(archive.read(name))
            if aligns is None:
                continue
            seen += 1
            smallest = min(aligns) if aligns else 0
            problems = []
            if abi in SIXTY_FOUR_BIT and smallest < PAGE:
                problems.append(f"LOAD aligned to {smallest // 1024} KB")
            if is_apk and info.compress_type == zipfile.ZIP_STORED:
                offset = data_offset(archive, info)
                if abi in SIXTY_FOUR_BIT and offset % PAGE:
                    problems.append(f"stored at offset {offset}, not a 16 KB boundary")
            if problems:
                ok = False
                print(f"FAIL  {name}: " + "; ".join(problems))
            else:
                note = "" if abi in SIXTY_FOUR_BIT else "  (32-bit, not required)"
                print(f"ok    {name}: LOAD aligned to {smallest // 1024} KB{note}")
    if seen == 0:
        print(f"{path}: no native libraries found")
    return ok


def main(argv) -> int:
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[-1].strip())
        return 2
    results = [check(p) for p in argv[1:]]
    if all(results):
        print("16 KB page size: every 64-bit native library is aligned")
        return 0
    print("16 KB page size: FAILED, see above")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
