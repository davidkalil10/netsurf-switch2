#!/usr/bin/env python3
"""Unit tests for tools/verify_switch2_package.py."""

from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import verify_switch2_package as vsp  # noqa: E402


def _make_synthetic_switch2_nro(include_oun0: bool = True, include_romfs: bool = True) -> bytes:
    nro_size = 0x200
    buf = bytearray(nro_size)
    mod0_offset = 0x80
    struct.pack_into("<I", buf, 0x04, mod0_offset)
    buf[0x10:0x14] = b"NRO0"
    struct.pack_into("<I", buf, 0x18, nro_size)
    buf[mod0_offset : mod0_offset + 4] = b"MOD0"
    if include_oun0:
        struct.pack_into("<4sII", buf, mod0_offset + 0x1C, b"OUN0", 2, 1)

    icon = b"\xff\xd8\xff\xe0" + b"\x00" * 60
    nacp = b"NetSurf (Switch 2)".ljust(0x4000, b"\x00")
    romfs = b"ROMFS_RES" if include_romfs else b""

    icon_off = 0x38
    nacp_off = icon_off + len(icon)
    romfs_off = nacp_off + len(nacp)
    aset = bytearray(0x38)
    aset[:4] = b"ASET"
    struct.pack_into(
        "<IQQQQQQ",
        aset,
        4,
        0,
        icon_off,
        len(icon),
        nacp_off,
        len(nacp),
        romfs_off,
        len(romfs),
    )
    return bytes(buf + aset + icon + nacp + romfs)


class VerifySwitch2PackageTests(unittest.TestCase):
    def test_valid_switch2_nro_passes(self) -> None:
        data = _make_synthetic_switch2_nro()
        self.assertEqual(vsp.verify_nro_bytes(data), [])

    def test_missing_oun0_marker_fails(self) -> None:
        data = _make_synthetic_switch2_nro(include_oun0=False)
        errors = vsp.verify_nro_bytes(data)
        self.assertTrue(any("OUN0" in e for e in errors), errors)

    def test_missing_romfs_fails(self) -> None:
        data = _make_synthetic_switch2_nro(include_romfs=False)
        errors = vsp.verify_nro_bytes(data)
        self.assertTrue(any("RomFS" in e for e in errors), errors)

    def test_clean_link_map_passes(self) -> None:
        map_text = (
            "/opt/devkitpro/libounce/lib/libnx.a(applet.o)\n"
            "/opt/devkitpro/portlibs/switch2/lib/libEGL.a(egl_api.c.o)\n"
            "/src/build-switch2/ffmpeg-install/lib/libavcodec.a(avpacket.o)\n"
        )
        self.assertEqual(vsp.verify_link_map_text(map_text), [])

    def test_switch1_contamination_in_link_map_fails(self) -> None:
        map_text = (
            "/opt/devkitpro/libounce/lib/libnx.a(applet.o)\n"
            "/opt/devkitpro/portlibs/switch2/lib/libEGL.a(egl_api.c.o)\n"
            "/opt/devkitpro/libnx/lib/libnx.a(applet.o)\n"
            "/opt/devkitpro/portlibs/switch/lib/libavutil.a(hwcontext_nvtegra.o)\n"
        )
        errors = vsp.verify_link_map_text(map_text)
        self.assertEqual(len(errors), 2)


if __name__ == "__main__":
    unittest.main()
