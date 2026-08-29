using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace Nabira.Win.Core;

internal sealed class NabiraApiException : Exception
{
    public string Code { get; }
    public bool Unauthorized => Code is "invalid_token" or "unauthorized";
    public NabiraApiException(string code, string message) : base(message) => Code = code;
}

internal sealed class NabiraApiClient
{
    private readonly HttpClient _http;
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web);

    public NabiraApiClient(HttpMessageHandler? handler = null)
    {
        string configured = Environment.GetEnvironmentVariable("NABIRA_API_URL")?.Trim() ?? "";
        if (!Uri.TryCreate(configured, UriKind.Absolute, out Uri? baseUri))
            baseUri = new Uri("https://api.nabira.site");
        _http = handler == null ? new HttpClient() : new HttpClient(handler);
        _http.BaseAddress = baseUri;
        _http.Timeout = TimeSpan.FromSeconds(15);
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("Nabira-Windows/0.10");
    }

    public async Task<AccountUser> RegisterAsync(string email, string password) =>
        (await SendAsync<RegisterEnvelope>(HttpMethod.Post, "/v1/auth/register", new { email, password }, null, 201)).User;

    public Task<TokenPair> SignInAsync(string email, string password) =>
        SendAsync<TokenPair>(HttpMethod.Post, "/v1/auth/login", new { email, password }, null, 200);

    public Task<AccountUser> MeAsync(string accessToken) =>
        SendAsync<AccountUser>(HttpMethod.Get, "/v1/me", null, accessToken, 200);

    public Task<TokenPair> RefreshAsync(string refreshToken) =>
        SendAsync<TokenPair>(HttpMethod.Post, "/v1/auth/refresh", new { refresh_token = refreshToken }, null, 200);

    public async Task LogoutAsync(string accessToken) =>
        _ = await SendAsync<object>(HttpMethod.Post, "/v1/auth/logout", null, accessToken, 204);

    public Task<Entitlement> AccessStatusAsync(string deviceId, DateTimeOffset? localTrialStartedAt, string? accessToken) =>
        SendAsync<Entitlement>(HttpMethod.Post, "/v1/access/status",
            new { device_id = deviceId, local_trial_started_at = localTrialStartedAt }, accessToken, 200);

    private async Task<T> SendAsync<T>(HttpMethod method, string path, object? body, string? token, int expected)
    {
        using var request = new HttpRequestMessage(method, path);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (!string.IsNullOrWhiteSpace(token))
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (body != null) request.Content = JsonContent.Create(body, options: _json);

        HttpResponseMessage response;
        try { response = await _http.SendAsync(request); }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            throw new NabiraApiException("service_unavailable", L10n.T("account.server.error"));
        }
        using (response)
        {
            if ((int)response.StatusCode != expected)
            {
                string code = "invalid_response", message = L10n.T("account.response.error");
                try
                {
                    var envelope = await response.Content.ReadFromJsonAsync<ErrorEnvelope>(_json);
                    if (envelope?.Error != null) { code = envelope.Error.Code; message = envelope.Error.Message; }
                }
                catch { }
                throw new NabiraApiException(code, Localize(code, message));
            }
            if (expected == 204) return default!;
            return await response.Content.ReadFromJsonAsync<T>(_json)
                ?? throw new NabiraApiException("invalid_response", L10n.T("account.response.error"));
        }
    }

    private static string Localize(string code, string fallback) => code switch
    {
        "email_exists" => L10n.T("account.email.exists"),
        "invalid_credentials" => L10n.T("account.credentials.error"),
        "email_unverified" => L10n.T("account.email.unverified"),
        "invalid_email" => L10n.T("account.email.error"),
        "weak_password" => L10n.T("account.password.error"),
        "rate_limited" => L10n.T("account.rate.error"),
        "invalid_token" or "unauthorized" => L10n.T("account.session.error"),
        _ => fallback,
    };

    private sealed class RegisterEnvelope
    {
        [System.Text.Json.Serialization.JsonPropertyName("user")] public AccountUser User { get; set; } = new();
    }
    private sealed class ErrorEnvelope
    {
        [System.Text.Json.Serialization.JsonPropertyName("error")] public ErrorBody? Error { get; set; }
    }
    private sealed class ErrorBody
    {
        [System.Text.Json.Serialization.JsonPropertyName("code")] public string Code { get; set; } = "";
        [System.Text.Json.Serialization.JsonPropertyName("message")] public string Message { get; set; } = "";
    }
}
