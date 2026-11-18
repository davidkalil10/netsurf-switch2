#!/usr/bin/env python3
"""Verify that a NetSurf Switch 2 NRO binary and linker map target Nintendo Switch 2 (libounce + OunceVK)."""

from __future__ import annotations

import argparse
from pathlib import Path
import struct
import sys


NRO_MAGIC = b"NRO0"
ASSET_MAGIC = b"ASET"
MOD0_MAGIC = b"MOD0"
OUNCE_MAGIC = b"OUN0"

FORBIDDEN_MAP_MARKERS = (
    "/libnx/lib/",
    "/portlibs/switch/lib/libEGL.a",
    "libglapi.a",
    "libdrm_nouveau.a",
    "libdeko3d",
    "hwcontext_nvtegra.o",
)

REQUIRED_MAP_MARKERS = (
    "/libounce/lib/",
    "/portlibs/switch2/lib/libEGL.a",
)


def verify_nro_bytes(data: bytes) -> list[str]:
    errors: list[str] = []
    if len(data) < 0x80:
        return ["NRO file is smaller than the 0x80-byte NRO header"]

    mod0_offset = struct.unpack_from("<I", data, 0x04)[0]
    magic = data[0x10:0x14]
    if magic != NRO_MAGIC:
        errors.append(f"Invalid NRO magic at 0x10: {magic!r} (expected {NRO_MAGIC!r})")
        return errors

    if mod0_offset + 0x1C > len(data):
        errors.append(f"MOD0 offset 0x{mod0_offset:x} is outside the NRO image")
    else:
        mod0_magic = data[mod0_offset : mod0_offset + 4]
        if mod0_magic != MOD0_MAGIC:
            errors.append(f"Invalid MOD0 magic at 0x{mod0_offset:x}: {mod0_magic!r}")
        ounce_window = data[mod0_offset : min(len(data), mod0_offset + 0x80)]
        oun0_idx = ounce_window.find(OUNCE_MAGIC)
        if oun0_idx < 0:
            errors.append("Missing OUN0 Switch 2 ABI marker in MOD0 startup header")
        else:
            oun0_pos = mod0_offset + oun0_idx
            if oun0_pos + 12 <= len(data):
                _, platform, version = struct.unpack_from("<4sII", data, oun0_pos)
                if platform != 2 or version != 1:
                    errors.append(
                        f"Unexpected OUN0 header values: platform={platform}, version={version} (expected 2, 1)"
                    )

    nro_size = struct.unpack_from("<I", data, 0x18)[0]
    if nro_size <= 0 or nro_size > len(data):
        errors.append(f"Invalid NRO size field: {nro_size} (total file size {len(data)})")
        return errors

    if len(data) < nro_size + 0x38:
        errors.append("NRO does not contain an appended ASET section (icon + NACP + RomFS)")
        return errors

    aset_header = data[nro_size : nro_size + 0x38]
    if aset_header[:4] != ASSET_MAGIC:
        errors.append(f"Invalid ASET magic at 0x{nro_size:x}: {aset_header[:4]!r}")
        return errors

    icon_off, icon_size, nacp_off, nacp_size, romfs_off, romfs_size = struct.unpack_from(
        "<QQQQQQ", aset_header, 8
    )
    if icon_size == 0 or nro_size + icon_off + icon_size > len(data):
        errors.append("Missing or truncated NRO icon in ASET section")
    if nacp_size < 0x4000 or nro_size + nacp_off + nacp_size > len(data):
        errors.append("Missing or truncated NACP metadata in ASET section")
    if romfs_size == 0 or nro_size + romfs_off + romfs_size > len(data):
        errors.append("Missing or truncated RomFS in ASET section")

    return errors


def verify_link_map_text(map_text: str) -> list[str]:
    errors: list[str] = []
    normalized = map_text.replace("\\", "/")

    for marker in REQUIRED_MAP_MARKERS:
        if marker not in normalized:
            errors.append(f"Linker map is missing required Switch 2 library marker: {marker}")

    for marker in FORBIDDEN_MAP_MARKERS:
        if marker in normalized:
            errors.append(f"Linker map contains forbidden Switch 1 library marker: {marker}")

    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("nro_path", type=Path, help="Path to netsurf-switch2.nro")
    parser.add_argument("--link-map", type=Path, default=None, help="Path to linker .map file")
    args = parser.parse_args(argv)

    errors: list[str] = []
    if not args.nro_path.is_file():
        errors.append(f"NRO file not found: {args.nro_path}")
    else:
        errors.extend(verify_nro_bytes(args.nro_path.read_bytes()))

    if args.link_map is not None:
        if not args.link_map.is_file():
            errors.append(f"Linker map not found: {args.link_map}")
        else:
            errors.extend(verify_link_map_text(args.link_map.read_text(encoding="utf-8", errors="replace")))

    if errors:
        for err in errors:
            print(f"[FAIL] {err}", file=sys.stderr)
        return 1

    print(f"[OK] Verified Switch 2 NRO package: {args.nro_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
