# Wireless Module Protocol Notes

Current understanding of the vendor USB/2.4G configuration channel for the CH582M-based module.

## Interfaces

- USB module config HID:
  - `VID_213F / PID_1108 / MI_03`
- 2.4G receiver config HID:
  - `VID_213F / PID_1109 / MI_03`
- Both use:
  - `InputReportLength = 65`
  - `OutputReportLength = 65`

## BLE status

BLE mode exposes only standard services:

- `1800` Generic Access
- `1801` Generic Attribute
- `180A` Device Information
- `180F` Battery
- `1812` HID
- `1813` Scan Parameters

No custom 128-bit GATT service was observed. Runtime companion traffic should focus on `USB + 2.4G`, not BLE.

## Confirmed high-level commands from USBHIDControl.exe

- `WriteBLNAME(String)`
  - Packet family: `0xAA`
  - Observed format: `[00] [AA] [nameLen] [name bytes...]`
- `WriteBLREST()`
  - Packet family: `0xBB`
- `WriteWF24(Byte[],Byte[],Byte[])`
  - Packet family: `0xEE`
  - Observed payload: `address, band, receiverId`
- `WriteSTDLXS(Byte)`
  - Packet family: `0xE2`
  - Used for module battery display enable/disable in vendor UI
- `WriteWIFIKG(Byte)`
  - Packet family: `0xE9`
  - Used for 2.4G multi-device switch enable/disable
- `WriteGBKEY10(Byte)`
  - Packet family: `0xEA`
  - Used for “关闭/开启10字节以上数据”
- `WriteSTKJJ(Byte[])`
  - Packet family: `0xE4`
  - One-byte payload in the existing UI path
- `WriteSTDMT(Byte[])`
  - Packet family: `0xE3`
  - 4-byte payload
- `WriteSTDMT_LY(Byte[])`
  - Packet family: `0xBE`
  - 2-byte payload
- `WriteSTDMT_XZ(Byte[])`
  - Packet family: `0xBA`
  - 6-byte payload
- `WriteWS()`
  - Packet family: `0xDC`
- `WriteSTQKBL()`
  - Packet family: `0xE6`
- `WriteSTXM(Byte)`
  - Packet family: `0xE2`
- `WriteQCDMTDYS()`
  - Packet family: `0xEB`

## USBHIDSET.exe reverse engineering notes

### button15_Click

Bluetooth name setting through the lower-level `Usb_send_data(Byte[])` path:

- Builds a 65-byte packet
- Observed format:
  - `[00] [AA] [nameLen] [name bytes...]`

This matches the higher-level `WriteBLNAME(String)` family.

### button8_Click

2.4G config through the lower-level path:

- Builds an 8-byte working buffer
- Sends packet:
  - `[00] [EE] [address] [band] [receiverId]`

This matches the higher-level `WriteWF24(...)` family.

### button10_Click

Builds a one-byte bitmask from 8 checkboxes, then sends:

- `[00] [E4] [mask]`

This looks like a switch-mask / hotkey-mask style packet.

### button9_Click

Builds a 4-byte data block from:

- one modifier/source selector
- one function-key selector
- one multimedia action selector mapped into code + flag bytes

Then sends:

- `[00] [E4] [b0] [b1] [b2] [b3]`

This is a richer `0xE4` command family than the single-byte mask used by `button10_Click`.

### button6_Click

This is the most promising generic data/mapping path observed so far.

The method uses:

- `comboBox10`
  - items observed: `默认设置无修改`, `修正媒体数据位`, `映射多媒体按键`
- `comboBox11`
  - slot/index values
- `comboBox12`
  - action/data type table
- `textBox2`, `textBox3`
  - hex byte inputs
- `comboBox13`
  - additional small selector (`0..8`)

Observed behavior:

1. It first sends a `0xBE` packet with 2 payload bytes:
   - `[00] [BE] [mode] [slot]`

2. When `mode = 2` (mapped multimedia path), it follows with a `0xBA` packet carrying 6 payload bytes:
   - `[00] [BA] [d0] [d1] [d2] [d3] [d4] [d5]`

Current best interpretation:

- `0xBE` selects a working mode + slot/context
- `0xBA` commits a 6-byte mapping/data record
- `d1` comes from `textBox2` as a hex byte
- `d2` comes from `textBox3` as a hex byte
- `d3` comes from `comboBox13.SelectedIndex` (`0..8`)
- `d0`, `d4`, and `d5` are chosen from the `comboBox12` action table

Known `comboBox12` -> `0xBA` payload patterns recovered from IL:

- index `9`:  `d0=0x10, d4=0xE2, d5=0x00`   (`mute`-like consumer usage)
- index `10`: `d0=0x11, d4=0xEA, d5=0x00`   (`volume down`-like consumer usage)
- index `11`: `d0=0x12, d4=0xE9, d5=0x00`   (`volume up`-like consumer usage)
- index `12`: `d0=0x13, d4=0xCD, d5=0x00`   (`play/pause`-like consumer usage)
- index `13`: `d0=0x14, d4=0xB7, d5=0x00`   (`stop`-like consumer usage)
- index `14`: `d0=0x15, d4=0xB6, d5=0x00`   (`previous track`-like consumer usage)
- index `15`: `d0=0x16, d4=0xB5, d5=0x00`   (`next track`-like consumer usage)

This `0xBE / 0xBA` pair is the most likely candidate for any reusable structured data path.

## Raw companion support already added

The companion tool now exposes raw packet helpers in:

- `C:\Users\Admin\Desktop\键盘\source1\tool_probe\wireless_companion.ps1`

Available raw commands:

- `raw65-set-name`
- `raw65-send-hex`
- `raw65-set-24g`
- `raw65-set-switch-mask`
- `raw65-data-select`
- `raw65-data-write`

## Current assessment for time / volume sync

- `PC -> module/receiver` transport: mostly solved
- `module/receiver -> keyboard master runtime forwarding`: still unknown

The best next reverse-engineering target remains the `0xBE / 0xBA` data-setting family, because it looks more generic than simple config commands like Bluetooth name or pairing reset.
