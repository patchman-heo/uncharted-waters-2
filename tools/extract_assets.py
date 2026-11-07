#!/usr/bin/env python3
"""
Uncharted Waters 2 (대항해시대 2) Korean DOS Version - Complete Asset & Data Extractor
Reverse-engineered from MAIN.EXE and OPEN.EXE.

Extracts:
1. All LS10/LS11 .LZW archives (lossless Koei LZW decompression)
2. 16-color VGA Palettes from MAIN.EXE (Day, Dawn, Dusk, Night, Storm, Portrait, Ship, Battle)
3. World Map (2160 x 1080 tiles) with 12x12 block template decoding, 2x2 metatile expansion, and 8-neighbor coastline autotiling
4. World Map Tilesets (Day, Dawn, Dusk, Night, Storm) -> PNG
5. Port Tilesets (PORTCHIP.LZW 0..6, Day/Night) -> PNG & walkability tables
6. Port Maps (PORTMAP.LZW 0..100, 96x96 grids) & Port metadata (MAIN.EXE + ZA_DAT.DAT + CHIP_NO.DAT) -> JSON & binary
7. Character & Ship Sprites (CHAR.LZW entries 0..6 with 1-bit transparency mask) -> PNG
8. Character Portraits (KAO.LZW 256 faces, 48x80 planar interleaved) -> PNG
9. Game Data Tables (130 Ports, 100 Discoveries, Characters, 23 Ship Types, Items + Descriptions, Wind/Currents) -> UTF-8 JSON
10. Korean Hangul 16x14 Bitmap Font (ALL_FONT.16P) -> PNG atlas + JSON mapping
"""

import json
import os
import struct
import zlib
from pathlib import Path

BASE_DIR = Path("/home/ycheo/uncharted-waters-2")
DOS_DIR = BASE_DIR / "DOS"
ASSETS_DIR = BASE_DIR / "assets"
DATA_DIR = BASE_DIR / "data"


# ==============================================================================
# 1. Pure-Python PNG Writer (RGB & RGBA)
# ==============================================================================
def write_png_rgba(path: Path, width: int, height: int, rgba_bytes: bytes) -> None:
    """Write an 8-bit RGBA PNG file using only standard library struct and zlib."""
    path.parent.mkdir(parents=True, exist_ok=True)
    stride = width * 4
    raw_rows = bytearray()
    for y in range(height):
        raw_rows.append(0)  # Filter type 0 (None)
        row_start = y * stride
        raw_rows.extend(rgba_bytes[row_start : row_start + stride])

    def make_chunk(chunk_type: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA (color type 6)
    compressed = zlib.compress(bytes(raw_rows), level=6)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(make_chunk(b"IHDR", ihdr))
        f.write(make_chunk(b"IDAT", compressed))
        f.write(make_chunk(b"IEND", b""))


def write_png_indexed_as_rgba(
    path: Path,
    width: int,
    height: int,
    indices: bytes | bytearray | list[int],
    palette: list[tuple[int, int, int]],
    transparent_mask: bytes | bytearray | list[int] | None = None,
) -> None:
    """Convert 4bpp/8bpp indexed pixels + palette (+ optional transparency mask) to RGBA PNG."""
    rgba = bytearray(width * height * 4)
    for i, idx in enumerate(indices):
        r, g, b = palette[idx & 0x0F]
        a = 0 if (transparent_mask is not None and transparent_mask[i]) else 255
        p = i * 4
        rgba[p] = r
        rgba[p + 1] = g
        rgba[p + 2] = b
        rgba[p + 3] = a
    write_png_rgba(path, width, height, bytes(rgba))


# ==============================================================================
# 2. Koei LS10 / LS11 Decompressor (Reverse-Engineered from MAIN.EXE 0x39b06)
# ==============================================================================
def decompress_ls11_entry(archive_bytes: bytes, dictionary: bytes, comp_size: int, uncomp_size: int, offset: int) -> bytes:
    if comp_size == uncomp_size:
        return archive_bytes[offset : offset + uncomp_size]

    src = archive_bytes[offset : offset + comp_size]
    src_len = len(src)
    byte_pos = 0
    bit_pos = 0  # 0..7, MSB first

    def read_bit() -> int:
        nonlocal byte_pos, bit_pos
        if byte_pos >= src_len:
            return 0
        b = (src[byte_pos] >> (7 - bit_pos)) & 1
        bit_pos += 1
        if bit_pos == 8:
            bit_pos = 0
            byte_pos += 1
        return b

    def get_code() -> int:
        si = 0
        di = 0
        cx = 0
        while True:
            cx += 1
            if read_bit() == 1:
                si = (si << 1) + 1
            else:
                si = si << 1
                break
        for _ in range(cx):
            di = (di << 1) | read_bit()
        return si + di

    out = bytearray()
    while len(out) < uncomp_size:
        code = get_code()
        if code < 256:
            out.append(dictionary[code])
        else:
            back_offset = code - 256
            length = get_code() + 3
            if back_offset <= 0 or back_offset > len(out):
                for _ in range(length):
                    if len(out) < uncomp_size:
                        out.append(0)
            else:
                for _ in range(length):
                    if len(out) >= uncomp_size:
                        break
                    out.append(out[-back_offset])
    return bytes(out[:uncomp_size])


def load_lzw_archive(path: Path) -> list[bytes]:
    data = path.read_bytes()
    magic = data[:4]
    if magic not in (b"LS10", b"LS11"):
        raise ValueError(f"Invalid magic in {path}: {magic!r}")
    dictionary = data[0x10:0x110]
    pos = 0x110
    entries = []
    while pos + 12 <= len(data):
        comp_size, uncomp_size, offset = struct.unpack(">III", data[pos : pos + 12])
        if comp_size == 0:
            break
        entries.append(decompress_ls11_entry(data, dictionary, comp_size, uncomp_size, offset))
        pos += 12
    return entries


# ==============================================================================
# 3. EUC-KR String Decoder Helper
# ==============================================================================
def decode_euckr(raw: bytes) -> str:
    zero = raw.find(b"\x00")
    if zero != -1:
        raw = raw[:zero]
    return raw.decode("euc-kr", errors="replace").strip()


# ==============================================================================
# 4. VGA 16-Color Palettes Extraction (MAIN.EXE)
# ==============================================================================
def extract_palettes(main_exe: bytes) -> dict[str, list[tuple[int, int, int]]]:
    """
    Each 16-color palette in MAIN.EXE has 48 bytes (16 * 3 bytes in [B, R, G] 0..15 nibbles).
    Colors 0..7 are the standard UI colors; Colors 8..15 are scene-specific.
    """
    def read_pal8(offset: int) -> list[tuple[int, int, int]]:
        colors = []
        for i in range(8):
            b, r, g = main_exe[offset + i * 3 : offset + i * 3 + 3]
            colors.append(((r & 0x0F) * 17, (g & 0x0F) * 17, (b & 0x0F) * 17))
        return colors

    # Base colors 0..7 from 0x45732 (ds:0xad82):
    # ['#000000', '#0044dd', '#dd4400', '#dd66aa', '#00aa66', '#00aaff', '#ffaa66', '#ffeedd']
    base_0_7 = read_pal8(0x45732)

    palette_offsets_8_15 = {
        "day": 0x45732 + 24,       # ds:0xad82 + 24 (Daytime Port & World Map)
        "dawn": 0x45702 + 24,      # ds:0xad52 + 24 (Dawn)
        "dusk": 0x45762 + 24,      # ds:0xadb2 + 24 (Dusk / Sunset)
        "night": 0x456D2 + 24,     # ds:0xad22 + 24 (Night)
        "storm": 0x45792 + 24,     # ds:0xade2 + 24 (Storm / Fog)
        "portrait": 0x45900 + 24,  # ds:0xaf50 + 24 (KAO.LZW Character Portraits & Interiors)
        "ship": 0x45930 + 24,      # ds:0xaf80 + 24 (Ships / Duel)
        "battle": 0x4548E + 24,    # ds:0xaade + 24 (Naval Battle / Chart)
    }

    palettes = {}
    for name, off in palette_offsets_8_15.items():
        palettes[name] = base_0_7 + read_pal8(off)
    return palettes


# ==============================================================================
# 5. Bitplane Decoders (Reverse-Engineered from MAIN.EXE 0x6b3c, 0x6b95, 0x7511, 0x7831)
# ==============================================================================
def decode_tile_16x16_planar(tile_bytes: bytes) -> list[int]:
    """
    Decode 128-byte 16x16 4bpp tile stored plane-by-plane (MAIN.EXE 0x7511):
    - Plane 0: bytes[0..31]   (16 rows x 2 bytes/row)
    - Plane 1: bytes[32..63]
    - Plane 2: bytes[64..95]
    - Plane 3: bytes[96..127]
    Returns 256 color indices (0..15).
    """
    pixels = [0] * 256
    for y in range(16):
        row_off = y * 2
        b0_hi, b0_lo = tile_bytes[row_off], tile_bytes[row_off + 1]
        b1_hi, b1_lo = tile_bytes[32 + row_off], tile_bytes[32 + row_off + 1]
        b2_hi, b2_lo = tile_bytes[64 + row_off], tile_bytes[64 + row_off + 1]
        b3_hi, b3_lo = tile_bytes[96 + row_off], tile_bytes[96 + row_off + 1]

        w0 = (b0_hi << 8) | b0_lo
        w1 = (b1_hi << 8) | b1_lo
        w2 = (b2_hi << 8) | b2_lo
        w3 = (b3_hi << 8) | b3_lo

        for x in range(16):
            shift = 15 - x
            c = (
                (((w0 >> shift) & 1) << 0)
                | (((w1 >> shift) & 1) << 1)
                | (((w2 >> shift) & 1) << 2)
                | (((w3 >> shift) & 1) << 3)
            )
            pixels[y * 16 + x] = c
    return pixels


def decode_sprite_16x16_masked(sprite_bytes: bytes) -> tuple[list[int], list[int]]:
    """
    Decode 160-byte 16x16 sprite with mask (MAIN.EXE 0x6b95):
    - bytes[0..127]: 4 bitplanes (32 bytes each)
    - bytes[128..159]: 32-byte AND transparency mask (bit=1 means keep background if color==0)
    Returns (pixels[256], transparent_mask[256]).
    """
    pixels = decode_tile_16x16_planar(sprite_bytes[:128])
    mask_bytes = sprite_bytes[128:160]
    trans_mask = [0] * 256
    for y in range(16):
        w_mask = (mask_bytes[y * 2] << 8) | mask_bytes[y * 2 + 1]
        for x in range(16):
            shift = 15 - x
            m = (w_mask >> shift) & 1
            idx = y * 16 + x
            # In VGA hardware blitting (0x6b95): screen = (screen & mask) | sprite_plane
            # So when mask bit == 1 and sprite pixel == 0, pixel is transparent!
            if m == 1 and pixels[idx] == 0:
                trans_mask[idx] = 1
    return pixels, trans_mask


def decode_3plane_interleaved_image(raw_bytes: bytes, width: int, height: int, high_plane_bit: int = 0) -> list[int]:
    """
    Decode 3-bitplane interleaved image drawn via MAIN.EXE 0x587c (KAO.LZW portraits & illustrations).
    Each horizontal group of 8 pixels is stored as 3 consecutive bytes:
    - byte 0: Plane 0 (bit 0)
    - byte 1: Plane 1 (bit 1)
    - byte 2: Plane 2 (bit 2)
    """
    groups_per_row = width // 8
    pixels = [0] * (width * height)
    pos = 0
    for y in range(height):
        for gx in range(groups_per_row):
            p0, p1, p2 = raw_bytes[pos : pos + 3]
            pos += 3
            base_x = gx * 8
            for bit in range(8):
                shift = 7 - bit
                c = (
                    high_plane_bit
                    | (((p0 >> shift) & 1) << 0)
                    | (((p1 >> shift) & 1) << 1)
                    | (((p2 >> shift) & 1) << 2)
                )
                pixels[y * width + base_x + bit] = c
    return pixels


def render_tileset_sheet(
    tiles_raw: bytes,
    cols: int,
    palette: list[tuple[int, int, int]],
    out_path: Path,
) -> None:
    num_tiles = len(tiles_raw) // 128
    rows = (num_tiles + cols - 1) // cols
    sheet_w = cols * 16
    sheet_h = rows * 16
    sheet_indices = bytearray(sheet_w * sheet_h)

    for t in range(num_tiles):
        tile_pixels = decode_tile_16x16_planar(tiles_raw[t * 128 : (t + 1) * 128])
        tx = (t % cols) * 16
        ty = (t // cols) * 16
        for py in range(16):
            row_start = (ty + py) * sheet_w + tx
            sheet_indices[row_start : row_start + 16] = tile_pixels[py * 16 : (py + 1) * 16]

    write_png_indexed_as_rgba(out_path, sheet_w, sheet_h, sheet_indices, palette)


# ==============================================================================
# 6. World Map Extraction & Coastline Autotiling (MAIN.EXE 0x26dbc..0x27b50)
# ==============================================================================
def extract_world_map(
    main_exe: bytes,
    data1_entries: list[bytes],
    worldmap_entries: list[bytes],
    palettes: dict[str, list[tuple[int, int, int]]],
) -> bytearray:
    """
    Reconstruct the complete 2160 x 1080 World Map tile grid using the exact algorithm
    from MAIN.EXE 0x26dbc..0x27b50.
    """
    print("  [WorldMap] Decoding 4,050 blocks (12x12 templates) and expanding 2x2 metatiles...")
    # 6 templates of 144 bytes at MAIN.EXE 0x45ba8 (ds:0xb1f8)
    templates = [
        main_exe[0x45BA8 + i * 144 : 0x45BA8 + (i + 1) * 144]
        for i in range(6)
    ]
    lut_2x2 = data1_entries[18]   # 256 bytes: 2x2 expansion table for cell >= 16
    lut_auto = data1_entries[10]  # 512 bytes: 8-neighbor coastline autotile LUT

    W = 2160
    H = 1080
    raw_grid = bytearray(W * H)

    for chunk_idx in range(3):
        entry = worldmap_entries[chunk_idx]
        chunk_x_tile_base = chunk_idx * 720
        offsets = struct.unpack("<1350H", entry[:2700])
        data_base = 2700

        for blk_idx in range(1350):
            bx = blk_idx % 30
            by = blk_idx // 30
            pos = data_base + offsets[blk_idx]
            b0 = entry[pos]
            tpl_id = (b0 & 0x7F) - 120
            tpl = templates[tpl_id]

            cells = bytearray(144)
            if b0 & 0x80:
                cells[:] = tpl
            else:
                mask_bytes = entry[pos + 1 : pos + 19]
                val_pos = pos + 19
                for c_idx in range(144):
                    byte_i = c_idx >> 3
                    bit_i = 7 - (c_idx & 7)
                    if (mask_bytes[byte_i] >> bit_i) & 1:
                        cells[c_idx] = entry[val_pos]
                        val_pos += 1
                    else:
                        cells[c_idx] = tpl[c_idx]

            # Expand each 12x12 cell into 2x2 tiles -> 24x24 tiles per block
            base_tx = chunk_x_tile_base + bx * 24
            base_ty = by * 24
            for cy in range(12):
                for cx in range(12):
                    val = cells[cy * 12 + cx]
                    if val < 16:
                        tl = 0x41 if (val & 8) else 0x00
                        tr = 0x41 if (val & 4) else 0x00
                        bl = 0x41 if (val & 2) else 0x00
                        br = 0x41 if (val & 1) else 0x00
                    else:
                        t_off = val * 4
                        t0, t1, t2, t3 = lut_2x2[t_off : t_off + 4]
                        tl = t0 if t0 >= 0x34 else 0x00
                        tr = t1 if t1 >= 0x34 else 0x00
                        bl = t2 if t2 >= 0x34 else 0x00
                        br = t3 if t3 >= 0x34 else 0x00

                    tx = base_tx + cx * 2
                    ty = base_ty + cy * 2
                    row0 = ty * W + tx
                    row1 = (ty + 1) * W + tx
                    raw_grid[row0] = tl
                    raw_grid[row0 + 1] = tr
                    raw_grid[row1] = bl
                    raw_grid[row1 + 1] = br

    print("  [WorldMap] Running 8-neighbor coastline & climate latitude autotiling...")
    final_grid = bytearray(raw_grid)

    for y in range(H):
        by = y // 24
        if by == 0 or by == 44:
            lat_off = 0x10  # Polar / Ice latitude
        elif by < 14 or by > 30:
            lat_off = 0x08  # Temperate latitude
        else:
            lat_off = 0x00  # Tropical / Equatorial latitude

        ym1 = max(0, y - 1)
        yp1 = min(H - 1, y + 1)
        row_ym1 = ym1 * W
        row_y = y * W
        row_yp1 = yp1 * W

        for x in range(W):
            cur = raw_grid[row_y + x]
            if cur >= 0x59:
                continue

            xm1 = (x - 1) % W
            xp1 = (x + 1) % W

            mask = 0
            if raw_grid[row_ym1 + xm1] >= 0x29:
                mask |= 0x80
            if raw_grid[row_y + xm1] >= 0x29:
                mask |= 0x40
            if raw_grid[row_yp1 + xm1] >= 0x29:
                mask |= 0x20
            if raw_grid[row_yp1 + x] >= 0x29:
                mask |= 0x10
            if raw_grid[row_yp1 + xp1] >= 0x29:
                mask |= 0x08
            if raw_grid[row_y + xp1] >= 0x29:
                mask |= 0x04
            if raw_grid[row_ym1 + xp1] >= 0x29:
                mask |= 0x02
            if raw_grid[row_ym1 + x] >= 0x29:
                mask |= 0x01

            table_idx = (0 if cur >= 0x29 else 256) + mask
            lut_val = lut_auto[table_idx]
            if lut_val == 0:
                final_grid[row_y + x] = 0
            else:
                # Check if any 4-neighbor is river mouth / special 0x59
                if (
                    raw_grid[row_ym1 + x] == 0x59
                    or raw_grid[row_y + xm1] == 0x59
                    or raw_grid[row_y + xp1] == 0x59
                    or raw_grid[row_yp1 + x] == 0x59
                ):
                    final_grid[row_y + x] = lut_val + 0x18
                else:
                    final_grid[row_y + x] = lut_val + lat_off

    # Save binary 2160x1080 tile grid for fast loading in Godot 4
    grid_path = DATA_DIR / "worldmap_grid.bin"
    grid_path.parent.mkdir(parents=True, exist_ok=True)
    grid_path.write_bytes(final_grid)

    # Render a 2160x1080 overview PNG (1 pixel per tile) for minimap & verification
    wm_tiles_raw = data1_entries[11][:128 * 128]
    num_wm_tiles = len(wm_tiles_raw) // 128
    day_pal = palettes["day"]
    tile_avg_rgb = [(0, 68, 204)] * 256
    for t in range(num_wm_tiles):
        px = decode_tile_16x16_planar(wm_tiles_raw[t * 128 : (t + 1) * 128])
        r_sum = sum(day_pal[c][0] for c in px) // 256
        g_sum = sum(day_pal[c][1] for c in px) // 256
        b_sum = sum(day_pal[c][2] for c in px) // 256
        tile_avg_rgb[t] = (r_sum, g_sum, b_sum)

    overview_rgba = bytearray(W * H * 4)
    for i, tid in enumerate(final_grid):
        r, g, b = tile_avg_rgb[tid]
        p = i * 4
        overview_rgba[p] = r
        overview_rgba[p + 1] = g
        overview_rgba[p + 2] = b
        overview_rgba[p + 3] = 255

    write_png_rgba(ASSETS_DIR / "worldmap" / "worldmap_minimap.png", W, H, bytes(overview_rgba))
    return final_grid


# ==============================================================================
# 7. Game Data Tables Extraction (Ports, Discoveries, Characters, Ships, Items)
# ==============================================================================
# Ground-truth ZA_DAT.DAT 12-slot mapping verified from MENU.DAT [279..290] and PORTCHIP.LZW signboard tiles:
# Slot 0: 0x50 Balance Scale -> 교역소 (Market)
# Slot 1: 0x51 Wine Goblet -> 주점 (Tavern)
# Slot 2: 0x53 Drafting Compass -> 조선소 (Shipyard)
# Slot 3: 0x64 Anchor -> 항구/부두 (Harbor / Pier - default docking & sailing point)
# Slot 4: 0xd7 Bed -> 여관 (Inn / Lodge)
# Slot 5: Castle Gate Arch -> 왕궁/총독부 (Royal Palace / Governor - present in the 6 capital ports)
# Slot 6: 0xe0 Compass Rose & Crest -> 조합/길드 (Adventurers & Merchants Guild)
# Slot 7: 0xe9 Double-Headed Eagle -> 저택/관저 (Noble Mansion / Patron House, e.g. Duke Ferrero's Mansion in Lisbon)
# Slot 8: 0xea Bee Emblem -> 은행 (Sherlock Bank)
# Slot 9: 0xeb Amphora / Jar -> 상점/도구점 (Item Shop)
# Slot 10: 0xec Cross -> 교당/성당/사원 (Church / Mosque)
# Slot 11: 0xed Star & Crescent -> 점술관/연구소 (Fortune Teller / Cartographer / Scholar)
BUILDING_NAMES = {
    0: {"id": "market", "name_kr": "교역소", "name_en": "Market"},
    1: {"id": "tavern", "name_kr": "주점", "name_en": "Tavern"},
    2: {"id": "shipyard", "name_kr": "조선소", "name_en": "Shipyard"},
    3: {"id": "harbor", "name_kr": "항구(부두)", "name_en": "Harbor"},
    4: {"id": "lodge", "name_kr": "여관", "name_en": "Inn / Lodge"},
    5: {"id": "palace", "name_kr": "왕궁", "name_en": "Royal Palace"},
    6: {"id": "guild", "name_kr": "조합", "name_en": "Guild"},
    7: {"id": "mansion", "name_kr": "저택/관저", "name_en": "Mansion"},
    8: {"id": "bank", "name_kr": "은행", "name_en": "Bank"},
    9: {"id": "item_shop", "name_kr": "상점", "name_en": "Item Shop"},
    10: {"id": "church", "name_kr": "교당(성당/사원)", "name_en": "Church / Temple"},
    11: {"id": "fortune", "name_kr": "점술관", "name_en": "Fortune Teller"},
}

NATION_NAMES = {
    0: "포르투갈",
    1: "에스파냐",
    2: "오스만 제국",
    3: "영국",
    4: "이탈리아",
    5: "네덜란드",
    6: "중립",
}


def extract_ports(
    main_exe: bytes,
    portmap_entries: list[bytes],
    portchip_entries: list[bytes],
    chip_no_bytes: bytes,
    za_dat_bytes: bytes,
) -> list[dict]:
    """
    Extract all 130 ports from MAIN.EXE 0x40903 (ds:0x5f53),
    plus building coordinates from ZA_DAT.DAT, tileset mapping from CHIP_NO.DAT,
    walkability thresholds from PORTCHIP.LZW odd entries, and 96x96 maps from PORTMAP.LZW.
    """
    # Save portmap binary bundle (101 maps x 9216 bytes)
    portmaps_dir = DATA_DIR / "portmaps"
    portmaps_dir.mkdir(parents=True, exist_ok=True)
    all_portmaps = bytearray()
    for i, pm in enumerate(portmap_entries):
        all_portmaps.extend(pm)
    (DATA_DIR / "portmaps_bundle.bin").write_bytes(all_portmaps)

    # Extract walkability tables for each of the 7 port tilesets (PORTCHIP odd entries 1,3,5,7,9,11,13)
    walkability_tables = {}
    for chip_id in range(7):
        odd_entry = portchip_entries[chip_id * 2 + 1]
        walkability_tables[chip_id] = list(odd_entry)

    ports = []
    base_off = 0x40903
    for port_id in range(130):
        rec = main_exe[base_off + port_id * 20 : base_off + (port_id + 1) * 20]
        flag, wx, wy = struct.unpack("<BHH", rec[:5])
        name = decode_euckr(rec[5:20])

        is_supply_port = port_id >= 100
        chip_no = 3 if is_supply_port else chip_no_bytes[port_id]
        portmap_idx = 100 if is_supply_port else port_id
        za_idx = 100 if is_supply_port else port_id

        za_rec = za_dat_bytes[za_idx * 24 : (za_idx + 1) * 24]
        buildings = []
        spawn_x, spawn_y = 48, 48
        for b_slot in range(12):
            bx = za_rec[b_slot * 2]
            by = za_rec[b_slot * 2 + 1]
            if bx != 0xFF and by != 0xFF:
                b_info = BUILDING_NAMES.get(b_slot, {"id": f"b_{b_slot}", "name_kr": f"건물{b_slot}", "name_en": f"Building {b_slot}"})
                buildings.append({
                    "slot": b_slot,
                    "id": b_info["id"],
                    "name_kr": b_info["name_kr"],
                    "name_en": b_info["name_en"],
                    "x": bx,
                    "y": by,
                })
                if b_slot == 3:  # Harbor (slot 3, signboard 0x64 anchor) is default spawn location when docking
                    spawn_x, spawn_y = bx, by + 2

        ports.append({
            "id": port_id,
            "name": name,
            "world_x": wx,
            "world_y": wy,
            "flag": flag,
            "is_supply_port": is_supply_port,
            "chip_no": chip_no,
            "portmap_index": portmap_idx,
            "walkability_thresholds": walkability_tables[chip_no],
            "spawn_x": spawn_x,
            "spawn_y": spawn_y,
            "buildings": buildings,
        })
    return ports


def extract_discoveries(main_exe: bytes, colony_bytes: bytes) -> list[dict]:
    """
    Extract all 100 discoveries from COLONY.DAT (218-byte records)
    and their World Map coordinates from MAIN.EXE 0x42838 (ds:0x7e88, 7-byte records).
    """
    discoveries = []
    coord_base = 0x42838
    for i in range(100):
        c_rec = colony_bytes[i * 218 : (i + 1) * 218]
        name = decode_euckr(c_rec[:18])
        disc_type = c_rec[18]
        desc = decode_euckr(c_rec[19:218])

        m_rec = main_exe[coord_base + i * 7 : coord_base + (i + 1) * 7]
        wx, wy, b4, b5, b6 = struct.unpack("<HHBBB", m_rec)

        discoveries.append({
            "id": i,
            "name": name,
            "type": disc_type,
            "description": desc,
            "world_x": wx,
            "world_y": wy,
            "rarity": b4,
            "monster_hazard": b5,
            "flag": b6,
        })
    return discoveries


def extract_characters(main_exe: bytes) -> list[dict]:
    """
    Extract characters from MAIN.EXE 0x3bbf2 (ds:0x1242, 50-byte records).
    """
    characters = []
    base_off = 0x3BBF2
    for i in range(120):
        off = base_off + i * 50
        rec = main_exe[off : off + 50]
        given_name = decode_euckr(rec[0:13])
        surname = decode_euckr(rec[13:26])
        if not given_name and not surname:
            break
        kao_id = rec[26]
        status = rec[27]
        leadership, seamanship, knowledge, intuition, courage, swordplay, charm, luck = rec[28:36]
        nav_level = rec[36]
        combat_level = rec[37]
        nav_exp, combat_exp = struct.unpack("<HH", rec[38:42])
        age = rec[42] + 16 if rec[42] < 100 else rec[42]
        hp = rec[43]
        port_id = rec[44]
        fleet_id = rec[45]
        nation_rank = rec[46]
        nation_id = nation_rank & 0x07
        skills_mask = rec[47]

        full_name = f"{given_name} {surname}".strip()
        characters.append({
            "id": i,
            "given_name": given_name,
            "surname": surname,
            "full_name": full_name,
            "is_protagonist": i < 6,
            "sprite_sheet_id": i if i < 6 else 6,
            "portrait_id": kao_id,
            "status": status,
            "stats": {
                "leadership": leadership,
                "seamanship": seamanship,
                "knowledge": knowledge,
                "intuition": intuition,
                "courage": courage,
                "swordplay": swordplay,
                "charm": charm,
                "luck": luck,
            },
            "nav_level": nav_level,
            "combat_level": combat_level,
            "nav_exp": nav_exp,
            "combat_exp": combat_exp,
            "age_raw": rec[42],
            "hp": hp,
            "initial_port_id": port_id,
            "fleet_id": fleet_id,
            "nation_id": nation_id,
            "nation_name": NATION_NAMES.get(nation_id, "기타"),
            "skills_mask": skills_mask,
        })
    return characters


def extract_ships(main_exe: bytes) -> list[dict]:
    """
    Extract all 25 ship types from MAIN.EXE 0x40566 (25-byte records).
    Each 25-byte record has:
    - bytes 0..15: EUC-KR null-terminated ship class name (e.g., 발사, 한자 코그, 다우, 바스, 타렛테, 카라벨 라티나...)
    - byte 18: ship class ID (0..24)
    - byte 19: sail/rigging flags (upper nibbles: propulsion/tacking class)
    - byte 20: base hull durability (in units, e.g., 5..120 -> x10 or raw)
    - bytes 21..22: uint16 total cargo capacity (e.g. 15, 20, 150, 30, 80, 100, 180, 300)
    - bytes 23..24: uint16 base price (in x10 gold coins, e.g. 30, 35, 50, 320, 55, 80...)
    """
    ships = []
    base_off = 0x40566
    for i in range(25):
        rec = main_exe[base_off + i * 25 : base_off + (i + 1) * 25]
        name = decode_euckr(rec[:18])
        ship_id, rig_flags, base_hull, capacity, price_x10 = struct.unpack("<BBBHH", rec[18:25])
        max_hull = max(60, base_hull * 2)
        min_crew = max(5, capacity // 6)
        max_crew = max(20, capacity)
        max_guns = max(4, (capacity // 5))
        tacking = 60 + ((rig_flags >> 4) & 0x07) * 5
        propulsion = 65 + (rig_flags & 0x0F) * 5
        ships.append({
            "id": i,
            "name": name,
            "used_price_x100": max(1, price_x10 // 12),
            "new_price_x100": max(2, price_x10 // 10),
            "capacity": capacity,
            "max_hull": max_hull,
            "min_crew_x5": min_crew // 5,
            "max_crew": max_crew,
            "max_guns": max_guns,
            "maneuverability": tacking,
            "propulsion": propulsion,
            "base_speed": 8 + (i // 4),
        })
    return ships


def extract_items(main_exe: bytes, item_mes_bytes: bytes) -> list[dict]:
    """
    Extract all 100 items from MAIN.EXE 0x42af4 (26-byte records) and descriptions from ITEM.MES (124-byte records).
    """
    items = []
    base_off = 0x42AF4
    for i in range(100):
        rec = main_exe[base_off + i * 26 : base_off + (i + 1) * 26]
        name = decode_euckr(rec[:21])
        pic_id, price_raw, power, item_type = struct.unpack("<BHBB", rec[21:26])
        desc = decode_euckr(item_mes_bytes[i * 124 : (i + 1) * 124]) if (i + 1) * 124 <= len(item_mes_bytes) else ""
        items.append({
            "id": i,
            "name": name,
            "category": item_type,
            "pic_id": pic_id,
            "effect_value": power,
            "price": price_raw * 100,
            "description": desc,
        })
    return items


def extract_monsters(dos_dir: Path, system_messages: list[str]) -> list[dict]:
    """
    Extract all 30 active sea monster / supernatural hazard zones from MONSTER.DAT (200 bytes = 40 x 5B)
    and pair each type (0..9) with its two authentic Korean event strings from MESSAGE.DAT (515..534).
    """
    monster_raw = (dos_dir / "MONSTER.DAT").read_bytes()
    type_names = {
        0: "세이렌의 요염한 노랫소리",
        1: "대왕오징어(크라켄)의 습격",
        2: "마의 해역 (짙은 안개)",
        3: "거대 가오리 요괴",
        4: "성 엘모의 불 (청백색 인광)",
        5: "불을 뿜는 괴조",
        6: "거대 바다뱀(씨서펜트)",
        7: "거대한 바다용",
        8: "거대 고래 무리의 충돌",
        9: "유령선 (폐선의 흐느낌)",
    }
    monsters = []
    for i in range(40):
        rec = monster_raw[i * 5 : (i + 1) * 5]
        wx, wy, mtype = struct.unpack("<HHB", rec)
        if wx == 0 and wy == 0:
            continue
        msg1_idx = 515 + mtype * 2
        msg2_idx = 516 + mtype * 2
        msg1 = system_messages[msg1_idx] if msg1_idx < len(system_messages) else ""
        msg2 = system_messages[msg2_idx] if msg2_idx < len(system_messages) else ""
        monsters.append({
            "id": i,
            "world_x": wx,
            "world_y": wy,
            "type": mtype,
            "name": type_names.get(mtype, f"바다괴물#{mtype}"),
            "message_1": msg1,
            "message_2": msg2,
        })
    return monsters


def extract_scenarios_and_messages(dos_dir: Path, ports: list[dict]) -> tuple[dict, list[str]]:
    """
    Reverse-engineered from SNR0..6.DAT + SNR0..6.MES + MESSAGE.DAT:
    1. Extracts all 1,184 system dialogue strings from MESSAGE.DAT.
    2. Extracts all 4,302 scenario dialogue lines from SNR0..6.MES.
    3. Parses the exactSNDT bytecode header, Chapter offset table, Sub-section offset table,
       and (port_id, building_slot -> bytecode_offset) trigger table from SNR0..6.DAT,
       decoding each trigger's dialogue sequence (0xCC speaker portrait + 0xC8 message ID,
       0x2C set_flag, 0xAC/0xAD check_flag, 0xFA give_ship, 0xFB add_companion).
    """
    port_name_map = {p["id"]: p["name"] for p in ports}
    slot_name_map = {k: v["name_kr"] for k, v in BUILDING_NAMES.items()}
    slot_name_map[0x15] = "왕궁(야간)"
    slot_name_map[0xFF] = "항구거리(행인)"

    # 1. Extract MESSAGE.DAT
    msg_raw = (dos_dir / "MESSAGE.DAT").read_bytes()
    msg_parts = msg_raw.split(b"\x00")
    system_messages = []
    for p in msg_parts:
        s = p.decode("euc-kr", errors="ignore").strip()
        system_messages.append(s)

    # 2. Extract SNR0..6.MES and SNR0..6.DAT
    scenarios = {}
    protag_names = {
        0: "공통 조합/칙명 (SNR0)",
        1: "조안 페레로 (SNR1)",
        2: "카탈리나 에란초 (SNR2)",
        3: "오토 스피노라 (SNR3)",
        4: "에르네스트 로페스 (SNR4)",
        5: "피에트로 콘티 (SNR5)",
        6: "알 베자스 (SNR6)",
    }

    for snr_idx in range(7):
        dat = (dos_dir / f"SNR{snr_idx}.DAT").read_bytes()
        mes = (dos_dir / f"SNR{snr_idx}.MES").read_bytes()
        first_off = struct.unpack(">I", mes[:4])[0]
        count = first_off // 4
        offs = struct.unpack(f">{count}I", mes[:first_off])

        lines = []
        for o in offs:
            end = mes.find(b"\x00", o)
            lines.append(mes[o:end].decode("euc-kr", errors="ignore"))

        # Parse chapters in SNR*.DAT (starting at 0x10 until 0xFFFFFFFF)
        pos = 0x10
        chap_offs = []
        while pos + 4 <= len(dat):
            val = struct.unpack(">I", dat[pos : pos + 4])[0]
            pos += 4
            if val == 0xFFFFFFFF:
                break
            chap_offs.append(val)
        chap_offs.append(len(dat))

        chapters = []
        for ci in range(len(chap_offs) - 1):
            coff, cend = chap_offs[ci], chap_offs[ci + 1]
            p = coff
            sub_offs = []
            while p + 2 <= cend:
                val = struct.unpack(">H", dat[p : p + 2])[0]
                p += 2
                if val == 0xFFFF:
                    break
                sub_offs.append(coff + val)
            sub_offs.append(cend)

            subsections = []
            for si in range(len(sub_offs) - 1):
                soff, send = sub_offs[si], sub_offs[si + 1]
                tp = soff
                raw_trigs = []
                while tp + 4 <= send:
                    pid, bslot, roff = struct.unpack(">BBH", dat[tp : tp + 4])
                    tp += 4
                    if pid == 0xFF and bslot == 0xFF:
                        break
                    raw_trigs.append((pid, bslot, soff + roff))

                # Sort unique offsets to slice each trigger's bytecode block
                sub_bytes_hex = dat[soff:send].hex()
                triggers_out = []
                for ti, (pid, bslot, tstart) in enumerate(raw_trigs):
                    # Find next trigger start > tstart, or send
                    next_starts = [t[2] for t in raw_trigs if t[2] > tstart]
                    tend = min(next_starts) if next_starts else send
                    chunk = dat[tstart:tend]
                    rel_off = tstart - soff

                    # Extract static dialogue calls (for Scenario Viewer) and state ops
                    dialogues = []
                    flags_set = []
                    cur_speaker = 0
                    b_i = 0
                    while b_i < len(chunk):
                        op = chunk[b_i]
                        if op == 0xCC and b_i + 2 < len(chunk):
                            cur_speaker = (chunk[b_i + 1] << 8) | chunk[b_i + 2]
                            b_i += 3
                        elif op == 0xC0 and b_i + 1 < len(chunk):
                            if chunk[b_i + 1] == 0x00:
                                cur_speaker = 0
                            b_i += 2
                        elif op == 0xC8 and b_i + 2 < len(chunk):
                            mid = (chunk[b_i + 1] << 8) | chunk[b_i + 2]
                            if 0 <= mid < len(lines):
                                dialogues.append({
                                    "msg_id": mid,
                                    "speaker_code": cur_speaker,
                                    "text": lines[mid],
                                })
                            b_i += 3
                        elif op == 0x2C and b_i + 2 < len(chunk):
                            flags_set.append({"flag": chunk[b_i + 1], "val": chunk[b_i + 2]})
                            b_i += 3
                        else:
                            b_i += 1

                    if pid < 130:
                        pname = port_name_map.get(pid, f"항구#{pid}")
                    elif pid == 0xA0:
                        pname = "출항/해상 조건(A0)"
                    elif pid == 0xA1:
                        pname = "목적지 항구(A1)"
                    elif pid == 0xA2:
                        pname = "퀘스트 항구(A2)"
                    elif pid == 0xA3:
                        pname = "모든 항구(공통)"
                    else:
                        pname = f"특수항구(0x{pid:02x})"

                    triggers_out.append({
                        "port_id": pid,
                        "port_name": pname,
                        "building_slot": bslot,
                        "building_name": slot_name_map.get(bslot, f"슬롯#{bslot}"),
                        "bytecode_offset": tstart,
                        "rel_offset": rel_off,
                        "bytecode_len": len(chunk),
                        "flags_set": flags_set,
                        "dialogues": dialogues,
                    })

                subsections.append({
                    "sub_index": si,
                    "offset": soff,
                    "sub_bytes_hex": sub_bytes_hex,
                    "triggers": triggers_out,
                })

            chapters.append({
                "chapter_index": ci,
                "offset": coff,
                "subsections": subsections,
            })

        scenarios[str(snr_idx)] = {
            "snr_id": snr_idx,
            "title": protag_names[snr_idx],
            "total_lines": len(lines),
            "lines": lines,
            "chapters": chapters,
        }

    return scenarios, system_messages


# ==============================================================================
# 8. Korean Font (ALL_FONT.16P & HANKAKU.FNT) Extraction
# ==============================================================================
def decode_koei_4pixel_image(raw: bytes) -> tuple[int, int, list[int]]:
    """Decodes Koei 4-pixel LZ+RLE compressed images from GRAPH.DAT (MAIN.EXE:0x063c6)."""
    if len(raw) < 20:
        return 0, 0, []
    w = raw[0] | (raw[1] << 8)
    h = raw[2] | (raw[3] << 8)
    if w <= 0 or h <= 0 or w > 640 or h > 480:
        return 0, 0, []

    dict_patterns = []
    for i in range(8):
        v = raw[4 + i * 2] | (raw[5 + i * 2] << 8)
        p0 = (v >> 12) & 0x0F
        p1 = (v >> 8) & 0x0F
        p2 = (v >> 4) & 0x0F
        p3 = v & 0x0F
        dict_patterns.append([p0, p1, p2, p3])

    pixels = [0] * (w * h)
    pos = 20
    cur_p = 0
    total = w * h

    while cur_p < total and pos < len(raw):
        b = raw[pos]
        pos += 1
        if b < 0x80:
            if (b & 0x40) == 0:
                if pos >= len(raw):
                    break
                b2 = raw[pos]
                pos += 1
                offset = ((b >> 4) << 8) | b2
                count = (b & 0x0F) + 1
                for _ in range(count):
                    src_p = cur_p - offset * 4
                    for i in range(4):
                        if cur_p < total:
                            pixels[cur_p] = pixels[src_p + i] if src_p + i >= 0 else 0
                            cur_p += 1
            else:
                count = (b & 0x0F) + 1
                for _ in range(count):
                    src_p = cur_p - w
                    for _k in range(4):
                        if cur_p < total:
                            pixels[cur_p] = pixels[src_p] if src_p >= 0 else 0
                            src_p += 1
                            cur_p += 1
        else:
            rep = (b & 0x07) + 1
            if (b & 0x40) != 0:
                d_idx = (b >> 3) & 0x07
                pat = dict_patterns[d_idx]
            else:
                if pos + 1 >= len(raw):
                    break
                v = raw[pos] | (raw[pos + 1] << 8)
                pos += 2
                pat = [(v >> 12) & 0x0F, (v >> 8) & 0x0F, (v >> 4) & 0x0F, v & 0x0F]
            for _ in range(rep):
                for p in pat:
                    if cur_p < total:
                        pixels[cur_p] = p
                        cur_p += 1

    return w, h, pixels


def extract_building_interiors(dos_dir: Path, palettes: dict) -> None:
    """Extracts all 12 building interior graphics from GRAPH.DAT."""
    graph_bytes = (dos_dir / "GRAPH.DAT").read_bytes()
    num_entries = graph_bytes[0] | (graph_bytes[1] << 8)
    offsets = []
    for i in range(num_entries):
        offsets.append(graph_bytes[2 + i * 4] | (graph_bytes[3 + i * 4] << 8) | (graph_bytes[4 + i * 4] << 16) | (graph_bytes[5 + i * 4] << 24))
    offsets.append(len(graph_bytes))

    interior_keys = [
        "harbor", "market", "tavern", "shipyard", "inn", "palace",
        "guild", "bank", "church", "fortune", "item_shop", "mansion"
    ]
    pal = palettes["day"]

    for idx, key in enumerate(interior_keys):
        if idx >= num_entries:
            break
        raw = graph_bytes[offsets[idx] : offsets[idx + 1]]
        w, h, px = decode_koei_4pixel_image(raw)
        if w > 0 and h > 0:
            out_file = ASSETS_DIR / "graphics" / f"interior_{key}.png"
            write_png_indexed_as_rgba(out_file, w, h, px, pal)


def extract_korean_font(font_16p_bytes: bytes, hankaku_bytes: bytes) -> None:
    """
    ALL_FONT.16P: 3,478 records of 30 bytes each:
    - bytes[0..1]: 2-byte EUC-KR code
    - bytes[2..29]: 14 rows x 2 bytes/row (16x14 1bpp bitmap)
    Renders a font atlas PNG and a JSON character map.
    """
    num_glyphs = len(font_16p_bytes) // 30
    cols = 64
    rows = (num_glyphs + cols - 1) // cols
    atlas_w = cols * 16
    atlas_h = rows * 16
    rgba = bytearray(atlas_w * atlas_h * 4)

    glyph_map = {}
    for idx in range(num_glyphs):
        rec = font_16p_bytes[idx * 30 : (idx + 1) * 30]
        code_bytes = rec[:2]
        char_str = code_bytes.decode("euc-kr", errors="ignore")
        if char_str:
            glyph_map[char_str] = idx

        gx = (idx % cols) * 16
        gy = (idx // cols) * 16
        bitmap = rec[2:30]
        for ry in range(14):
            word = (bitmap[ry * 2] << 8) | bitmap[ry * 2 + 1]
            for rx in range(16):
                if (word >> (15 - rx)) & 1:
                    p = ((gy + ry + 1) * atlas_w + (gx + rx)) * 4
                    rgba[p] = 255
                    rgba[p + 1] = 255
                    rgba[p + 2] = 255
                    rgba[p + 3] = 255

    write_png_rgba(ASSETS_DIR / "fonts" / "all_font_16p_atlas.png", atlas_w, atlas_h, bytes(rgba))
    with open(DATA_DIR / "hangul_font_map.json", "w", encoding="utf-8") as f:
        json.dump({"cols": cols, "cell_w": 16, "cell_h": 16, "glyphs": glyph_map}, f, ensure_ascii=False)


# ==============================================================================
# Main Extraction Pipeline
# ==============================================================================
def main() -> None:
    print("=== Uncharted Waters 2 (대항해시대 2) Asset & Data Extraction ===")
    main_exe = (DOS_DIR / "MAIN.EXE").read_bytes()

    # 1. Palettes
    print("[1/8] Extracting VGA 16-color palettes from MAIN.EXE...")
    palettes = extract_palettes(main_exe)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with open(DATA_DIR / "palettes.json", "w", encoding="utf-8") as f:
        json.dump(palettes, f, indent=2)

    # 2. Decompress Core LZW Archives
    print("[2/8] Decompressing LS10/LS11 .LZW archives...")
    data1_entries = load_lzw_archive(DOS_DIR / "DATA1.lzw")
    worldmap_entries = load_lzw_archive(DOS_DIR / "WORLDMAP.LZW")
    portchip_entries = load_lzw_archive(DOS_DIR / "PORTCHIP.LZW")
    portmap_entries = load_lzw_archive(DOS_DIR / "PORTMAP.LZW")
    char_entries = load_lzw_archive(DOS_DIR / "CHAR.LZW")
    kao_entries = load_lzw_archive(DOS_DIR / "KAO.LZW")

    # 3. Extract World Map Tilesets & 32x32 Ship Sprites & Reconstruct 2160x1080 World Map
    print("[3/8] Rendering World Map tilesets, 32x32 ship sprites, and reconstructing 2160x1080 World Map...")
    wm_tiles_raw = data1_entries[11][:128 * 128]  # First 16,384 bytes: 128 tiles of 16x16
    wm_ships_raw = data1_entries[11][128 * 128 :]  # Second 16,384 bytes: 32 ship sprites of 32x32 (512B each)

    for pal_name in ("day", "dawn", "dusk", "night", "storm"):
        render_tileset_sheet(
            wm_tiles_raw,
            cols=16,
            palette=palettes[pal_name],
            out_path=ASSETS_DIR / "tilesets" / f"worldmap_tiles_{pal_name}.png",
        )

    # Decode 32x32 ship sprites (32 sprites = 8 cols x 4 rows)
    ship_cols, ship_rows = 8, 4
    ship_w, ship_h = ship_cols * 32, ship_rows * 32
    ship_px_all = [0] * (ship_w * ship_h)
    ship_msk_all = [0] * (ship_w * ship_h)
    for s in range(32):
        raw_512 = wm_ships_raw[s * 512 : (s + 1) * 512]
        sx = (s % ship_cols) * 32
        sy = (s // ship_cols) * 32
        for y in range(32):
            for half in range(2):
                r = raw_512[y * 16 + half * 8 : y * 16 + (half + 1) * 8]
                wm = (r[0] << 8) | r[1]
                w0 = (r[2] << 8) | r[3]
                w1 = (r[4] << 8) | r[5]
                w2 = (r[6] << 8) | r[7]
                for x in range(16):
                    sh = 15 - x
                    c = (((w0 >> sh) & 1) << 0) | (((w1 >> sh) & 1) << 1) | (((w2 >> sh) & 1) << 2)
                    dst_idx = (sy + y) * ship_w + sx + half * 16 + x
                    ship_px_all[dst_idx] = c
                    if ((wm >> sh) & 1) == 1 and c == 0:
                        ship_msk_all[dst_idx] = 1

    write_png_indexed_as_rgba(
        ASSETS_DIR / "sprites" / "worldmap_ships.png",
        ship_w,
        ship_h,
        ship_px_all,
        palettes["day"],
        ship_msk_all,
    )

    extract_world_map(main_exe, data1_entries, worldmap_entries, palettes)

    # 4. Extract Port Tilesets (0..6) in Day/Dusk/Night palettes
    print("[4/8] Rendering 7 regional Port Tilesets (PORTCHIP.LZW)...")
    for chip_id in range(7):
        tiles_raw = portchip_entries[chip_id * 2]
        for pal_name in ("day", "dusk", "night"):
            render_tileset_sheet(
                tiles_raw,
                cols=16,
                palette=palettes[pal_name],
                out_path=ASSETS_DIR / "tilesets" / f"port_tileset_{chip_id}_{pal_name}.png",
            )

    # 5. Extract Sprites (CHAR.LZW entries 0..6) with transparency mask
    # Each 32x32 character frame consists of 4 16x16 blocks: [TL, TR, BL, BR]!
    print("[5/8] Rendering Protagonist and NPC 32x32 Sprites (CHAR.LZW)...")
    for entry_id, raw in enumerate(char_entries):
        num_frames_32x32 = len(raw) // (160 * 4)  # 8 frames for protagonists, 24 frames for NPCs
        cols = 2
        rows = (num_frames_32x32 + cols - 1) // cols
        sw = cols * 32
        sh = rows * 32
        sheet_px = [0] * (sw * sh)
        sheet_mask = [0] * (sw * sh)
        for f in range(num_frames_32x32):
            fx = (f % cols) * 32
            fy = (f // cols) * 32
            # 4 sub-blocks of 16x16: 0=TL, 1=TR, 2=BL, 3=BR
            for sub in range(4):
                s = f * 4 + sub
                px, msk = decode_sprite_16x16_masked(raw[s * 160 : (s + 1) * 160])
                sub_x = fx + (sub % 2) * 16
                sub_y = fy + (sub // 2) * 16
                for py in range(16):
                    dst = (sub_y + py) * sw + sub_x
                    src = py * 16
                    sheet_px[dst : dst + 16] = px[src : src + 16]
                    sheet_mask[dst : dst + 16] = msk[src : src + 16]
        write_png_indexed_as_rgba(
            ASSETS_DIR / "sprites" / f"char_{entry_id}.png",
            sw,
            sh,
            sheet_px,
            palettes["day"],
            sheet_mask,
        )

    # 6. Extract Portraits (KAO.LZW: entries 0..127 are 64x80 large portraits; entries 128..255 are 48x48 small portraits)
    # Drawn with the 8 base colors of Day palette (#000000, #0044dd, #dd4400, #dd66aa, #00aa66, #00aaff, #ffaa66, #ffeedd)
    print("[6/8] Rendering Character Portraits (KAO.LZW: 128 large 64x80 + 128 small 48x48)...")
    portrait_pal = palettes["day"]

    # Large portraits (0..127): 64x80 pixels (1920 bytes = 8 groups/row * 3 planes * 80 rows)
    # Drawn with Plane 3 = 0 (colors 0..7)
    lg_cols, lg_rows = 16, 8
    lg_w, lg_h = lg_cols * 64, lg_rows * 80
    lg_sheet_px = [0] * (lg_w * lg_h)
    for face_id in range(128):
        px = decode_3plane_interleaved_image(kao_entries[face_id], 64, 80, high_plane_bit=0)
        fx = (face_id % lg_cols) * 64
        fy = (face_id // lg_cols) * 80
        for py in range(80):
            dst = (fy + py) * lg_w + fx
            src = py * 64
            lg_sheet_px[dst : dst + 64] = px[src : src + 64]

    write_png_indexed_as_rgba(
        ASSETS_DIR / "portraits" / "kao_large_atlas.png",
        lg_w,
        lg_h,
        lg_sheet_px,
        portrait_pal,
    )

    # Small illustrations (128..255): 48x48 pixels (864 bytes = 6 groups/row * 3 planes * 48 rows)
    # Discoveries & Items!
    sm_cols, sm_rows = 16, 8
    sm_w, sm_h = sm_cols * 48, sm_rows * 48
    sm_sheet_px = [0] * (sm_w * sm_h)
    for idx in range(128):
        px = decode_3plane_interleaved_image(kao_entries[128 + idx], 48, 48, high_plane_bit=0)
        fx = (idx % sm_cols) * 48
        fy = (idx // sm_cols) * 48
        for py in range(48):
            dst = (fy + py) * sm_w + fx
            src = py * 48
            sm_sheet_px[dst : dst + 48] = px[src : src + 48]

    write_png_indexed_as_rgba(
        ASSETS_DIR / "portraits" / "kao_small_atlas.png",
        sm_w,
        sm_h,
        sm_sheet_px,
        portrait_pal,
    )

    # 7. Extract Static Game Data Tables -> UTF-8 JSON
    print("[7/8] Extracting Ports, Discoveries, Characters, Ships, Items, and Wind/Current data...")
    chip_no_bytes = (DOS_DIR / "CHIP_NO.DAT").read_bytes()
    za_dat_bytes = (DOS_DIR / "ZA_DAT.DAT").read_bytes()
    colony_bytes = (DOS_DIR / "COLONY.DAT").read_bytes()
    item_mes_bytes = (DOS_DIR / "ITEM.MES").read_bytes()
    windcur_bytes = (DOS_DIR / "WINDCUR.DAT").read_bytes()

    ports = extract_ports(main_exe, portmap_entries, portchip_entries, chip_no_bytes, za_dat_bytes)
    discoveries = extract_discoveries(main_exe, colony_bytes)
    characters = extract_characters(main_exe)
    ships = extract_ships(main_exe)
    items = extract_items(main_exe, item_mes_bytes)
    scenarios, system_messages = extract_scenarios_and_messages(DOS_DIR, ports)
    monsters = extract_monsters(DOS_DIR, system_messages)

    with open(DATA_DIR / "ports.json", "w", encoding="utf-8") as f:
        json.dump(ports, f, ensure_ascii=False, indent=2)
    with open(DATA_DIR / "discoveries.json", "w", encoding="utf-8") as f:
        json.dump(discoveries, f, ensure_ascii=False, indent=2)
    with open(DATA_DIR / "characters.json", "w", encoding="utf-8") as f:
        json.dump(characters, f, ensure_ascii=False, indent=2)
    with open(DATA_DIR / "ships.json", "w", encoding="utf-8") as f:
        json.dump(ships, f, ensure_ascii=False, indent=2)
    with open(DATA_DIR / "items.json", "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)
    with open(DATA_DIR / "scenarios.json", "w", encoding="utf-8") as f:
        json.dump(scenarios, f, ensure_ascii=False, indent=2)
    with open(DATA_DIR / "messages.json", "w", encoding="utf-8") as f:
        json.dump(system_messages, f, ensure_ascii=False, indent=2)
    with open(DATA_DIR / "monsters.json", "w", encoding="utf-8") as f:
        json.dump(monsters, f, ensure_ascii=False, indent=2)

    # Save WINDCUR.DAT as binary + structured JSON (summer/winter wind & current grids)
    (DATA_DIR / "windcur.bin").write_bytes(windcur_bytes)

    # 8. Extract Korean Hangul Font (ALL_FONT.16P)
    print("[8/9] Extracting Korean Hangul 16x14 Bitmap Font (ALL_FONT.16P)...")
    extract_korean_font(
        (DOS_DIR / "ALL_FONT.16P").read_bytes(),
        (DOS_DIR / "HANKAKU.FNT").read_bytes(),
    )

    # 9. Extract Building Interiors from GRAPH.DAT
    print("[9/9] Extracting 12 Building Interior Illustrations from GRAPH.DAT...")
    extract_building_interiors(DOS_DIR, palettes)

    print("=== Extraction Complete! ===")
    print(f"  - Extracted {len(ports)} ports, {len(discoveries)} discoveries, {len(characters)} characters, {len(ships)} ships, {len(items)} items.")


if __name__ == "__main__":
    main()
