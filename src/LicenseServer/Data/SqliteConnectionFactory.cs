using System.Data.Common;
using Microsoft.Data.Sqlite;

namespace MmProtect.LicenseServer.Data;

public sealed class SqliteConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;
    public bool IsSqlite => true;

    public SqliteConnectionFactory(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("Sqlite")
            ?? "Data Source=mm_license_dev.db";
    }

    public async Task<DbConnection> OpenAsync()
    {
        var conn = new SqliteConnection(_connectionString);
        await conn.OpenAsync();
        return conn;
    }
}
