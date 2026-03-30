# Video dump

When CTRL+F11 is pressed in the CPS3 driver, a dump of the video memory should be created.

The files should be dumped to debug/setname in the configuration MAME homepath. Where setname is the game name specified in the GAME declaration at the bottom of the driver file

The following elements should be dumped

# SS memory

Details

- The SS video memory is only used on odd bytes, so the unused bytes should not be dumped
- Divide the dump in three files
	- sschar.bin, tile pixel data, CPU offset range: 0x8000-0xFFFF, file size 16kB
	- ssmap.bin, tilemap layout, CPU offset range: 0x0000-0x3FFF, file size 8kB
	- ssscr.bin, per-line scroll, CPU offset range: 0x4000-0x7FFF, file size 8kB
- The SS configuration registers, should be dump to ssreg.bin. These registers are mapped at 0x05050000 but only odd bytes are accessed.

# Tile Characters

Dump the 8MB character tiles to a file called tilechar.bin

# Sprite Buffer DMA

Dump the 8kB sprite buffer to a file called objdma.bin

# Palette

The full 256kB of the palette memory should be dumped to pal.bin

# Compilation

Use the script mkmame.sh without arguments to compile MAME.