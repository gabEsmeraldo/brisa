# Brisa

A tiny macOS menu bar app to control an LG air conditioner through LG's official **ThinQ Connect API**.

- Power, mode, target temperature, fan speed, Eco and Jet mode, sleep timer and airflow direction
- Room temperature in the menu bar; the item only shows while the AC is on (open Brisa again from Spotlight to bring it back)
- Right-click the icon to toggle power
- Only shows the controls your unit's profile supports
- English and Portuguese (Brazil)

> Not affiliated with, endorsed by, or sponsored by LG Electronics. "LG" and "ThinQ" are trademarks of their owners.

## Install

1. Download the latest `Brisa-x.y.z.dmg` from [Releases](../../releases) and drag **Brisa** into Applications.
2. Brisa isn't notarized (no paid Apple Developer account), so macOS blocks the first launch. Open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Brisa.app
   ```

Requires macOS 14 or later.

## Set up

1. Sign in at [connect-pat.lgthinq.com](https://connect-pat.lgthinq.com), choose **Add new token**, select all scopes and copy the token.
2. Click the Brisa icon, paste the token in **Settings** and press **Save**. It's stored in your macOS Keychain.
3. Pick your air conditioner if you have more than one.

The country of your ThinQ account is taken from your Mac's region (e.g. Brazil → `BR`, Americas server).

Status refreshes every 5 minutes in the background, and every minute while the panel is open.

## Build

```bash
make run    # build Brisa.app and open it
make dmg    # build/Brisa-<version>.dmg
```

Pushing a `v*` tag builds the DMG on GitHub Actions and attaches it to a release.

## License

MIT
