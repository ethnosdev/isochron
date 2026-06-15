# macOS Release & DMG Distribution Guide

This guide explains how to package, sign, and distribute this Flutter macOS app as a `.dmg` file outside of the Mac App Store.

## Part 1: First-Time Mac Setup
*You only need to do this once on a new development machine.*

### 1. Verify Entitlements
Ensure your `macos/Runner/Release.entitlements` has the correct sandbox keys and allows Hardened Runtime:
```xml
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.process-inheritance</key>
	<true/>
</dict>
```

### 2. Generate Developer ID Certificate
Because we are distributing outside the App Store, you need a specific Apple certificate:
1. Open Xcode -> **Settings** -> **Accounts**.
2. Select your Apple ID and Team.
3. Click **Manage Certificates...**
4. Click the **+** button in the bottom left and add a **Developer ID Application** certificate.

### 3. Install `create-dmg`
We use `create-dmg` to generate the classic macOS installation window.
Open your terminal and install it via Homebrew:
```bash
brew install create-dmg
```

### 4. Setup your Notarization File (`notarization.md`)
Apple requires the final DMG to be uploaded and checked for malware (Notarization). To make this easy, we store the exact terminal command locally.

**A. Get an App-Specific Password:**
1. Go to [appleid.apple.com](https://appleid.apple.com) and log in.
2. Go to **Sign-In and Security** -> **App-Specific Passwords**.
3. Generate a new password (e.g., "Mac Notarytool") and copy it.

**B. Find your Team ID:**
If you ever need to find your Team ID, you can extract it directly from your signed app by running:
```bash
codesign -dv ~/Desktop/Isochron_DMG_Source/Isochron.app
```
*Look for the line that says `TeamIdentifier=ABCDE12345`. That 10-character code is your Team ID.*

**C. Create your secure file:**
1. Open `.gitignore` and add the following line to the bottom: 
   `macos/notarization.md`
2. Create a file at `macos/notarization.md` and paste your customized command inside it:
```bash
xcrun notarytool submit ~/Desktop/Isochron.dmg \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id "YOUR_10_CHAR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD" \
  --wait
```

---

## Part 2: Making Updates (Release Workflow)
*Follow these steps every time you want to release a new version of the app.*

### 1. Pre-build the Flutter App
Ensure all Dart code and Flutter assets are compiled for release:
```bash
flutter clean
flutter build macos --release
```

### 2. Archive and Export in Xcode
This ensures the app is signed with the correct Developer ID certificate and Hardened Runtime.
1. Open `macos/Runner.xcworkspace` in Xcode.
2. At the very top, ensure the target device is set to **Any Mac** or **My Mac**.
3. Go to the top menu: **Product** -> **Archive**.
4. When the Organizer window opens, click **Distribute App**.
5. Select: **Custom** -> **Developer ID** -> **Export** -> **Automatically manage signing**.
6. Save the exported folder (e.g., `Isochron_Release`) to your **Desktop**.

### 3. Generate the DMG
Open your terminal and run the following commands to wrap your `.app` into a `.dmg`:

```bash
cd ~/Desktop

# 1. Create a fresh staging folder
rm -rf Isochron_DMG_Source
mkdir Isochron_DMG_Source

# 2. Copy the exported app into the staging folder
# IMPORTANT: You MUST use `ditto` instead of `cp -r`! 
# `cp` breaks framework symlinks which invalidates the Apple Code Signature.
ditto "Isochron_Release/Isochron.app" "Isochron_DMG_Source/Isochron.app"

# 3. Create the DMG
# (Delete any existing DMG first)
rm -f Isochron.dmg
create-dmg \
  --volname "Isochron Installer" \
  --volicon "Isochron_DMG_Source/Isochron.app/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Isochron.app" 150 190 \
  --hide-extension "Isochron.app" \
  --app-drop-link 450 190 \
  "Isochron.dmg" \
  "Isochron_DMG_Source/"
```

### 4. Notarize the DMG
Apple must scan the DMG before users can open it without Gatekeeper warnings. 
1. Open `macos/notarization.md`.
2. Copy the `xcrun notarytool...` command you saved there.
3. Paste it into your terminal and press Enter.
4. Wait for the terminal to say **Accepted** *(this usually takes 1-3 minutes)*.

### 5. Staple the Ticket to the DMG
Once accepted, you must "staple" the notarization ticket to the file. This physically attaches Apple's approval to the DMG so users can install the app even if they are offline.

Run this final command in your terminal:
```bash
xcrun stapler staple ~/Desktop/Isochron.dmg
```

**Done!** `Isochron.dmg` is now fully signed, notarized, stapled, and ready to be distributed to users on the internet.