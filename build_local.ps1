$ErrorActionPreference = 'Stop'

$env:JAVA_HOME = 'F:\gemini\toolchains\jdk21\jdk-21.0.13.1+2'
$env:ANDROID_HOME = 'F:\gemini\toolchains\android-sdk'
$env:ANDROID_SDK_ROOT = 'F:\gemini\toolchains\android-sdk'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_CACHE = 'F:\gemini\toolchains\pub-cache'
$env:GRADLE_USER_HOME = 'F:\gemini\toolchains\gradle-home'

$env:PATH = (
    'F:\gemini\toolchains\jdk21\jdk-21.0.13.1+2\bin;' +
    'F:\gemini\toolchains\mingit\cmd;' +
    'F:\gemini\toolchains\flutter\bin;' +
    'F:\gemini\toolchains\gradle\gradle-9.5.0\bin;' +
    'F:\gemini\toolchains\android-sdk\cmdline-tools\latest\bin;' +
    'F:\gemini\toolchains\android-sdk\platform-tools;' +
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
