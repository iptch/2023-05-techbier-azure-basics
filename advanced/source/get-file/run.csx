using System.Net;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;

// Read configuration values (App Settings)
static string StorageConnectionString => System.Environment.GetEnvironmentVariable(nameof(StorageConnectionString), EnvironmentVariableTarget.Process);
static string StorageBlobContainer => System.Environment.GetEnvironmentVariable(nameof(StorageBlobContainer), EnvironmentVariableTarget.Process);
static string DownloadMetricName => System.Environment.GetEnvironmentVariable(nameof(DownloadMetricName), EnvironmentVariableTarget.Process);

public static async Task<IActionResult> Run(HttpRequest req, string filename, ILogger log)
{
    log.LogInformation($"Get file '{filename}' triggered");

    if (string.IsNullOrWhiteSpace(Path.GetFileNameWithoutExtension(filename)) || !Path.HasExtension(filename))
    {
        return new BadRequestObjectResult($"Invalid parameter '{filename}'");
    }

    // Establish connection to Blob Storage blob
    var blob = new BlobClient(StorageConnectionString, StorageBlobContainer, filename);

    if (!await blob.ExistsAsync())
    {
        return new NotFoundResult();
    }

    // Download blob properties (note: a blob may also have custom metadata...)
    var properties = await GetBlobProperties(StorageConnectionString, StorageBlobContainer, filename);

    if (properties == null)
    {
        return new BadRequestObjectResult($"File '{filename}' exists, but has corrupted metadata");
    }

    // Generate SAS URL for protected download
    if (!blob.CanGenerateSasUri)
    {
        return new UnauthorizedResult();
    }

    // SAS = Shared Access Signature, more: https://learn.microsoft.com/en-us/azure/storage/common/storage-sas-overview
    var sasBuilder = new BlobSasBuilder()
    {
        BlobContainerName = StorageBlobContainer,
        BlobName = blob.Name, // Token is valid for this particular blob only
        Resource = "b",
        ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(5) // Token will be valid for 5 minutes only
    };
    sasBuilder.SetPermissions(BlobSasPermissions.Read);

    Uri sasUri = blob.GenerateSasUri(sasBuilder);

    // Build result object
    var result = new FileInfo
    {
        Name = blob.Name,
        ContentType = properties.ContentType,
        SizeInBytes = properties.ContentLength?.ToString(),
        LastModified = properties.LastModified?.ToString("s"),
        Uri = sasUri.AbsoluteUri
    };

    // Metrics are specialized log entries which simplify monitoring. They're summarizable because of their numeric value and can also contain metadata
    log.LogMetric(DownloadMetricName, 1, new Dictionary<string, object> { { "File", filename } });

    var serializerSettings = new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver(), NullValueHandling = NullValueHandling.Ignore };

    return new OkObjectResult(JsonConvert.SerializeObject(result, serializerSettings));
}

public static async Task<BlobItemProperties> GetBlobProperties(string storageConnectionString, string storageBlobContainer, string filename)
{
    // Note: The BlobClient does have a method to get properties directly (https://learn.microsoft.com/en-us/dotnet/api/azure.storage.blobs.specialized.blobbaseclient.getpropertiesasync)
    //       Unfortunately this has a bug with current library version and does not provide a valid object, therefore this workaround
    var blobContainer = new BlobContainerClient(storageConnectionString, storageBlobContainer);
    await foreach (BlobItem blobItem in blobContainer.GetBlobsAsync(prefix: filename))
    {
        return blobItem.Properties;
    }

    return null;
}

public class FileInfo
{
    public string Name { get; set; }
    public string ContentType { get; set; }
    public string SizeInBytes { get; set; }
    public string LastModified { get; set; }
    public string Uri { get; set; }
}