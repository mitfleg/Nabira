# winget manifests

Templates for publishing Nabira to the Windows Package Manager community repo
([microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)). Submission is a manual PR — it
is intentionally not automated here.

## Steps for a new version

1. Publish the Windows release first (push a `win-v<version>` tag → the `windows-release` workflow
   builds the installer and a `SHA256SUMS.txt`).
2. In all three manifests, set `PackageVersion` to the new version.
3. In `Mitfleg.Nabira.installer.yaml`:
   - set `InstallerUrl` to the release's `Nabira-Setup-<version>.exe` asset URL;
   - set `InstallerSha256` to that file's hash from `SHA256SUMS.txt` (upper- or lower-case both work).
4. Validate locally:
   ```
   winget validate --manifest windows/winget
   ```
5. Submit: fork microsoft/winget-pkgs, copy the three files to
   `manifests/r/Nabira/Nabira/<version>/`, and open a PR. The winget bot runs its own
   automated checks.

> Note: the `PackageIdentifier` (`Mitfleg.Nabira`) is permanent once accepted — do not change
> it between versions.
