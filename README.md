# Hardware Diagnostics App - Automated Release Pipeline

A premium cross-platform mobile hardware diagnostics utility built with Flutter that collects hardware specifications (CPU, RAM, storage, battery) and allows users to export them as JSON. This repository is configured to build, sign, and publish APKs automatically to GitHub Releases.

---

## 1. Setup Android Signing Keys

To build a secure, signed APK that users can install directly, you must create a release keystore.

### Step A: Generate the Keystore
Run the following command in your terminal. Fill out the prompts and **note down the values you choose**.

```bash
keytool -genkey -v \
  -keystore android/app/upload-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias release
```

> [!WARNING]
> Keep your keystore password, key alias, and key password in a safe place.
> **DO NOT** commit the `upload-keystore.jks` file to your public Git repository. It is already added to `.gitignore`.

### Step B: Encode the Keystore to Base64
GitHub Secrets only accepts text-based values. Convert your binary keystore file into a Base64 string so the CI/CD environment can decode it during execution:

* **macOS / Linux:**
  ```bash
  base64 -i android/app/upload-keystore.jks | pbcopy
  ```
  *(The Base64 string is now in your clipboard)*

* **Windows (PowerShell):**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | clip
  ```

---

## 2. Store Secrets in GitHub

Go to your repository on GitHub:
1. Navigate to **Settings** → **Secrets and variables** → **Actions**.
2. Click **New repository secret**.
3. Create the following four secrets:

| Secret Name | Value |
| :--- | :--- |
| `RELEASE_KEYSTORE` | Paste the **Base64 string** from your clipboard. |
| `RELEASE_KEYSTORE_PASSWORD` | The password you chose for the keystore file. |
| `RELEASE_KEY_ALIAS` | The key alias you specified (e.g., `release`). |
| `RELEASE_KEY_PASSWORD` | The password you chose for the specific key alias. |

---

## 3. Local Development (Optional)

If you wish to sign and build the APK locally, create a file named `key.properties` inside the `android/` directory (do not commit this file):

```properties
storePassword=your_keystore_password
keyPassword=your_key_password
keyAlias=release
storeFile=upload-keystore.jks
```

Ensure your keystore file `upload-keystore.jks` is placed inside `android/app/`.

---

## 4. How to Trigger a Build and Publish a Release

Whenever you want to release a new version of the app to your users:

1. Update the app version in `pubspec.yaml` (e.g., from `1.0.0+1` to `1.0.1+2`).
2. Commit your changes:
   ```bash
   git add pubspec.yaml
   git commit -m "Bump version to 1.0.1"
   ```
3. Create a version tag matching the `v*` pattern (e.g., `v1.0.1`):
   ```bash
   git tag -a v1.0.1 -m "Release version 1.0.1"
   ```
4. Push the code and the tag to GitHub:
   ```bash
   git push origin main
   git push origin v1.0.1
   ```

GitHub Actions will automatically trigger, build the signed APKs (universal + split), and upload them to a newly created Release page with release notes.

---

## 5. OTA (Over-The-Air) In-App Updates

The application is pre-configured with a custom, premium Update Checker.
1. Tap the **Settings icon (cog)** in the top right of the application dashboard.
2. Enter your **GitHub Username** (or Organization) and **Repository Name**.
3. Tap **Save**.
4. The **Check for Updates** button on the dashboard will call the GitHub API, check if the latest release tag is newer than the current version, display release notes, and prompt the user to download the update directly.

---

## 6. Recommended Direct Distribution Tools

For users downloading APKs directly, keeping track of updates manually can be tedious. We highly recommend recommending **Obtainium** to your users.

### What is Obtainium?
[Obtainium](https://github.com/ImranR98/Obtainium) is an open-source Android app that allows users to install and update apps directly from their source releases (GitHub, GitLab, etc.) without using an app store.

### Why recommend it?
- **Auto-checks**: Obtainium will check your GitHub Releases page automatically in the background.
- **Sideload convenience**: Users get a notification when you publish a new tag, and they can download and install the new version with one click.
- **Free**: No fees, no trackings, completely open-source.
