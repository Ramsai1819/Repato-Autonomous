using System.IO;
using System.Text.Json;

namespace Repato.Revit.TestRunner;

internal sealed record CreatePlanViewsReceipt(
    string RequestId, string TaskId, string WorkflowId, string QaWorkflowId, string TestId,
    string AttemptId, string RunId, string ClaimId, string ReportPath, string Status);

internal static class CreatePlanViewsResultContract
{
    internal static CreatePlanViewsReceipt CreateReceipt(CreatePlanViewsRequest request, string requestId, string taskId,
        string workflowId, string testId, string attemptId, string runId, string claimId, string status, string reportPath)
    {
        if (requestId != request.RequestId || taskId != request.TaskId || workflowId != request.WorkflowId ||
            testId != request.TestId || attemptId != request.AttemptId || runId != request.RunId || claimId != request.ClaimId ||
            status is not ("Passed" or "Failed"))
            throw new InvalidDataException("QA report identity does not match its request-bound receipt.");
        return new CreatePlanViewsReceipt(request.RequestId, request.TaskId, request.WorkflowId, request.QaWorkflowId,
            request.TestId, request.AttemptId, request.RunId, request.ClaimId, reportPath, status);
    }

    // Mirrors the canonical controller's identity/status, assertion, rollback, fixture and assembly checks.
    internal static bool IsPassing(string receiptJson, string reportJson, CreatePlanViewsRequest request, string expectedArtifactSha256)
    {
        try
        {
            using var receiptDoc = JsonDocument.Parse(receiptJson);
            using var reportDoc = JsonDocument.Parse(reportJson);
            JsonElement receipt = receiptDoc.RootElement, report = reportDoc.RootElement;
            string R(string name) => receipt.GetProperty(name).GetString() ?? "";
            string P(string name) => report.GetProperty(name).GetString() ?? "";
            if (R("RequestId") != request.RequestId || R("TaskId") != request.TaskId || R("WorkflowId") != request.WorkflowId ||
                R("QaWorkflowId") != request.QaWorkflowId || R("TestId") != request.TestId || R("AttemptId") != request.AttemptId ||
                R("RunId") != request.RunId || R("ClaimId") != request.ClaimId || R("Status") != "Passed" ||
                P("RequestId") != request.RequestId || P("TaskId") != request.TaskId || P("WorkflowId") != request.WorkflowId ||
                P("TestId") != request.TestId || P("AttemptId") != request.AttemptId || P("RunId") != request.RunId || P("ClaimId") != request.ClaimId ||
                P("Status") != "Passed" || P("RollbackStatus") != "RolledBack" ||
                !P("FixtureSha256").Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase) ||
                !P("RuntimeModelSha256").Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase) ||
                !DateTimeOffset.TryParse(P("FinishedUtc"), out DateTimeOffset finished) || finished == default)
                return false;
            JsonElement assembly = report.GetProperty("AssemblyIdentity");
            if (!assembly.GetProperty("Sha256").GetString()!.Equals(expectedArtifactSha256, StringComparison.OrdinalIgnoreCase)) return false;
            if (report.GetProperty("Errors").GetArrayLength() != 0) return false;
            JsonElement assertions = report.GetProperty("Assertions");
            return assertions.GetArrayLength() > 0 && assertions.EnumerateArray().All(item => item.GetProperty("Passed").GetBoolean());
        }
        catch { return false; }
    }

    private static bool IsHash(string value) => value.Length == 64 && value.All(Uri.IsHexDigit);
}
