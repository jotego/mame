# CPS3 Per-line stats

I am working on a FPGA implementation of the CPS3 system. For that purpose, I
plan to implement a cache memory that has a copy of the graphics data that is
needed. The goal of this task is to modify the MAME cps3.cpp driver so it has
an auxiliary C++ class that keeps track of the memory requirements of each frame,
so I can evaluate how the design of the FPGA cache system needs to be.

## The PPU

The implemented PPU (Picture Processing Unit) will parse the layers one
at a time, like MAME. The layers will be drawn line by line. For each line, the
system needs to read tile data or sprite character data from memory.

## The Cache system

The FPGA uses a external SDRAM memory that operates in bursts. It is not possible
to read just the data for one tile or sprite character. The SDRAM will always
deliver adjacent information because of the burst operation. The FPGA system
will use a small cache to minimize the number of SDRAM accesses.

Let's assume I use a burt size of 1kB. If the tiles have a size of 16x16 pixels
and each pixel is one byte, then in 1kB there will be 4 tiles. If the tilemap
is drawing adjacent tiles, the tile data will already be cached, and it will
not require a new SDRAM access. There are multiple 1kB cache blocks available
for the tilemap. Each time we need a tile that is not cached, one of the cache
blocks is randomly dropped and replace by the required one.

When accessing the SDRAM, the tile code is masked to clear the lower 2 bits. If
for example the code of the required tile is 0x12345, then the cached data will
contain from code 0x12344 to 0x12347. This makes it easy to compare required
codes with cache contents and determine whether a SDRAM access is required or not.

### Cache Emulator

Create a class in cps3.cpp to emulate the cache. The driver will not read data
from the cache. You do not need to change how the image is rendered in MAME. The
class needs to know which tiles are cached in the each block.

Each time a new tile is required while drawing a frame, the class will evaluate
whether the tile exists in cache or not. If it does not exist, it will discard
one block following either a random strategy or LRU strategy (Least Recently
Used), and assign the required code range to that block. The cache class does
not need to retrieve or store any actual image data. It only has to keep track
of how many SDRAM requests will occur when the system is implemented on FPGA.

Note that the drawing must be tracked for both tiles in the tilemap and _tiles_
for the sprites. For this purpose a _sprite character_ and a _sprite tile_ refer
to the same concept: a 16x16 pixel graphics chunk. As the 8MB character RAM is
shared by both the tilemap and sprite rendering engines, it makes sense that a
single cache is used for both.

Special care is needed for sprites that take multiple characters, like 32x16
instead of 16x16. These sprites have a rule to determine which codes are used
for each part. If the MAME code is already breaking up this multi-char sprites
and drawing each 16x16 component individually, then you can keep track of char
code requests at that point. The important thing is to correctly count all codes
of the multi-char sprites.

The size of the tile cache can be configured to be:

- 256, 128, 64, 32, 16, 8 blocks
- 32, 16, 8 or 4 tiles cached per block

Important: The tiles are consequitive in memory. The first tile in the cache
block has its LSB bits at zero, like this:

| Block size |  Masked bits    |
|------------|-----------------|
|   4        | 1:0             |
|   8        | 2:0             |
|  16        | 3:0             |
|  32        | 4:0             |
|  64        | 5:0             |

It is possible to select via MAME UI menu the number of tile cache blocks and
the size of each block among the options given above. Whether the cache uses a
random strategy or a LRU strategy can be set in the menu too.

The cached tiles are preserved between frames. Cache data is only replaced by
new data when needed but never cleared.

## Tilemap Stats

While drawing tilemaps, use the cache emulator to keep track of the required
SDRAM access.

Calculate these metrics per frame:

- total number of unique tile codes used
- total number of SDRAM requests (cache failures)
- tile Cache size in kB: calculated as block x tiles divided by 4
- Tiles SDRAM usage: calculated as tile SDRAM requests x tiles per block x 256 divided by
the FPGA clock (85909000) x screen frame rate (59.59) x 100. Do not display
decimals and add a % sign. Add one-digit zero padding.

Every 20 frames, report the average of the metrics above.

Print this information as a screen overlay in MAME. Join similar items in the
same line so the overlay is not too tall.

# Compilation

Compile mame to work only with the cps3.cpp driver in order to increase
compilation speed. Call the compiled executable `cps3`.

# References

You can read cps3-gfx.md for a summary description of how CPS3 graphics work.