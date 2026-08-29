using System.Text.Json.Serialization;

namespace Nabira.Win.Core;

internal enum SubscriptionStatus
{
    Inactive,
    Active,
    PastDue,
    Canceled,
}

internal sealed class AccountUser
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("email")] public string Email { get; set; } = "";
    [JsonPropertyName("email_verified")] public bool EmailVerified { get; set; }
    [JsonPropertyName("subscription_status")] public string SubscriptionStatus { get; set; } = "inactive";
    [JsonPropertyName("created_at")] public string CreatedAt { get; set; } = "";
}

internal sealed class TokenPair
{
    [JsonPropertyName("access_token")] public string AccessToken { get; set; } = "";
    [JsonPropertyName("refresh_token")] public string RefreshToken { get; set; } = "";
    [JsonPropertyName("token_type")] public string TokenType { get; set; } = "Bearer";
    [JsonPropertyName("expires_in")] public int ExpiresIn { get; set; }
}

internal sealed class Entitlement
{
    [JsonPropertyName("server_time")] public DateTimeOffset ServerTime { get; set; }
    [JsonPropertyName("trial_started_at")] public DateTimeOffset TrialStartedAt { get; set; }
    [JsonPropertyName("trial_ends_at")] public DateTimeOffset TrialEndsAt { get; set; }
    [JsonPropertyName("trial_active")] public bool TrialActive { get; set; }
    [JsonPropertyName("trial_days_remaining")] public int TrialDaysRemaining { get; set; }
    [JsonPropertyName("authenticated")] public bool Authenticated { get; set; }
    [JsonPropertyName("subscription_status")] public string SubscriptionStatus { get; set; } = "inactive";
    [JsonPropertyName("active_subscription")] public bool ActiveSubscription { get; set; }
    [JsonPropertyName("has_access")] public bool HasAccess { get; set; }
    [JsonPropertyName("authentication_required")] public bool AuthenticationRequired { get; set; }
}

internal sealed class StoredAccountSession
{
    public string AccessToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public DateTimeOffset AccessExpiresAt { get; set; }
    public AccountUser User { get; set; } = new();
}

internal sealed record AccountSnapshot(
    DateTimeOffset Now,
    DateTimeOffset? TrialStartedAt,
    DateTimeOffset? TrialEndsAt,
    string? Email,
    SubscriptionStatus Subscription,
    string? Error)
{
    public TimeSpan TrialRemaining => TrialEndsAt is { } end && end > Now ? end - Now : TimeSpan.Zero;
    public int TrialDaysRemaining => TrialRemaining > TimeSpan.Zero
        ? Math.Max(1, (int)Math.Ceiling(TrialRemaining.TotalDays)) : 0;
    public bool TrialActive => TrialRemaining > TimeSpan.Zero;
    public bool Authenticated => !string.IsNullOrWhiteSpace(Email);
    public bool HasAccess => TrialActive || (Authenticated && Subscription == SubscriptionStatus.Active);
}
