using System.IO.Pipes;
using System.Text.Json;

namespace Repato.QaLaunchAgent;

public interface IQaLaunchTransport
{
    QaLaunchResponse Send(QaLaunchRequest request, TimeSpan timeout);
}

public sealed class QaHealthClient(string pipeName = "Repato\\QaLaunch")
{
    public QaHealthResponse GetHealth(TimeSpan timeout)
    {
        using var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.WriteThrough);
        pipe.Connect((int)timeout.TotalMilliseconds);
        using var writer = new StreamWriter(pipe) { AutoFlush = true };
        writer.WriteLine(JsonSerializer.Serialize(new QaHealthRequest(QaLaunchPolicy.SchemaVersion, QaLaunchPolicy.HealthOperation)));
        using var reader = new StreamReader(pipe);
        var response = JsonSerializer.Deserialize<QaHealthResponse>(reader.ReadLine() ?? "") ?? throw new InvalidDataException("Invalid health response.");
        if (response.SchemaVersion != QaLaunchPolicy.SchemaVersion || response.Operation != QaLaunchPolicy.HealthOperation) throw new InvalidDataException("Unexpected health response.");
        return response;
    }
}

public sealed class NamedPipeQaLaunchTransport(string pipeName = "Repato\\QaLaunch") : IQaLaunchTransport
{
    public QaLaunchResponse Send(QaLaunchRequest request, TimeSpan timeout)
    {
        using var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.WriteThrough);
        pipe.Connect((int)timeout.TotalMilliseconds);
        var json = JsonSerializer.Serialize(request);
        using var writer = new StreamWriter(pipe) { AutoFlush = true };
        writer.WriteLine(json);
        using var reader = new StreamReader(pipe);
        return JsonSerializer.Deserialize<QaLaunchResponse>(reader.ReadLine() ?? "")
            ?? throw new InvalidDataException("Empty QA launch response.");
    }
}
