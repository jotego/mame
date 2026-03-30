# CPS3 GFX stats

Implement a helper class in cps3.cpp that will be used to keep track of
graphics usage. The stats will be updated frame by frame and will be dumped
to a file when MAME exits

# What to track

These elements must be tracked:

- individual (distinct code) tiles used per tile map
- individual (distinct code) sprites drawn per sprite list item
- individual (distinct code) tiles used on the SS layer
- individual palettes used by each layer: per tile map, per sprite list and SS
- combined metrics for the whole frame: total individual tiles of **all** tile 
maps, total sprites of **all** sprite lists, total palettes used
- number of pixels drawn to the frame buffer per frame. You can calculate this
as you know the size of each tile map tile and each sprite (take into account
the variable sprite size)

The metrics must be registered for each frame, and stats obtained
over the total number of frames. For each metric register minimum, maximum 
and average. For instance:

If the first frame draws:

- one tilemap using 100 different tiles
- one sprite lists using 250 sprites
- another tilemap using 50 different tiles
- another sprite list using 30 sprites

Then metrics for the frame should look like:

- tilemap: max 100, min 50, average 75
- sprites: max 250, min 30, average 140

Then the next frame may require an update of some of these numbers, etc. At the
end, I want to understand the usage of the graphics memory.

# File dump

Create a cps3-stats.yml file in YAML format

# On-screen stats

Display an overlay layer with the frame stats: total number of tiles drawn,
total number of sprites, total number of palettes and total number of pixels
drawn to the buffer

# Documentation

Apart of the capcom/cps3.cpp file itself, you can read the file cps3-gfx.md for
a summary of how graphics work in this system

# Other Remarks

Compile MAME with just the cps3 driver, to speed up compilation. At the end of
the task, leave a compiled version of MAME ready.

Time how long it took to run all these tasks