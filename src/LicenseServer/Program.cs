using Dapper;
using MmProtect.LicenseServer.Data;
using MmProtect.LicenseServer.Models;
using MmProtect.LicenseServer.Security;
using System.Security.Cryptography;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<MySqlConnectionFactory>();
builder.Services.AddSingleton<ApiKeyValidator>();
builder.Services.AddSingleton<CryptoService>();
builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    version = typeof(Program).Assembly.GetName().Version?.ToString() ?? "dev",
    timeUtc = DateTimeOffset.UtcNow
}));

var encoder = app.MapGroup("/api/v1/encoder");
encoder.AddEndpointFilter<ApiKeyEndpointFilter>();

encoder.MapPost("/customers/upsert", async (CustomerUpsertRequest request, MySqlConnectionFactory db) =>
{
    var uid = "cust_" + Ids.NewId();
    await using var conn = await db.OpenAsync();

    await conn.ExecuteAsync("""
        INSERT INTO customers (customer_uid, external_customer_ref, name, email, notes)
        VALUES (@Uid, @ExternalCustomerRef, @Name, @Email, @Notes)
        ON DUPLICATE KEY UPDATE name = VALUES(name), email = VALUES(email), notes = VALUES(notes), updated_at = CURRENT_TIMESTAMP;
        """, new { Uid = uid, request.ExternalCustomerRef, request.Name, request.Email, request.Notes });

    var customerUid = await conn.ExecuteScalarAsync<string>(
        "SELECT customer_uid FROM customers WHERE external_customer_ref = @ExternalCustomerRef",
        new { request.ExternalCustomerRef });

    return Results.Ok(new CustomerUpsertResponse(customerUid, customerUid == uid));
});

encoder.MapPost("/projects/upsert", async (ProjectUpsertRequest request, MySqlConnectionFactory db) =>
{
    var uid = "proj_" + Ids.NewId();
    await using var conn = await db.OpenAsync();

    await conn.ExecuteAsync("""
        INSERT INTO projects (project_uid, project_key, name, php_min_version, description)
        VALUES (@Uid, @ProjectKey, @Name, @PhpMinVersion, @Description)
        ON DUPLICATE KEY UPDATE name = VALUES(name), php_min_version = VALUES(php_min_version), description = VALUES(description), updated_at = CURRENT_TIMESTAMP;
        """, new { Uid = uid, request.ProjectKey, request.Name, request.PhpMinVersion, request.Description });

    var projectUid = await conn.ExecuteScalarAsync<string>(
        "SELECT project_uid FROM projects WHERE project_key = @ProjectKey",
        new { request.ProjectKey });

    return Results.Ok(new ProjectUpsertResponse(projectUid, projectUid == uid));
});

encoder.MapPost("/licenses/upsert", async (LicenseUpsertRequest request, MySqlConnectionFactory db) =>
{
    var uid = "lic_" + Ids.NewId();
    await using var conn = await db.OpenAsync();

    var customerDbId = await DbLookup.CustomerIdAsync(conn, request.CustomerId);
    var projectDbId = await DbLookup.ProjectIdAsync(conn, request.ProjectId);

    await conn.ExecuteAsync("""
        INSERT INTO licenses
            (license_uid, customer_id, project_id, license_key, valid_from, valid_until, max_activations, features, status)
        VALUES
            (@Uid, @CustomerDbId, @ProjectDbId, @LicenseKey, @ValidFrom, @ValidUntil, @MaxActivations, @FeaturesJson, 'active')
        ON DUPLICATE KEY UPDATE
            valid_from = VALUES(valid_from),
            valid_until = VALUES(valid_until),
            max_activations = VALUES(max_activations),
            features = VALUES(features),
            updated_at = CURRENT_TIMESTAMP;
        """, new
    {
        Uid = uid,
        CustomerDbId = customerDbId,
        ProjectDbId = projectDbId,
        request.LicenseKey,
        ValidFrom = request.ValidFrom.UtcDateTime,
        ValidUntil = request.ValidUntil?.UtcDateTime,
        request.MaxActivations,
        FeaturesJson = JsonCanonical.Serialize(request.Features ?? [])
    });

    var licenseUid = await conn.ExecuteScalarAsync<string>(
        "SELECT license_uid FROM licenses WHERE license_key = @LicenseKey",
        new { request.LicenseKey });

    return Results.Ok(new LicenseUpsertResponse(licenseUid, licenseUid == uid));
});

encoder.MapPost("/builds/start", async (BuildStartRequest request, MySqlConnectionFactory db, CryptoService crypto) =>
{
    var buildUid = "build_" + Ids.NewId();
    var keyUid = "key_" + Ids.NewId();
    var buildKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));

    await using var conn = await db.OpenAsync();

    var customerDbId = await DbLookup.CustomerIdAsync(conn, request.CustomerId);
    var projectDbId = await DbLookup.ProjectIdAsync(conn, request.ProjectId);
    var licenseDbId = await DbLookup.LicenseIdAsync(conn, request.LicenseId);

    await conn.ExecuteAsync("""
        INSERT INTO crypto_keys (key_uid, key_type, algorithm, encrypted_secret_key)
        VALUES (@KeyUid, 'build', 'AES-256-GCM', @EncryptedSecretKey);
        """, new { KeyUid = keyUid, EncryptedSecretKey = crypto.ProtectForDemoOnly(buildKey) });

    var keyDbId = await conn.ExecuteScalarAsync<ulong>(
        "SELECT id FROM crypto_keys WHERE key_uid = @KeyUid", new { KeyUid = keyUid });

    await conn.ExecuteAsync("""
        INSERT INTO builds
            (build_uid, customer_id, project_id, license_id, key_id, version, source_revision, encoder_version)
        VALUES
            (@BuildUid, @CustomerDbId, @ProjectDbId, @LicenseDbId, @KeyDbId, @Version, @SourceRevision, @EncoderVersion);
        """, new
    {
        BuildUid = buildUid,
        CustomerDbId = customerDbId,
        ProjectDbId = projectDbId,
        LicenseDbId = licenseDbId,
        KeyDbId = keyDbId,
        request.Version,
        request.SourceRevision,
        request.EncoderVersion
    });

    return Results.Ok(new BuildStartResponse(buildUid, keyUid, buildKey, Convert.ToBase64String(RandomNumberGenerator.GetBytes(16))));
});

encoder.MapPost("/builds/{buildId}/files", async (string buildId, BuildFilesRequest request, MySqlConnectionFactory db) =>
{
    await using var conn = await db.OpenAsync();
    var buildDbId = await DbLookup.BuildIdAsync(conn, buildId);

    foreach (var file in request.Files)
    {
        await conn.ExecuteAsync("""
            INSERT INTO build_files
                (build_id, file_uid, relative_path, path_hash, plain_hash, cipher_hash, algorithm, kdf)
            VALUES
                (@BuildDbId, @FileId, @RelativePath, @PathHash, @PlainHash, @CipherHash, @Algorithm, @Kdf)
            ON DUPLICATE KEY UPDATE
                relative_path = VALUES(relative_path),
                path_hash = VALUES(path_hash),
                plain_hash = VALUES(plain_hash),
                cipher_hash = VALUES(cipher_hash),
                algorithm = VALUES(algorithm),
                kdf = VALUES(kdf);
            """, new
        {
            BuildDbId = buildDbId,
            file.FileId,
            file.RelativePath,
            file.PathHash,
            file.PlainHash,
            file.CipherHash,
            file.Algorithm,
            file.Kdf
        });
    }

    await conn.ExecuteAsync(
        "UPDATE builds SET file_count = @FileCount, status = 'files_registered' WHERE id = @BuildDbId",
        new { FileCount = request.Files.Count, BuildDbId = buildDbId });

    return Results.Ok(new { accepted = request.Files.Count, rejected = 0 });
});

encoder.MapPost("/builds/{buildId}/manifest/sign", async (string buildId, ManifestSignRequest request, MySqlConnectionFactory db, CryptoService crypto) =>
{
    await using var conn = await db.OpenAsync();
    var signature = crypto.SignForDemoOnly(request.ManifestHash);

    await conn.ExecuteAsync("""
        UPDATE builds
        SET manifest_hash = @ManifestHash,
            manifest_signature = @Signature,
            file_count = @FileCount,
            status = 'signed',
            signed_at = CURRENT_TIMESTAMP
        WHERE build_uid = @BuildId;
        """, new { BuildId = buildId, request.ManifestHash, Signature = signature, request.FileCount });

    return Results.Ok(new ManifestSignResponse(signature, "dev-demo-key", DateTimeOffset.UtcNow));
});

app.MapPost("/api/v1/runtime/lease", async (RuntimeLeaseRequest request, MySqlConnectionFactory db, CryptoService crypto, IConfiguration config) =>
{
    await using var conn = await db.OpenAsync();

    var row = await conn.QuerySingleOrDefaultAsync<dynamic>("""
        SELECT
            l.id AS LicenseDbId,
            b.id AS BuildDbId,
            k.encrypted_secret_key AS EncryptedSecretKey,
            l.status AS LicenseStatus,
            l.valid_until AS ValidUntil,
            l.max_activations AS MaxActivations
        FROM licenses l
        JOIN builds b ON b.license_id = l.id
        JOIN crypto_keys k ON b.key_id = k.id
        WHERE l.license_uid = @LicenseId
          AND b.build_uid = @BuildId
          AND b.manifest_hash = @ManifestHash
        LIMIT 1;
        """, new { request.LicenseId, request.BuildId, request.ManifestHash });

    if (row is null)
        return Results.BadRequest(ErrorDto.Create("LEASE_DENIED", "License, build or manifest invalid."));

    if ((string)row.LicenseStatus != "active")
        return Results.BadRequest(ErrorDto.Create("LICENSE_REVOKED", "License is not active."));

    if (row.ValidUntil is not null && (DateTime)row.ValidUntil < DateTime.UtcNow)
        return Results.BadRequest(ErrorDto.Create("LICENSE_EXPIRED", "License is expired."));

    var activationUid = "act_" + Ids.NewId();
    await conn.ExecuteAsync("""
        INSERT INTO license_activations (activation_uid, license_id, machine_fingerprint, last_seen_at)
        VALUES (@ActivationUid, @LicenseDbId, @MachineFingerprint, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE last_seen_at = CURRENT_TIMESTAMP;
        """, new { ActivationUid = activationUid, LicenseDbId = (ulong)row.LicenseDbId, request.MachineFingerprint });

    var activationDbId = await conn.ExecuteScalarAsync<ulong>("""
        SELECT id FROM license_activations
        WHERE license_id = @LicenseDbId AND machine_fingerprint = @MachineFingerprint
        """, new { LicenseDbId = (ulong)row.LicenseDbId, request.MachineFingerprint });

    var activeCount = await conn.ExecuteScalarAsync<int>("""
        SELECT COUNT(*) FROM license_activations
        WHERE license_id = @LicenseDbId AND status = 'active'
        """, new { LicenseDbId = (ulong)row.LicenseDbId });

    if (activeCount > (int)row.MaxActivations)
        return Results.BadRequest(ErrorDto.Create("ACTIVATION_LIMIT_REACHED", "Activation limit reached."));

    var ttl = config.GetValue<int>("Security:LeaseTtlMinutes", 1440);
    var graceDays = config.GetValue<int>("Security:GracePeriodDays", 7);
    var issuedAt = DateTimeOffset.UtcNow;
    var expiresAt = issuedAt.AddMinutes(ttl);
    var graceUntil = expiresAt.AddDays(graceDays);
    var leaseUid = "lease_" + Ids.NewId();

    await conn.ExecuteAsync("""
        INSERT INTO runtime_leases
            (lease_uid, license_id, build_id, activation_id, nonce, issued_at, expires_at, grace_until)
        VALUES
            (@LeaseUid, @LicenseDbId, @BuildDbId, @ActivationDbId, @Nonce, @IssuedAt, @ExpiresAt, @GraceUntil);
        """, new
    {
        LeaseUid = leaseUid,
        LicenseDbId = (ulong)row.LicenseDbId,
        BuildDbId = (ulong)row.BuildDbId,
        ActivationDbId = activationDbId,
        request.Nonce,
        IssuedAt = issuedAt.UtcDateTime,
        ExpiresAt = expiresAt.UtcDateTime,
        GraceUntil = graceUntil.UtcDateTime
    });

    var runtimeKey = crypto.UnprotectForDemoOnly((string)row.EncryptedSecretKey);
    var signature = crypto.SignForDemoOnly($"{leaseUid}:{request.BuildId}:{request.MachineFingerprint}:{expiresAt:O}");

    return Results.Ok(new RuntimeLeaseResponse(
        "MMENC-LEASE-1",
        leaseUid,
        request.ProjectId,
        request.CustomerId,
        request.LicenseId,
        request.BuildId,
        "runtime-key",
        runtimeKey,
        issuedAt,
        expiresAt,
        graceUntil,
        signature));
});

app.Run();

public partial class Program { }
