$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Installer parse error.'}
$helper=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-CpvRevitProcesses'},$true).Extent.Text
$early=$ast.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text.Contains('Get-CpvRevitProcesses')},$true).Clauses[0].Item1.Extent.Text
$assignment=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$revit' -and $n.Right.Extent.Text.Contains('Get-CpvRevitProcesses')},$true).Extent.Text
$late=$ast.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$revit.Count'},$true).Clauses[0].Item1.Extent.Text
& {
    param($helper,$early,$assignment,$late)
    Set-StrictMode -Version Latest
    $script:fakeMode='empty'
    function Get-Process {param($Name,$ErrorAction)if($script:fakeMode -ceq 'unknown'){throw 'synthetic process access denied'};if($script:fakeMode -ceq 'present'){[pscustomobject]@{Id=123}}}
    Invoke-Expression $helper
    $count=0
    foreach($mode in @('empty','present')){
        $script:fakeMode=$mode
        $expected=$mode -ceq 'present'
        if([bool](Invoke-Expression $early) -ne $expected){throw 'Early process guard rejected expected shape.'};$count++
        Invoke-Expression $assignment
        if([bool](Invoke-Expression $late) -ne $expected){throw 'Late process guard rejected expected shape.'};$count++
    }
    $script:fakeMode='unknown'
    foreach($expression in @($early,$assignment)){
        $rejected=$false;try{Invoke-Expression $expression|Out-Null}catch{if($_.Exception.Message -notmatch 'synthetic process access denied'){throw};$rejected=$true}
        if(!$rejected){throw 'Unknown process state was accepted.'};$count++
    }
    "PASS: $count strict process-guard assertions; actual installer AST; injected processes only."
} $helper $early $assignment $late
