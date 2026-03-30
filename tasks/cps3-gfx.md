# CPS3 Graphics Hardware

All references are to the MAME source files `cps3.cpp` and `cps3.h` in the
`src/mame/capcom/` directory. Line numbers correspond to the copy at
`cores/cps3/doc/cps3.cpp` and `cores/cps3/doc/cps3.h`.

## Table of Contents

1. [Video Memory Map](#1-video-memory-map)
2. [DMA System](#2-dma-system)
3. [Graphic Layers](#3-graphic-layers)
4. [Sprite Properties](#4-sprite-properties)
5. [Tile Properties](#5-tile-properties)
6. [Palette System](#6-palette-system)
7. [Full-Image Effects](#7-full-image-effects)
8. [Rendering Architecture](#8-rendering-architecture)
9. [PPU Registers](#9-ppu-registers)
10. [CPU–PPU Communication](#10-cpuppu-communication)

---

## 1. Video Memory Map

The CPS3 video subsystem occupies SH-2 address area 2 (CS2, 0x04000000–0x05FFFFFF).
The CPU memory map is defined in `cps3_map()` (cps3.cpp:2123–2170).

```
 Address Range        Size     Description
 ─────────────────────────────────────────────────────────────────
 0x04000000–0x0407FFFF  512 KB  Sprite RAM (read/write, 32-bit)
 0x04080000–0x040BFFFF  256 KB  Colour RAM (read/write, 16-bit big-endian)
 0x040C0000–0x040C001F   32 B   PPU Global-Scroll registers (write-only)
 0x040C000C–0x040C000D    2 B   DMA status (read-only)
 0x040C0020–0x040C005F   64 B   PPU Tilemap registers (write-only)
 0x040C0060–0x040C007F   32 B   PPU CRTC / Zoom registers (write-only)
 0x040C0080–0x040C0083    4 B   Sprite-list DMA control (write-only, low 16 bits)
 0x040C0084–0x040C0087    4 B   Character RAM bank select
 0x040C0088–0x040C008B    4 B   GFX flash bank select
 0x040C0094–0x040C009B    8 B   Character DMA control (write-only)
 0x040C00A0–0x040C00AF   16 B   Palette DMA control (write-only)
 0x040E0000–0x040E02FF  768 B   Sound registers (16-voice PCM)
 0x04100000–0x041FFFFF    1 MB  Character RAM window (banked, 8 × 1 MB banks)
 0x04200000–0x043FFFFF    2 MB  GFX flash window (banked)
 ─────────────────────────────────────────────────────────────────
 0x05040000–0x0504FFFF   64 KB  SS RAM (odd bytes only, umask 0x00FF00FF)
 0x05050000–0x0505002B   44 B   SS registers (odd bytes only)
 0x05100000               4 B   VBlank IRQ acknowledge (write-only)
 0x05110000               4 B   DMA IRQ acknowledge (write-only)
```

### 1.1 Sprite RAM (512 KB)

Mapped at 0x04000000 (cps3.cpp:2129). This is a 32-bit-wide, byte-addressable SRAM shared between the CPU and the PPU. It holds two data structures:

- **Main sprite list** (0x00000–0x01FFF): up to 0x800/4 = 512 entries of 4 words
  each (16 bytes). Parsed at rendering time (cps3.cpp:1123).
- **Sub-lists** (variable offsets): each main-list entry points to a sub-list of
  individual sprite tiles. Sub-list entries are also 4 words (16 bytes) each.

During sprite-list DMA the PPU does **not** keep a second copy of the original
main-list/sub-list structure. Instead, MAME flattens the active sprite commands
into an internal 8 kB `m_spritelist` buffer so the renderer can walk a compact,
frame-stable list while the CPU updates Sprite RAM for the next frame.

This copied list is **not mapped back into the CPU address space** in MAME. The
SH-2 can only access the original Sprite RAM at 0x04000000–0x0407FFFF; the DMA
destination is an internal renderer snapshot buffer allocated in
`video_start()`. However, the internal format is now well-defined in the MAME
implementation: it is a linear array of 4-word render records terminated by a
stopper entry whose word 0 has bit 31 set.

### 1.2 Colour RAM (256 KB)

Mapped at 0x04080000 (cps3.cpp:2130). This is 0x20000 16-bit entries (128 K entries × 2 bytes = 256 KB) stored in big-endian byte order (cps3.h:41, `ENDIANNESS_BIG`).

Each 16-bit entry encodes one colour:

```
 Bit   15   14:10   9:5   4:0
      Unk     B       G     R     (5-5-5 RGB, each 5-bit channel)
```

The CPU can read and write Colour RAM directly (cps3.cpp:2109–2118). Palette DMA can also bulk-load entries from GFX flash with an optional fade effect.

### 1.3 Character RAM (8 MB total, 1 MB window)

Character RAM is 8 MB of internal SRAM holding decoded tile pixel data (cps3.cpp:972, `m_char_ram` = 0x800000/4 = 2 MW). It is accessed through a 1 MB window at 0x04100000–0x041FFFFF, banked by the `cram_bank` register at 0x040C0084 (cps3.cpp:2138, 2145).

```
 cram_bank (3 bits)   Character RAM offset
 ──────────────────────────────────────────
       0              0x000000–0x0FFFFF
       1              0x100000–0x1FFFFF
       2              0x200000–0x2FFFFF
       ...            ...
       7              0x700000–0x7FFFFF
```

The banking is implemented in `cram_data_r/w` (cps3.cpp:1368–1381):
`fulloffset = (cram_bank & 7) * 0x100000/4 + offset`.

Character RAM is populated by the **Character DMA** engine, which decompresses
graphics from GFX flash into this memory (see [§2.1](#21-character-dma)).

### 1.4 GFX Flash Window (2 MB, banked)

Mapped at 0x04200000–0x043FFFFF (cps3.cpp:2146). This provides access to the
raw GFX flash SIMMs (SIMMs 3–6) through a bank register at 0x040C0088
(cps3.cpp:2139).

Each GFX flash bank selects a pair of interleaved flash ROMs. The bank value
selects which 2 MB region of the total ~128 MB GFX flash address space is
visible (cps3.cpp:1628–1674).

### 1.5 SS RAM (Score Screen, 64 KB)

Mapped at 0x05040000 (cps3.cpp:2156). Only odd bytes are accessible
(`umask32 0x00FF00FF`). The layout is (cps3.cpp:1312–1317):

```
 Offset Range    Size     Description
 ──────────────────────────────────────────────
 0x0000–0x3FFF   16 KB    Tilemap layout (64×64 tiles, 2 bytes/tile)
 0x4000–0x7FFF   16 KB    Per-line horizontal scroll table
 0x8000–0xFFFF   32 KB    SS tile pixel data (4bpp, 8×8 tiles, up to 512 tiles)
```

SS tiles are 4bpp, 8×8 pixels. The pixel data lives at bus offsets 0x8000–0xFFFF
(array offsets 0x4000–0x7FFF in the 0x8000-byte `m_ss_ram`). The CPU can update
tiles dynamically (cps3.cpp:1326–1327: `mark_dirty` on array offset ≥ 0x4000).

Note: bus-side offsets in the table above are twice the corresponding array
offsets because SS RAM is accessed through `umask32(0x00FF00FF)` (odd bytes
only), so each 4-byte bus word yields 2 usable bytes. The specified size also
represents the size from the CPU point of view, but the real memory size is
half of that as only odd bytes are connected (8-bit memory)

Actual memory size: 8+8+16 = 32kB. This matches the F9 memory to the G6 custom
chip in the schematics

Despite the `rowscroll` variable name used by MAME, this table is consumed as a
**per-scanline** horizontal scroll table, not as one value per 8-pixel tile
row. In `draw_fg_layer()` the index depends directly on the current output line
(`line`), and one byte is fetched for each scanline from `m_ss_ram[((line +
scrolly - 1) & 0x1ff) * 2 + 0x2000]` (cps3.cpp:1302). That value is then used
for all tiles drawn on that single scanline (cps3.cpp:1304–1313). In other
words, the SS layer supports line scroll.

---

## 2. DMA System

The CPS3 has three independent DMA engines. Their status is tracked in the
`m_dma_status` register (cps3.cpp:1684–1687), read at 0x040C000C:

| Bit | Engine          | Set when…                | Cleared when…            |
|:----|:----------------|:-------------------------|:-------------------------|
| 0   | Sprite-list DMA | DMA starts (line 1404)   | DMA finishes (line 2263) |
| 1   | Character DMA   | DMA finishes (line 2060) | IRQ fires (line 2257)    |
| 2   | Palette DMA     | DMA finishes (line 1832) | IRQ fires (line 2257)    |

### 2.1 Character DMA

Triggered by writing to 0x040C0094–0x040C009B (cps3.cpp:2064–2107, 2140).

**Registers:**

| Offset | Width | Field                                             |
|:-------|:------|:--------------------------------------------------|
| 0x94   | 32    | Source address low 16 bits (written to bits 0–15) |
| 0x98   | 32    | Control + source high bits; bit 22 = start        |

When bit 22 of the second word is set (cps3.cpp:2086), the DMA reads a
**command list** from Character RAM at the combined source address
(cps3.cpp:2088–2092).

**Command list format** (cps3.cpp:2015–2058): Each entry is 3 × 32-bit words
read from Character RAM (little-endian within the array):

```
 Word 0 (dat1):
   Bit 24      = end-of-list marker (1 = stop)
   Bits 23:21  = DMA command (0, 2, 3, or 4)
   Bits 20:0   = (length − 1), in units of 8 bytes

 Word 1 (dat2):
   Bits 31:0   = destination address / 8 (into Character RAM)

 Word 2 (dat3):
   Bits 31:0   = source address / 2 (byte address = dat3 × 2 − 0x400000)
```

**DMA commands:**

| Cmd | Description                | Function             | Reference         |
|-----|----------------------------|----------------------|-------------------|
|  0  | Uncompressed copy          | byte-for-byte        | cps3.cpp:2045–2054|
|  2  | 6bpp RLE decompression     | `do_char_dma()`      | cps3.cpp:1889–1937|
|  3  | 8bpp RLE decompression     | `do_alt_char_dma()`  | cps3.cpp:1971–2008|
|  4  | Set decompression table    | stores table address | cps3.cpp:2033–2036|

**6bpp RLE (command 2)** — `do_char_dma()` (cps3.cpp:1889–1937):
- Reads source bytes from GFX flash.
- If bit 7 is set: use the byte as a 7-bit index into the decompression table
  (set by command 4). Each table entry is 2 bytes; both are passed through
  `process_byte()`.
- If bit 7 is clear: pass the byte directly to `process_byte()`.
- `process_byte()` (cps3.cpp:1845–1887): if bit 6 is set, the low 6 bits + 1
  are an RLE repeat count of the previously written byte. Otherwise write the
  6-bit pixel value to the destination.

**8bpp RLE (command 3)** — `do_alt_char_dma()` (cps3.cpp:1971–2008):
- Reads a control byte, then 8 source bytes.
- For each bit of the control byte (MSB first): if 1, the data byte is a 7-bit
  table index yielding two bytes; if 0, the data byte is written directly.
- `ProcessByte8()` (cps3.cpp:1940–1968): if the last two written bytes are
  equal, the next byte is an RLE count; otherwise write the byte directly.

**IRQ**: When the command list is exhausted, `m_dma_status |= 2` and a ~100 µs
timer is started (cps3.cpp:2060–2061). On expiry, the timer handler clears
`m_dma_status` bits 1–2 and asserts IRQ level 10 (cps3.cpp:2255–2258).

### 2.2 Palette DMA

Triggered by writing to 0x040C00A0–0x040C00AF (cps3.cpp:1793–1836, 2141).

**Registers (4 × 32-bit words):**

| Offset | Field                                  |
|:-------|:---------------------------------------|
| 0xA0   | Source address (GFX flash, word units) |
| 0xA4   | Destination (Colour RAM index)         |
| 0xA8   | Fade value (per-channel 7-bit control) |
| 0xAC   | Length (bits 31:16) + start (bit 1)    |

When bit 1 of offset 0xAC is written (cps3.cpp:1818), the DMA transfers
`length` 16-bit colour values from GFX flash to Colour RAM, applying the fade
value to each entry via `set_mame_colours()` (cps3.cpp:1830).

In the MAME implementation this is a **one-shot transfer**. The start write
enters a tight CPU-side loop in `palettedma_w()` (cps3.cpp:1818–1831), reads
each source colour once, applies the current `m_paldma_fade` once, and writes
the final 15-bit RGB value into Colour RAM immediately. There is no background
state machine here that keeps modifying the palette after the DMA launch.

This is therefore a different class of effect from sprite/tilemap blending:
palette DMA fade modifies the RGB components of palette entries themselves,
whereas sprite/tilemap blend changes the palette-index value used to select a
colour.

The source address is computed as `(paldma_source << 1) − 0x400000`
(cps3.cpp:1798). The length can be 17 bits: bits 31:16 of word 3 provide bits
15:0, and bit 0 of word 3 provides bit 16 (cps3.cpp:1823).

After the transfer, `m_dma_status |= 4` and the same ~100 µs DMA timer fires
(cps3.cpp:1832–1833), ultimately asserting IRQ level 10. In other words, the
~100 µs delay in MAME is only the **DMA completion IRQ latency**; it is not a
gradual fade duration. Any multi-step fade seen by software must come from the
CPU issuing repeated Palette DMA operations with updated fade parameters.

### 2.3 Sprite-List DMA

Triggered by writing to 0x040C0080 (cps3.cpp:1384–1407, 2137).

This is a **display-list preprocessing step**, not a pixel DMA. It reads the
hardware sprite main list and sub-lists from Sprite RAM, resolves the inherited
per-main-entry attributes, and emits a compact 8 kB renderer input buffer in
`m_spritelist` so the renderer uses a consistent snapshot while the CPU updates
Sprite RAM for the next frame.

**Trigger condition** (cps3.cpp:1390): the DMA starts on a falling edge of
bit 0 while bit 3 is set, provided no sprite DMA is already active:
`!(dma_status & 1) && (new & 9) == 8 && (old & 9) == 9`.

**Output buffer size and layout**

- `m_spritelist` is 8 kB total (`0x2000` bytes = 512 32-bit words).
- The buffer is interpreted as 128 consecutive records of 4 words each.
- Each emitted record is one fully resolved draw command for either a sprite or
  a tilemap-style command.
- The final valid record is followed by a **stopper record** whose word 0 is
  `0x80000000`.
- On startup/reset the buffer begins with an immediate stopper, so an empty list
  is represented by the first record being the stopper.

**DMA expansion process** (`spritedma_w()`):
1. Iterate through the hardware main list in Sprite RAM, 4 words per entry.
2. Stop when a main-list word 0 has bit 31 set.
3. Decode from the main-list entry:
   - sub-list base pointer (`(word0 & 0x00007ff0) << 2`)
   - sub-list length (`word0[24:16]`)
   - main-list X/Y offset (`word1[25:16]`, `word1[9:0]`)
   - global-scroll selector (`word0[30:28]`)
   - palette/bpp override enable bits and values
   - global X/Y flip and global alpha-enable bits
4. Fetch the selected global-scroll X/Y pair from `m_ppu_gscroll`.
5. Walk each sub-list entry and emit one flattened 4-word record into the 8 kB
   destination buffer.
6. Stop emitting when there is no room left for another 4-word record plus the
   stopper.
7. Write the stopper record and latch `m_ppu_gscroll` into
   `m_ppu_gscroll_buff`.

**Contents of each copied record**

Each output record is 4 × 32-bit words. Words 2 and 3 are copied verbatim from
the source sub-list entry. Words 0 and 1 are rewritten so the renderer no
longer needs the main-list context.

```
 Copied record word 0:
   Bits 31:17  = tile number (copied from sub-list word 0)
   Bit  12     = final X flip = sub flip XOR main-list global X flip
   Bit  11     = final Y flip = sub flip XOR main-list global Y flip
   Bit  10     = final alpha  = sub alpha OR main-list global alpha
   Bit   9     = final bpp    = sub bpp or main-list override-selected bpp
   Bits  8:0   = final palette index = sub palette or main-list override-selected palette

 Copied record word 1:
   Bits 25:16  = final X = main-list X + sub-list X + selected gscroll X + 1
   Bits  9:0   = final Y = main-list Y + sub-list Y + selected gscroll Y

 Copied record word 2:
   Copied verbatim from the sub-list entry

 Copied record word 3:
   Copied verbatim from the sub-list entry
```

In other words, the 8 kB DMA buffer does **not** contain raw hardware main-list
entries. It contains already-expanded renderer commands where the palette,
colour depth, alpha flag, flip flags, and screen position have already been
resolved.

The important architectural point is that `m_spritelist` is still an **internal
snapshot**, not a second CPU-visible RAM. Software prepares the source data in
Sprite RAM and triggers DMA, but it never reads or addresses the copied list
directly.

**Completion**: `m_dma_status |= 1`, then after ~4 µs `m_dma_status &= ~1`
(cps3.cpp:1404–1405, 2261–2263). No IRQ is generated.

---

## 3. Graphic Layers

The CPS3 renders three types of visual layers, composited in a specific order.

### 3.1 Layer Types

| Layer           | Count | Tile size | Source          | Rendering target     |
|-----------------|-------|-----------|-----------------|----------------------|
| Sprites         | N/A   | 16×16     | Character RAM   | Render buffer        |
| Tilemaps        | 4     | 16×16     | Character RAM   | Render buffer        |
| SS (foreground) | 1     | 8×8       | SS RAM          | Output bitmap        |

### 3.2 Rendering Order and Priority

The rendering order is fixed (cps3.cpp `screen_update`, lines 1086–1310):

```
                   Back
                    │
  ┌─────────────────▼─────────────────────┐
  │  1. Clear render buffer (value 0)     │   cps3.cpp:1119
  │                                       │
  │  2. For each main-list entry:         │   cps3.cpp:1123–1272
  │     ├─ if xsize2==0 → draw tilemap    │   cps3.cpp:1180–1195
  │     └─ else → draw sprite tiles       │   cps3.cpp:1197–1270
  │                                       │
  │  3. Copy render buffer to output      │   cps3.cpp:1274–1305
  │     (with optional full-screen zoom)  │
  │                                       │
  │  4. Draw SS foreground layer          │   cps3.cpp:1307
  └─────────────────┬─────────────────────┘
                    │
                  Front
```

**Key insight**: tilemaps and sprites are **interleaved** within the same
sprite list. A main-list entry with `xsize2 == 0` is a tilemap draw command;
otherwise it is a sprite. This means priority between sprites and tilemaps is
determined by their order in the sprite list — entries drawn later overwrite
earlier ones (painter's algorithm).

The ordering is fully programmable: any tilemap draw command can appear before,
between, or after sprite draw commands, and the same tilemap can be referenced
multiple times in one frame. The only hard limit is that the tilemap selector is
2 bits wide (`tilemapnum = value3[5:4]`, cps3.cpp:1182), so there are only
**four distinct tilemap register banks** (tilemaps 0-3). A frame can therefore
contain more than four tilemap draw operations, but they are redraws/slices of
those same four tilemap definitions.

For these tilemap draw commands, the main-list position fields do **not** behave
like normal sprite X/Y origins. In the MAME implementation, the tilemap branch
does not use the main-list `xpos` at all, and it does not use the main-list
`ypos` either. Instead, it uses the sub-entry `ypos2` together with the selected
global-scroll group's Y value (`gscrolly`) to choose which screen scanlines will
be generated (cps3.cpp:1184–1192):

```c
int cury_pos = ypos2 + gscrolly - yy;
cury_pos = ~cury_pos;
cury_pos -= 18;
```

Once a scanline is selected, the tilemap's actual pixel fetch position comes
from the tilemap register bank itself via `scrollx` and `scrolly` in
`draw_tilemapsprite_line()` (cps3.cpp:1006–1017). So, for tilemaps, the
sprite-list command acts more like a "draw this tilemap on these output lines"
command than a sprite-style X/Y placement command.

The SS foreground is always on top, drawn last directly to the output bitmap
after the render buffer has been copied (with zoom applied).

### 3.3 Tilemap Structure

Each tilemap is a 64×64 grid of 16×16 tiles (1024×1024 virtual pixels). The
tilemap data is stored in Sprite RAM (not in a dedicated tilemap RAM). The base
address within Sprite RAM is specified by the `mapbase` field in the tilemap
registers.

Each tilemap entry is a 32-bit word (cps3.cpp:1034):

```
 Bits 31:17  = tile number (15 bits, max 32768 tiles)
 Bit  15     = tile number bit 16 (for expanded Character RAM; unused in released games)
 Bit  12     = X flip
 Bit  11     = Y flip
 Bit  10     = alpha/blend enable
 Bit   9     = bpp mode (0 = 8bpp/256-colour granularity, 1 = 6bpp/64-colour)
 Bits  8:0   = palette index (9 bits)
```

---

## 4. Sprite Properties

### 4.1 Main Sprite List Entry

Each main-list entry is 4 × 32-bit words (cps3.cpp:1123–1146):

```
 Word 0:
   Bit 31       = end-of-list marker (1 = stop processing)
   Bits 30:28   = global-scroll group index (0–7)
   Bits 24:16   = sub-list length (number of sub-entries)
   Bits 14:4    = sub-list start (× 0x100 >> 2 = byte offset in Sprite RAM)

 Word 1:
   Bits 25:16   = X position (10-bit, signed via wraparound)
   Bits  9:0    = Y position (10-bit, signed via wraparound)

 Word 2:
   Bit 30       = which-bpp selector (use global_bpp vs per-tile bpp)
   Bit 29       = which-palette selector (use global_pal vs per-tile pal)
   Bit 28       = global X flip
   Bit 27       = global Y flip
   Bit 26       = global alpha/blend enable
   Bit 25       = global bpp mode
   Bits 24:16   = global palette index (9 bits)
```

The main list occupies Sprite RAM `0x0000–0x1FFF` (§1.1) and is scanned by
`screen_update()` as:

```c
for (int i = 0; i < 0x2000 / 4; i += 4)
```

(cps3.cpp:1123). Since each record is 4 words = 16 bytes, the hardware-visible
main list has room for **512 entries maximum**. Processing usually stops sooner
when bit 31 of word 0 is set.

### 4.2 Sub-List Entry (Individual Sprite Tile)

Each sub-list entry is 4 × 32-bit words (cps3.cpp:1148–1172):

```
 Word 0 (value1):
   Bits 31:17  = tile number (15 bits)
   Bit  12     = X flip
   Bit  11     = Y flip
   Bit  10     = alpha/blend enable
   Bit   9     = bpp mode
   Bits  8:0   = palette index (9 bits)

 Word 1 (value2):
   Bits 25:16  = X offset (10-bit)
   Bits  9:0   = Y offset (10-bit)

 Word 2 (value3):
   Bits 30:24  = Y draw size − 1 (pixels, 7-bit → max 128)
   Bits 22:16  = X draw size − 1 (pixels, 7-bit → max 128)
   Bits  5:4   = tilemap number (for tilemap-as-sprite commands; jojo/jojoba)
   Bits  3:2   = Y tile count code (0=invalid, 1=1, 2=2, 3=4 via tilestable[])
   Bits  1:0   = X tile count code (0=tilemap cmd, 1=1, 2=2, 3=4)
```

### 4.3 Sprite Sizes

Sprites are **variable-size**. The tile-count codes select 1×1, 1×2, 2×1, 2×2,
up to 4×4 arrangements of 16×16 tiles (cps3.cpp:1154: `tilestable[] = {8,1,2,4}`
— note index 0 maps to 8 but is actually the special tilemap case).

The maximum native tile area is 4×4 tiles = 64×64 pixels, but the draw size
(xsizedraw2 × ysizedraw2) can be up to 128×128 pixels through hardware scaling.

So, with **no scaling** (`xscale = yscale = 0x10000`), a sprite is **not**
limited to a single 16×16 tile. One sprite command can be assembled from a
packed rectangular array of tiles:

- 1×1 tile = 16×16 pixels
- 1×2 or 2×1 tiles = 16×32 or 32×16 pixels
- 2×2 tiles = 32×32 pixels
- 4×4 tiles = 64×64 pixels maximum

The renderer walks this tile array with:

```c
for (int xx = 0; xx < xsize2 + 1; xx++)
for (int yy = 0; yy < ysize2 + 1; yy++)
    cps3_drawgfxzoom(..., tileno + count, ...);
```

(cps3.cpp:1238–1268), incrementing `count` for each tile. This means the tiles
for one sprite are taken as a **contiguous sequence** in Character RAM,
starting at `tileno`, and packed together into one larger meta-sprite.

### 4.4 Sprite Scaling (Zoom)

Sprites support independent X and Y scaling via 16.16 fixed-point factors
(cps3.cpp:1202–1206):

```c
xinc = (xsizedraw2 << 16) / xsize2;  // pixels-per-tile in 16.16
yinc = (ysizedraw2 << 16) / ysize2;
xscale = xinc / 16;                   // scale factor for 16-pixel tiles
yscale = yinc / 16;
```

A scale of `0x10000` (1.0) is identity. Scales < 1.0 shrink, > 1.0 enlarge.

The actual pixel rendering is done by `cps3_drawgfxzoom()` (cps3.cpp:614–801),
which iterates over destination pixels, sampling source pixels at the
appropriate rate based on the scale factor.

### 4.5 Sprite Flip

- **Per-tile flip**: bits 12 (X) and 11 (Y) of the sub-list word 0.
- **Global flip**: bits 28 (X) and 27 (Y) of the main-list word 2.
- These are XORed together (cps3.cpp:1216–1217): `flipx ^= global_xflip`.

### 4.6 Sprite Positioning

Position is 10-bit with sign extension via wraparound (cps3.cpp:1247–1248,
1258–1262):

```c
current_xpos &= 0x3ff;
if (current_xpos & 0x200) current_xpos -= 0x400;  // sign extend
```

The Y coordinate is inverted: `current_ypos = 0x3ff - current_ypos - 17`
(cps3.cpp:1258–1259). The −17 is a hardware vertical offset.

Each main-list entry specifies a **global-scroll group** (3 bits, index 0–7).
The scroll values from `m_ppu_gscroll_buff[group]` are added to the sprite
position (cps3.cpp:1144–1145, 1245, 1257).

This full X/Y addition applies to the sprite path. For tilemap commands
(`xsize2 == 0`), MAME only uses the selected group's `gscrolly` in the outer
tilemap dispatch loop; `gscrollx`, main-list `xpos`, and main-list `ypos` are
not applied as tilemap origin coordinates there (cps3.cpp:1179–1195). The
tilemap's horizontal and vertical scrolling instead comes from the tilemap PPU
registers (`regs[0]`) inside `draw_tilemapsprite_line()` (cps3.cpp:1006–1017).

### 4.7 Transparency and Blending

Three transparency modes are used (cps3.cpp:606–612):

| Mode                                | Effect                        |
|:------------------------------------|:------------------------------|
| `CPS3_TRANSPARENCY_PEN`             | Pixel index 0 is transparent  |
| `CPS3_TRANSPARENCY_PEN_INDEX`       | Write palette index to buffer |
| `CPS3_TRANSPARENCY_PEN_INDEX_BLEND` | Shadow/highlight blending     |

The blend mode (cps3.cpp:758–796) does not write a colour — it modifies the
existing framebuffer pixel by ORing bits into the upper palette index bits:

- **64-colour granularity (6bpp)**: `dest |= (c & 0xf) << 13` — used for
  spotlight effects (sfiii world map).
- **256-colour granularity (8bpp)**: `dest |= ((c & 1) << 15) | ((color & 1) << 16)`
  — used for shadow effects (jojo, warzard swords, sf games).

This is a **palette manipulation effect**, not true alpha blending. The ORed
bits shift the colour lookup into a different palette region where darker or
highlighted versions of the underlying colour are stored.

So, for sprites, the blend operation happens in the indexed render-buffer
domain, before RGB conversion. The renderer first modifies the stored
palette+pen index, and only later converts the final 17-bit index into RGB when
copying the render buffer to the output bitmap.

For sprites, the blend path is selected when either the per-tile `alpha` bit or
the main-list `global_alpha` bit is set (cps3.cpp:1160, 1235). The source pixel
still treats pen 0 as transparent; only non-zero source pixels affect the
destination.

### 4.8 Sprite Pixel Data Layout

Sprites use 16×16 pixel tiles stored in Character RAM. Two formats exist:

**8bpp (256 colours)** — `cps3_tiles16x16_layout` (cps3.cpp:909–919):
- 8 bitplanes, packed as 8 bits per pixel.
- Row stride = 16 pixels × 8 bits = 128 bits = 16 bytes.
- Tile size = 16 rows × 16 bytes = 256 bytes.
- Pixel order within a row is reversed in groups of 8:
  `{3,2,1,0,7,6,5,4,11,10,9,8,15,14,13,12}` (column indices).

**6bpp mode**: uses the same 8bpp layout but with `granularity = 64` instead of
256 (cps3.cpp:1045, 1233), meaning only the low 6 bits of each pixel value
select within a 64-colour palette group.

---

## 5. Tile Properties

### 5.1 Background Tilemap Tiles (16×16)

Tilemap tiles share the same Character RAM pixel data and layout as sprite tiles
(§4.8). Each tile in the tilemap map is a 32-bit word with these fields
(cps3.cpp:1034–1041):

| Bits  | Field  | Description                       |
|:------|:-------|:----------------------------------|
| 31:17 | tileno | Tile number (index into Char RAM) |
| 12    | xflip  | Horizontal flip                   |
| 11    | yflip  | Vertical flip                     |
| 10    | alpha  | Blend enable                      |
| 9     | bpp    | 0 = 8bpp, 1 = 6bpp                |
| 8:0   | colour | Palette group (9-bit index)       |

Tiles can be individually flipped in X and Y. The tilemap also supports
**global flip** via the tilemap register control word (cps3.cpp:1009–1010):
`global_flip_x` (bit 11) and `global_flip_y` (bit 10) of `regs[1]`.

Tilemap pixels are not opaque by default. `draw_tilemapsprite_line()` selects
either `CPS3_TRANSPARENCY_PEN_INDEX` or `CPS3_TRANSPARENCY_PEN_INDEX_BLEND`
(cps3.cpp:1043), both with transparent pen value 0. So:

- pixel value 0 leaves the previously drawn render-buffer pixel unchanged
- non-zero pixels either write a new palette index (normal mode) or modify the
  existing palette index bits in place (blend mode)

As a result, earlier sprite/tilemap layers remain visible wherever the current
tilemap contributes pen 0.

Bit 10 (`alpha`) in each tilemap entry does **not** request conventional
per-pixel alpha. It switches the tile from normal indexed drawing to the same
palette-index blend mode used by sprites. In MAME this works as follows:

- in 8bpp / 256-colour mode: `dest |= ((c & 1) << 15) | ((colour & 1) << 16)`
- in 6bpp / 64-colour mode: `dest |= (c & 0xf) << 13`

So the tile's pixel data does not replace the destination colour. Instead, it
ORs extra bits into the palette index already present in the render buffer,
selecting a shadow/highlight variant of the previously drawn layer.

Again, this is an indexed-colour effect, not direct arithmetic on RGB pixel
components. The RGB conversion happens later, after the render buffer contents
have been finalized.

### 5.2 SS Foreground Tiles (8×8)

SS tiles are 4bpp, 8×8 pixels. The layout is defined by `cps3_tiles8x8_layout`
(cps3.cpp:923–932):

- 4 bitplanes, packed as 4 bits per pixel.
- Row stride = 8 pixels × 4 bits = 32 bits = 4 bytes.
- Tile size = 8 rows × 4 bytes = 32 bytes.
- Pixel order within a row: `{1,0,3,2,5,4,7,6}`.

Each SS tilemap entry is 16 bits (cps3.cpp:1071–1075):

```
 Bit  15    = X flip
 Bit  14    = Y flip
 Bits 13:9  = palette group (5 bits, added to ss_pal_base << 5)
 Bits  8:0  = tile number (9 bits, max 512 tiles)
```

The tile pixel data is stored in SS RAM at offset 0x4000 and above
(cps3.cpp:980, 1326–1327). Up to 512 tiles × 32 bytes = 16 KB of tile data.

---

## 6. Palette System

### 6.1 Colour RAM Size and Organization

Colour RAM holds **0x20000 (131,072) 16-bit entries** = 256 KB total
(cps3.h:41, cps3.cpp:2130). The entries are stored big-endian.

Each entry is a 15-bit RGB colour (cps3.cpp:945–964):

```
 Bit 15     = unused (preserved during palette DMA fade)
 Bits 14:10 = Blue  (5 bits, 0–31)
 Bits  9:5  = Green (5 bits, 0–31)
 Bits  4:0  = Red   (5 bits, 0–31)

 Output to DAC: each channel is left-shifted by 3 (5→8 bit),
 with lower 3 bits tied to GND (cps3.cpp:964).
```

The colour RAM has a 16-bit interface with the CPU as it is made of two individual 128kB chips.

### 6.2 Palette Indexing

The palette is addressed as a flat 17-bit index (0x00000–0x1FFFF). The index
is computed as:

```
palbase = granularity × colour_field
```

Where `granularity` is 256 (8bpp mode) or 64 (6bpp mode), and `colour_field`
is the 9-bit palette value from the sprite/tile entry. The pixel value from the
tile data is added to `palbase` to form the final Colour RAM index
(cps3.cpp:644, 752).

**Examples:**
- 8bpp, colour=5: palbase = 256 × 5 = 1280. Pixel values 0–255 select entries
  1280–1535.
- 6bpp, colour=5: palbase = 64 × 5 = 320. Pixel values 0–63 select entries
  320–383.

The 17-bit index space means up to 512 palette groups of 256 colours, or 2048
groups of 64 colours, all within the 128K entry Colour RAM.

### 6.3 SS Palette

The SS layer uses a separate palette base register (`m_ss_pal_base`, set via SS
register offset 0x12, cps3.cpp:1779). The 5-bit palette field from each SS tile
entry is combined with this base (cps3.cpp:1076):

```c
pal += m_ss_pal_base << 5;
```

Since SS tiles use 4bpp (16 colours), the SS draws through `gfx(0)` with
the default granularity of 16 (cps3.cpp:980). So the final colour index is:
`16 × pal + pixel_value`.

This means the SS layer is **not restricted to a small dedicated palette
window**. In the MAME model:

- `m_ss_pal_base` is written as an 8-bit register value (cps3.cpp:1779)
- each SS tile contributes a 5-bit palette field (`data[13:9]`, cps3.cpp:1073)
- together they form a 13-bit palette selector: `pal = (ss_pal_base << 5) + tile_pal`

That yields `256 × 32 = 8192` possible SS palette groups. At 16 colours per
group, the SS layer can address `8192 × 16 = 131072` palette entries, which is
exactly the full 128K-entry Colour RAM space.

### 6.4 No Strict Sprite/Tilemap Palette Partitioning

There is **no hardware-enforced separation** between sprite and tilemap palette
areas. Both share the same Colour RAM. The 9-bit colour field in each
sprite/tile entry is free to point anywhere in the 128K colour space. Software
convention typically assigns different ranges, but the hardware does not enforce
this.

### 6.5 Palette DMA Fade

During Palette DMA, each transferred colour can be faded per-channel using the
`m_paldma_fade` register (cps3.cpp:1806, 945–958). The fade value is a 32-bit
word with three 7-bit fields:

```
 Bits 30:24 = Red fade   (7 bits)
 Bits 22:16 = Green fade (7 bits)
 Bits  6:0  = Blue fade  (7 bits)
```

Each channel's fade byte (cps3.cpp:934–942):
- Bit 6: enable (0 = pass through, 1 = apply fade)
- Bit 5: mode (0 = fade to black, 1 = fade to white)
- Bits 4:0: fade amount (0 = full fade, 31 = no fade)

```c
// Fade to black: c = c * fade_amount / 32
// Fade to white: c = 31 - ((31 - c) * (31 - fade_amount) / 32)
```

Timing-wise, the fade is **not** an autonomous palette effect that continues
after DMA start. In MAME, `set_mame_colours()` is called once per transferred
entry from inside the Palette DMA loop (cps3.cpp:1823–1830), so each colour is
converted exactly once for that DMA command. Once the loop ends, the palette is
already in its faded state; the later timer callback only clears DMA status
bits and raises IRQ 10 (cps3.cpp:2255–2258).

So, if a game performs a smooth fade over several frames, the driver model says
it must be doing so under CPU control by launching multiple Palette DMA passes,
not by arming a hardware fade sequencer and letting it run unattended.

---

## 7. Full-Image Effects

This section separates two different questions:

- what the **CPS3 register interface clearly suggests the hardware can do**
- what **MAME currently does** in order to render games correctly enough

The distinction matters because the CRTC/zoom register block is only partially
understood in MAME.

### 7.1 What Can Be Stated About CPS3 Hardware

From the register map alone, the CPS3 exposes a CRTC-style block with:

- normal horizontal timing fields: `h_sync_width`, `h_blank_end`,
  `h_screen_end`, `h_total_end`
- normal vertical timing fields: `v_sync_end`, `v_blank_end`,
  `v_screen_end`, `v_total_end`
- a separate horizontal zoom group: `h_zoom_mstr`, `h_zoom_off`,
  `h_zoom_size`, `h_zoom_scl`
- a separate vertical zoom group: `v_zoom_mstr`, `v_zoom_off`,
  `v_zoom_size`, `v_zoom_scl`

Those names come directly from [`mmr.yaml`](/home/jtejada/jtcores/cores/cps3/cfg/mmr.yaml).
At minimum, this tells us the video hardware exposes more than just simple
sprite/tile scaling. There is a dedicated set of registers for a whole-image or
CRTC-level transform.

What is reasonably solid at the hardware-behavior level:

- `h_blank_end`/`h_screen_end` and `v_blank_end`/`v_screen_end` are part of the
  visible-area definition.
- `h_zoom_scl` and `v_zoom_scl` are very likely scale controls for a global
  image transform.
- `h_zoom_mstr`, `h_zoom_off`, `h_zoom_size`, `v_zoom_mstr`, `v_zoom_off`, and
  `v_zoom_size` are real hardware registers and probably participate in that
  same transform.

What is **not** established from the available evidence:

- the exact mathematical meaning of `*_zoom_mstr`, `*_zoom_off`, and
  `*_zoom_size`
- whether the transform is truly a framebuffer scaler, a display-window scaler,
  or some other CRTC-domain effect
- the exact numeric interpretation of the scale fields on original hardware
- whether hardware clamps, wraps, or otherwise special-cases out-of-range zoom
  values the same way MAME does

So the safest hardware statement is: CPS3 definitely has a global zoom/display
control block, but only part of its behavior is confirmed by the current
emulator.

### 7.2 What MAME Implements

MAME models the effect as a **post-render full-screen scale** applied after the
main sprite/tilemap render buffer has been produced (cps3.cpp:1088–1307).

The implemented path is:

1. Draw sprites and tilemaps into `m_renderbuffer_bitmap`.
2. Read a horizontal and vertical zoom value from the CRTC block.
3. Copy from the render buffer to the output bitmap with optional resampling.
4. Draw the SS foreground after that copy.

In `screen_update()`, MAME uses only these two fields for the scaling step:

```c
u32 fullscreenzoomx = m_ppu_crtc_zoom[3] & 0x000000ff;
u32 fullscreenzoomy = m_ppu_crtc_zoom[7] & 0x000000ff;
```

That corresponds to `h_zoom_scl` and `v_zoom_scl`. The scale is converted with:

```c
fszx = (fullscreenzoomx << 16) / 0x40;
fszy = (fullscreenzoomy << 16) / 0x40;
```

So in MAME:

| Register value | MAME interpretation |
|:---------------|:--------------------|
| `0x40`         | 1.0x (identity)     |
| `0x20`         | 0.5x                |
| `0x80`         | 2.0x                |

MAME also clamps both values to `0x80` before applying the scale
(cps3.cpp:1103–1104). That clamp is an emulator policy, not a proven hardware
rule.

When the scale is `0x40`, MAME copies the render buffer 1:1
(cps3.cpp:1274–1287). Otherwise it samples source pixels from the render buffer
with the computed fixed-point step (cps3.cpp:1288–1305).

This is an implementation detail of the emulator. It should not be read as
proof that the original hardware literally contained a 1024×448 software-style
framebuffer and then performed the same copy loop. MAME uses that structure
because it is a convenient way to reproduce the visible result.

### 7.3 Registers Present In Hardware But Not Modeled By MAME

MAME currently does **not** use these zoom-related registers in its renderer:

| Address | MMR name | MAME status |
|:--------|:---------|:------------|
| `0x68`  | `h_zoom_mstr` | stored, not used in rendering |
| `0x6A`  | `h_zoom_off`  | stored, not used in rendering |
| `0x6C`  | `h_zoom_size` | stored, not used in rendering |
| `0x78`  | `v_zoom_mstr` | stored, not used in rendering |
| `0x7A`  | `v_zoom_off`  | stored, not used in rendering |
| `0x7C`  | `v_zoom_size` | stored, not used in rendering |

This is the clearest line between CPS3 and MAME:

- on **CPS3**, those registers exist and are almost certainly meaningful
- in **MAME**, they currently have no effect on the rendered picture

The most plausible reading of the register names is:

- `*_zoom_off`: source offset or window origin
- `*_zoom_size`: source size or zoom-window span
- `*_zoom_mstr`: master reference, center, or coarse origin term

But that is still an inference from naming and register grouping, not a
confirmed hardware description.

### 7.4 Dynamic Visible Area

Dynamic screen sizing is better supported by the current evidence than the full
zoom model.

In MAME, visible width and height are derived from:

```c
width  = (m_ppu_crtc_zoom[1] >> 16) - (m_ppu_crtc_zoom[0] & 0xffff);
height = (m_ppu_crtc_zoom[5] >> 16) - (m_ppu_crtc_zoom[4] & 0xffff);
```

Those correspond to:

- width  = `h_screen_end - h_blank_end`
- height = `v_screen_end - v_blank_end`

This matches the naming in the CRTC register block and is a reasonable
hardware-level interpretation, not just an arbitrary emulator trick. MAME
reconfigures the visible area when these values change (cps3.cpp:1089–1097).
Common outputs are 384×224 and 496×224.

### 7.5 No Evidence For Whole-Screen Rotation

Nothing in the known register set or the MAME driver suggests a dedicated
rotation stage for the final image. If games need rotation-like effects, the
current evidence points to them being built from ordinary sprite/tilemap motion
rather than a hardware full-image rotator.

---

## 8. Rendering Architecture

### 8.1 Framebuffer-Based Rendering

The CPS3 uses a **framebuffer architecture** for its main graphics layers.

The render buffer (`m_renderbuffer_bitmap`) is a 1024×448 bitmap
(cps3.cpp:990). During `screen_update()` (called once per frame during vblank):

1. The active clip region of the render buffer is selected according to the
   current full-screen zoom state, then only that region is cleared
   (cps3.cpp:1108–1119).
2. All sprites and tilemaps are drawn into the render buffer by iterating the
   sprite list (cps3.cpp:1123–1272).
3. The render buffer is copied to the screen output bitmap, applying full-screen
   zoom if needed (cps3.cpp:1274–1305).
4. The SS foreground is drawn directly on top of the output bitmap
   (cps3.cpp:1307).

Important clarification: the render path does **not** guarantee that every
pixel of the 1024×448 buffer is touched every frame, nor that the tilemaps
cover all of it every frame. Tilemaps are drawn only when the sprite list
contains tilemap draw commands, and only for the output lines those commands
request. Sprites likewise affect only the positioned/scaled tile areas they
cover.

This is distinct from the direct-rendering approach used by older arcade systems
where sprites are rendered line-by-line in real time. In the CPS3, the CPU
pre-builds the sprite list, triggers sprite-list DMA during vblank, and the
rendering is performed as a batch operation on the buffered copy.

### 8.2 Double Buffering via Sprite-List DMA

The sprite-list DMA (§2.3) provides partial double-buffering:

```
 Frame N vblank:
   1. Sprite-list DMA copies main/sub-list entries → m_spritelist
   2. Global scroll values are latched → m_ppu_gscroll_buff
   3. Renderer reads m_spritelist for sprite entries

 Frame N+1 active:
   CPU freely updates Sprite RAM for frame N+1
```

Tilemap tile data and linescroll values are **not** part of the DMA snapshot.
The renderer reads these directly from live Sprite RAM (`m_spriteram`) during
`draw_tilemapsprite_line()` (cps3.cpp:1034, 1028). Only the sprite list
structure and global scroll registers are protected by the DMA copy.

### 8.3 SS Layer: Direct Rendering

The SS foreground is rendered **directly** to the output bitmap, not through the
render buffer. It bypasses the full-screen zoom, so it always appears at native
resolution. This is typical for score/status overlays that should remain
sharp regardless of gameplay zoom effects.

### 8.4 Colour Lookup Stage

The render buffer stores **palette indices** (17-bit values), not final RGB
colours. The colour lookup happens during the copy-to-output stage
(cps3.cpp:1284, 1300):

```c
dstbitmap[renderx] = m_mame_colours[srcbitmap[renderx] & 0x1ffff];
```

This late-binding approach means palette changes (including DMA fade effects)
are applied to the entire frame atomically during the buffer copy.

---

## 9. PPU Registers

All PPU registers are mapped at 0x040C0000. The following tables use byte
offsets from that base address.

### 9.1 Global Scroll Registers (0x00–0x1F)

8 scroll pairs, each 32 bits (cps3.cpp:2134, cps3.h:96):

| Offset   | Bits  | Field              |
|:---------|:------|:-------------------|
| 0x00+n×4 | 25:16 | Scroll X (10 bits) |
| 0x00+n×4 | 9:0   | Scroll Y (10 bits) |

Where n = 0–7. These are latched into `m_ppu_gscroll_buff` during sprite-list
DMA (cps3.cpp:1402) and used as position offsets for sprites assigned to each
scroll group.

### 9.2 Tilemap Registers (0x20–0x5F)

4 tilemaps, each with 4 × 32-bit registers = 16 bytes (cps3.cpp:2135,
cps3.h:97, usage in lines 1002–1051):

| Offset    | Bits  | Field                            |
|:----------|:------|:---------------------------------|
| 0x20+n×16 | 31:16 | Scroll X (16 bits)               |
| 0x20+n×16 | 15:0  | Scroll Y (16 bits)               |
| 0x24+n×16 | 15    | Enable (1=draw)                  |
| 0x24+n×16 | 14    | Line-scroll enable               |
| 0x24+n×16 | 11    | Global X flip                    |
| 0x24+n×16 | 10    | Global Y flip                    |
| 0x28+n×16 | 30:24 | Line-scroll base (7 bits, ×1024) |
| 0x28+n×16 | 22:16 | Tile-map base (7 bits, ×1024)    |

Where n = 0–3.

**Scroll Y** has a +4 adjustment applied in hardware/MAME (cps3.cpp:1016).

**Line-scroll**: when enabled, each scanline adds an additional X scroll value
read from Sprite RAM at `linebase + ((line + 16) & 0x3FF)`, bits 25:16
(cps3.cpp:1028). Test case: sfiii Ryu's stage 2nd round floor.

**Map base**: the tilemap data is at `Sprite_RAM[mapbase × 1024]`. Each tilemap
is 64 columns × 64 rows of 32-bit tile entries.

### 9.3 CRTC / Zoom Registers (0x60–0x7F)

8 × 32-bit registers (cps3.cpp:2136, cps3.h:98):

| Index | Offset | Function                           |
|-------|--------|------------------------------------|
| 0     | 0x60   | H zoom: screen start (low 16)      |
| 1     | 0x64   | H zoom: screen end (high 16)       |
| 2     | 0x68   | H zoom: unknown / master           |
| 3     | 0x6C   | H zoom: scale (low 8 bits)         |
| 4     | 0x70   | V zoom: screen start (low 16)      |
| 5     | 0x74   | V zoom: screen end (high 16)       |
| 6     | 0x78   | V zoom: unknown / master           |
| 7     | 0x7C   | V zoom: scale (low 8 bits)         |

Screen dimensions derived from these (cps3.cpp:1088, 1094):

```
width  = crtc_zoom[1][31:16] − crtc_zoom[0][15:0]
height = crtc_zoom[5][31:16] − crtc_zoom[4][15:0]
```

Full-screen zoom: `crtc_zoom[3][7:0]` and `crtc_zoom[7][7:0]`, where 0x40 = 1:1.

### 9.4 Config Registers (0x80–0x8B)

| Offset | Function                              | Reference          |
|--------|---------------------------------------|--------------------|
| 0x80   | Sprite-list DMA control (low 16)      | cps3.cpp:2137      |
| 0x84   | Character RAM bank select (bits 2:0)  | cps3.cpp:2138      |
| 0x88   | GFX flash bank select (bits 31:16)    | cps3.cpp:2139      |

### 9.5 DMA Registers (0x94–0xAF)

See [§2.1](#21-character-dma) and [§2.2](#22-palette-dma) for detailed
field descriptions.

### 9.6 SS Registers (0x05050000)

Written as odd bytes only (`umask32 0x00FF00FF`), handled in `ssregs_w()`
(cps3.cpp:1762–1787):

| Offset | Field                                 |
|--------|---------------------------------------|
| 0x07   | H scroll low byte                     |
| 0x08   | H scroll high byte                    |
| 0x10   | V scroll low byte                     |
| 0x11   | V scroll high byte                    |
| 0x12   | Palette base                          |
| 0x14   | Unknown (write ignored)               |

**SS Scroll limitations:**

- **V scroll**: only bit 8 is effective — `(-ss_vscroll) & 0x100`
  (cps3.cpp:1056) — giving a 0 or 256 pixel vertical jump, not smooth
  scrolling.
- **H scroll register** (`m_ss_hscroll`, offsets 0x07/0x08): written by the
  CPU but **never read** by the rendering code (`draw_fg_layer()`). It is dead
  state in the current MAME emulation.
- **Actual horizontal scrolling** comes from a per-row scroll table in SS RAM
  at offset 0x2000 (cps3.cpp:1067). Each scanline reads its own 8-bit scroll
  value, enabling line-by-line horizontal displacement (used by the JoJo combo
  meter).

---

## 10. CPU–PPU Communication

### 10.1 Register Write Access

The CPU writes PPU registers at 0x040C0000–0x040C00AF. Most are **write-only**:
- Global scroll (0x00–0x1F): write-only (cps3.cpp:2134).
- Tilemap regs (0x20–0x5F): write-only (cps3.cpp:2135).
- CRTC zoom (0x60–0x7F): write-only (cps3.cpp:2136).

### 10.2 Read-Back Registers

Very few registers are readable by the CPU:

| Address      | Register          | Reference        |
|--------------|-------------------|------------------|
| 0x040C000C   | DMA status (16-bit) | cps3.cpp:2133  |
| 0x040C0000–7 | Unknown (reads return 0, warzard reads but ignores) | cps3.cpp:2132 |

The DMA status register reports the state of all three DMA engines (§2).

### 10.3 Video Memory Read-Back

The CPU has full read/write access to:
- **Sprite RAM** (0x04000000): cps3.cpp:2129
- **Colour RAM** (0x04080000): cps3.cpp:2130
- **Character RAM window** (0x04100000, banked): cps3.cpp:2145
- **SS RAM** (0x05040000): cps3.cpp:2156

### 10.4 Interrupt System

Two video-related interrupts:

| IRQ Level | Source        | Trigger                              | Acknowledge Address |
|-----------|---------------|--------------------------------------|---------------------|
| 12        | VBlank        | Screen vblank rising edge            | 0x05100000          |
| 10        | DMA complete  | Character or Palette DMA finishes    | 0x05110000          |

**VBlank IRQ** (cps3.cpp:2248–2252): asserted on the vblank edge of the screen
device. Cleared by any write to 0x05100000 (cps3.cpp:2159).

**DMA IRQ** (cps3.cpp:2255–2258): asserted ~100 µs after Character DMA or
Palette DMA completes. Cleared by any write to 0x05110000 (cps3.cpp:2160).
The timer handler also clears `m_dma_status` bits 1 and 2.

Two additional IRQ clear addresses exist at 0x05120000 (level 14) and
0x05130000 (level 6) but appear unused in released games (cps3.cpp:2161–2162).

### 10.5 Sprite-List DMA as Synchronization

The sprite-list DMA serves as the primary CPU–PPU synchronization mechanism:

1. During active display, the CPU prepares the next frame's sprite data in
   Sprite RAM.
2. On vblank, the CPU triggers sprite-list DMA (write to 0x040C0080).
3. The DMA copies Sprite RAM to the internal buffer and latches scroll values.
4. The renderer uses the buffered copy, immune to CPU writes.

This eliminates tearing artifacts without requiring the CPU to double-buffer
its own sprite data.

### 10.6 No PPU-Generated Status Feedback

The PPU does not report rendering status (such as sprite overflow or line
counters) to the CPU. The only dynamic status readable from the PPU region is
the DMA status register at 0x040C000C. The CPS3 PPU is simpler than some
contemporaries in this regard — it relies on software timing (vblank IRQ)
rather than hardware status signals for frame synchronization.
