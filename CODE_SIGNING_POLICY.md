# Nabira code signing policy

Free code signing provided by [SignPath.io](https://signpath.io/), certificate by
[SignPath Foundation](https://signpath.org/).

## Scope

This policy covers the Windows executables and installer published by the Nabira project. Release
artifacts are built only from this public repository by the `windows-release` GitHub Actions
workflow on GitHub-hosted Windows runners. A release is started by an explicit `win-vX.Y.Z` tag or
manual release workflow invocation.

The workflow builds and tests the source, signs the x64 and arm64 application executables, builds
the Inno Setup installer from the already signed x64 executable, signs the installer, verifies all
Authenticode signatures, and only then publishes checksums and release assets. Every SignPath
Foundation signing request requires manual approval.

## Project roles

- Committer and reviewer: [@mitfleg](https://github.com/mitfleg)
- Signing approver: [@mitfleg](https://github.com/mitfleg)

Changes proposed by other contributors must be reviewed before they are merged. The maintainer
must use multi-factor authentication for repository and signing-service access.

## Privacy and network access

Nabira processes typed text locally. It does not send keystrokes, messages, documents, clipboard
contents, or text corrections to Nabira servers and does not include telemetry. Network access is
used for user-requested account operations, trial and subscription status, release update checks,
and downloads. Details are published in the
[Nabira privacy policy](https://nabira.site/legal/privacy).

## System changes and removal

The Windows installer performs a per-user installation without administrator privileges and adds a
Start menu shortcut. Launch at login is disabled unless the user enables it in Nabira settings. The
installer registers a standard uninstaller, available from Windows Settings → Apps → Installed apps.

## Reporting security issues

Security and signing concerns can be reported privately to
[mitfleg@icloud.com](mailto:mitfleg@icloud.com). Do not include passwords, session tokens, private
keys, or other secrets in a report.

## SignPath CI configuration

After SignPath Foundation approves the project, the repository owner configures one GitHub Actions
secret and five repository variables:

- secret `SIGNPATH_API_TOKEN`;
- variable `SIGNPATH_ORGANIZATION_ID`;
- variable `SIGNPATH_PROJECT_SLUG`;
- variable `SIGNPATH_SIGNING_POLICY_SLUG`;
- variable `SIGNPATH_APP_ARTIFACT_CONFIGURATION_SLUG`;
- variable `SIGNPATH_INSTALLER_ARTIFACT_CONFIGURATION_SLUG`.

The application artifact configuration accepts `Nabira-win-x64.exe` and
`Nabira-win-arm64.exe`. The installer configuration accepts `Nabira-Setup-<version>.exe`. Both use
the required `version` request parameter, restrict the product name to `Nabira`, enforce matching
product/file versions, and apply an SHA-256 Authenticode signature. Ready-to-import configurations
are stored in [`.signpath/app-binaries.xml`](.signpath/app-binaries.xml) and
 [`.signpath/installer.xml`](.signpath/installer.xml).
