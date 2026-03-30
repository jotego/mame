# Flatten CPS3 Sprite DMA Into a 512-Entry Render List

## Summary

Replace the current CPS3 sprite DMA behavior in `cps3_state::spritedma_w` with a true preprocessing step that converts the hardware's main-list + sublist format into a compact post-DMA render list stored in `m_spritelist`. The new buffer will be capped at 8192 bytes total, meaning 512 `u32` entries or 128 sprite records of 4 words each. `screen_update` will then render only this flattened DMA output instead of traversing the original two-level structure.

Defaults chosen for planning:

- Preserve tilemap pseudo-sprite commands in the flattened buffer.
- On overflow, truncate output and append a stopper record.

## Implementation Changes

- Change `m_spritelist` semantics from "partial mirror of sprite RAM" to "DMA-expanded render list".
- Reduce the `m_spritelist` allocation/save-state size from the current large copy buffer to 8192 bytes total.
- Define the flattened record format as one 4-word entry per drawable command:
  - Word 0: sublist sprite word 0, but with palette/bpp/global flag overrides already applied.
  - Word 1: sublist sprite word 1, but with main-list X/Y offsets and selected global scroll effects already folded in.
  - Word 2: sublist sprite word 2 unchanged unless needed for flattened rendering.
  - Word 3: sublist sprite word 3 unchanged, including `xsize == 0` tilemap commands.
- In `spritedma_w`:
  - Clear the output cursor at DMA start.
  - Iterate main-list records until the stopper bit.
  - Decode each main entry once: base X/Y, global scroll index, palette/bpp override selectors, global flip, alpha, and other per-sublist attributes currently applied during rendering.
  - Walk the referenced sublist and emit one flattened 4-word record per sub-entry.
  - Apply the main-list effects during emission instead of later in the renderer:
    - Add main-list X/Y offsets to each sub-entry position.
    - Apply global palette/bpp selection rules into the emitted entry.
    - Fold global flip/alpha state into emitted flags so the renderer no longer needs the parent record.
    - Preserve enough information for tilemap pseudo-sprites to render correctly after flattening.
  - Maintain the existing DMA completion behavior and gscroll buffering.
  - Terminate the flattened list explicitly with a stopper record. If the buffer fills, stop emitting, write the stopper if space remains, and render the truncated prefix only.
- In `screen_update`:
  - Replace the current outer loop over main entries plus inner loop over sublists with a single linear walk over flattened 4-word records until the stopper.
  - Keep the existing sprite/tilemap drawing code paths, but make them consume already-resolved per-entry state rather than combining main-list and sublist state on the fly.
  - Remove dependence on main-list-only fields such as sublist start/length in the renderer.
- Keep the cache stats display, but make the reported sub-sprite count reflect the DMA-expanded entry count actually emitted into the flattened list.

## Interfaces / State

- No external API changes.
- Internal state changes:
  - `m_spritelist` becomes a compact post-DMA command buffer.
  - `m_spritelist_dma_subsprite_count` should track emitted flattened entries, not raw referenced sublist length totals.
- Save-state/reset handling must remain correct:
  - Save the resized `m_spritelist`.
  - Reset the buffer to an immediate stopper on startup/reset.
  - Preserve the current DMA status/timer behavior.

## Test Plan

- Build only the affected driver/target, not full MAME.
- Verify the driver compiles after:
  - shrinking the saved sprite list buffer,
  - rewriting `spritedma_w`,
  - simplifying the sprite renderer.
- Run representative CPS3 scenes that exercise:
  - normal sprites with parent X/Y offsets,
  - palette and bpp overrides from main-list entries,
  - global flip and alpha interactions,
  - tilemap pseudo-sprite entries (`xsize == 0`),
  - frames with many sub-sprites to confirm truncation is safe and terminated cleanly.
- Check the on-screen cache stats:
  - sub-sprite count changes with scene complexity,
  - count matches emitted flattened entries, not the old two-level bookkeeping.
- Regression check:
  - no reads past the compact `m_spritelist`,
  - no rendering path still depends on main-list `start/length` fields.

## Assumptions

- The flattened buffer remains a 4-word record format so most existing per-sprite decode logic can be reused with minimal churn.
- Tilemap commands must remain supported in the DMA output to avoid visual regressions.
- Truncation is acceptable for now if a frame exceeds 128 emitted records; correctness of the compact format is the immediate goal, not perfect worst-case coverage.
