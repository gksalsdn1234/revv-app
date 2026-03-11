# REVV App 설정 현황 📋

## ✅ 자동 완료된 항목

- [x] **Flutter 3.41.4 설치** (기본 설정)
- [x] **Dart 3.11.1 설치** (Flutter에 포함)
- [x] **Flutter 의존성 설치** (`flutter pub get`)
  - provider, mapbox_maps_flutter, geolocator, permission_handler, http, shared_preferences 등 30개 패키지 설치됨
- [x] **iOS 권한 설정** (Info.plist에 추가)
  - 위치 정보 (Location)
  - 마이크 (Microphone)
  - 음성 인식 (Speech Recognition)

## ⏳ 남은 작업 (수동 필요)

### 1️⃣ CocoaPods 설치 **[가장 중요]**
```bash
# 방법 1: Homebrew 사용 (권장)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install cocoapods

# 또는 방법 2: Ruby gem 사용
sudo gem install cocoapods
```

### 2️⃣ iOS 의존성 설치
```bash
cd /Users/minwoohan/revv-app
cd ios
pod install --repo-update
cd ..
```

### 3️⃣ 앱 실행
```bash
export PATH="/Users/minwoohan/flutter/bin:$PATH"
flutter run
```

## 📝 편리한 명령어

설정 후 다음 명령어 사용 가능:
```bash
revv-run          # 앱 실행
revv-simulator    # 시뮬레이터 열고 앱 실행
```

## 🎯 다음 단계

1. **CocoaPods 설치** → iOS 빌드에 필수
2. **`pod install` 실행** → 플러그인 의존성 해결
3. **`flutter run` 실행** → 앱 시작!

---
마지막 업데이트: 2026년 3월 11일
