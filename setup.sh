#!/bin/bash

# REVV App 설정 스크립트
set -e

echo "🚗 REVV App 설정 시작..."

# 1. Flutter 경로 설정
export PATH="/Users/minwoohan/flutter/bin:$PATH"

echo "✅ Flutter 경로 설정"

# 2. 의존성 설치
echo "📦 Flutter 패키지 설치 중..."
flutter pub get

echo "✅ Flutter 패키지 설치 완료"

# 3. iOS 설정
if command -v pod &> /dev/null; then
    echo "🍎 CocoaPods 감지됨, iOS 의존성 설치 중..."
    cd ios
    pod install --repo-update
    cd ..
    echo "✅ iOS 의존성 설치 완료"
else
    echo "⚠️  CocoaPods가 설치되지 않았습니다."
    echo "다음 명령어를 실행하세요:"
    echo "  brew install cocoapods"
    echo "또는"
    echo "  sudo gem install cocoapods"
fi

# 4. 앱 정보 출력
echo ""
echo "🎉 설정 완료!"
echo "앱 실행 명령어:"
echo "  export PATH=\"/Users/minwoohan/flutter/bin:\$PATH\""
echo "  flutter run"
