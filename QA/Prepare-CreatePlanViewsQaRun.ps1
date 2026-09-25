param([Parameter(Mandatory)][string]$RunDirectory)
New-Item -ItemType Directory -Path $RunDirectory -Force|Out-Null
'CreatePlanViewsEmpty'|Set-Content (Join-Path $RunDirectory 'fixture.identity.txt')
