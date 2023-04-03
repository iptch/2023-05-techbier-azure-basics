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

public static async Task<IActionResult> Run(HttpRequest req, ILogger log)
{
    log.LogInformation($"Get files triggered");

    // Establish connection to Blob Storage container (containing all our files as blobs)
    var blobContainer = new BlobContainerClient(StorageConnectionString, StorageBlobContainer);

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
        // Establish connection to specific blob object
        var blobClient = blobContainer.GetBlobClient(blobItem.Name);
        
        // SAS = Shared Access Signature, more: https://learn.microsoft.com/en-us/azure/storage/common/storage-sas-overview
        var sasBuilder = new BlobSasBuilder()
        {
            BlobContainerName = StorageBlobContainer,
            BlobName = blobClient.Name, // Token is valid for this particular blob only
            Resource = "b",
            ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(5) // Token will be valid for 5 minutes only
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