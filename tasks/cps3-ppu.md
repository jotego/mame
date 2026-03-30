# Create a dump of CPS3 PPU registers at exit

The following PPU registers should be dumped, in this order:

- H sync end, at: 0x60, 0x61
- H blank end, at: 0x62, 0x63
- H screen end, at: 0x64, 0x65
- H total end, at: 0x66, 0x67
- H zoom master, at: 0x68[1:0], 0x69
- H zoom offset, at: 0x6A, 0x6B
- H zoom size, at: 0x6C, 0x6D
- H zoom scale, at: 0x6E, 0x6F
- V sync end, at: 0x70, 0x71
- V blank end, at: 0x72, 0x73
- V screen end, at: 0x74, 0x75
- V total end, at: 0x76, 0x77
- V zoom master, at: 0x78[1:0], 0x79
- V zoom offset, at: 0x7A, 0x7B
- V zoom size, at: 0x7C, 0x7D
- V zoom scale, at: 0x7E, 0x7F
- pixel clock divider, at: 0x81[2:0]

Most of these probably exist already as class properties and can be taken
directly from there.

The dump must be done at exit to the folder to the path `homepath/debug/setname`
where `homepath` is a MAME setting (set in mame.ini) and setname is the game
setname given in the driver. The file should be called: `vtimer.md`

# tasks

- Modify the MAME source code to dump the CPS3 PPU registers
