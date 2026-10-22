using System.Text.Json;
using Repato.QaLaunchAgent;

int assertions = 0;
void Check(bool value, string name) { assertions++; if (!value) throw new Exception(name); }
void Reject(Action action, string name) { assertions++; try { action(); } catch { return; } throw new Exception("Accepted " + name); }
string root = Path.Combine(Path.GetTempPath(), "repato-cpv-protocol-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try {
    if (args.Contains("--verify-failure-reporting"))
        throw new InvalidDataException("synthetic-failure-reporting-probe");
    var now = DateTimeOffset.UtcNow;
    var identity = new Identity();
    var evidence = new QaCandidateEvidence(1, "task-" + Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"),
        "create-plan-views-v1", "create-plan-views-v1", new string('a',40), "candidate", "candidate.dll", new string('A',64), new string('A',64), "manifest", new string('B',64), "provenance");
    CpvPreparationRequest Request() => new(1, CpvPreparationService.Operation, Guid.NewGuid().ToString("N"), evidence.TaskId,
        evidence.WorkflowId, Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), now.AddHours(3), 7200, evidence);
    string Json(CpvPreparationRequest r) => JsonSerializer.Serialize(r, CpvPreparationService.StrictJson);
    QaAgentOptions Options(string suffix) => new("never-revit.exe", root, root, Path.Combine(root,suffix+"ledger.json"), Path.Combine(root,suffix));
    var boundary = new Boundary(); var ledger = new Ledger(); var options = Options("valid");
    var service = new CpvPreparationService(options, identity, ledger, boundary);
    Check(JsonSerializer.SerializeToElement(service.Capabilities()).GetProperty("reconciliationOperation").GetString()==CpvPreparationService.ReconcileOperation,"authenticated capabilities advertise fixed reconciliation operation");
    var r = Request();
    var executing = (CpvPreparationReceipt)service.Handle(Json(r),now);
    Check(executing.Status == "Executing", "valid request reserves before execution");
    Check(((CpvPreparationReceipt)service.Handle(Json(r),now)).RequestId == r.RequestId, "identical retry returns existing receipt");
    Reject(()=>service.Handle(Json(r with { RunId = Guid.NewGuid().ToString("N") }),now),"same request different payload");
    Reject(()=>service.Handle(Json(Request()),now),"concurrent request");
    var restarted = new CpvPreparationService(options, identity, ledger, boundary);
    var interrupted = (CpvPreparationReceipt)restarted.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,r.RequestId),CpvPreparationService.StrictJson),now);
    Check(interrupted.Status == "OutcomeUnknown", "interrupted execution fails closed");
    boundary.Completion.SetResult(new(new string('C',64),new string('D',64),true,"CommittedDisposableFixtureOnly"));
    // Synthetic boundary also writes the request file expected by receipt hashing.
    CpvPreparationReceipt terminal = executing;
    for(int i=0;i<200 && terminal.Status=="Executing";i++) { await Task.Delay(5); terminal=(CpvPreparationReceipt)service.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,r.RequestId),CpvPreparationService.StrictJson),now); }
    Check(terminal.Status == "Passed" && terminal.CleanupVerified, "authenticated terminal receipt");
    Reject(()=>service.Handle(Json(Request() with { AttemptId=r.AttemptId }),now),"duplicate attempt");
    Reject(()=>service.Handle(Json(Request() with { RunId=r.RunId }),now),"duplicate run");
    foreach(var invalid in new[] {r with { AttemptId=new string('0',32) },r with { WorkflowId="bad" },r with { TaskId="other" },
        r with { ExpiresUtc=now },r with { TimeoutSeconds=0 },r with { Operation="powershell" },r with { SchemaVersion=2 }})
        Reject(()=>new CpvPreparationService(Options(Guid.NewGuid().ToString()),identity,new Ledger(),new Boundary()).Handle(Json(invalid),now),"invalid schema/identity/expiry");
    Reject(()=>service.Handle(Json(r).Replace("\"schemaVersion\":1","\"schemaVersion\":1,\"schemaVersion\":1"),now),"duplicate fields");
    Reject(()=>service.Handle(Json(r).Replace("\"schemaVersion\":1","\"arbitraryExecutable\":\"cmd.exe\",\"schemaVersion\":1"),now),"unknown fields");
    Reject(()=>service.Handle(Json(r with { CandidateEvidence=evidence with { TaskId="other" } }),now),"candidate task identity mismatch");
    Check(!QaLaunchPolicy.IsValidCandidateEvidence(evidence with { CandidateDllPath=Path.Combine(root,"arbitrary.dll") },r.TaskId,r.WorkflowId,evidence.QaWorkflowId,evidence.TestId),"production candidate root/hash policy rejects arbitrary DLL");
    Check(!QaLaunchPolicy.IsValidCandidateEvidence(evidence with { RunnerManifestPath=Path.Combine(root,"arbitrary.addin") },r.TaskId,r.WorkflowId,evidence.QaWorkflowId,evidence.TestId),"production manifest root/hash policy rejects arbitrary manifest");
    Reject(()=>new CpvPreparationService(Options("unauthorized"),new Identity{User="wrong"},new Ledger(),new Boundary()).Handle(Json(Request()),now),"unauthorized identity");
    Reject(()=>new CpvPreparationService(Options("sid"),new Identity{Sid="wrong"},new Ledger(),new Boundary()).Handle(Json(Request()),now),"wrong SID");
    Reject(()=>new CpvPreparationService(Options("session"),new Identity{Interactive=false},new Ledger(),new Boundary()).Handle(Json(Request()),now),"noninteractive");
    foreach(string code in new[]{"candidate-mismatch","manifest-mismatch","model-lock","revit-present","provenance-mismatch"}) {
        var bad=new Boundary{ValidationError=code};var l=new Ledger();
        Reject(()=>new CpvPreparationService(Options(code),identity,l,bad).Handle(Json(Request()),now),code);
        Check(l.Count==0,"invalid artifacts never reserve or launch");
    }
    foreach(string failure in new[]{"timeout","missing-result","cleanup-failure","ambiguous"}) {
        var b=new Boundary();var o=Options(failure);var s=new CpvPreparationService(o,identity,new Ledger(),b);var req=Request();s.Handle(Json(req),now);
        if(failure=="cleanup-failure") b.Completion.SetResult(new("C","D",false,"Unknown"));
        else b.Completion.SetException(failure=="timeout"?new TimeoutException():new IOException(failure));
        object response;CpvPreparationReceipt outcome;
        do {await Task.Delay(5);response=s.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,req.RequestId),CpvPreparationService.StrictJson),now);outcome=(CpvPreparationReceipt)response;}while(outcome.Status=="Executing");
        Check(outcome.Status!="Passed" && !outcome.CleanupVerified,"failure cannot approve: "+failure);
        Reject(()=>s.Handle(Json(Request()),now),"failed/ambiguous execution blocks retry");
    }
    string model=Path.Combine(root,"model.rvt");File.WriteAllText(model,"prepared");
    string result=JsonSerializer.Serialize(new { Status="Passed",Operation=CpvPreparationService.RunnerOperation,TaskId=r.TaskId,WorkflowId=r.WorkflowId,AttemptId=r.AttemptId,RunId=r.RunId,ModelPath=model,SourceModelSha256=CpvPreparationService.FixtureSha256,PreparedModelSha256=CpvPreparationService.Hash(model),Levels=new[]{new{ Name="0",ElevationMeters=0d,ElementId=1L},new{Name="1",ElevationMeters=4d,ElementId=2L},new{Name="2",ElevationMeters=7.8d,ElementId=3L}} });
    using (File.Open(model,FileMode.Open,FileAccess.ReadWrite,FileShare.None))
        Reject(()=>RevitCpvPreparationBoundary.VerifyResultAfterChildExit(result,r,model,()=>false),"result verification waits for owned Revit child exit");
    Reject(()=>RevitCpvPreparationBoundary.OpenModelExclusivelyAfterChildExit(model,()=>false,TimeSpan.FromMilliseconds(100)).GetAwaiter().GetResult(),"exclusive model open rejects a live child");
    RevitCpvPreparationBoundary.VerifyResultAfterChildExit(result,r,model,()=>true);Check(true,"exact prepared levels and result identity after child exit");
    var delayedLock=File.Open(model,FileMode.Open,FileAccess.ReadWrite,FileShare.None);
    var delayedRelease=Task.Run(async()=>{await Task.Delay(200);delayedLock.Dispose();});
    using(var acquired=RevitCpvPreparationBoundary.OpenModelExclusivelyAfterChildExit(model,()=>true,TimeSpan.FromSeconds(2),TimeSpan.FromMilliseconds(25)).GetAwaiter().GetResult())
        Check(acquired.CanRead,"exclusive model validation waits for delayed file release after child exit");
    delayedRelease.GetAwaiter().GetResult();
    Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result.Replace("7.8","8.8"),r,model),"wrong elevation");
    Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result.Replace(r.AttemptId,Guid.NewGuid().ToString("N")),r,model),"wrong result attempt");
    File.AppendAllText(model,"changed");Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result,r,model),"prepared bytes mismatch");
    (CpvPreparationReceipt Receipt,CpvPreparationService Service,CpvPreparationReconciliation Query,string Store,string RequestJson) ReconciliationCase(string name, Boundary boundary, bool corruptModel = false, bool resultPresent = false, bool lockPresent = false, bool corruptRunner = false, bool wrongIdentity = false)
    {
        string testRoot=Path.Combine(root,"reconcile-"+name),logRoot=Path.Combine(testRoot,"logs"),store=Path.Combine(logRoot,"CpvPreparation"),runtime=Path.Combine(testRoot,"runtime");Directory.CreateDirectory(store);Directory.CreateDirectory(runtime);
        var rr=Request();string run=Path.Combine(runtime,"cpv-preparation-"+rr.RunId);Directory.CreateDirectory(run);
        string modelPath=Path.Combine(run,"model.rvt"),runnerPath=Path.Combine(run,"tara-"+rr.AttemptId+".request.json");
        File.Copy(@"C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt",modelPath);
        if(corruptModel)File.AppendAllText(modelPath,"corrupt");
        var runner=new {schemaVersion=1,operation=CpvPreparationService.RunnerOperation,requestId=rr.AttemptId,taskId=rr.TaskId,workflowId=rr.WorkflowId,attemptId=rr.AttemptId,runId=rr.RunId,requestPath=runnerPath,modelPath,modelSha256=CpvPreparationService.FixtureSha256,selectedManifestPath=QaLaunchPolicy.ExpectedRunnerManifestPath,selectedManifestSha256=rr.CandidateEvidence.RunnerManifestSha256,outputPath=runnerPath+".preparation.json",expiresUtc=rr.ExpiresUtc};
        File.WriteAllText(runnerPath,JsonSerializer.Serialize(runner));if(corruptRunner)File.WriteAllText(runnerPath,"{}");if(resultPresent)File.WriteAllText(runnerPath+".preparation.json","{}");if(lockPresent)File.WriteAllText(modelPath+".slog","");
        var rec=new CpvPreparationReceipt(1,CpvPreparationService.Operation,rr.RequestId,rr.TaskId,rr.WorkflowId,rr.AttemptId,rr.RunId,"OutcomeUnknown",identity.User,identity.Sid,identity.SessionId,rr.CandidateEvidence.CandidateDllSha256,rr.CandidateEvidence.RunnerManifestSha256,modelPath,"",runnerPath,"","","",false,"Unknown","preparation-failed-reconcile-required",rr.ExpiresUtc);
        string requestJson=Json(rr);File.WriteAllText(Path.Combine(store,"active.json"),requestJson);File.WriteAllText(Path.Combine(store,rr.RequestId+".request.json"),requestJson);File.WriteAllText(Path.Combine(store,rr.RequestId+".failure.txt"),"System.IO.InvalidDataException: preparation-exited-without-result");File.WriteAllText(Path.Combine(store,rr.RequestId+".json"),JsonSerializer.Serialize(rec,CpvPreparationService.StrictJson));
        var svc=new CpvPreparationService(Options("reconcile-"+name) with {LogRoot=logRoot,RuntimeRoot=runtime},identity,new Ledger(),boundary);
        var query=new CpvPreparationReconciliation(1,CpvPreparationService.ReconcileOperation,rr.RequestId,rr.TaskId,wrongIdentity?Guid.NewGuid().ToString("N"):rr.WorkflowId,rr.AttemptId,rr.RunId);
        var terminal=(CpvPreparationReceipt)svc.Handle(JsonSerializer.Serialize(query,CpvPreparationService.StrictJson),now);
        return (terminal,svc,query,store,requestJson);
    }
    var reconcileBoundary=new Boundary();
    var failedReconciled=ReconciliationCase("valid",reconcileBoundary);
    Check(failedReconciled.Receipt.Status=="FailedReconciled" && !failedReconciled.Receipt.CleanupVerified && failedReconciled.Receipt.FailureCode=="preparation-exited-without-result","valid evidence reconciles only to terminal failure");
    Check(!File.Exists(Path.Combine(failedReconciled.Store,"active.json")),"validated agent reconciliation removes only its active marker");
    Reject(()=>ReconciliationCase("identity-mismatch",new Boundary(),wrongIdentity:true),"identity-mismatch");
    Reject(()=>ReconciliationCase("bad-model",new Boundary(),corruptModel:true),"model-hash-mismatch");
    Reject(()=>ReconciliationCase("bad-runner",new Boundary(),corruptRunner:true),"runner-request-mismatch");
    Reject(()=>ReconciliationCase("result",new Boundary(),resultPresent:true),"result-or-lock");
    Reject(()=>ReconciliationCase("lock",new Boundary(),lockPresent:true),"result-or-lock");
    var uncertainProcess=new Boundary{ReconciliationError="reconciliation-process-state-unknown"};Reject(()=>ReconciliationCase("process-unknown",uncertainProcess),"process-state-unknown");
    Check(true,"unreadable process evidence fails closed through injected boundary");
    var replayed=(CpvPreparationReceipt)failedReconciled.Service.Handle(JsonSerializer.Serialize(failedReconciled.Query,CpvPreparationService.StrictJson),now);
    Check(replayed.Status=="FailedReconciled","duplicate agent reconciliation is idempotent after marker removal");
    File.WriteAllText(Path.Combine(failedReconciled.Store,"active.json"),failedReconciled.RequestJson);
    string receiptPath=Path.Combine(failedReconciled.Store,replayed.RequestId+".json");
    var interruptedReceipt=replayed with {Status="OutcomeUnknown",RequestSha256="",FailureCode="preparation-failed-reconcile-required",RollbackStatus="Unknown"};
    File.WriteAllText(receiptPath,JsonSerializer.Serialize(interruptedReceipt,CpvPreparationService.StrictJson));
    string orphanedPartial=receiptPath+".crash.reconcile.partial";File.WriteAllText(orphanedPartial,"interrupted partial evidence");
    var resumed=(CpvPreparationReceipt)failedReconciled.Service.Handle(JsonSerializer.Serialize(failedReconciled.Query,CpvPreparationService.StrictJson),now);
    Check(resumed.Status=="FailedReconciled" && File.Exists(orphanedPartial) && !File.Exists(Path.Combine(failedReconciled.Store,"active.json")),"interrupted partial is preserved while terminal receipt resumes safely");
    (CpvPreparationRecoveryCommit Commit,CpvPreparationService Service,string Store,string OriginalJson,CpvPreparationCompletedRecovery Query) CompletedRecoveryCase(string name, bool corruptResult=false, bool missingResult=false, bool wrongBinding=false, bool expiredAuthorization=false, bool corruptModel=false, int receiptSession=-1, string? receiptUser=null, string? receiptSid=null)
    {
        string testRoot=Path.Combine(root,"completed-recovery-"+name),logRoot=Path.Combine(testRoot,"logs"),store=Path.Combine(logRoot,"CpvPreparation"),runtime=Path.Combine(testRoot,"runtime");Directory.CreateDirectory(store);Directory.CreateDirectory(runtime);
        var rr=Request();string run=Path.Combine(runtime,"cpv-preparation-"+rr.RunId);Directory.CreateDirectory(run);
        string modelPath=Path.Combine(run,"model.rvt"),runnerPath=Path.Combine(run,"tara-"+rr.AttemptId+".request.json"),resultPath=runnerPath+".preparation.json";
        File.Copy(@"C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt",modelPath);
        File.AppendAllText(modelPath,"prepared");
        File.WriteAllText(modelPath+".fixture.json", "{\"fixtureId\":\"CreatePlanViewsEmpty\",\"sourceSha256\":\""+CpvPreparationService.FixtureSha256+"\"}");
        string modelHash=CpvPreparationService.Hash(modelPath);
        if(corruptModel) File.AppendAllText(modelPath,"changed");
        var runner=new {schemaVersion=1,operation=CpvPreparationService.RunnerOperation,requestId=rr.AttemptId,taskId=rr.TaskId,workflowId=rr.WorkflowId,attemptId=rr.AttemptId,runId=rr.RunId,requestPath=runnerPath,modelPath,modelSha256=CpvPreparationService.FixtureSha256,selectedManifestPath=QaLaunchPolicy.ExpectedRunnerManifestPath,selectedManifestSha256=rr.CandidateEvidence.RunnerManifestSha256,outputPath=resultPath,expiresUtc=rr.ExpiresUtc};
        File.WriteAllText(runnerPath,JsonSerializer.Serialize(runner));
        string result=JsonSerializer.Serialize(new {Status="Passed",Operation=CpvPreparationService.RunnerOperation,TaskId=rr.TaskId,WorkflowId=rr.WorkflowId,AttemptId=rr.AttemptId,RunId=rr.RunId,ModelPath=modelPath,SourceModelSha256=CpvPreparationService.FixtureSha256,PreparedModelSha256=modelHash,Levels=new[]{new{Name="0",ElevationMeters=0d,ElementId=101L},new{Name="1",ElevationMeters=4d,ElementId=202L},new{Name="2",ElevationMeters=7.8d,ElementId=303L}}});
        if(!missingResult) File.WriteAllText(resultPath,corruptResult?result.Replace(rr.RunId,Guid.NewGuid().ToString("N")):result);
        var original=new CpvPreparationReceipt(1,CpvPreparationService.Operation,rr.RequestId,rr.TaskId,rr.WorkflowId,rr.AttemptId,rr.RunId,"OutcomeUnknown",receiptUser??identity.User,receiptSid??identity.Sid,receiptSession<0?identity.SessionId:receiptSession,rr.CandidateEvidence.CandidateDllSha256,rr.CandidateEvidence.RunnerManifestSha256,modelPath,"",runnerPath,"","","",false,"Unknown","preparation-failed-reconcile-required",rr.ExpiresUtc);
        string originalJson=JsonSerializer.Serialize(original,CpvPreparationService.StrictJson),requestJson=Json(rr);
        string originalPath=Path.Combine(store,rr.RequestId+".json"),requestPath=Path.Combine(store,rr.RequestId+".request.json");
        File.WriteAllText(originalPath,originalJson);File.WriteAllText(requestPath,requestJson);File.WriteAllText(Path.Combine(store,"active.json"),requestJson);string failurePath=Path.Combine(store,rr.RequestId+".failure.txt");File.WriteAllText(failurePath,"IOException: model remained locked after Revit child exit");
        var q=new CpvPreparationCompletedRecovery(1,CpvPreparationService.RecoverCompletedOperation,rr.RequestId,rr.TaskId,rr.WorkflowId,rr.AttemptId,rr.RunId,Guid.NewGuid().ToString("N"),101,new string('E',64),expiredAuthorization?now.AddMinutes(-1):now.AddMinutes(10),CpvPreparationService.Hash(originalPath),CpvPreparationService.Hash(Path.Combine(store,"active.json")),CpvPreparationService.Hash(failurePath),CpvPreparationService.Hash(requestPath),missingResult?new string('0',64):CpvPreparationService.Hash(resultPath),wrongBinding?new string('0',64):modelHash);
        var svc=new CpvPreparationService(Options("completed-"+name) with {LogRoot=logRoot,RuntimeRoot=runtime},identity,new Ledger(),boundary);
        return (null!,svc,store,originalJson,q);
    }
    var sourceSidecarCase=CompletedRecoveryCase("source-only-sidecar");
    var sourceSidecarModel=JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(Path.Combine(sourceSidecarCase.Store,sourceSidecarCase.Query.RequestId+".request.json")),CpvPreparationService.StrictJson)!;
    var sourceSidecarPath=Path.Combine(root,"completed-recovery-source-only-sidecar","runtime","cpv-preparation-"+sourceSidecarModel.RunId,"model.rvt.fixture.json");
    const string sourceSidecarJson="{\"fixtureId\":\"CreatePlanViewsEmpty\",\"sourceSha256\":\"92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45\"}";
    File.WriteAllText(sourceSidecarPath,sourceSidecarJson);
    using(var sourceDocument=JsonDocument.Parse(sourceSidecarJson)) {
        try { sourceDocument.RootElement.GetProperty("preparedModelSha256"); throw new Exception("Legacy missing-property failure not reproduced"); }
        catch(KeyNotFoundException ex) { Check(NamedPipeLaunchServer.PreparedFailureCode(ex)=="preparation-rejected-or-reconcile-required","source-only sidecar reproduces masked legacy failure"); }
    }
    var sourceCommit=(CpvPreparationRecoveryCommit)sourceSidecarCase.Service.Handle(JsonSerializer.Serialize(sourceSidecarCase.Query,CpvPreparationService.StrictJson),now);
    Check(File.ReadAllText(sourceSidecarPath)==sourceSidecarJson,"historical source-only sidecar remains byte-for-byte unchanged");
    Check(sourceCommit.RecoveredProvenancePath==sourceCommit.Receipt.ModelPath+".recovered.fixture.json" &&
        CpvPreparationService.Hash(sourceCommit.RecoveredProvenancePath)==sourceCommit.RecoveredProvenanceSha256,"separate recovered provenance published and bound to durable commit");
    using(var provenance=JsonDocument.Parse(File.ReadAllText(sourceCommit.RecoveredProvenancePath!))) {
        var p=provenance.RootElement;
        Check(p.GetProperty("historicalSidecarSha256").GetString()==CpvPreparationService.Hash(sourceSidecarPath),"provenance binds exact historical sidecar bytes");
        Check(p.GetProperty("approvalBindingHash").GetString()==sourceSidecarCase.Query.ApprovalBindingHash &&
            p.GetProperty("originalReceiptSha256").GetString()==sourceSidecarCase.Query.OriginalReceiptSha256 &&
            p.GetProperty("activeMarkerSha256").GetString()==sourceSidecarCase.Query.ActiveMarkerSha256 &&
            p.GetProperty("failureEvidenceSha256").GetString()==sourceSidecarCase.Query.FailureEvidenceSha256 &&
            p.GetProperty("requestSha256").GetString()==sourceSidecarCase.Query.RequestSha256,"provenance retains approved evidence and approval binding identities");
    }
    foreach(var historical in new[]{"{}",sourceSidecarJson.Replace("CreatePlanViewsEmpty","WrongFixture"),sourceSidecarJson.Replace(CpvPreparationService.FixtureSha256,new string('0',64)),sourceSidecarJson.TrimEnd('}')+",\"preparedModelSha256\":\""+new string('A',64)+"\"}",sourceSidecarJson.TrimEnd('}')+",\"sourceSha256\":\""+CpvPreparationService.FixtureSha256+"\"}"}) {
        var bad=CompletedRecoveryCase("bad-history-"+Guid.NewGuid().ToString("N"));
        string badHistoryModel=JsonSerializer.Deserialize<CpvPreparationReceipt>(bad.OriginalJson,CpvPreparationService.StrictJson)!.ModelPath;
        File.WriteAllText(badHistoryModel+".fixture.json",historical);
        Reject(()=>bad.Service.Handle(JsonSerializer.Serialize(bad.Query,CpvPreparationService.StrictJson),now),"reject invalid, duplicate, or partially prepared historical sidecar");
        Check(File.ReadAllText(badHistoryModel+".fixture.json")==historical && !File.Exists(badHistoryModel+".recovered.fixture.json") && File.Exists(Path.Combine(bad.Store,"active.json")),"invalid history remains unchanged and publishes no recovered provenance");
    }
    var missingHistory=CompletedRecoveryCase("missing-history");
    string missingModel=JsonSerializer.Deserialize<CpvPreparationReceipt>(missingHistory.OriginalJson,CpvPreparationService.StrictJson)!.ModelPath;
    File.Delete(missingModel+".fixture.json");
    try { missingHistory.Service.Handle(JsonSerializer.Serialize(missingHistory.Query,CpvPreparationService.StrictJson),now); throw new Exception("Missing history unexpectedly accepted"); }
    catch (InvalidDataException ex) { Check(ex.Message=="completed-recovery-historical-sidecar-missing","missing historical evidence produces the exact fail-closed diagnostic without crashing the harness"); }
    var preparedHistory=CompletedRecoveryCase("prepared-history");
    var preparedReceipt=JsonSerializer.Deserialize<CpvPreparationReceipt>(preparedHistory.OriginalJson,CpvPreparationService.StrictJson)!;
    string preparedHistoryJson=JsonSerializer.Serialize(new {fixtureId="CreatePlanViewsEmpty",sourceSha256=CpvPreparationService.FixtureSha256,
        preparedModelSha256=preparedHistory.Query.ModelSha256,fixturePreparationRequestPath=preparedReceipt.RequestPath,
        fixturePreparationRequestSha256=CpvPreparationService.Hash(preparedReceipt.RequestPath),fixturePreparationResultPath=preparedReceipt.RequestPath+".preparation.json",
        fixturePreparationResultSha256=preparedHistory.Query.ResultSha256,fixturePreparationAttemptId=preparedHistory.Query.AttemptId,
        fixturePreparationRunId=preparedHistory.Query.RunId});
    File.WriteAllText(preparedReceipt.ModelPath+".fixture.json",preparedHistoryJson);
    var preparedCommit=(CpvPreparationRecoveryCommit)preparedHistory.Service.Handle(JsonSerializer.Serialize(preparedHistory.Query,CpvPreparationService.StrictJson),now);
    Check(preparedCommit.Receipt.Status=="Passed" && File.ReadAllText(preparedReceipt.ModelPath+".fixture.json")==preparedHistoryJson,"fully bound legacy prepared history is accepted and preserved");
    var collisionCase=CompletedRecoveryCase("publication-collision");
    string collisionModel=JsonSerializer.Deserialize<CpvPreparationReceipt>(collisionCase.OriginalJson,CpvPreparationService.StrictJson)!.ModelPath;
    File.WriteAllText(collisionModel+".recovered.fixture.json","unrelated protected evidence");
    Reject(()=>collisionCase.Service.Handle(JsonSerializer.Serialize(collisionCase.Query,CpvPreparationService.StrictJson),now),"unmatched recovered provenance is never overwritten");
    Check(File.ReadAllText(collisionModel+".recovered.fixture.json")=="unrelated protected evidence","publication collision preserves existing evidence");
    var completedBoundary=new Boundary();
    var completed=CompletedRecoveryCase("valid");
    var committed=(CpvPreparationRecoveryCommit)completed.Service.Handle(JsonSerializer.Serialize(completed.Query,CpvPreparationService.StrictJson),now);
    Check(committed.Receipt.Status=="Passed" && committed.Receipt.CleanupVerified && committed.Receipt.RollbackStatus=="CommittedDisposableFixtureOnly","authenticated recovery requires passed result and exclusive model verification");
    Check(File.ReadAllText(Path.Combine(completed.Store,completed.Query.RequestId+".json"))==completed.OriginalJson,"recovery preserves original failure receipt bytes");
    Check(!File.Exists(Path.Combine(completed.Store,"active.json")) && File.Exists(Path.Combine(completed.Store,completed.Query.RequestId+".recovered.json")),"recovery receipt is durable before exact active marker removal");
    var recoveredStatus=(CpvPreparationReceipt)completed.Service.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,completed.Query.RequestId),CpvPreparationService.StrictJson),now);
    Check(recoveredStatus.Status=="Passed" && recoveredStatus.ModelSha256==completed.Query.ModelSha256,"status exposes verified recovery only after marker removal");
    var recoveryCommitStatus=(CpvPreparationRecoveryCommit)completed.Service.Handle(JsonSerializer.Serialize(new CpvPreparationCompletedRecoveryStatus(1,CpvPreparationService.RecoverCompletedStatusOperation,completed.Query.RequestId),CpvPreparationService.StrictJson),now);
    Check(recoveryCommitStatus.RecoveryApprovalId==completed.Query.RecoveryApprovalId && recoveryCommitStatus.ExpectedTaskRevision==completed.Query.ExpectedTaskRevision,"authenticated recovery status binds terminal evidence to approval and task revision");
    string terminalCommitPath=Path.Combine(completed.Store,completed.Query.RequestId+".recovered.json");
    string terminalCommitBytes=File.ReadAllText(terminalCommitPath),provenanceBytes=File.ReadAllText(committed.RecoveredProvenancePath!);
    string requestEvidenceBytes=File.ReadAllText(Path.Combine(completed.Store,completed.Query.RequestId+".request.json"));
    // Simulate interruption after publishing the commit but before removing the marker.
    File.WriteAllText(Path.Combine(completed.Store,"active.json"),requestEvidenceBytes);
    var resumedCommit=(CpvPreparationRecoveryCommit)completed.Service.Handle(JsonSerializer.Serialize(completed.Query,CpvPreparationService.StrictJson),now.AddSeconds(1));
    Check(resumedCommit==committed && File.ReadAllText(terminalCommitPath)==terminalCommitBytes &&
        File.ReadAllText(committed.RecoveredProvenancePath!)==provenanceBytes,"interrupted durable commit resumes idempotently without rewriting commit or provenance");
    Check(File.ReadAllText(Path.Combine(completed.Store,completed.Query.RequestId+".json"))==completed.OriginalJson &&
        File.ReadAllText(Path.Combine(completed.Store,completed.Query.RequestId+".request.json"))==requestEvidenceBytes,"idempotent completion preserves original receipt and request evidence");
    object RecoveryStatus() => completed.Service.Handle(JsonSerializer.Serialize(new CpvPreparationCompletedRecoveryStatus(1,CpvPreparationService.RecoverCompletedStatusOperation,completed.Query.RequestId),CpvPreparationService.StrictJson),now);
    File.AppendAllText(committed.RecoveredProvenancePath!," ");
    Reject(()=>RecoveryStatus(),"status refuses changed recovered provenance hash");
    File.WriteAllText(committed.RecoveredProvenancePath!,provenanceBytes);
    string historicalBytes=File.ReadAllText(committed.Receipt.ModelPath+".fixture.json");
    File.AppendAllText(committed.Receipt.ModelPath+".fixture.json"," ");
    Reject(()=>RecoveryStatus(),"status refuses changed historical sidecar even semantically identical JSON");
    File.WriteAllText(committed.Receipt.ModelPath+".fixture.json",historicalBytes);
    File.Delete(committed.RecoveredProvenancePath!);
    Reject(()=>RecoveryStatus(),"status refuses missing recovered provenance");
    File.WriteAllText(committed.RecoveredProvenancePath!,provenanceBytes);
    Check((CpvPreparationRecoveryCommit)RecoveryStatus()==committed,"restoring exact synthetic evidence restores authenticated status");
    Reject(()=>completed.Service.Handle(JsonSerializer.Serialize(completed.Query,CpvPreparationService.StrictJson),now),"duplicate completed recovery after terminal commit");
    foreach(var item in new[]{CompletedRecoveryCase("bad-result",corruptResult:true),CompletedRecoveryCase("missing-result",missingResult:true),CompletedRecoveryCase("model-binding",wrongBinding:true),CompletedRecoveryCase("bad-model",corruptModel:true),CompletedRecoveryCase("expired",expiredAuthorization:true)})
    {
        Reject(()=>item.Service.Handle(JsonSerializer.Serialize(item.Query,CpvPreparationService.StrictJson),now),"invalid completed recovery evidence or expiry");
        Check(File.Exists(Path.Combine(item.Store,"active.json")),"failed recovery preserves active marker");
    }
    var restartedCase=CompletedRecoveryCase("agent-restarted-session",receiptSession:2);
    var restartedCommit=(CpvPreparationRecoveryCommit)restartedCase.Service.Handle(JsonSerializer.Serialize(restartedCase.Query,CpvPreparationService.StrictJson),now);
    Check(restartedCommit.Receipt.Status=="Passed" && restartedCommit.Receipt.CleanupVerified && restartedCommit.Receipt.RollbackStatus=="CommittedDisposableFixtureOnly","regression: recovery completes when the agent restarted into a different Windows session");
    Check(identity.SessionId==1 && restartedCommit.Receipt.SessionId==2,"recovery preserves the historical receipt's recorded session while running under the current session");
    Check(restartedCommit.Receipt.User==identity.User && restartedCommit.Receipt.Sid==identity.Sid,"recovery requires the historical receipt to bind the same user and SID as the current session");
    Reject(()=>new CpvPreparationService(Options("recovery-noninteractive"),new Identity{Interactive=false},new Ledger(),new Boundary()).Handle(JsonSerializer.Serialize(restartedCase.Query,CpvPreparationService.StrictJson),now),"recover-completed still requires a live interactive current session");
    Reject(()=>new CpvPreparationService(Options("recovery-wronguser"),new Identity{User="wrong"},new Ledger(),new Boundary()).Handle(JsonSerializer.Serialize(restartedCase.Query,CpvPreparationService.StrictJson),now),"recover-completed still requires the authorized current user");
    Reject(()=>new CpvPreparationService(Options("recovery-wrongsid"),new Identity{Sid="wrong"},new Ledger(),new Boundary()).Handle(JsonSerializer.Serialize(restartedCase.Query,CpvPreparationService.StrictJson),now),"recover-completed still requires the authorized current SID");
    var sessionZeroCase=CompletedRecoveryCase("receipt-session-zero",receiptSession:0);
    Reject(()=>sessionZeroCase.Service.Handle(JsonSerializer.Serialize(sessionZeroCase.Query,CpvPreparationService.StrictJson),now),"recovery rejects a receipt that did not record a positive interactive session");
    var otherUserCase=CompletedRecoveryCase("receipt-other-user",receiptUser:"Ramsai\\SomeoneElse");
    Reject(()=>otherUserCase.Service.Handle(JsonSerializer.Serialize(otherUserCase.Query,CpvPreparationService.StrictJson),now),"recovery still rejects a receipt written by a different account");
    var otherSidCase=CompletedRecoveryCase("receipt-other-sid",receiptSid:"S-1-5-21-0-0-0-1000");
    Reject(()=>otherSidCase.Service.Handle(JsonSerializer.Serialize(otherSidCase.Query,CpvPreparationService.StrictJson),now),"recovery still rejects a receipt written by a different SID");
    Check(NamedPipeLaunchServer.PreparedFailureCode(new InvalidDataException("completed-recovery-path-or-process-evidence-invalid"))=="completed-recovery-path-or-process-evidence-invalid","agent surfaces the specific CPV failure token to the authenticated client");
    Check(NamedPipeLaunchServer.PreparedFailureCode(new InvalidDataException("completed-recovery-original-receipt-changed"))=="completed-recovery-original-receipt-changed","agent surfaces every distinct CPV recovery failure token");
    Check(NamedPipeLaunchServer.PreparedFailureCode(new IOException("model locked at C:\\Repato-Autonomous\\Source\\QA\\TestRuns\\model.rvt"))=="preparation-rejected-or-reconcile-required","agent never leaks path-bearing or on-token errors outside the CPV vocabulary");
    Check(NamedPipeLaunchServer.PreparedFailureCode(new InvalidOperationException("Unattended preparation stopped at dialog: Save As"))=="preparation-rejected-or-reconcile-required","agent never leaks dialog text or mixed-case detail");
    Check(NamedPipeLaunchServer.PreparedFailureCode(new InvalidDataException(new string('a',200)))=="preparation-rejected-or-reconcile-required","agent bounds the surfaced failure token length");
    CpvPreparationCompletedRecoveryReconcile ReconcileQuery(CpvPreparationCompletedRecovery r) =>
        new(1,CpvPreparationService.RecoverCompletedReconcileOperation,r.RequestId,r.TaskId,r.WorkflowId,r.AttemptId,r.RunId,r.RecoveryApprovalId,
            r.ApprovalBindingHash,r.OriginalReceiptSha256,r.ActiveMarkerSha256,r.FailureEvidenceSha256,r.RequestSha256);
    string ReconcileJson(CpvPreparationCompletedRecoveryReconcile q) => JsonSerializer.Serialize(q,CpvPreparationService.StrictJson);
    string StatusOf(object o) => JsonSerializer.SerializeToElement(o).GetProperty("status").GetString()!;
    Check(JsonSerializer.SerializeToElement(service.Capabilities()).GetProperty("recoveryReconcileOperation").GetString()==CpvPreparationService.RecoverCompletedReconcileOperation,"authenticated capabilities advertise the completed-recovery reconcile operation");
    var reconcilePending=CompletedRecoveryCase("reconcile-notexecuted");
    var before=reconcilePending.Service.Handle(ReconcileJson(ReconcileQuery(reconcilePending.Query)),now);
    Check(StatusOf(before)=="NotExecuted" && JsonSerializer.SerializeToElement(before).GetProperty("activeMarkerSha256").GetString()==reconcilePending.Query.ActiveMarkerSha256,"positive non-execution evidence reconciles to NotExecuted, never to a bare Not-found");
    Check(File.Exists(Path.Combine(reconcilePending.Store,"active.json")),"read-only recovery reconciliation preserves the active marker");
    Reject(()=>reconcilePending.Service.Handle(ReconcileJson(ReconcileQuery(reconcilePending.Query) with { TaskId="task-"+Guid.NewGuid().ToString("N") }),now),"reconcile rejects identity mismatch");
    Reject(()=>reconcilePending.Service.Handle(ReconcileJson(ReconcileQuery(reconcilePending.Query) with { OriginalReceiptSha256=new string('0',64) }),now),"reconcile rejects a changed original receipt");
    Reject(()=>reconcilePending.Service.Handle(ReconcileJson(ReconcileQuery(reconcilePending.Query) with { RequestSha256=new string('0',64) }),now),"reconcile rejects changed request evidence");
    var executedReconcile=completed.Service.Handle(ReconcileJson(ReconcileQuery(completed.Query)),now);
    Check(JsonSerializer.SerializeToElement(executedReconcile).GetProperty("status").GetString()=="Executed" &&
        JsonSerializer.SerializeToElement(executedReconcile).GetProperty("recoveryApprovalId").GetString()==completed.Query.RecoveryApprovalId,"committed recovery reconciles to Executed bound to its approval");
    Reject(()=>completed.Service.Handle(ReconcileJson(ReconcileQuery(completed.Query) with { ApprovalBindingHash=new string('0',64) }),now),"Executed reconcile refuses a mismatched approval binding");
    Reject(()=>completed.Service.Handle(ReconcileJson(ReconcileQuery(completed.Query) with { OriginalReceiptSha256=new string('0',64) }),now),"Executed reconcile refuses changed original evidence binding");
    Reject(()=>collisionCase.Service.Handle(ReconcileJson(ReconcileQuery(collisionCase.Query)),now),"orphaned provenance prevents a false NotExecuted attestation");
    var publicationInterrupted=CompletedRecoveryCase("publication-interrupted");
    var publicationCommit=(CpvPreparationRecoveryCommit)publicationInterrupted.Service.Handle(JsonSerializer.Serialize(publicationInterrupted.Query,CpvPreparationService.StrictJson),now);
    string publicationBytes=File.ReadAllText(publicationCommit.RecoveredProvenancePath!);
    File.Delete(Path.Combine(publicationInterrupted.Store,publicationInterrupted.Query.RequestId+".recovered.json"));
    File.WriteAllText(Path.Combine(publicationInterrupted.Store,"active.json"),File.ReadAllText(Path.Combine(publicationInterrupted.Store,publicationInterrupted.Query.RequestId+".request.json")));
    Reject(()=>publicationInterrupted.Service.Handle(ReconcileJson(ReconcileQuery(publicationInterrupted.Query)),now),"interrupted provenance publication requires positive repair rather than non-execution reset");
    var publicationResumed=(CpvPreparationRecoveryCommit)publicationInterrupted.Service.Handle(JsonSerializer.Serialize(publicationInterrupted.Query,CpvPreparationService.StrictJson),now.AddSeconds(1));
    Check(publicationResumed.Receipt.Status=="Passed" && File.ReadAllText(publicationCommit.RecoveredProvenancePath!)==publicationBytes,"exact interrupted provenance publication resumes without evidence rewrite");
    Console.WriteLine($"PASS: {assertions} CPV preparation protocol assertions; injected processes only; Revit launched=false.");
} catch (Exception ex) {
    // Report assertion/setup failures as a normal nonzero exit, without Windows Error Reporting UI.
    Console.Error.WriteLine(ex);
    Environment.ExitCode = 1;
} finally {
    try { Directory.Delete(root,true); }
    catch (Exception ex) { Console.Error.WriteLine("Synthetic fixture cleanup failed: " + ex); Environment.ExitCode = 1; }
}

sealed class Identity:IIdentitySessionProvider {public string User{get;set;}=QaLaunchPolicy.ExpectedUser;public string Sid{get;set;}=QaLaunchPolicy.ExpectedUserSid;public int SessionId=>1;public bool Interactive{get;set;}=true;}
sealed class Ledger:IReplayLedger {readonly HashSet<string> keys=[];public int Count=>keys.Count;public bool TryReserve(string id,DateTimeOffset now)=>keys.Add(id);public bool TryReserve(QaLaunchRequest r,DateTimeOffset now)=>TryReserve(r.RequestId,now);}
sealed class Boundary:ICpvPreparationBoundary {
    public string? ValidationError{get;set;}
    public string? ReconciliationError{get;set;}
    public TaskCompletionSource<CpvPreparationOutcome> Completion{get;}=new(TaskCreationOptions.RunContinuationsAsynchronously);
    public void Validate(CpvPreparationRequest r){if(ValidationError!=null)throw new InvalidDataException(ValidationError);}
    public IDisposable ValidateReconciliation(CpvPreparationRequest r,CpvPreparationReceipt receipt,string expectedModelSha256){if(ReconciliationError!=null)throw new InvalidDataException(ReconciliationError);var stream=File.Open(receipt.ModelPath,FileMode.Open,FileAccess.Read,FileShare.None);if(Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream))!=expectedModelSha256){stream.Dispose();throw new InvalidDataException("reconciliation-model-hash-mismatch");}return stream;}
    public async Task<CpvPreparationOutcome> Execute(CpvPreparationRequest r,string dir){Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,"tara-"+r.AttemptId+".request.json"),"synthetic");return await Completion.Task;}
}
