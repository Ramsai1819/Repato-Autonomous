using Autodesk.Revit.UI;
using System.Net;
using System.Text;
using System.Text.Json;

namespace Forma.RevitConnector;

public sealed class ConnectorServer : IDisposable
{
    private const string Prefix = "http://127.0.0.1:47823/";
    private const string PublishedOrigin = "https://forma-revit-workflow.rsworkspace1819.chatgpt.site";
    private const string RegistryPath = @"C:\Forma-Revit-Tools\ToolRegistry.json";

    private readonly FormaEventHandler _handler;
    private readonly ExternalEvent _externalEvent;
    private readonly HttpListener _listener = new();
    private readonly CancellationTokenSource _stop = new();

    public ConnectorServer(FormaEventHandler handler, ExternalEvent externalEvent)
    {
        _handler = handler;
        _externalEvent = externalEvent;
        _listener.Prefixes.Add(Prefix);
    }

    public void Start()
    {
        _listener.Start();
        _ = Task.Run(ListenAsync);
    }

    private async Task ListenAsync()
    {
        while (!_stop.IsCancellationRequested)
        {
            try
            {
                _ = HandleAsync(await _listener.GetContextAsync());
            }
            catch when (_stop.IsCancellationRequested)
            {
                return;
            }
            catch
            {
                // Keep listening after an individual request failure.
            }
        }
    }

    private static bool OriginAllowed(string? origin) =>
        origin == PublishedOrigin ||
        (origin?.StartsWith("http://localhost:", StringComparison.OrdinalIgnoreCase) ?? false) ||
        (origin?.StartsWith("http://127.0.0.1:", StringComparison.OrdinalIgnoreCase) ?? false);

    private static JsonElement LoadToolRegistry()
    {
        if (!File.Exists(RegistryPath))
        {
            throw new FileNotFoundException(
                $"Tool registry was not found at: {RegistryPath}");
        }

        var json = File.ReadAllText(RegistryPath);

        using var document = JsonDocument.Parse(json);

        if (document.RootElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException(
                "ToolRegistry.json must contain a JSON array.");
        }

        return document.RootElement.Clone();
    }

    private static int GetToolCount()
    {
        try
        {
            return LoadToolRegistry().GetArrayLength();
        }
        catch
        {
            return 0;
        }
    }

    private async Task HandleAsync(HttpListenerContext context)
    {
        var origin = context.Request.Headers["Origin"];

        if (!OriginAllowed(origin))
        {
            await WriteAsync(
                context,
                403,
                new { error = "Origin not allowed." },
                null);
            return;
        }

        if (context.Request.HttpMethod == "OPTIONS")
        {
            context.Response.Headers["Access-Control-Allow-Origin"] = origin;
            context.Response.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
            context.Response.Headers["Access-Control-Allow-Headers"] = "Content-Type";
            context.Response.Headers["Access-Control-Allow-Private-Network"] = "true";
            context.Response.StatusCode = 204;
            context.Response.Close();
            return;
        }

        try
        {
            var path = context.Request.Url?.AbsolutePath;

            if (context.Request.HttpMethod == "GET" && path == "/status")
            {
                await WriteAsync(
                    context,
                    200,
                    new
                    {
                        connected = true,
                        connector = "Forma Revit Connector",
                        version = "0.2.0",
                        registryPath = RegistryPath,
                        registeredToolCount = GetToolCount()
                    },
                    origin);
                return;
            }

            if (context.Request.HttpMethod == "GET" && path == "/tools")
            {
                var tools = LoadToolRegistry();

                await WriteAsync(
                    context,
                    200,
                    new
                    {
                        registeredToolCount = tools.GetArrayLength(),
                        tools
                    },
                    origin);
                return;
            }

            var bridge = new BridgeRequest
            {
                Kind = path == "/context" ? "context" : "execute"
            };

            if (path == "/execute" && context.Request.HttpMethod == "POST")
            {
                using var reader = new StreamReader(
                    context.Request.InputStream,
                    context.Request.ContentEncoding);

                var body = await reader.ReadToEndAsync();

                bridge = new BridgeRequest
                {
                    Kind = "execute",
                    Workflow = JsonSerializer.Deserialize<WorkflowRequest>(
                        body,
                        new JsonSerializerOptions
                        {
                            PropertyNameCaseInsensitive = true
                        })
                        ?? throw new InvalidOperationException("Invalid workflow.")
                };
            }
            else if (path != "/context" || context.Request.HttpMethod != "GET")
            {
                await WriteAsync(
                    context,
                    404,
                    new { error = "Route not found." },
                    origin);
                return;
            }

            _handler.Enqueue(bridge);
            _externalEvent.Raise();

            var result = await bridge.Completion.Task.WaitAsync(
                TimeSpan.FromSeconds(30));

            await WriteAsync(context, 200, result, origin);
        }
        catch (Exception ex)
        {
            await WriteAsync(context, 500, new { error = ex.Message }, origin);
        }
    }

    private static async Task WriteAsync(
        HttpListenerContext context,
        int status,
        object data,
        string? origin)
    {
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(data));

        context.Response.StatusCode = status;
        context.Response.ContentType = "application/json";

        if (origin is not null)
        {
            context.Response.Headers["Access-Control-Allow-Origin"] = origin;
        }

        context.Response.Headers["Cache-Control"] = "no-store";
        context.Response.ContentLength64 = bytes.Length;

        await context.Response.OutputStream.WriteAsync(bytes);
        context.Response.Close();
    }

    public void Dispose()
    {
        _stop.Cancel();

        if (_listener.IsListening)
        {
            _listener.Stop();
        }

        _listener.Close();
        _stop.Dispose();
    }
}