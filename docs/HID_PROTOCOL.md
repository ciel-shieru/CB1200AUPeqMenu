# WalkPlay / CB1200AU HID Protocol Reference

This document records the protocol as established for the tested CB1200AU/Hi-MAX implementation. It combines the captured official WalkPlay WebHID frames, the device readbacks observed during development, and the code's current interpretation.

## Scope and certainty

Some command numbers are firmly established by working captures. Others are documented protocol concepts that the tested Hi-MAX firmware did not expose usefully.

The application therefore prefers observed, working packet sequences over speculative protocol commands.

## HID framing

- HID report ID: `0x4B`.
- WebHID captures log the logical payload without the report ID.
- Native IOKit calls pass a buffer beginning with `0x4B` and an explicit report length.
- **WalkPlay PEQ filter writes are 36 payload bytes / 37 bytes total including report ID.**
- Do not append an additional END byte to a PEQ filter record.
- Do not pad short output packets to the descriptor's 64-byte maximum on the tested device.

The distinction is critical. During development, a misplaced zero produced a 38-byte native PEQ write and corrupted the readback/audio state.

## Command bytes

| Name | Value | Meaning in this project |
|---|---:|---|
| `READ` | `0x80` | Read/request operation. |
| `WRITE` | `0x01` | Write/register/Flash operation. |
| `END` | `0x00` | Protocol terminator used by selected commands. |
| `FLASH_EQ` | `0x01` | Flash commit command when used after the write command byte. |
| `GLOBAL_GAIN` | `0x03` | Global/DAC gain read/write. |
| `PEQ_VALUES` | `0x09` | PEQ filter read/write. |
| `TEMP_WRITE` | `0x0A` | Flush/register-cache/DSP apply step. |
| `VERSION` | `0x0C` | Firmware/version read. |
| `GET_SLOT` | `0x0F` | Publicly documented active-slot command, but not used by the current Hi-MAX implementation because no usable response was observed. |
| `0x17` | `0x17` | Factory-reset-related command in public protocol material; **never send for PEQ toggling**. |

## Firmware/version probe

Request payload:

```text
80 0C
```

Native report:

```text
4B 80 0C
```

The application accepts a matching read response beginning:

```text
80 0C ...
```

For the tested device, bytes `[3..<6]` decode as ASCII firmware version, e.g. `0.1`.

The version probe is used as the decisive protocol check before selecting an HID interface.

## PEQ filter read request

For filter index `i` in `0...7`, request:

```text
80 09 00 00 ii 00
```

where `ii` is the zero-based filter index.

Example for filter 1:

```text
80 09 00 00 00 00
```

## Canonical PEQ filter record

After report-ID stripping and any required firmware normalization, the parser expects exactly 36 bytes with this layout:

| Offset | Size | Meaning |
|---:|---:|---|
| `0` | 1 | command; `0x80` for a read response, `0x01` for a write packet |
| `1` | 1 | `PEQ_VALUES` = `0x09` |
| `2` | 1 | PEQ packet mode/version field; write value `0x18` |
| `3` | 1 | reserved/zero |
| `4` | 1 | zero-based filter index |
| `5` | 1 | reserved/zero |
| `6` | 1 | firmware/status or reserved byte depending on response/write path |
| `7..26` | 20 | five signed 32-bit coefficient values, little-endian, Q30-scaled |
| `27..28` | 2 | frequency, unsigned 16-bit little-endian Hz |
| `29..30` | 2 | Q, unsigned 8.8 fixed-point |
| `31..32` | 2 | gain, signed 8.8 fixed-point |
| `33` | 1 | filter type byte |
| `34` | 1 | metadata/namespace byte |
| `35` | 1 | slot ID in the canonical read/write representation |

A key lesson is that byte 6 is not a universal PEQ field with one stable semantic across every firmware/report path. The current parser handles the known extra `FF 00` response insertion without shifting the fixed fields incorrectly.

## Response normalization (`FF 00` case)

Some responses observed after a built-in-profile write look like:

```text
80 09 00 00 <index> 00 FF 00 <canonical-record-byte-7> ...
```

The canonical record must remain 36 bytes.

The current debug23-compatible normalization rule is:

```text
if response.count >= 38
and response[6] == 0xFF
and response[7] == 0x00
and response[8] != 0x00:
    normalized = response[0..<7] + response[8..<37]
else:
    normalized = response.prefix(36)
```

This removes the inserted `0x00` at index 7 while preserving the observed `0xFF` at index 6.

Do **not** use an unconditional `remove byte at index 6` rule. That variant broke the tested response shape.

Do **not** search for an `0A 02` trailer. The byte `0x0A` can appear naturally as part of the encoded gain or coefficient data.

## PEQ filter write packet

A generated/captured filter write is exactly 36 bytes:

```text
01 09 18 00 ii 00 00
[20 bytes coefficient block]
[freq LE u16]
[Q 8.8 LE u16]
[gain signed 8.8 LE i16]
[type]
[metadata]
[slot]
```

The native HID report is:

```text
4B + 36-byte payload
```

so the IOKit report length is exactly 37 bytes.

### Coefficient block

The five coefficients are generated from a 96 kHz biquad implementation and quantized to signed Q30 (`2^30`) values. They are serialized little-endian as five 32-bit words.

The generated array is conceptually:

```text
[b0/a0, b1/a0, b2/a0, -a1/a0, -a2/a0]
```

scaled by `1073741824` and rounded to signed 32-bit integers.

Supported filter types:

| Text | Byte |
|---|---:|
| `LSQ` | `0x01` |
| `PK` | `0x02` |
| `HSQ` | `0x03` |
| `LP` | `0x04` |
| `HP` | `0x05` |

The current default/primary DevicePEQ use case is `PK`.

## Frequency, Q, and gain encoding

### Frequency

Read/write frequency is the raw unsigned 16-bit little-endian integer in Hz.

Example:

```text
4B 00 -> 0x004B -> 75 Hz
```

The current text serializer intentionally does **not** apply the older frequency compensation formula that produced values like `73 Hz` from a raw `75 Hz` field.

### Q

Q is unsigned 8.8 fixed-point:

```text
Q = raw / 256
```

The cache text representation rounds this to two decimal places internally and prints three decimal places, so values such as:

```text
raw 0x00EC = 236 / 256 = 0.921875 -> canonical text Q 0.920
```

When writing a cached profile back to HID, the canonical decimal Q is reconstructed into an 8.8 raw value before coefficient generation.

### Gain

Gain is signed 8.8 fixed-point:

```text
gain_dB = Int16(raw) / 256
```

Global/DAC gain is different: the global-gain command currently interprets the device byte as a signed integer dB value (`Int8`), e.g. `0x00` = `0.0 dB`, `0xFE` = `-2.0 dB`.

## Global/DAC gain read

Request:

```text
80 03 00
```

Native report:

```text
4B 80 03 00
```

The response byte at index `4` is interpreted as a signed 8-bit dB value.

## Register-cache flush

Observed working payload:

```text
01 0A 04 00 00 FF FF
```

It is sent after all eight filter records and before global/DAC gain.

## Global/DAC gain write

Observed working payload:

```text
01 03 02 00 gg
```

where `gg` is the signed 8-bit global/DAC gain byte.

For the built-in flat slot 1, this is:

```text
01 03 02 00 00
```

For the previously captured custom profile with `-2 dB`, it is `... FE`.

## Flash commit

Observed working payload:

```text
01 01 00
```

This is sent after the register/DAC writes.

The tested official WalkPlay web implementation schedules the Flash commit one second after the register-write sequence. The native implementation therefore waits 1.0 seconds before sending it, then waits another 200 ms before verification.

## Complete toggle sequence

### Enable custom profile

1. Eight custom filter writes, exactly 36 payload bytes each, 25 ms apart.
2. Wait 100 ms.
3. Send `01 0A 04 00 00 FF FF`.
4. Wait 50 ms.
5. Send `01 03 02 00 <gain>`.
6. Wait 50 ms.
7. Wait 1 second.
8. Send `01 01 00`.
9. Wait 200 ms.
10. Read all eight filters and global gain for verification.

### Disable / built-in flat profile

1. Eight captured slot-1 flat filter writes, exactly 36 payload bytes each, 25 ms apart.
2. Wait 100 ms.
3. Send `01 0A 04 00 00 FF FF`.
4. Wait 50 ms.
5. Send `01 03 02 00 00`.
6. Wait 50 ms.
7. Wait 1 second.
8. Send `01 01 00`.
9. Wait 200 ms.
10. Read all eight filters and global gain for verification.

No speculative `0x05` or `0x17` commands are included.

## Built-in flat slot 1

Slot 1 is represented by the exact eight captured WalkPlay packets stored in `WalkPlayProtocol.slot1Profile`.

They are not regenerated from the IIR algorithm. Keeping these captures literal is important because the goal is to reproduce the device's official built-in profile exactly.

## Custom-profile reconstruction

When a custom slot is read from the device, the app does not round-trip it through the text codec before a normal toggle. It preserves the raw canonical 36-byte read responses and turns those directly into write packets by changing only the command/index/slot fields needed for writing.

This avoids accumulating coefficient-generation differences on repeated enable/disable cycles.

## Slot semantics

Known observations:

- `0x01` = built-in flat/default profile; application treats it as PEQ OFF.
- `0x65` (`101`) = tested Hi-MAX custom profile.
- `0xFF` (`255`) = observed valid custom slot on another WalkPlay-compatible device.
- `0x00` = fresh/uninitialized or ambiguous metadata, and is unsafe to interpret as a custom profile.

After applying the captured flat profile on the tested Hi-MAX, the device may read back filter metadata/slot bytes corresponding to `0x00` even though all coefficient/filter data and global gain exactly match slot 1. The current code therefore recognizes the complete flat data pattern + `0 dB` gain and resolves that specific state as logical slot 1.

## Public/unsupported command caveats

`0x0F` exists in public protocol descriptions as an active-slot operation, but the current Hi-MAX did not provide a useful response to a speculative read. The code therefore does not rely on it.

`0x17` is associated with factory reset in independent protocol material. It is categorically excluded from normal PEQ switching.

## Protocol change policy

When new captures disagree with the above:

1. Prefer an official WalkPlay WebHID capture over guesses.
2. Preserve exact packet lengths.
3. Verify both TX bytes and post-write RX fields.
4. Test audio behavior, not merely readback.
5. Document the exact device/firmware before generalizing the behavior.
