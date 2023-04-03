using System.Net;
using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;

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

    var results = new List<string>();

    // List all blobs in the container
    await foreach (BlobItem blobItem in blobContainer.GetBlobsAsync())
    {
        results.Add(blobItem.Name);
    }

    // Metrics are specialized log entries which simplify monitoring. They're summarizable because of their numeric value and can also contain metadata
    log.LogMetric("Listing", 1, new Dictionary<string, object> { { "Count", results.Count } });
    log.LogInformation($"Found {results.Count} files");
    
    var serializerSettings = new JsonSerializerSettings { ContractResolver = new CamelCasePropertyNamesContractResolver(), NullValueHandling = NullValueHandling.Ignore };

    return new OkObjectResult(JsonConvert.SerializeObject(results, serializerSettings));
}