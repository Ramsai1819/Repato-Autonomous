Task task-bf61fe7f22d74df7a92599681da5919e; workflow fa2c2f578cbc40cbacac45c96313ca4c.

Actual outcome: Failed. User approval c01a2efa2d704d64ac0a03bca155ffc2 at revision 34 was validated. One Tara claim (3b86be2d21ca4f8ca85f4422e7f53eb9) and one native request (48bc83318cb04068b106625f1d9df77f) were dispatched for attempt d609705ad1bb46f9b5eddc4a81fd1872, run 71d2e887d7d741f5a085124ba26e152f. Native Revit PID 33544 ran in RepatoQA session 2. Result wait was configured to 7200 seconds; authorization expiry was not changed.

Native failure: `System.InvalidOperationException: Start a fresh Revit 2025 QA session with no open documents.` The launcher supplies the disposable model as a Revit command-line argument, while the frozen runner rejects open documents at startup. The journal confirms the exact disposable model opened before the runner. This is a launcher/runner contract mismatch; no second dispatch was attempted.

Report: QA/Reports/71d2e887d7d741f5a085124ba26e152f.json. SHA256 CCD9120C26BE74C29CE04B08A2836C7B0F11EC312CB6EB0D330C0EDDEAB70755.
Native failure receipt: QA/TestRuns/71d2e887d7d741f5a085124ba26e152f-retry/maya-tara-71d2e887d7d741f5a085124ba26e152f.request.json.result.json. SHA256 FF08F3816DFA38A3B218FF82129DD106E1A55025551B42180CA2CDAF24A1304C.
QA session screenshot: QA/Screenshots/cpv-71d2e887d7d741f5a085124ba26e152f-20261013-191003.png. It shows Revit UI, not proof of test success. The earlier screenshot at 190911 shows the coordinator session and is not Revit QA evidence.
Journal copy: QA/TestRuns/71d2e887d7d741f5a085124ba26e152f-retry/revit-journal.0114.txt.
Preflight evidence: QA/TestRuns/71d2e887d7d741f5a085124ba26e152f-retry/maya-approved-execution-preflight.json.

Request/result/report identities and frozen assembly SHA256 match. Only the request-identity assertion ran. CreatedIds, ChangedIds and DeletedIds are empty; RollbackStatus is NotStarted. No rollback success or passing receipt is claimed. The failed disposable QA PID was terminated without saving after process image, session, command line and launch time checks. The temporary QA screenshot task was removed.

Final canonical task revision: 38, status blocked, workflowStage qa; execution qa-failed / QaFailed, VerificationStatus Failed, CompletionStatus Failed. Supported guarded failure recording preserves report/result paths and hashes, native PID, claim, original attempt, approval history and fixture preparation evidence, without creating a replacement attempt.

Prepared model SHA256 remains 0F07DCC6F459E3880C14650302F90C0BFE935D00DBAA70F6E0FFF6E981D4AA6E. Frozen candidate SHA256 remains 8C3F6EF16790247B9949EADED8FF098B4D95598791011C418D003DAAC0680AB5. No fixture preparation, Release build, deployment, new approval or retry occurred. A correction and separately authorized retest are required; do not reuse this executed attempt.

Focused synthetic validation passed for correlated startup-failure bookkeeping, including stale revision and incorrect claim rejection without mutation. Starting commit f1f9ee087ddb39b55cfa0c14d5eaacd98a51ad75 remains reachable; no Revit QA passing baseline was promoted. Unrelated working-tree changes remain preserved.
