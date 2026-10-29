# Signing secrets on GitHub

Gaea's repos live in the **xocialize-code** organization (moved from the `xocialize` account on 2026-10-29). The four
signing and notary secrets are organization secrets there, so every plugin repo's release workflow reads them, and a
new plugin needs nothing set up. Visibility is **all repositories**, since the plugins are public and the organization's
"private repositories" visibility leaves public repos out.

| Secret | Value |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | the Developer ID Application certificate and its key, as a .p12, base64 |
| `DEVELOPER_ID_P12_PASSWORD` | the .p12's export password |
| `NOTARY_APPLE_ID` | the Apple ID on team CFZS6RXUCP |
| `NOTARY_APP_PASSWORD` | an app-specific password for that Apple ID |

Releases made on this Mac don't use them: `scripts/release.sh` signs with the keychain and notarizes with the
`mlx-notary` profile.

## Setting or rotating them

1. **Give `gh` the organization scope** (it opens the browser once):

   ```bash
   gh auth refresh -h github.com -s admin:org
   ```

2. **Export the certificate.** Keychain Access → login → My Certificates → **Developer ID Application: Dustin Nielson
   (CFZS6RXUCP)**. Check that a private key is underneath, then Export… as `developer-id.p12` with a password.

3. **Have an app-specific password:** account.apple.com → Sign-In and Security → App-Specific Passwords.

4. **Run the script.** It asks for the .p12 password, the Apple ID and the app-specific password once, sets the four
   organization secrets, and removes any per-repo copies from the `gaea-plugin-*` repos (a repo's own secret overrides
   the organization's):

   ```bash
   tools/set-signing-secrets.sh ~/Desktop/developer-id.p12
   ```

5. **Delete the .p12:**

   ```bash
   rm -P ~/Desktop/developer-id.p12
   ```

6. **Check:**

   ```bash
   gh secret list --org xocialize-code
   ```

   Then re-run one release workflow, e.g. `gh workflow run release -R xocialize-code/gaea-plugin-demo -f tag=v0.3.0`.

## The move

- GitHub redirects the old `github.com/xocialize/gaea*` URLs (git, web, API and release downloads), so existing clones,
  installs and links keep working. Nothing may be created at an old name, or its redirect stops.
- Releases built before the move carry `https://github.com/xocialize/gaea-plugin-…` in their sealed manifest. Gaea
  0.6.1 accepts that when GitHub says both names are the same repo (`PluginManager.repository(declared:addedFrom:)`),
  so a plugin added by its new URL installs its old releases, and one added by its old URL takes releases built after.
- `tools/release-standin.py --moved xocialize=xocialize-code` answers the old owner the same way for the acceptance
  scripts.
