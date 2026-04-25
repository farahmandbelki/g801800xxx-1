# g801800xxx

This repository is the project baseline restored from the `2026-04-21` local backup.

It contains the keyboard-side source tree we use as the stable starting point for future development.

## Repository Layout

- `tool_probe/`
  Windows-side helper scripts and tooling used during wireless module and HID protocol exploration.
- `ui for keyboard/`
  OLED UI source assets, icons, and image references.
- `viar80_master/`
  QMK keyboard source for the master MCU.
- `viar80_slave/`
  QMK keyboard source for the slave MCU.

## Build Workflow

This repository is the source baseline, not the full QMK firmware tree.

Typical workflow:

1. Copy `viar80_master/` into `QMK_FIRMWARE/keyboards/g801800xxx/viar80_master`
2. Copy `viar80_slave/` into `QMK_FIRMWARE/keyboards/g801800xxx/viar80_slave`
3. Build from the QMK root:

```bash
qmk compile -kb g801800xxx/viar80_master -km via
qmk compile -kb g801800xxx/viar80_slave -km via
```

## Notes

- This repository is intended to be the clean development baseline before further fixes and feature work.
- Temporary local files, macOS metadata, and build artifacts should not be committed.
