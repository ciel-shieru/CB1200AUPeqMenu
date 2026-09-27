# DevicePEQ Cache Format and Numeric Conversion

## Purpose

The cache is a DevicePEQ-compatible text representation of the current custom PEQ profile, extended with one application-specific line:

```text
Slot: <0-255>
```

DevicePEQ export files that omit `Slot:` can be used as a source for constructing a cache only after a valid custom slot is known; the current parser requires the `Slot:` extension in an app-managed custom cache.

## File format

Example:

```text
Preamp: 0.0 dB
Filter 1: ON PK Fc 20 Hz Gain 10.0 dB Q 0.180
Filter 2: ON PK Fc 20 Hz Gain 6.0 dB Q 0.180
Filter 3: ON PK Fc 75 Hz Gain 5.0 dB Q 0.920
Filter 4: ON PK Fc 320 Hz Gain -0.8 dB Q 0.400
Filter 5: ON PK Fc 1450 Hz Gain -10.0 dB Q 0.440
Filter 6: ON PK Fc 1500 Hz Gain -4.7 dB Q 0.330
Filter 7: ON PK Fc 8000 Hz Gain -8.0 dB Q 0.420
Filter 8: ON PK Fc 20000 Hz Gain -5.0 dB Q 0.100
Slot: 101
```

Supported text filter types are:

- `PK`
- `LSQ`
- `HSQ`
- `LP`
- `HP`

A disabled filter may simply be written as:

```text
Filter N: OFF
```

The parser fills missing filter numbers as disabled.

## Validations

The parser requires:

- a `Preamp:` line;
- eight total filter slots after filling omitted filters;
- `Slot:` in the range `2...255` for a custom cached profile;
- frequency `20...20000 Hz` for enabled filters;
- gain `-10...+10 dB` for the supported filter calculation;
- Q `0.1...10.0`;
- a supported filter type.

Slot `0` and slot `1` are rejected as cached custom-profile slot IDs.

## Why `Slot:` exists

DevicePEQ exports do not contain the application-specific active slot ID. CB1200AUPeqMenu needs that value to know which device profile to restore, especially because custom slots are not universally `101`.

The extra line is ignored by DevicePEQ because it is outside the fields used by the normal export format, making the file useful as a cross-tool cache.

## Serialization rules

The current serializer writes:

- preamp/global gain to one decimal place;
- frequency as an integer Hz;
- gain to one decimal place;
- Q to three printed decimal places, using a canonical value rounded to two decimal places first;
- slot as an integer.

This deliberate asymmetry is important: the printed Q has three decimals for the DevicePEQ-friendly text format, while the canonical internal value is first rounded to hundredths because that is what the tested DevicePEQ representation expects.

## HID → text conversion

For each enabled filter readback:

### Frequency

```text
raw = littleEndianUInt16(response[27...28])
textHz = raw
```

Example:

```text
0x004B -> 75 Hz
```

Do not apply the previous `0.9775`/cos-Nyquist correction. That old conversion produced a cache such as `73 Hz` from a raw `75 Hz` value even though the HID data itself was correct.

### Q

```text
rawQ = littleEndianUInt16(response[29...30])
q = rawQ / 256
canonicalQ = round(q, 2 decimal places)
printedQ = canonicalQ formatted to 3 decimal places
```

Example:

```text
0x00EC = 236 / 256 = 0.921875
canonicalQ = 0.92
printed = 0.920
```

### Gain

```text
rawGain = signedInt16(littleEndian(response[31...32]))
gainDB = rawGain / 256
```

## Text → HID conversion

When enabling from the cached text file, the app reconstructs the 36-byte filter packet.

For frequency:

```text
storedFrequency = clamp(round(textFrequency), 20, 20000)
```

For Q:

```text
canonicalQ = round(textQ, 2 decimal places)
qRaw = round(canonicalQ * 256)
storedQ = qRaw / 256
```

The stored Q used for the coefficient calculation is the exact reconstructed 8.8 value, not the unquantized decimal supplied by the user.

For gain:

```text
gainRaw = round(gainDB * 256)
```

The resulting signed 8.8 value is inserted in the packet.

## Why HID coefficients are authoritative

The text file is a human-readable representation. The device's coefficient block is the authoritative binary DSP data.

When the app connects while a custom slot is already active, it preserves the raw coefficients from the HID readback and writes those same coefficients back during normal enable/disable cycles. It therefore avoids unnecessary recomputation.

The text codec is used when:

- exporting the live custom profile to disk;
- loading a profile from disk;
- advanced users intentionally editing the cached text file.

## Storage path

The logical path is:

```text
<Application Support inside the App Sandbox>/CB1200AUPeqMenu/DevicePEQ Profiles/
```

No external filesystem path is used.
