using System.Net;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;

public static async Task<IActionResult> Run(HttpRequest req, string filename, ILogger log)
{
    log.LogInformation($"Get file '{filename}' triggered");

    string storageConnectionString = System.Environment.GetEnvironmentVariable("StorageConnectionString", EnvironmentVariableTarget.Process);
    string storageBlobContainer = System.Environment.GetEnvironmentVariable("StorageBlobContainer", EnvironmentVariableTarget.Process);

    var blob = new BlobClient(storageConnectionString, storageBlobContainer, filename);

    if (!await blob.ExistsAsync())
    {
        return new NotFoundResult();
    }

    // Download blob properties (note: a blob may also have custom metadata...)
    var properties = await GetBlobProperties(storageConnectionString, storageBlobContainer, filename);

    if (properties == null)
    {
        return new BadRequestObjectResult($"File '{filename}' exists, but has corrupted metadata");
    }

    // Generate SAS URL for protected download
    if (!blob.CanGenerateSasUri)
    {
        return new UnauthorizedResult();
    }

    var sasBuilder = new BlobSasBuilder()
    {
        BlobContainerName = storageBlobContainer,
        BlobName = blob.Name,
        Resource = "b",
        ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(5)
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

    log.LogMetric("Download", 1, new Dictionary<string, object> { { "File", filename } });

    var serializerSettings = new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver(), NullValueHandling = NullValueHandling.Ignore };

    return new OkObjectResult(JsonConvert.SerializeObject(result, serializerSettings));
}

public static async Task<BlobItemProperties> GetBlobProperties(string storageConnectionString, string storageBlobContainer, string filename)
{
    // Note: The BlobClient does have a method to get properties directly (https://learn.microsoft.com/en-us/dotnet/api/azure.storage.blobs.specialized.blobbaseclient.getpropertiesasync)
    //       Unfortunately this has a bug and does not provide a valid object, therefore this workaround
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