# CPV compatibility release ready for deployment review

Task task-bf61fe7f22d74df7a92599681da5919e remains revision122, in-progress/qa,
recovery Dispatching, consumed reservation acfd8643ed2846b8a43b98d3a74c3217 retained.
Branch fix/cpv-active-marker-binding-20261019. Starting commit
513419e1d542daf39cb041e3f4342cb76802433b remains reachable; no verified Revit passing
baseline is claimed. Unrelated worktree changes remain outside scoped commits.

## Release identity

Runtime source commit: 6119aceaab0a34c3e0323089a29f1cefb2c14aaa.
Version: 1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa.
Immutable release root:
`C:\Repato-Autonomous\Source\DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa`

| Artifact | SHA256 |
| --- | --- |
| Repato.QaLaunchAgent.release.json | 7612D0657CF6287381F30A470D2B511BBF281B56CC36A095322845982879D726 |
| Repato.QaLaunchAgent.exe | 0A947BBD24C8A95CDB5C0AE94AA586ACE922765438DD1430FA4F1BBB8EF737CD |
| Repato.QaLaunchAgent.dll | F22C2E694ABE9A23893A97FFEE804D453191A60C031F48855DB071869A677F03 |
| Repato.QaLaunchAgent.deps.json | 78FEBC5E3DEB35F8A46125FB39EA36F30CDFE4DB154F76B49502FE92792259D4 |
| Repato.QaLaunchAgent.runtimeconfig.json | CA1A6B5B185174698E0F5F9AE732AD3D2D3ED5B122ED666F35CC214283E83B7F |

Built with Release, UseAppHost=true, Version explicitly bound to runtime source
commit; packaged using New-QaLaunchAgentRelease.ps1. Manifest, all four file hashes,
EXE/DLL product identity and runtime source binding verified. No runtime C# changes
followed packaging. The later tooling-only follow-up fixes module import lifetime
and records preflight evidence; identify its commit with git log on this file.

## Changes and crash correction

- QaLaunchAgent/CpvPreparation.cs preserves source-only two-field or exact fully
  prepared historical sidecars. It creates a separate model.rvt.recovered.fixture.json
  with original identities, approval/evidence bindings and historical sidecar hash.
  Durable commits bind its path/hash. Status/reconcile validate provenance. Partial
  publication, replay mismatch, missing evidence and orphan provenance fail closed.
- Repato.CpvRecoveredProvenance.psm1, Repato.CpvCompletedOutcomeRecovery.psm1 and
  scoped Maya/Tara consumer changes validate the recovered provenance, correlate
  request/result/model hashes and retain its hash in preparation evidence.
- Install-CpvPreparationAgentCandidate.ps1, Repato.CpvCompletedOutcomeUpgrade.psm1
  and scoped bootstrap guards support only the exact installed1.0.21/current
  reservation/revision122/committed generation13 -> candidate1.0.22 transition.
  Fresh authenticated NotExecuted proof and approved snapshot remain required.
- Contract fixture factory now includes historical evidence; missing-history
  rejection tests its exact managed exception. The harness catches unexpected
  exceptions, reports full stderr/stack and exits1, avoiding unhandled crash UI.
  See CPV-Compatibility-Crash-Diagnosis-20261019.md for captured exception and older
  Windows event records; do not conflate those different failures.
- Invoke-CpvEngineeringProcess.ps1 runs hidden noninteractive children, captures
  stdout/stderr/exit code and enforces configurable timeout minimum/default7200s.
  Corrects only the child WindowsPS module path when launched through Process.Start.
- Preflight exposed forced nested module reload removing Invoke-MayaQaLaunchAgentHealth.
  Recovery imports now reuse dependencies. A command-discovery regression covers
  the actual installer import order. No health or integrity guard was removed.

## Validation

Both Windows PowerShell5.1.26100.9711 and PowerShell7.6.7 passed:

| Suite | Count |
| --- | ---: |
| C# CPV preparation protocol | 127 |
| recovered provenance and actual Save/downstream consumers | 47 |
| completed outcome authorization | 41 |
| completed outcome guarded upgrade | 38 |
| marker timestamp | 12 |
| compatibility bootstrap journal | 56 |
| durable install recovery | 46 |
| guarded module imports | 9 |

376 counted assertions per engine; additional existing correlated/prepared fixture
provenance and post-install rollback suites passed in both engines. C# protocol-v2
interop passed. An isolated copy of the exact packaged agent DLL passed127 contract
assertions. The failure-reporting probe returned expected exit1 with captured stack;
normal tests returned0. No Revit or native QA execution.

Required product Release build passed, zero errors/two MSB3277 warnings. Product
bin/Release/net8.0-windows/Repato.Revit.dll SHA256
878DAAF2B9F2E3205CFE64D766F8AA8AE84BDEAEB9BE6EEE42904014934EAD72.
Agent Release build passed, zero errors/one NU1900 cached vulnerability-metadata
warning. Product output is not the approved frozen candidate and was not deployed.

## Guarded read-only deployment preflight

PASS in elevated WindowsPS5.1 and PS7 using the supported installer -PreflightOnly,
CompletedOutcomeRecoveryRequestId c11b311638a54bfc9ebdd1803671ec40,
ExpectedTaskRevision122 and exact release root/manifest hash above.
UpgradeAccepted=true, prior task contract valid, four rollback runtime files,
generation13, authenticated health/session1, no Revit, evidence snapshot present.
Both runs compare28 protected/task/frozen/runtime file hashes unchanged and confirm
same installed process PID11372/start2026-10-19T14:49:41.6798583Z. Installed agent
remains1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f. No restart/installation.

Logs, per-run exit records, exact release metadata and protected-file comparison
evidence are under QA/Engineering/CPV-Compatibility-20261019. Final preflight files:
elevated-preflight-final-ps51.* and elevated-preflight-final-ps7.*. Earlier failed
preflight logs retained separately. Elevated launcher has no Execute parameter.

## Next safe action and limits

READY FOR SEPARATE USER DEPLOYMENT AUTHORIZATION for the exact release above.
After authorization, use the supported installer with the same identities/hash and
-Execute in elevated PowerShell; revalidation must still pass at execution time.
Deployment authorization must explicitly cover replacing/restarting the QA Launch
Agent. It does not authorize reservation reset or recovery dispatch. Do not reuse
the consumed approval. A later reservation reset needs separate authorization and
fresh authenticated proof; any subsequent request/approval/dispatch is a separate
decision, with its current revision and expiry checks. No expiry was extended.

No engineering blocker remains for this agent deployment decision. Final native QA
is a separate limitation: frozen TestRunner reads model.rvt.fixture.json and does
not recognize the recovered companion file. The historical sidecar and frozen
candidate hashes remain unchanged; do not claim native readiness. A separately
supported disposable staging continuation or authorized new candidate is needed
before final QA. Neither was performed or silently substituted by this release.

COMPACTION / HANDOFF NOTES: resume revision122 and this immutable release, not the
older revision119 approval instructions. Runtime commit6119acea above; tooling-only
follow-up introduces this handoff. Original evidence/handoffs preserved. No reservation
reset, new approval, redispatch, protected evidence edit, deployment/restart or Revit
operation occurred. Next action is user review of exact guarded deployment only.
