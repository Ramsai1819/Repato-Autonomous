$ErrorActionPreference='Stop'
$manifest=Join-Path $PSScriptRoot '..\QA\Repato.CreatePlanViews.TestRunner.addin'
[xml]$xml=Get-Content -LiteralPath $manifest -Raw
$assembly=$xml.RevitAddIns.AddIn.Assembly
if($assembly -cne '.\RepatoQA\Repato.Revit.dll'){throw "Create Plan Views manifest assembly path is invalid: $assembly"}
if($assembly -match '(^|[\\/])\.\.[\\/]|^[A-Za-z]:|^Repato\.Revit\.dll$'){throw 'Manifest assembly path escapes or bypasses RepatoQA deployment.'}
if($xml.RevitAddIns.AddIn.FullClassName -cne 'Repato.Revit.TestRunner.CreatePlanViewsQaApplication'){throw 'Create Plan Views native runner mapping changed.'}
if($xml.RevitAddIns.AddIn.VendorId -cne 'RPTQ'){throw 'Create Plan Views VendorId is missing.'}
if([string]::IsNullOrWhiteSpace($xml.RevitAddIns.AddIn.VendorDescription)){throw 'Create Plan Views VendorDescription is missing.'}
$negative='<RevitAddIns><AddIn><Assembly>..\Repato.Revit.dll</Assembly></AddIn></RevitAddIns>'
[xml]$bad=$negative
$badAssembly=$bad.RevitAddIns.AddIn.Assembly
if($badAssembly -notmatch '(^|[\\/])\.\.') {throw 'Regression fixture did not represent an outside deployment path.'}
Write-Host 'Create Plan Views manifest deployment checks passed: 4'
