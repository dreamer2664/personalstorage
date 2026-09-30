# Native integrations: one-tap capture from anywhere

Everything is a **deep link** into the Flutter app. The contract:

| URL | Result |
|---|---|
| `personalstorage:///capture` | opens (or returns to) the **Capture** tab with the composer focused |
| `personalstorage:///voice` | same, and starts dictation |

Flutter's engine hands the URL to the Navigator; `PersonalStorageApp.normalizeRoute` accepts every form the
platforms deliver (`/voice`, `personalstorage:///voice`, `personalstorage://voice`) for warm *and* cold
starts, so no Swift/Kotlin glue is needed for routing. The shell also re-focuses the composer whenever the
app comes back to the foreground (resume-to-capture).

## Android (`android/app/src/main`)

| Entry point | Implementation |
|---|---|
| **Quick Settings tile** "Quick note" (pull down the shade, also from the lock screen after the usual unlock prompt) | `CaptureTileService.kt` - starts the deep link; uses the `PendingIntent` overload on Android 14+ |
| **Home / lock-screen widget** with *New note* and *Voice* buttons | `CaptureWidgetProvider.kt` + `res/layout/widget_capture.xml`; declared `home_screen|keyguard`, horizontally resizable, light/dark colours |
| **App shortcuts** (long-press the icon) | `res/xml/shortcuts.xml` (static: they exist before the app has ever run); `@string/app_id` is generated from `applicationId` |
| **Share sheet** "Personal Storage" for text, links and photos | intent filters + `MainActivity.kt`, which copies shared images into app-private cache and passes `{text, images}` over the `app.personalstorage/launch` channel |
| **Reminders** | receivers + `RECEIVE_BOOT_COMPLETED` so scheduled notifications survive a reboot; core-library desugaring enabled |

Try it (device or emulator):

```bash
adb shell am start -a android.intent.action.VIEW -d "personalstorage:///capture" com.personalstorage.personalstorage
adb shell am start -a android.intent.action.VIEW -d "personalstorage:///voice"   com.personalstorage.personalstorage
adb shell am start -a android.intent.action.SEND -t text/plain \
   --es android.intent.extra.TEXT "https://example.com/article" com.personalstorage.personalstorage/.MainActivity
```

The Quick Settings tile appears under *edit tiles*; widgets under *Widgets -> Personal Storage*.
If you change the Kotlin package, update `targetClass` in `shortcuts.xml`.

## iOS (`ios/`)

| Entry point | Implementation |
|---|---|
| URL scheme `personalstorage://` | `CFBundleURLTypes` + `FlutterDeepLinkingEnabled` in `Info.plist` |
| **Lock-screen widgets** (circular, rectangular, inline) and home-screen small widget: *Quick note*, *Voice note* | `ios/PersonalStorageWidgets/CaptureWidgets.swift` (`widgetURL`) |
| **Control Center / lock-screen controls** (iOS 18) | `CaptureControls.swift` (`ControlWidgetButton` + `OpenURLIntent`) |
| **Home-screen quick actions** | `quick_actions` (iOS only; Android uses the static shortcuts) |

The WidgetKit extension is **opt-in on purpose**: its Swift sources are not part of the Xcode project until you
run one command, so a plain `flutter run` on iOS can never be broken by code that could not be compiled
where this project was written.

```bash
gem install xcodeproj                    # once
ruby tool/ios/add_widget_extension.rb    # creates the target, embeds it, orders build phases; idempotent
open ios/Runner.xcworkspace              # choose your Team for both targets, then run
xcrun simctl openurl booted "personalstorage:///capture"      # test the deep link
```

The script creates the `PersonalStorageWidgets` app-extension target (iOS 16+), attaches WidgetKit/SwiftUI,
embeds it in *Runner* and places "Embed Foundation Extensions" *before* Flutter's "Thin Binary" phase (the
usual fix for Xcode's "Cycle inside Runner" error). No App Group is needed because the widgets only open URLs.

**Lock-screen privacy:** the app never shows itself above the lock screen; the recent-captures strip would
expose notes. Tapping a widget or control shows the normal unlock step first.

## Permissions

| Platform | Declared |
|---|---|
| Android | `INTERNET`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`; `<queries>` for speech recognition and https links |
| iOS | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription` (notification permission is requested at runtime) |

## What is verified

| Item | Status |
|---|---|
| Android: `flutter build apk --debug` (AGP 9.1, Gradle 9.3, JDK 21) compiles the Kotlin and merges manifests | **Verified** |
| Android merged manifest contains the tile service, widget receiver + provider metadata, shortcuts resource, share/deep-link filters, speech `<queries>`, notification receivers, permissions | **Verified** (inspected with `aapt2`) |
| Deep-link routing for warm and cold starts, share text into composer, graceful no-speech-engine | **Verified** by widget tests |
| iOS `Info.plist` edits; Ruby script adds the widget target, is idempotent, yields a well-formed project | **Verified** (run against the real `project.pbxproj`, which is left untouched) |
| Android tile / widget / shortcut / share behaviour on a device or emulator | **Not verified** (no emulator in the build environment) |
| Anything iOS at runtime, including Swift compilation of the widget extension | **Not verified** (no Xcode) |
