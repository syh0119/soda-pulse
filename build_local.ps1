$ErrorActionPreference = 'Stop'

$env:JAVA_HOME = 'D:\WorkBuddy\_tools\jdk21\jdk-21.0.13.1+2'
$env:ANDROID_HOME = 'D:\WorkBuddy\_tools\android-sdk'
$env:ANDROID_SDK_ROOT = 'D:\WorkBuddy\_tools\android-sdk'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = 'D:\WorkBuddy\_tools\flutter-pub-cache'
$env:GRADLE_USER_HOME = 'D:\WorkBuddy\_tools\gradle-home'

$env:PATH = (
    'D:\WorkBuddy\_tools\jdk21\jdk-21.0.13.1+2\bin;' +
    'D:\WorkBuddy\_tools\mingit\cmd;' +
    'D:\WorkBuddy\_tools\flutter\bin;' +
    'D:\WorkBuddy\_tools\gradle-9.8.0\bin;' +
    'D:\WorkBuddy\_tools\android-sdk\cmdline-tools\latest\bin;' +
    'D:\WorkBuddy\_tools\platform-tools;' +
    'D:\WorkBuddy\_tools\android-sdk\platform-tools;' +
    $env:PATH
)

Set-Location 'F:\gemini\soda_pulse'

if (-not (Test-Path 'android\gradlew.bat')) {
    Push-Location 'android'
    gradle wrapper --gradle-version 9.5.0 --gradle-distribution-url https://repo.huaweicloud.com/gradle/gradle-9.5.0-bin.zip
    Pop-Location
}

flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build apk --release --target-platform android-arm64
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
