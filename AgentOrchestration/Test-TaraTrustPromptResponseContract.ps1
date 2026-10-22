$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1'
Import-Module $modulePath -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.TaraRevitQa
$root=Join-Path ([IO.Path]::GetTempPath()) ('tara-prompt-contract-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
try {
    $resultPath=Join-Path $root 'result.json'
    [IO.File]::WriteAllText($resultPath,'{}')
    $plan=[pscustomobject]@{
        TrustConfiguration=[pscustomobject]@{PromptRecords=@()}
        TimeoutSeconds=7200
        ResultPath=$resultPath
        InstalledManifest=Join-Path $root 'runner.addin'
        TaskId='synthetic-task'
        WorkflowId='synthetic-workflow'
        RequestId='11111111111111111111111111111111'
        RunId='22222222222222222222222222222222'
        QaRunnerManifestSha256=('A'*64)
        Context=[pscustomobject]@{ArtifactSha256=('B'*64)}
    }
    $process=[Diagnostics.Process]::GetCurrentProcess()
    $handler=[pscustomobject]@{Handled=@()}
    $response=& $module {param($p,$proc,$h) Handle-TaraTrustPrompt $p $proc $h} $plan $process $handler
    if(!$response.PromptFree -or $response.PromptDetected -or $response.PromptAction -ne 'None'){
        throw 'Synthetic no-prompt response did not remain prompt-free and unapproved.'
    }
    if($response.PSObject.Properties.Name -notcontains 'ManualApprovalEvidence' -or $null -ne $response.ManualApprovalEvidence){
        throw 'Automatic prompt response must carry an explicit null ManualApprovalEvidence value.'
    }
    'Tara trust-prompt response contract passed: automatic no-prompt response includes explicit null manual evidence.'
} finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
