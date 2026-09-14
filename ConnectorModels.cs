using System.Text.Json.Serialization;

namespace Forma.RevitConnector;

public sealed class WorkflowRequest
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "Untitled workflow";

    [JsonPropertyName("steps")]
    public List<WorkflowStep> Steps { get; set; } = [];
}

public sealed class WorkflowStep
{
    [JsonPropertyName("toolId")]
    public string ToolId { get; set; } = "";

    [JsonPropertyName("level")]
    public string Level { get; set; } = "";

    [JsonPropertyName("type")]
    public string Type { get; set; } = "";

    [JsonPropertyName("scale")]
    public string Scale { get; set; } = "";

    [JsonPropertyName("levelData")]
    public string LevelData { get; set; } = "";

    [JsonPropertyName("verticalGridData")]
    public string VerticalGridData { get; set; } = "";

    [JsonPropertyName("horizontalGridData")]
    public string HorizontalGridData { get; set; } = "";

    [JsonPropertyName("gridLength")]
    public string GridLength { get; set; } = "";
}

public sealed class BridgeRequest
{
    public string Kind { get; init; } = "";
    public WorkflowRequest? Workflow { get; init; }

    public TaskCompletionSource<object> Completion { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
}