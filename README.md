# Forma Revit Connector — Revit 2025

This local add-in lets the private Forma website detect Revit, read the active
project context, and send a reviewed workflow to Revit.

The starter implements two command adapters:

- `scale`: sets the active view scale.
- `project-info`: reads project information.

Every other Forma tool is received safely and reported as `adapter_required`.
Add its Revit API or Dynamo adapter in `FormaEventHandler.ExecuteStep`.

## Build

1. Install Visual Studio 2022 with **.NET desktop development**, or the .NET 8 SDK.
2. Confirm Revit 2025 is installed in the default Autodesk folder.
3. Find the Revit API files:

   `Get-ChildItem C:\ -Filter RevitAPI.dll -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DirectoryName`

4. If the result is `C:\Program Files\Autodesk\Revit 2025`, run:

   `dotnet build -c Release`

   For another location, for example `D:\Autodesk\Revit 2025`, run:

   `dotnet build -c Release -p:RevitInstallDir="D:\Autodesk\Revit 2025"`

5. Copy `bin\Release\net8.0-windows\Forma.RevitConnector.dll` to:

   `%APPDATA%\Autodesk\Revit\Addins\2025\FormaConnector\`

6. Copy `FormaConnector.addin` to:

   `%APPDATA%\Autodesk\Revit\Addins\2025\`

7. Edit the `Assembly` path in `FormaConnector.addin` if your Windows user
   folder is different.
8. Open **Command Prompt as Administrator** once and run:

   `netsh http add urlacl url=http://127.0.0.1:47823/ user=%USERNAME%`

9. Start Revit 2025. Windows may ask to allow local network access.
10. Open Forma, choose **Connect Revit**, and press **Test connection**.

The connector listens only on `127.0.0.1:47823`. It accepts browser requests
only from the published Forma site or a local development address.
