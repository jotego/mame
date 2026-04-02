# CPS3 Sprite DMA Double-Dump Hook

## Goal

Extend the CPS3 video debug dump so that a sprite DMA snapshot is captured
both immediately before and immediately after `dump_ss_debug_state()` runs.
This yields two 8 kB dumps per trigger to detect any changes caused by the
dump routine itself.

## Scope

- Trigger path remains `Ctrl+F11` inside `cps3_state::screen_update()`.
- `dump_ss_debug_state()` stays unchanged and is called as-is.
- Add exactly two additional files per trigger:
    - Sprite DMA snapshot **before** `dump_ss_debug_state()`.
    - Sprite DMA snapshot **after** `dump_ss_debug_state()`.
- On failure, continue attempting the remaining dumps.

## Behavior

1. User presses `Ctrl+F11` (same as current).
2. Dump sprite DMA buffer (8 kB) to file `sprdma_pre.bin`.
3. Run `dump_ss_debug_state()` (existing behavior).
4. Dump sprite DMA buffer (8 kB) to file `sprdma_post.bin`.
5. Display a **new wrapper on-screen message** indicating success/failure.

## Data Source

- Use the same sprite DMA buffer already used by CPS3 rendering:
    - `m_spritelist` in `cps3_state` (8 kB, 0x2000 bytes).

## File Location

- Use the same debug output root as existing dumps:
  `plugin_data_path/debug/<romname>/`.

## Naming

- `sprdma_pre.bin`: snapshot before `dump_ss_debug_state()`.
- `sprdma_post.bin`: snapshot after `dump_ss_debug_state()`.

## Implementation Plan

1. **Add a helper dump call**
    - Reuse `dump_ss_file()` to write the 8 kB sprite DMA buffer.
    - Call `dump_ss_file("sprdma_pre.bin", m_spritelist.get(), 0x2000)`.

2. **Wrap the existing dump sequence (without modifying it)**
    - Replace the direct call to `dump_ss_debug_state()` in `screen_update()`
      with a new wrapper routine that performs:
        - pre dump
        - `dump_ss_debug_state()`
        - post dump
    - `dump_ss_debug_state()` remains unchanged.

3. **Single success/failure report**
    - Attempt all dumps even if one fails.
    - Aggregate the result and show one **new wrapper** on-screen message:
      success only if all files are written.

## Tests / Checks

- Build only the affected driver/targets (not full MAME).
- Run `sfiiin` and press `Ctrl+F11`:
    - `sprdma_pre.bin` and `sprdma_post.bin` are created.
    - Existing dump files are still produced.
    - The wrapper on-screen message indicates success.
- Optionally diff `sprdma_pre.bin` vs `sprdma_post.bin` to confirm if any
  differences occur during the dump routine.
- Run with `-log` and confirm `error.log` stays clean (no dump failures).
- Trigger the dump multiple times to confirm files overwrite cleanly and the
  status message remains consistent.

## Open Questions

- None for now.
