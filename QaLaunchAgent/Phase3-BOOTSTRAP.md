# Phase 3 administrator bootstrap

An authorized administrator installs the hash-pinned agent under the protected
`Program Files\Repato\QaLaunchAgent` directory. Policy values remain compiled
into the matching runtime set. The administrator validates the manifest and
registers the `\Repato\Repato QA Launch Agent` RepatoQA-logon-only task. Its
sole action is the fixed agent executable, with no request arguments.

The administrator will configure the RepatoQA account SID, orchestration client
SID, exact Revit path, disposable QA runtime root, manifest root, protected
replay/log directory, and pipe name. The pipe DACL will be verified before the
agent is started. A harmless synthetic handshake will be completed before any
Revit authorization. No password is collected or stored. The task uses the
interactive token, least privilege, no arguments, `IgnoreNew`, and three
one-minute restart attempts.

Installation requires an elevated terminal and an independently reviewed hash
of `Repato.QaLaunchAgent.release.json`. It performs an atomic directory swap,
restores the prior runtime and task on failure, and never starts the agent,
Revit, or a QA request. Verification and execution remain separate.
