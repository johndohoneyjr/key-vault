using Azure;
using Azure.Core;
using Azure.Identity;
using Azure.Security.KeyVault.Keys;
using Azure.Security.KeyVault.Keys.Cryptography;
using Azure.Storage;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Blobs.Specialized;
using System;
using Azure.Security.KeyVault.Certificates;

    public class Program
    {
        static async Task Main(string[] args)
        {
            // Read Environment Variables - CLIENT_ID, CLIENT_SECRET, TENANT_ID

            var clientId = Environment.GetEnvironmentVariable("CLIENT_ID", EnvironmentVariableTarget.Process);
            var clientSecret = Environment.GetEnvironmentVariable("CLIENT_SECRET");
            var tenantId = Environment.GetEnvironmentVariable("TENANT_ID");

            var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);

            // Upload the certificate to Azure Key Vault
            var kvUri = "https://my-by-demo-kv.vault.azure.net/";
            var client = new CertificateClient(new Uri(kvUri), credential);

            var keyName = "BY-RSA-KEY";
            var keyVaultName = "my-by-demo-kv";

            // URI for the key vault resource
            var keyVaultUri = $"https://{keyVaultName}.vault.azure.net";

            // Create a KeyClient object
            var keyClient = new KeyClient(new Uri(keyVaultUri), credential);

            // Add a key to the key vault
            var key = await keyClient.CreateKeyAsync(keyName, KeyType.Rsa);

            // Cryptography client and key resolver instances using Azure Key Vault client library
            CryptographyClient cryptoClient = keyClient.GetCryptographyClient(key.Value.Name, key.Value.Properties.Version);

            // Demo existing Key in the Vault
            // var keyVaultKeyUri = $"https://{keyVaultName}.vault.azure.net/keys/{keyName}";
            // CryptographyClient cryptoClient = new CryptographyClient(new Uri(keyVaultKeyUri), credential);

            KeyResolver keyResolver = new (credential);
            // Configure the encryption options to be used for upload and download
            ClientSideEncryptionOptions encryptionOptions = new (ClientSideEncryptionVersion.V2_0)
            {
                KeyEncryptionKey = cryptoClient,
                KeyResolver = keyResolver,
                // String value that the client library will use when calling IKeyEncryptionKey.WrapKey()
                KeyWrapAlgorithm = "RSA-OAEP"
            };

            // Set the encryption options on the client options.
            BlobClientOptions options = new SpecializedBlobClientOptions() { ClientSideEncryption = encryptionOptions };
            // Create a blob client with client-side encryption enabled.
            // Attempting to construct a BlockBlobClient, PageBlobClient, or AppendBlobClient from a BlobContainerClient
            // with client-side encryption options present will throw, as this functionality is only supported with BlobClient.

            var accountName = "dohoneystorage";

            Uri blobUri = new (string.Format($"https://{accountName}.blob.core.windows.net"));
            BlobClient blob = new BlobServiceClient(blobUri, credential, options).GetBlobContainerClient("blogdata").GetBlobClient("BY-DEMO-ENCRYPTED-BLOB");

            // Upload the encrypted contents to the blob
            Stream blobContent = BinaryData.FromString("Blue Yonder Rocks!!!").ToStream();

            // Linux OpenSSL not happy about AESGCM -- Pointed Launch Config at SSL library

            await blob.UploadAsync(blobContent);

            // Download and decrypt the encrypted contents from the blob
            Response<BlobDownloadInfo>  response = await blob.DownloadAsync();
            BlobDownloadInfo downloadInfo = response.Value;
            Console.WriteLine((await BinaryData.FromStreamAsync(downloadInfo.Content)).ToString());
        }
    }
