The current DMA system for the sprite RAM is simply copying all data to m_spritelist. This requires all the memory of the original m_spriteram. But I think, it should be possible to limit the m_spritelist size to something small, like 8192 bytes.

The CPS3 system has a 512-entry list with global information that applies to a sprite list. The main entry list has a stopper bit. Each sublist has a size defined by the main list.

I think the right transformation for the sprite list, should be one that converts from the two list simple to a simple concatenation of sprites to be drawn, where the settings in the main list entry that apply to the sublist have already been applied as part of the DMA process.

So the DMA process should be something like:

- for each entry in the main list, until we hit the stop bit
- take note of the global parameters
- next copy each entry in the sublist, applying the corrections that the global parameters set
- continue for the next main list entry.

The DMA filled buffer will not have multiple lists anymore, but just an array of sprites to draw. This array will need a stopper, as normally not all entries would be drawn. Setting Y tile count to zero could be used as the stopper.

I want to modify cps3_state::spritedma_w so it performs these transformations, producing a new m_spritelist limited to just 8192 bytes (512 entries). Then modify screen_update so it only reads the information from this m_spritelist, rather than the full copy of that data as it does now.

I think that for the DMA processed data, the current sublist data format is probably good. The DMA will need to apply the global settings in the main list to each sublist element before copying it. For instance:

- the X/Y position in the main list should be added to those in the sublist
- bpp and palette selectors should be overriden if specified to be the global ones

