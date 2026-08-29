using System.Diagnostics;
using System.Text.Json;

namespace Nabira.Win.Core;

internal sealed class AccountAccessManager : IDisposable
{
    private readonly NabiraApiClient _api;
    private readonly SynchronizationContext _ui;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private readonly System.Threading.Timer _timer;
    private StoredAccountSession? _session;
    private DateTimeOffset? _serverTimeAnchor;
    private long _stopwatchAnchor;
    private Entitlement? _entitlement;

    public event Action<AccountSnapshot>? Changed;
    public AccountSnapshot Snapshot { get; private set; } =
        new(DateTimeOffset.UtcNow, null, null, null, SubscriptionStatus.Inactive, null);
    public bool HasAccess => Snapshot.HasAccess;

    public AccountAccessManager(SynchronizationContext ui, NabiraApiClient? api = null)
    {
        _ui = ui;
        _api = api ?? new NabiraApiClient();
        _session = LoadSession();
        _timer = new System.Threading.Timer(_ => _ = RefreshAsync(), null,
            TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(5));
    }

    public string MenuTitle
    {
        get
        {
            if (Snapshot.Authenticated) return Snapshot.Email!;
            if (Snapshot.TrialActive) return L10n.T("account.trial.menu", Snapshot.TrialDaysRemaining);
            return L10n.T("account.required.menu");
        }
    }

    public async Task RefreshAsync()
    {
        if (!await _refreshGate.WaitAsync(0)) return;
        try
        {
            string? error = null;
            try
            {
                if (_session != null) await RefreshSessionAsync();
                await RefreshEntitlementAsync();
            }
            catch (NabiraApiException ex) when (ex.Unauthorized)
            {
                ClearSession();
                try { await RefreshEntitlementAsync(); }
                catch (Exception retry) { error = retry.Message; }
            }
            catch (Exception ex) { error = ex.Message; }
            Publish(error);
        }
        finally { _refreshGate.Release(); }
    }

    public async Task<string> RegisterAsync(string email, string password, string confirmation)
    {
        email = ValidateEmail(email);
        ValidatePassword(password, confirmation);
        AccountUser user = await _api.RegisterAsync(email, password);
        return user.Email;
    }

    public async Task SignInAsync(string email, string password)
    {
        email = ValidateEmail(email);
        if (password.Length is < 8 or > 128) throw new InvalidOperationException(L10n.T("account.password.error"));
        TokenPair pair = await _api.SignInAsync(email, password);
        try
        {
            AccountUser user = await _api.MeAsync(pair.AccessToken);
            var stored = new StoredAccountSession
            {
                AccessToken = pair.AccessToken,
                RefreshToken = pair.RefreshToken,
                AccessExpiresAt = DateTimeOffset.UtcNow.AddSeconds(pair.ExpiresIn),
                User = user,
            };
            SaveSession(stored);
            _session = stored;
            await RefreshEntitlementAsync();
            Publish(null);
        }
        catch
        {
            try { await _api.LogoutAsync(pair.AccessToken); } catch { }
            throw;
        }
    }

    public async Task SignOutAsync()
    {
        string? access = _session?.AccessToken;
        ClearSession();
        if (access != null) { try { await _api.LogoutAsync(access); } catch { } }
        await RefreshAsync();
    }

    private async Task RefreshSessionAsync()
    {
        if (_session == null) return;
        if (_session.AccessExpiresAt > DateTimeOffset.UtcNow.AddSeconds(30))
        {
            _session.User = await _api.MeAsync(_session.AccessToken);
            SaveSession(_session);
            return;
        }

        TokenPair pair = await _api.RefreshAsync(_session.RefreshToken);
        AccountUser user = await _api.MeAsync(pair.AccessToken);
        _session = new StoredAccountSession
        {
            AccessToken = pair.AccessToken,
            RefreshToken = pair.RefreshToken,
            AccessExpiresAt = DateTimeOffset.UtcNow.AddSeconds(pair.ExpiresIn),
            User = user,
        };
        SaveSession(_session);
    }

    private async Task RefreshEntitlementAsync()
    {
        string deviceId = DeviceIdentity.Identifier();
        DateTimeOffset? localStart = Settings.Current.TrialStartedAtUnixSeconds > 0
            ? DateTimeOffset.FromUnixTimeSeconds(Settings.Current.TrialStartedAtUnixSeconds) : null;
        _entitlement = await _api.AccessStatusAsync(deviceId, localStart, _session?.AccessToken);
        _serverTimeAnchor = _entitlement.ServerTime;
        _stopwatchAnchor = Stopwatch.GetTimestamp();
        Settings.Current.TrialStartedAtUnixSeconds = _entitlement.TrialStartedAt.ToUnixTimeSeconds();
        Settings.Current.Save();
    }

    private void Publish(string? error)
    {
        DateTimeOffset now = _serverTimeAnchor is { } anchor
            ? anchor.Add(Stopwatch.GetElapsedTime(_stopwatchAnchor))
            : DateTimeOffset.UtcNow;
        Snapshot = new AccountSnapshot(
            now,
            _entitlement?.TrialStartedAt,
            _entitlement?.TrialEndsAt,
            _session?.User.Email,
            ParseSubscription(_entitlement?.SubscriptionStatus ?? _session?.User.SubscriptionStatus),
            error);
        var snapshot = Snapshot;
        _ui.Post(_ => Changed?.Invoke(snapshot), null);
    }

    private static SubscriptionStatus ParseSubscription(string? value) => value switch
    {
        "active" => SubscriptionStatus.Active,
        "past_due" => SubscriptionStatus.PastDue,
        "canceled" => SubscriptionStatus.Canceled,
        _ => SubscriptionStatus.Inactive,
    };

    private static string ValidateEmail(string raw)
    {
        string email = raw.Trim().ToLowerInvariant();
        int at = email.IndexOf('@');
        if (at <= 0 || at != email.LastIndexOf('@') || at == email.Length - 1 ||
            !email[(at + 1)..].Contains('.') || email.EndsWith('.') || email[(at + 1)..].StartsWith('.'))
            throw new InvalidOperationException(L10n.T("account.email.error"));
        return email;
    }

    private static void ValidatePassword(string password, string confirmation)
    {
        if (password.Length is < 8 or > 128) throw new InvalidOperationException(L10n.T("account.password.error"));
        if (password != confirmation) throw new InvalidOperationException(L10n.T("account.password.mismatch"));
    }

    private static StoredAccountSession? LoadSession()
    {
        try
        {
            string? json = CredentialStore.Load();
            return json == null ? null : JsonSerializer.Deserialize<StoredAccountSession>(json);
        }
        catch { return null; }
    }

    private static void SaveSession(StoredAccountSession session)
    {
        if (!CredentialStore.Save(JsonSerializer.Serialize(session)))
            throw new InvalidOperationException(L10n.T("account.credential.error"));
    }

    private void ClearSession()
    {
        CredentialStore.Clear();
        _session = null;
    }

    public void Dispose()
    {
        _timer.Dispose();
        _refreshGate.Dispose();
    }
}
