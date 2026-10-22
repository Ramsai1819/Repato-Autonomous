using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;

namespace Repato.QaLaunchAgent;

public sealed class NamedPipeLaunchServer(QaAgentOptions options, LaunchCoordinator coordinator)
{
    public async Task ServeOnceAsync(CancellationToken cancellationToken)
    {
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(options.ClientSid), PipeAccessRights.ReadWrite, AccessControlType.Allow));
        using var pipe = NamedPipeServerStreamAcl.Create(options.PipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 8192, 8192, security);
        await pipe.WaitForConnectionAsync(cancellationToken);
        using var reader = new StreamReader(pipe);
        var line = await reader.ReadLineAsync(cancellationToken);
        if (line is null || line.Length > 32768)
        {
            // A probe that connects and disconnects, or sends an oversized envelope,
            // must release the connection without a response and without terminating
            // the long-lived scheduled-task listener.
            return;
        }
        object response;
        string? observedOperation = null;
        try
        {
            using var document = JsonDocument.Parse(line);
            var operation = document.RootElement.TryGetProperty("operation", out var op) ? op.GetString() : null;
            observedOperation = operation;
            if (operation == QaLaunchPolicy.HealthOperation)
            {
                var identity = WindowsIdentity.GetCurrent();
                response = new QaHealthResponse(1, QaLaunchPolicy.HealthOperation, true, identity.Name, identity.User?.Value ?? "", System.Diagnostics.Process.GetCurrentProcess().SessionId, Environment.UserInteractive, null);
            }
            else if (operation == QaLaunchPolicy.PreflightOperation)
            {
                var request = JsonSerializer.Deserialize<QaPreflightRequest>(line, QaLaunchPolicy.JsonOptions);
                response = coordinator.HandlePreflight(request);
            }
            else if (operation == QaLaunchPolicy.StageOperation)
            {
                var request = JsonSerializer.Deserialize<QaStageRequest>(line, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException();
                response = coordinator.HandleStage(request, DateTimeOffset.UtcNow);
            }
            else if (operation == QaLaunchPolicy.ValidateDeploymentOperation)
            {
                var request = JsonSerializer.Deserialize<QaDeploymentValidationRequest>(line, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException();
                response = coordinator.HandleDeploymentValidation(request, DateTimeOffset.UtcNow);
            }
            else
            {
                response = RouteLaunchRequest(line, coordinator, DateTimeOffset.UtcNow);
            }
        }
        catch (Exception exception)
        {
            response = observedOperation is CpvPreparationService.Operation or CpvPreparationService.StatusOperation or CpvPreparationService.ReconcileOperation or CpvPreparationService.RecoverCompletedOperation or CpvPreparationService.RecoverCompletedStatusOperation or CpvPreparationService.RecoverCompletedReconcileOperation
                ? new { schemaVersion = 1, operation = observedOperation, status = "RejectedOrUnknown", failureCode = PreparedFailureCode(exception) }
                : observedOperation == RcpQaLaunchPolicy.Operation
                ? new RcpQaLaunchResponse(1, RcpQaLaunchPolicy.Operation, "", "", "", RcpQaLaunchPolicy.ToolId, RcpQaLaunchPolicy.ToolId, "", "", "", false, "rejected", null, WindowsIdentity.GetCurrent().Name, WindowsIdentity.GetCurrent().User?.Value ?? "", System.Diagnostics.Process.GetCurrentProcess().SessionId, null, "malformed-request")
                : new QaLaunchResponseV2(2, QaLaunchPolicy.Operation, "", "", false, null, null, null, null, null, null, null, null, null, null, null, null, null, "malformed-request");
        }
        try
        {
            using var writer = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
            await writer.WriteLineAsync(SerializeResponse(response));
        }

        catch (IOException)
        {
            // A client may time out while a bounded staging/validation adapter is still running.
            // Its disconnect must not terminate the long-lived scheduled-task listener.
        }
    }

    public static string PreparedFailureCode(Exception exception) =>
        exception is InvalidDataException or InvalidOperationException &&
        exception.Message.Length is > 0 and <= 96 &&
        exception.Message.All(character => character is '-' or '_' || character >= 'a' && character <= 'z')
            ? exception.Message
            : "preparation-rejected-or-reconcile-required";

    public static object RouteLaunchRequest(string line, LaunchCoordinator coordinator, DateTimeOffset now)
    {
        using var document = JsonDocument.Parse(line);
        string? operation = document.RootElement.TryGetProperty("operation", out var op) ? op.GetString() : null;
        if (operation == CpvPreparationService.CapabilitiesOperation) return coordinator.PreparationCapabilities();
        if (operation is CpvPreparationService.Operation or CpvPreparationService.StatusOperation or CpvPreparationService.ReconcileOperation or CpvPreparationService.RecoverCompletedOperation or CpvPreparationService.RecoverCompletedStatusOperation or CpvPreparationService.RecoverCompletedReconcileOperation)
            return coordinator.HandlePreparation(line, now);
        if (operation == RcpQaLaunchPolicy.Operation)
        {
            var request = JsonSerializer.Deserialize<RcpQaLaunchRequest>(line, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException();
            return coordinator.HandleRcp(request, now, line);
        }
        if (operation == QaLaunchPolicy.Operation)
        {
            var request = JsonSerializer.Deserialize<QaLaunchRequest>(line, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException();
            return coordinator.Handle(request, now, line);
        }
        return new { schemaVersion = 1, operation = operation ?? "", accepted = false, disposition = "rejected", failureCode = "unsupported-operation" };
    }

    public static string SerializeResponse(object response) =>
        JsonSerializer.Serialize(response, response.GetType(), QaLaunchPolicy.JsonOptions);
}
