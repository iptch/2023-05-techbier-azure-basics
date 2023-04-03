using System.Net;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;

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

    var results = new List<string>();

    // List all blobs in the container
    await foreach (BlobItem blobItem in blobContainer.GetBlobsAsync())
    {
        results.Add(blobItem.Name);
    }

    log.LogInformation($"Found {results.Count} files");
    log.LogMetric("Listing", 1, new Dictionary<string, object> { { "Count", results.Count } });

    var serializerSettings = new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver(), NullValueHandling = NullValueHandling.Ignore };

    return new OkObjectResult(JsonConvert.SerializeObject(results, serializerSettings));
}