# Repato multi-tool QA framework v1

## Scope

`QA/ToolQaRegistry.v1.json` is the explicit tool allowlist. It registers the existing
Create Plan Views runner (`create-plan-views-v1`, request schema 2) and the separate
Create RCP Views runner (`create-rcp-views-v1`, request schema 1). Descriptors name
runner types, manifest filenames, fixture-preparation contract IDs, and fixture-spec IDs,
never executable paths. The registry is embedded
in `Repato.Revit.dll`; runner startup checks the actual loaded runner type against the
registered identity. Unknown tools, path-bearing manifest names, duplicate IDs, and
unsupported schema versions fail closed.

`ToolQaFramework/ToolQaDescriptor.cs` contains shared binding, approval, fixture,
exactly-once dispatch-state, and terminal-result gates. CPV uses the shared registry
and fixture-correlation gate while retaining its existing request and canonical task
contracts. RCP consumes the same registry through its runner identity check and keeps
its tool-specific model/view assertions in `RcpQaRunner`.

## Compatibility and dispatch boundary

The currently deployed Launch Agent protocol remains CPV-specific: its request shape,
manifest pin, candidate pin, and allowlist were intentionally not changed. The RCP
descriptor is an offline framework registration, not authorization to dispatch RCP.
Enabling live RCP requires a separately reviewed versioned native protocol/agent
adapter, candidate and manifest binding, QA profile isolation, deployment validation,
and a fresh human-approved canonical attempt. Do not add RCP to the existing agent's
allowlist alone.

The shared dispatch state machine treats an unauthenticated/lost response as
`OutcomeUnknown`; it cannot be dispatched again. Only authenticated terminal evidence
can reconcile it. Approval expiry does not infer process termination. Result acceptance
requires request/attempt correlation plus rollback and cleanup verification.

## Offline tests and artifacts

`ToolQaFramework.ContractTests` exercises CPV/RCP registry, candidate/manifest binding,
stale/expired approval, synthetic fixture evidence persisted only in a unique OS temp
directory, exactly-once/ambiguous dispatch, terminal reconciliation, and result,
rollback, and cleanup rejection cases. Runner-specific contracts remain in
`TestRunner.ContractTests` and `RcpQaRunner.ContractTests`.

The new RCP build candidate is kept separate at
`DeploymentCandidates/RcpQa/RcpQa-multitool-framework-20261014`. It is not installed.
The existing CPV candidate, the existing RCP candidate, installed QA environment, and
canonical task store are not changed by this work.
