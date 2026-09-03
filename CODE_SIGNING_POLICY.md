# Nabira code signing policy

## Current signing status

Nabira does not currently have a trusted Authenticode certificate. The SignPath Foundation
application was not approved because the project is still new and does not yet have enough public
adoption signals. Current Windows downloads may therefore trigger browser reputation warnings and
Microsoft Defender SmartScreen.

Windows artifacts are built from this public repository by GitHub Actions. The release workflow
publishes SHA-256 checksums, while the application's update feed is signed with a separate offline
ECDSA release key. These checks protect file integrity and update metadata, but they are not a
replacement for an Authenticode signature and do not establish a trusted Windows publisher.

## Scope

This policy covers the Windows executables and installer published by the Nabira project. Release
artifacts are built only from this public repository by the `windows-release` GitHub Actions
workflow on GitHub-hosted Windows runners. A release is started by an explicit `win-vX.Y.Z` tag or
manual release workflow invocation.

The workflow builds and tests the source, builds the Inno Setup installer, and publishes checksums
and release assets. When a trusted provider is configured, it also signs the x64 and arm64
executables and installer and verifies every Authenticode signature before publication. Stable
workflow runs fail closed without a trusted signer; explicitly selected beta runs may remain
unsigned.

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

## Optional signing configuration

The workflow retains support for either SignPath or a conventional PFX certificate. If SignPath
approves a future application, the repository owner configures one GitHub Actions secret and five
repository variables:

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
