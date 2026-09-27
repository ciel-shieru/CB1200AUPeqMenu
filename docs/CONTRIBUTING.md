# Contributing / Extending the Protocol Client

## Before changing protocol code

Capture the exact transaction from an authoritative implementation whenever possible. Record:

- device VID/PID;
- product/firmware version;
- report ID;
- exact transmitted bytes;
- exact native report length;
- exact response bytes and lengths;
- whether the operation was audible/functional, not only whether the device accepted the packet.

## Safe extension pattern

1. Add or update the command constant.
2. Document the packet in `docs/HID_PROTOCOL.md`.
3. Add length/bounds checks.
4. Keep report-ID framing explicit.
5. Keep asynchronous results generation-checked.
6. Add a regression note to `docs/PITFALLS.md`.
7. Add an entry to `docs/CHANGELOG.md`.
8. Update `AGENTS.md` if the invariant changes.

## Security review before merge

Ask:

- Does this introduce an entitlement?
- Does this introduce a new file path?
- Does this allow a user-controlled path to escape the sandbox container?
- Does this broaden HID matching?
- Does this add a network dependency?
- Does this add a helper process or privilege requirement?
- Does it introduce a new unsafe command or factory-reset path?
- Can stale async work affect current state?

A change that answers yes to any of these should receive an explicit security/protocol review before being accepted.


## Multi-device UI and discovery changes

Do not silently choose the first supported device merely because it appears first in `IOHIDManagerCopyDevices`. Confirm candidates by protocol, preserve stable device identity data, and expose the user-controlled Device submenu. The startup picker is only for the initial multi-device ambiguity; later selection belongs in the menu.

## Logging changes

All new diagnostics must use `DebugLog`. Do not add unconditional `NSLog`, `print`, or raw file writes for debugging. Document any new sensitive diagnostic fields in `docs/SECURITY.md`.
