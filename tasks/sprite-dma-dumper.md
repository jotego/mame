# CPS3 Sprite DMA Consistent Dump Hook

## Goal

Extend the CPS3 video debug dump so that a **consistent pair** of dumps is
captured: the full 512 KB Sprite RAM and the compact 8 KB DMA-expanded
`m_spritelist`, taken immediately after the **next** sprite DMA completes
building `m_spritelist`.

## Scope

- Trigger path remains `Ctrl+F11` inside `cps3_state::screen_update()`.
- `dump_ss_debug_state()` is extended to include `spriteram.bin`.
- Add one additional dump (`spriteram.bin`) and keep `scene.bin` as the
  `m_spritelist` dump produced by `dump_ss_debug_state()`.
- The dump is **deferred** until the next `spritedma_w()` completes, to ensure
  Sprite RAM and `m_spritelist` are consistent.
- On failure, continue attempting the remaining dumps.

## Behavior

1. User presses `Ctrl+F11` (same as current) → sets a **pending dump request**.
2. The next time `spritedma_w()` finishes building `m_spritelist`, the pending
   request is serviced:
   - Dump Sprite RAM (512 KB) to `spriteram.bin`.
   - Call `dump_ss_debug_state()` (which writes `scene.bin` from `m_spritelist`).

## Data Source

- `m_spriteram` (Sprite RAM, 0x80000 bytes).
- `m_spritelist` (DMA-expanded list, 0x2000 bytes), dumped via `scene.bin`
  inside `dump_ss_debug_state()`.

## File Location

- Use the same debug output root as existing dumps:
  `plugin_data_path/debug/<romname>/`.

## Naming

- `spriteram.bin`: full Sprite RAM (512 KB).
- `scene.bin`: already produced by `dump_ss_debug_state()` (8 KB).

## Implementation Plan

1. **Add a pending-dump flag**
    - When `Ctrl+F11` is pressed, set `m_ss_dump_pending`.
    - Do not dump immediately.

2. **Declare new names before use**
    - Ensure any new variables/functions are declared in the proper headers or
      class declarations before they are referenced in source files.
    - This avoids compile errors from missing prototypes or members.
    - Add `m_ss_dump_pending` to `cps3_state`.
    - Keep `dump_ss_debug_state()` as `void` (do not change its signature).

3. **Service the dump request at DMA completion**
    - When `spritedma_w()` finishes building `m_spritelist` (right after the
      final list terminator is written), check `m_ss_dump_pending`:
        - Call `dump_ss_debug_state()` (now also dumps `spriteram.bin`).
        - Clear the pending flag.

4. **Single success/failure report**
    - Attempt all dumps even if one fails.

5. **Compile with `mkmame.sh`**
    - Run `~/mame/mkmame.sh REGENIE=1` after code changes (do not build full MAME
      outside this script).

## Tests / Checks

- Build only the affected driver/targets (not full MAME) via `mkmame.sh`.
- Run `sfiiin` and press `Ctrl+F11`:
    - `spriteram.bin` is created.
    - `scene.bin` is created by `dump_ss_debug_state()`.
    - Existing dump files are still produced.
    - The wrapper on-screen message indicates success.
- Run with `-log` and confirm `error.log` stays clean (no dump failures).
- Trigger the dump multiple times to confirm files overwrite cleanly and the
  status message remains consistent.

## Open Questions

- None for now.
