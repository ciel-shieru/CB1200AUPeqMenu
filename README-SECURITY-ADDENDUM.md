# Security Addendum

Version 0.0.1 uses native macOS App Sandbox + Hardened Runtime with only sandboxed USB access required for CB1200AU HID operation. The sandbox USB entitlement is broad at the capability level, so the application additionally enforces the historical 19-Vendor-ID allowlist and USB transport restriction before protocol probing.

All persistent runtime files are sandbox-contained. Debug logs are opt-in via `--debug` or `CB1200AU_DEBUG=true`; no application debug output is emitted when neither is enabled.

See [`docs/SECURITY.md`](docs/SECURITY.md) for the full design, threat model, and verification procedure.
