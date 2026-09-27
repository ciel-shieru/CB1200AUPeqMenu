# Changelog / Development History

This changelog records the protocol and architecture discoveries that led to the current implementation. It is intentionally more detailed than a normal release changelog because several changes were required to distinguish harmless metadata differences from actual DSP corruption.

# Changelog / Development History

This file records both release-facing changes and the protocol/lifecycle discoveries that shaped the implementation.

Historical `debugXX` headings below are internal development milestones only; v0.0.1 is the release version and future release builds must not use debug-number versioning.

## v0.0.1 — initial documented release

### User-visible functionality

- Added a **Device** submenu to the status-bar dropdown. It lists all currently confirmed WalkPlay-compatible CB1200AU devices.
- Added a **Toggle PEQ** menu command in addition to the existing status-item left-click trigger.
- Added one-time startup device selection when more than one supported device is discovered.
- Automatically selects the only discovered device when exactly one is present.
- Allows device switching later through the Device submenu without restarting the application.
- Preserved event-driven disconnect/reconnect behavior; unplugging does not terminate the app.

### Discovery

- Restored the complete historical CB1200AU vendor-ID allowlist:
  `0104, 011B, 011D, 0661, 0663, 0666, 0762, 0909, 0D8C, 2FC6, 3302, 34BE, 35D8, 36A7, 373B, 60C1, 60E1, B445, B44D`.
- Switched the HID manager to `IOHIDManagerSetDeviceMatchingMultiple` with USB transport constraints.
- A device becomes selectable only after a successful WalkPlay protocol probe.
- Deduplicated matching HID interfaces by stable device identity information before protocol probing.

### Logging

- Debug logging is now opt-in only via `--debug` or `CB1200AU_DEBUG=true`.
- Removed direct unconditional application `NSLog` debug output.
- Without the debug switch/environment variable, the application logger produces no output.

### Release/versioning

- Removed `debugXX` release versioning.
- Set the application version to **0.0.1** with release fingerprint `v0.0.1`.
- Updated build/install/security documentation for the release.

### Security

- Retained native App Sandbox + Hardened Runtime.
- Runtime data remains in the sandbox container.
- USB access remains the only functional sandbox capability.
- Runtime discovery is narrowed by the historical VID allowlist, USB transport, and successful protocol probing.


## debug31

- Enabled native macOS App Sandbox.
- Added only the USB entitlement needed for sandboxed USB HID access.
- Enabled Hardened Runtime with no runtime exception entitlements.
- Moved all explicit application data/log storage into the sandbox container.
- Removed broad IORegistry fallback enumeration.
- Restricted HID manager matching to VID `0x3302` / PID `0x12CA` and USB transport.
- Added/updated security documentation.

## debug30

- Reverted the debug29 read-normalization experiment to the working debug23-style `FF 00` handling.
- Corrected HID → DevicePEQ text conversion:
  - frequency now uses the raw little-endian integer Hz field;
  - Q uses raw 8.8 conversion with the tested canonical decimal representation;
  - no old frequency compensation is applied.
- Preserved raw coefficient data for live custom profiles instead of needlessly regenerating it.
- Fixed selected-device unplug behavior so the menu-bar app stays alive.
- Reconnection relies on the event-driven HID matching callback.
- `Rescan now` became a true reset using generation invalidation.
- Added live profile-file/directory monitoring with vnode dispatch sources.
- Added automatic valid-profile reload into RAM without relaunch.

## debug29

- An attempted verification-layer change interpreted the Hi-MAX built-in flat readback signature (`metadata=0x01`, `slot=0x00`) as a special logical slot-1 state.
- This experiment was later reverted because the user confirmed the working behavior should remain based on debug28 plus the earlier normalization semantics.

## debug28

- Corrected the slot-1 built-in profile packet layout.
- Removed the stray `0x00` from the middle of the PEQ filter record and placed the final record byte correctly.
- Restored exact WalkPlay framing:
  - 36-byte payload;
  - 37-byte native report including `0x4B`.
- Removed debug27's 64-byte HID-output padding.
- Added length validation for both captured flat writes and generated custom writes.
- This fixed the audible hiss caused by malformed PEQ write framing.

## debug27

- Experimented with zero-padding native HID output reports to the advertised 64-byte output size.
- Added detailed logical/padded report logging.
- This was later superseded by the exact captured 37-byte WalkPlay framing in debug28.

## debug26

- Fixed an earlier normalization bug where an inserted replacement zero produced a 37-byte canonical record instead of 36 bytes.
- Matched the official WalkPlay Flash timing by waiting one second after register/global-gain writes before `01 01 00`.

## debug25

- Removed speculative flat-profile commands `01 05 00` and `01 17 00`.
- Restored the authoritative captured flat-profile sequence only.
- Identified `0x17` as unsafe for PEQ toggling because it is associated with factory reset.
- Refined the extra-`FF` read normalization.

## debug24

- Tested additional pre-commit control packets during investigation of the flat-profile problem.
- Introduced the firmware-response normalization experiments that eventually led to the stable debug23/debug30 behavior.

## debug23

- Captured and adopted the exact built-in flat-profile packets supplied from the official WalkPlay WebHID flow.
- Established the stable PEQ packet length model.
- Added the known response normalization behavior for the firmware's extra `FF 00` form.
- Rejected periodic polling in favor of event-driven HID lifecycle handling.

## Earlier development milestones (pre-debug23)

### Protocol discovery

- Identified the tested Hi-MAX HID identity:
  - VID `0x3302`
  - PID `0x12CA`
  - product `Hi-MAX`
  - USB transport
  - report ID `0x4B`
  - maximum report size 64 bytes.
- Identified the core commands used by the working implementation: version `0x0C`, PEQ `0x09`, global gain `0x03`, temporary write/flush `0x0A`, Flash commit `0x01`.
- Established eight-band PEQ packet structure and the signed/fixed-point encodings.

### Device discovery and lifecycle

- Worked through `IOHIDManagerCopyDevices` returning no devices in some states.
- Found and selected the correct HID interface from multiple HID interfaces.
- Added stable input-report callback handling and correct callback signature.
- Added robust device open/close logging and status-bar state updates.
- Confirmed that the application should use a real HID-device lifecycle rather than browser-only behavior.

### Slot semantics

- Discovered that slot `1` behaves as the built-in flat/PEQ-off state on the tested device.
- Identified custom slot `101` on the Hi-MAX, while preserving support for slot `255` on another compatible device.
- Established that slot `0` can mean uninitialized/ambiguous metadata and is not safe to treat as normal OFF without full profile verification.

### DevicePEQ persistence

- Implemented per-device cache naming using product/VID/PID/serial metadata.
- Added all eight filters plus global/DAC gain to the cache.
- Added the application-specific `Slot:` line so non-101 custom slots can be restored.
- Added RAM-first restore behavior so toggles use the cached profile rather than repeatedly reading disk.

## Lessons retained in the current branch

The most important historical conclusions are also repeated in [`PITFALLS.md`](PITFALLS.md): exact packet lengths matter, firmware readback can contain an extra response byte, slot metadata is not always authoritative by itself, and audio behavior must be tested alongside protocol readback.
