using System.Net;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;

public static async Task<IActionResult> Run(HttpRequest req, ILogger log)
{
    log.LogInformation($"Get files triggered");

    string storageConnectionString = System.Environment.GetEnvironmentVariable("StorageConnectionString", EnvironmentVariableTarget.Process);
    string storageBlobContainer = System.Environment.GetEnvironmentVariable("StorageBlobContainer", EnvironmentVariableTarget.Process);

    var blobContainer = new BlobContainerClient(storageConnectionString, storageBlobContainer);

    if (!await blobContainer.ExistsAsync())
    {
        return new NoContentResult();
    }

    if (!blobContainer.CanGenerateSasUri)
    {
        return new UnauthorizedResult();
    }

    var results = new List<FileInfo>();

    // List all blobs in the container
    await foreach (BlobItem blobItem in blobContainer.GetBlobsAsync())
    {
        var blobClient = blobContainer.GetBlobClient(blobItem.Name);
        var sasBuilder = new BlobSasBuilder()
        {
            BlobContainerName = storageBlobContainer,
            BlobName = blobClient.Name,
            Resource = "b",
            ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(5)
        };
        sasBuilder.SetPermissions(BlobSasPermissions.Read);

        Uri sasUri = blobClient.GenerateSasUri(sasBuilder);

        results.Add(new FileInfo
        {
            Name = blobItem.Name,
            ContentType = blobItem.Properties.ContentType,
            SizeInBytes = blobItem.Properties.ContentLength?.ToString(),
            LastModified = blobItem.Properties.LastModified?.ToString("s"),
            Uri = sasUri.AbsoluteUri
        });
    }

    log.LogInformation($"Found {results.Count} files");
    log.LogMetric("Listing", 1, new Dictionary<string, object> { { "Count", results.Count } });

    var serializerSettings = new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver(), NullValueHandling = NullValueHandling.Ignore };

    return new OkObjectResult(JsonConvert.SerializeObject(results, serializerSettings));
}

public class FileInfo
{
    public string Name { get; set; }
    public string ContentType { get; set; }
    public string SizeInBytes { get; set; }
    public string LastModified { get; set; }
    public string Uri { get; set; }
}