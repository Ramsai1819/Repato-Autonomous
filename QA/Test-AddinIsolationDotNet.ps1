$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('Repato-Isolation-DotNet-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$source = [Security.SecurityElement]::Escape((Join-Path $repository 'TestRunner\AddinIsolationPolicy.cs'))
$project = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><Compile Include="$source" Link="AddinIsolationPolicy.cs" /></ItemGroup>
</Project>
"@
[IO.File]::WriteAllText((Join-Path $scratch 'Checks.csproj'), $project)
$program = @'
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Repato.Revit.TestRunner;

string root = Path.Combine(AppContext.BaseDirectory, "fixtures");
Directory.CreateDirectory(root);
int passed = 0;
void Test(string name, Action<string,string,string,string> arrange, bool expected)
{
    string caseRoot = Path.Combine(root, name);
    string machine = Path.Combine(caseRoot, "machine"), user = Path.Combine(caseRoot, "user"), source = Path.Combine(caseRoot, "source");
    foreach (string directory in new[] { machine, user, source }) Directory.CreateDirectory(directory);
    string policy = Path.Combine(caseRoot, "policy.json");
    string manifest = Path.Combine(machine, "Reviewed.addin");
    File.WriteAllText(manifest, "reviewed");
    WritePolicy(policy, machine, new[] { Entry(manifest) });
    arrange(policy, machine, user, source);
    AddinInventory result = AddinIsolationPolicy.Inspect(policy, machine, user, source);
    if (result.Allowed != expected) throw new Exception(name + ": expected Allowed=" + expected + "; " + JsonSerializer.Serialize(result));
    Console.WriteLine("PASS " + name);
    passed++;
}
object Entry(string path) => new { path, sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))), reviewReason = "controlled test manifest" };
void WritePolicy(string path, string machine, object[] entries) => File.WriteAllText(path, JsonSerializer.Serialize(new { schemaVersion = 1, machineWideRoot = machine, approvedMachineWideManifests = entries }), new UTF8Encoding(true));
Test("approved-bom", (_,_,_,_) => {}, true);
Test("unknown", (_,m,_,_) => File.WriteAllText(Path.Combine(m,"Other.ADDIN"),"unknown"), false);
Test("tampered", (_,m,_,_) => File.AppendAllText(Path.Combine(m,"Reviewed.addin"),"changed"), false);
Test("user-shadow", (_,m,u,_) => File.Copy(Path.Combine(m,"Reviewed.addin"),Path.Combine(u,"Reviewed.addin")), false);
Test("qa-exact", (_,_,u,s) => { foreach(string n in new[]{"Repato.CreateLevels.TestRunner.addin","Repato.TestRunner.addin","Repato.GridBubbleVisibility.TestRunner.addin","Repato.GridBubbleOffset.TestRunner.addin","Repato.GridResequence.TestRunner.addin"}) { File.WriteAllText(Path.Combine(s,n),"qa"); File.WriteAllText(Path.Combine(u,n),"qa"); } }, true);
Test("qa-modified", (_,_,u,s) => { const string n="Repato.TestRunner.addin"; File.WriteAllText(Path.Combine(s,n),"qa"); File.WriteAllText(Path.Combine(u,n),"changed"); }, false);
Test("missing-policy", (p,_,_,_) => File.Delete(p), false);
Test("malformed-policy", (p,_,_,_) => File.WriteAllText(p,"{"), false);
Test("duplicate-path", (p,m,_,_) => { object e=Entry(Path.Combine(m,"Reviewed.addin")); WritePolicy(p,m,new[]{e,e}); }, false);
Test("wildcard-path", (p,m,_,_) => WritePolicy(p,m,new object[]{new {path=Path.Combine(m,"*.addin"),sha256=new string('A',64),reviewReason="invalid wildcard"}}), false);
Test("wrong-schema", (p,m,_,_) => File.WriteAllText(p,JsonSerializer.Serialize(new {schemaVersion=2,machineWideRoot=m,approvedMachineWideManifests=Array.Empty<object>()})), false);
Test("missing-root", (_,_,u,_) => Directory.Delete(u), false);
Test("unreadable-file", (p,m,u,s) =>
{
    // A locked manifest is unreadable to the inspection hash reader.
    string file=Path.Combine(m,"Reviewed.addin");
    using var locked=new FileStream(file,FileMode.Open,FileAccess.ReadWrite,FileShare.None);
    if(AddinIsolationPolicy.Inspect(p,m,u,s).Allowed) throw new Exception("locked manifest accepted");
    File.WriteAllText(Path.Combine(u,"blocked.addin"),"forces outer rejection too");
}, false);
Test("reparse-root", (_,_,u,_) =>
{
    string target=u+"-target";
    Directory.CreateDirectory(target);
    Directory.Delete(u);
    var start=new System.Diagnostics.ProcessStartInfo("cmd.exe") {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
    start.ArgumentList.Add("/c"); start.ArgumentList.Add("mklink"); start.ArgumentList.Add("/J"); start.ArgumentList.Add(u); start.ArgumentList.Add(target);
    using var process=System.Diagnostics.Process.Start(start)!;
    process.WaitForExit();
    if(process.ExitCode!=0) throw new Exception("Could not create isolated junction: "+process.StandardError.ReadToEnd());
}, false);
Console.WriteLine($"{passed}/{passed} checks passed; no Revit references or process used.");

namespace Repato.Revit.TestRunner
{
    public sealed class TestRunReport
    {
        public AddinInventory? AddinIsolation {get;set;}
        public void Assert(string id,bool passed,object expected,object actual) { }
    }
}
'@
[IO.File]::WriteAllText((Join-Path $scratch 'Program.cs'), $program)
Write-Output "Standalone scratch harness: $scratch"
& dotnet run --project (Join-Path $scratch 'Checks.csproj') -c Release
if ($LASTEXITCODE -ne 0) { throw "Add-in isolation .NET checks failed (exit $LASTEXITCODE)." }
