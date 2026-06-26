using Dapper;
using MySqlConnector.MySql;

namespace MmProtect.LicenseServer.Data;

public static class DbLookup
{
    public static Task<ulong> CustomerIdAsync(MySqlConnection conn, string customerUid)
        => LookupAsync(conn, "customers", "customer_uid", customerUid);

    public static Task<ulong> ProjectIdAsync(MySqlConnection conn, string projectUid)
        => LookupAsync(conn, "projects", "project_uid", projectUid);

    public static Task<ulong> LicenseIdAsync(MySqlConnection conn, string licenseUid)
        => LookupAsync(conn, "licenses", "license_uid", licenseUid);

    public static Task<ulong> BuildIdAsync(MySqlConnection conn, string buildUid)
        => LookupAsync(conn, "builds", "build_uid", buildUid);

    private static async Task<ulong> LookupAsync(MySqlConnection conn, string table, string column, string value)
    {
        var sql = $"SELECT id FROM {table} WHERE {column} = @Value LIMIT 1";
        var id = await conn.ExecuteScalarAsync<ulong?>(sql, new { Value = value });

        if (id is null)
            throw new InvalidOperationException($"Database object not found: {table}.{column}={value}");

        return id.Value;
    }
}
