$ErrorActionPreference='Stop'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('FixturePolicy-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$source=(Resolve-Path (Join-Path $PSScriptRoot '..\TestRunner\FixtureContentPolicy.cs')).Path
@"
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup><ItemGroup><Compile Include="$source" Link="FixtureContentPolicy.cs" /></ItemGroup></Project>
"@ | Set-Content (Join-Path $scratch 'PolicyChecks.csproj')
@'
using Repato.Revit.TestRunner;
string[] approved = ["A","B","C","D","1","2","3","4"];
int passed=0;
void Accept(string id,string? fixture,string[] grids,int links){FixtureContentPolicy.Validate(fixture,grids,links);passed++;Console.WriteLine("PASS "+id);}
void Reject(string id,string? fixture,string[] grids,int links){try{FixtureContentPolicy.Validate(fixture,grids,links);throw new Exception("accepted");}catch(InvalidOperationException){passed++;Console.WriteLine("PASS "+id);}}
Accept("default-empty", "CreateLevelsEmpty", [], 0);
Reject("default-rejects-grids", "CreateLevelsEmpty", ["A"], 0);
Accept("offset-approved-exact", "GridBubbleOffsetEmpty", approved, 0);
Accept("offset-approved-order-independent", "GridBubbleOffsetEmpty", approved.Reverse().ToArray(), 0);
Reject("offset-missing-grid", "GridBubbleOffsetEmpty", approved.Where(n=>n!="4").ToArray(), 0);
Reject("offset-unexpected-grid", "GridBubbleOffsetEmpty", [..approved,"X"], 0);
Reject("offset-duplicate-replaces-grid", "GridBubbleOffsetEmpty", ["A","A","B","C","D","1","2","3"], 0);
Reject("offset-rejects-links", "GridBubbleOffsetEmpty", approved, 1);
Reject("default-rejects-links", "CreateLevelsEmpty", [], 1);
string[] resequence = ["1","2","3","3.2","4","A","A.1","B","C"];
Accept("resequence-approved-exact", "GridResequenceEmpty", resequence, 0);
Reject("resequence-missing-decimal", "GridResequenceEmpty", resequence.Where(n=>n!="3.2").ToArray(), 0);
Reject("resequence-unexpected-grid", "GridResequenceEmpty", [..resequence,"X"], 0);
Reject("resequence-links", "GridResequenceEmpty", resequence, 1);
if(passed!=13) throw new Exception("wrong check count");
Console.WriteLine($"{passed}/13 fixture policy checks passed");
'@ | Set-Content (Join-Path $scratch 'Program.cs')
dotnet run --project (Join-Path $scratch 'PolicyChecks.csproj') --configuration Release --nologo
if($LASTEXITCODE -ne 0){throw 'Fixture policy harness failed'}
