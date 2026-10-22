using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Xml;

if (args.Length != 4) throw new ArgumentException("Usage: <candidate.dll> <trusted.addin> <expected-class> <expected-assembly-spec>");
string candidatePath = Path.GetFullPath(args[0]);
string manifestPath = Path.GetFullPath(args[1]);
string expectedClass = args[2];
string expectedAssembly = args[3];
var xml = new XmlDocument { XmlResolver = null };
xml.Load(manifestPath);
XmlElement[] applications = xml.SelectNodes("/RevitAddIns/AddIn[@Type='Application']")!.OfType<XmlElement>().ToArray();
if (applications.Length != 1 || applications[0].SelectSingleNode("FullClassName")?.InnerText != expectedClass ||
    applications[0].SelectSingleNode("Assembly")?.InnerText != expectedAssembly)
    throw new InvalidDataException("Trusted manifest does not bind the exact expected class and assembly spec.");

using var stream = File.OpenRead(candidatePath);
using var pe = new PEReader(stream);
if (!pe.HasMetadata) throw new BadImageFormatException("Candidate DLL has no managed metadata.");
MetadataReader metadata = pe.GetMetadataReader();
TypeDefinitionHandle match = default;
foreach (TypeDefinitionHandle handle in metadata.TypeDefinitions)
{
    TypeDefinition type = metadata.GetTypeDefinition(handle);
    string fullName = Join(metadata.GetString(type.Namespace), metadata.GetString(type.Name));
    if (fullName == expectedClass) { match = handle; break; }
}
if (match.IsNil) throw new InvalidDataException("Manifest class is absent from the compiled candidate.");
TypeDefinition definition = metadata.GetTypeDefinition(match);
if ((definition.Attributes & TypeAttributes.VisibilityMask) != TypeAttributes.Public || (definition.Attributes & TypeAttributes.Abstract) != 0)
    throw new InvalidDataException("Manifest class is not a public, concrete type.");
string[] interfaces = definition.GetInterfaceImplementations()
    .Select(handle => metadata.GetInterfaceImplementation(handle).Interface)
    .Select(handle => FullName(metadata, handle))
    .ToArray();
const string required = "Autodesk.Revit.UI.IExternalApplication";
if (!interfaces.Contains(required, StringComparer.Ordinal)) throw new InvalidDataException("Manifest class does not implement " + required + ".");
Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new
{
    Passed = true, Class = expectedClass, Interface = required, CandidateSha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(candidatePath))),
    ManifestPath = manifestPath, AssemblySpec = expectedAssembly
}));

static string Join(string ns, string name) => string.IsNullOrEmpty(ns) ? name : ns + "." + name;
static string FullName(MetadataReader metadata, EntityHandle handle) => handle.Kind switch
{
    HandleKind.TypeDefinition => TypeDefinitionName(metadata, (TypeDefinitionHandle)handle),
    HandleKind.TypeReference => TypeReferenceName(metadata, (TypeReferenceHandle)handle),
    _ => ""
};
static string TypeDefinitionName(MetadataReader metadata, TypeDefinitionHandle handle)
{
    TypeDefinition type = metadata.GetTypeDefinition(handle);
    return Join(metadata.GetString(type.Namespace), metadata.GetString(type.Name));
}
static string TypeReferenceName(MetadataReader metadata, TypeReferenceHandle handle)
{
    TypeReference type = metadata.GetTypeReference(handle);
    return Join(metadata.GetString(type.Namespace), metadata.GetString(type.Name));
}
