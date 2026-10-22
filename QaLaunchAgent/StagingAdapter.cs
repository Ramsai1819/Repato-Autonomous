using System.Diagnostics;
using System.Text.Json;

namespace Repato.QaLaunchAgent;

public static class StagingAdapter
{
    public static QaStageResponse Run(QaStageRequest request)
    {
        var temp = Path.Combine(Path.GetTempPath(), "repato-qa-stage-" + request.RequestId + ".json");
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(request, QaLaunchPolicy.JsonOptions));
            var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{QaLaunchPolicy.StagingAdapterPath}\" -RequestPath \"{temp}\"")
            { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
            using var process = Process.Start(psi) ?? throw new InvalidOperationException("Staging adapter process creation failed.");
            if (!process.WaitForExit(120000)) { try { process.Kill(true); } catch { } throw new TimeoutException("Staging adapter timed out."); }
            var output = process.StandardOutput.ReadToEnd();
            var error = process.StandardError.ReadToEnd();
            if (process.ExitCode != 0) throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "Staging adapter rejected the request." : error.Trim());
            return JsonSerializer.Deserialize<QaStageResponse>(output, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException("Staging adapter returned no result.");
        }
        finally { try { if (File.Exists(temp)) File.Delete(temp); } catch { } }
    }
    public static QaDeploymentValidationResponse ValidateDeployment(QaDeploymentValidationRequest request)
    {
        var temp = Path.Combine(Path.GetTempPath(), "repato-qa-validate-" + request.RequestId + ".json");
        try
        {
            File.WriteAllText(temp, JsonSerializer.Serialize(request, QaLaunchPolicy.JsonOptions));
            var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{QaLaunchPolicy.StagingAdapterPath.Replace("Invoke-RepatoQaFrozenCandidateStaging.ps1", "Invoke-RepatoQaDeploymentValidation.ps1")}\" -RequestPath \"{temp}\"") { UseShellExecute=false, RedirectStandardOutput=true, RedirectStandardError=true, CreateNoWindow=true };
            using var process=Process.Start(psi) ?? throw new InvalidOperationException("Validation adapter process creation failed.");
            if(!process.WaitForExit(120000)){try{process.Kill(true);}catch{};throw new TimeoutException("Validation adapter timed out.");}
            var output=process.StandardOutput.ReadToEnd();var error=process.StandardError.ReadToEnd();if(process.ExitCode!=0)throw new InvalidOperationException(string.IsNullOrWhiteSpace(error)?"Validation adapter rejected the request.":error.Trim());
            return DeserializeDeploymentValidationResponse(output);
        } finally { try{if(File.Exists(temp))File.Delete(temp);}catch{} }
    }

    public static QaDeploymentValidationResponse DeserializeDeploymentValidationResponse(string output) =>
        JsonSerializer.Deserialize<QaDeploymentValidationResponse>(output, QaLaunchPolicy.JsonOptions)
        ?? throw new InvalidDataException("Validation adapter returned no result.");
}
