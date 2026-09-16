using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;

namespace Repato.Revit.TestRunner;

public sealed class TestRunReport
{
    public string SchemaVersion { get; } = "1";
    public string RunId { get; } = Guid.NewGuid().ToString("N");
    public string TestId { get; set; } = "";
    public string Status { get; set; } = "Failed";
    public string DocumentPath { get; set; } = "";
    public string FixtureId { get; set; } = "";
    public string FixtureSha256 { get; set; } = "";
    public object Inputs { get; set; } = new
    {
        VerticalNames = new[] { "A", "B", "C", "D" },
        HorizontalNames = new[] { "1", "2", "3", "4" },
        PositionsMm = new[] { 0, 6000, 12000, 18000 },
        SpacingMm = 6000,
        LengthMm = 48000
    };
    public List<string> CreatedIds { get; } = [];
    public List<string> ChangedIds { get; } = [];
    public List<string> DeletedIds { get; } = [];
    public List<ScreenshotEvidence> Screenshots { get; } = [];
    public List<TestAssertion> Assertions { get; } = [];
    public List<string> Errors { get; } = [];
    public DateTimeOffset StartedUtc { get; } = DateTimeOffset.UtcNow;
    public DateTimeOffset FinishedUtc { get; set; }
    public double DurationMilliseconds { get; set; }
    public string RevitVersion { get; set; } = "";
    public object? AssemblyIdentity { get; set; }
    public AddinInventory? AddinIsolation { get; set; }
    public string RollbackStatus { get; set; } = "NotStarted";
    public string CreatedIdsLifecycle { get; } =
        "Observed before rollback; not persistent model elements.";

    public void Assert(string id, bool passed, object expected, object actual) =>
        Assertions.Add(new TestAssertion(id, passed, expected, actual));

    public void IdentifyAssembly()
    {
        Assembly assembly = typeof(RepatoTestCommand).Assembly;

        AssemblyIdentity = new
        {
            assembly.FullName,
            Path = assembly.Location,
            Sha256 = Hash(assembly.Location),
            ModuleVersionId = assembly.ManifestModule.ModuleVersionId
        };
    }

    public string Write()
    {
        QAPathPolicy.ValidatePath(
            TestSafetyGate.ReportsRoot,
            TestSafetyGate.RepositoryRoot,
            false
        );

        Directory.CreateDirectory(TestSafetyGate.ReportsRoot);

        string path = Path.Combine(
            TestSafetyGate.ReportsRoot,
            $"{RunId}.json"
        );

        string temporaryPath = path + ".partial";

        using (var stream = new FileStream(
            temporaryPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None
        ))
        {
            JsonSerializer.Serialize(
                stream,
                this,
                new JsonSerializerOptions { WriteIndented = true }
            );

            stream.Flush(true);
        }

        File.Move(temporaryPath, path);

        return path;
    }

    internal static string Hash(string path)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite
        );

        return Convert.ToHexString(SHA256.HashData(stream));
    }
}

public sealed record TestAssertion(
    string Id,
    bool Passed,
    object Expected,
    object Actual
);

public sealed record ScreenshotEvidence(string Phase, string Path, string Sha256, string ViewId, string ViewName);
