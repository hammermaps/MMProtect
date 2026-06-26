using Dapper;
using System.Data.Common;

namespace MmProtect.LicenseServer.Data;

public static class DbLookup
{
    public static Task<long> CustomerIdAsync(DbConnection conn, string customerUid)
        => LookupAsync(conn, "customers", "customer_uid", customerUid);

    public static Task<long> ProjectIdAsync(DbConnection conn, string projectUid)
        => LookupAsync(conn, "projects", "project_uid", projectUid);

    public static Task<long> LicenseIdAsync(DbConnection conn, string licenseUid)
        => LookupAsync(conn, "licenses", "license_uid", licenseUid);

    public static Task<long> BuildIdAsync(DbConnection conn, string buildUid)
        => LookupAsync(conn, "builds", "build_uid", buildUid);

    private static async Task<long> LookupAsync(DbConnection conn, string table, string column, string value)
    {
        var sql = $"SELECT id FROM {table} WHERE {column} = @Value LIMIT 1";
        var id = await conn.ExecuteScalarAsync<long?>(sql, new { Value = value });

        if (id is null)
            throw new InvalidOperationException($"Database object not found: {table}.{column}={value}");

        return id.Value;
    }
}
