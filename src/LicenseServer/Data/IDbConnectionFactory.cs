using System.Data.Common;

namespace MmProtect.LicenseServer.Data;

public interface IDbConnectionFactory
{
    Task<DbConnection> OpenAsync();
    bool IsSqlite { get; }
}
