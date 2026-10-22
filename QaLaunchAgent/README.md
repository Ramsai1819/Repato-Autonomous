# RepatoQA launch agent (Phase 1)

The agent is intentionally limited to `launch-revit-qa`. It is designed to run as
the already-authenticated `RepatoQA` interactive user and to launch only the
configured Revit executable. The production implementation must add the final
restricted named-pipe server ACL and child-process launch routine before Phase 2.

One-time setup remains deferred: install the signed binary in a protected
location, configure the fixed Revit/runtime/profile roots, and register a
RepatoQA-logon startup task that starts this fixed agent only. No password is
stored or passed by the protocol.
