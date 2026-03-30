# Goal

The goal is to modify MAME so it can dump the current emulated tile map to a file.

# Abstract

Many MAME drivers use tile maps to produce graphics. This tile maps are a basic class of the MAME design. During game play, the user can press F4 to access to a graphics inspector window. In this window, first the current game palette is shown. When the user presses enter, we switch to a dump of the graphics ROMs. Pressing enter again displays the current tile map.

The user can then hover the mouse over it. The tile code and tile attributes for the tile pointed at by the mouse are displayed. If there are more than one tilemap, the user can use the +/- keys to cycle through them.

MAME can also save snapshots to the folder ~/.mame/snap/game-name by pressing the F12 key.

The goal is to create a JSON dump of the all the tilemaps in the folder ~/.mame/tilemap/game-name/tilemap-##.json when SHIFT+F12 is pressed.

# Details

The JSON should look like

```JSON
{
	"tilemap1": [
		"0x120", "0x20", "0x121", "0x20"
	],
	"tilemap2": [
		"0x120", "0x20", "0x121", "0x20"
	],
	"palette": [
		"0x01", "0x02"
	]
}
```

Each tile map contains an array of hexadecimal numbers, saved as strings. The first number is the code of the tile, and the second is the attributes. The tilemap array goes from top left to right, and then goes down row by row.

The file name in the folder automatically increases so as not to overwrite previous dumps.

The contents of the palette at the time of the dump are also dumped as part of the JSON file under the `palette` entry.

# Tasks

1. Read MAME source code
2. Identify how the tile map class works and how to access tile map information of the emulated system
3. Identify how to link to the GUI and react to key presses
4. Identify where the access to the MAME output folders is decided, the place where things like cfg_directory and snapshot_directory are handled
5. Plan the change in a way that is consistent with the files and reuses MAME code base
6. Execute the changes

# Tests

If MAME has a test infrastucture in place, leverage it to write and pass tests for the new feature. If you need me to install a new tool, tell me.

# Git Commits

Commit when you have finished the task and achieved good test results
