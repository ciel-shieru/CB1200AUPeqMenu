# Testing and Verification Checklist

## Build verification

On macOS:

```sh
swift package clean
swift build -c release
./build-app.sh
```

Verify the final signature:

```sh
codesign --verify --strict --verbose=2 ./dist/CB1200AUPeqMenu.app
codesign -d -vvv ./dist/CB1200AUPeqMenu.app
codesign -d --entitlements :- ./dist/CB1200AUPeqMenu.app/Contents/MacOS/CB1200AUPeqMenu
```

Expected functional entitlements:

```text
com.apple.security.app-sandbox
com.apple.security.device.usb
```

Expected: no network or broad file-access entitlements.

## HID protocol tests

### Connect

- Start the app with the CB1200AU already attached.
- Confirm the initial scan applies the historical vendor allowlist + USB transport filter, then succeeds on the expected WalkPlay protocol interface.
- Confirm the version probe succeeds.
- Confirm all eight filter reads complete.
- Confirm global gain is read.

### Disconnect

- Unplug the CB1200AU while selected.
- Confirm the process remains alive.
- Confirm the status changes to no-device/unknown.
- Confirm no polling loop is created.

### Reconnect

- Reconnect the CB1200AU.
- Confirm macOS's HID matching callback triggers the probe.
- Confirm the device is selected without restarting the app.

### Disable

- Start from a known custom profile.
- Left-click to disable.
- Verify all eight transmitted PEQ payloads are exactly 36 bytes.
- Verify the native report length is exactly 37 bytes including report ID `0x4B`.
- Verify the flush/gain/1-second/Flash sequence.
- Verify audible PEQ-off behavior.
- Verify the post-write full read does not report malformed coefficient data.

### Enable

- Start from slot 1 with a known cached custom profile.
- Left-click to enable.
- Verify the exact custom filter bytes are sent.
- Verify the custom slot is preserved.
- Verify post-write readback and audible custom PEQ behavior.

## Cache tests

### Export

- Start with a known custom profile.
- Confirm a DevicePEQ file is saved inside the sandbox container.
- Confirm all eight filters, preamp/global gain, and `Slot:` appear.

### Numeric round-trip

Compare the cache against DevicePEQ's export for a known profile. Pay special attention to frequencies and Q values.

Known expected example:

```text
Filter 3: ... Fc 75 Hz ... Q 0.920
Filter 4: ... Fc 320 Hz ... Q 0.400
Filter 6: ... Fc 1500 Hz ... Q 0.330
```

### Live edit

- Edit the active profile file while the app runs.
- Confirm a valid change reloads into RAM.
- Confirm an invalid change is rejected and the previous valid cache remains usable.
- Test an editor that uses atomic-save replacement rather than in-place writing.
- Delete the profile and verify the in-memory custom profile is cleared.

## Recovery tests

### Rescan now

- Force a transient HID/protocol error.
- Click **Rescan now**.
- Confirm stale errors disappear.
- Confirm a fresh device discovery starts.
- Confirm a late result from the old operation does not overwrite the new state.

## Security tests

Under a real sandboxed build:

- attempt to open an unrelated HID device: should not be matched/probed;
- attempt to read/write an arbitrary home-directory file: should fail under App Sandbox;
- confirm profile/log writes remain inside the application container;
- confirm no network sockets are opened by the application;
- inspect entitlements and Hardened Runtime status;
- inspect the app's filesystem/container after normal operation for unexpected persistent files.

## Regression tests for known protocol pitfalls

- PEQ write length must remain 36 payload / 37 total.
- Do not restore 64-byte zero-padding.
- Do not remove the `FF` at read-response index 6 unconditionally.
- Do not search for `0A 02` as a trailer.
- Do not add `0x17` to PEQ switching.
- Do not hardcode custom slot 101.
- Keep the 1-second Flash delay.
