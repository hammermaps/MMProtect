namespace MmProtect.LicenseServer.Security;

public sealed class ApiKeyValidator
{
    private readonly HashSet<string> _allowedKeys;

    public ApiKeyValidator(IConfiguration configuration)
    {
        _allowedKeys = configuration
            .GetSection("Security:EncoderApiKeys")
            .Get<string[]>()?
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .ToHashSet(StringComparer.Ordinal)
            ?? [];
    }

    public bool IsValid(string? authorizationHeader)
    {
        if (string.IsNullOrWhiteSpace(authorizationHeader))
            return false;

        const string prefix = "Bearer ";
        if (!authorizationHeader.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            return false;

        var token = authorizationHeader[prefix.Length..].Trim();
        return _allowedKeys.Contains(token);
    }
}

public sealed class ApiKeyEndpointFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var validator = context.HttpContext.RequestServices.GetRequiredService<ApiKeyValidator>();
        var auth = context.HttpContext.Request.Headers.Authorization.FirstOrDefault();

        if (!validator.IsValid(auth))
            return Results.Json(ErrorDto.Create("AUTH_INVALID", "Invalid or missing API key."), statusCode: 401);

        return await next(context);
    }
}

public sealed record ErrorDto(ErrorBody Error)
{
    public static ErrorDto Create(string code, string message)
        => new(new ErrorBody(code, message, Guid.NewGuid().ToString("N")));
}

public sealed record ErrorBody(string Code, string Message, string TraceId);
