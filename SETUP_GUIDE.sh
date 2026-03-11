#!/bin/bash

# REVV App - 최종 설정 가이드
# 이 파일을 터미널에서 복사해서 실행하세요

echo "===================="
echo "🚗 REVV App 최종 설정"
echo "===================="

# 1단계: Homebrew 설치 (아직 설치 안 됐으면)
echo ""
echo "📍 1단계: Homebrew 설치"
if ! command -v brew &> /dev/null; then
    echo "Homebrew를 설치하는 중입니다..."
    echo "(비밀번호를 입력해야 할 수 있습니다)"
    sleep 2
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
echo "✅ Homebrew 설치 완료"

# 2단계: CocoaPods 설치 (Homebrew로)
echo ""
echo "📍 2단계: CocoaPods 설치"
if ! command -v pod &> /dev/null; then
    echo "CocoaPods를 설치하는 중입니다..."
    brew install cocoapods
fi
pod --version
echo "✅ CocoaPods 설치 완료"

# 3단계: 프로젝트 디렉토리로 이동
echo ""
echo "📍 3단계: iOS 의존성 설치"
cd /Users/minwoohan/revv-app
export PATH="/Users/minwoohan/flutter/bin:$PATH"

echo "Flutter pub get 실행 중..."
flutter pub get

echo "Pod install 실행 중..."
cd ios
pod install --repo-update
cd ..
echo "✅ 모든 의존성 설치 완료"

# 4단계: 앱 실행 준비
echo ""
echo "===================="
echo "🎉 모든 설정 완료!"
echo "===================="
echo ""
echo "다음 명령어로 앱을 실행하세요:"
echo ""
echo "  export PATH=\"/Users/minwoohan/flutter/bin:\$PATH\""
echo "  flutter run"
echo ""
echo "또는 시뮬레이터를 먼저 열려면:"
echo "  open -a Simulator"
echo "  (그 다음) flutter run"
echo ""
