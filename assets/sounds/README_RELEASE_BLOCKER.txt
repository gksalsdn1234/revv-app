⚠️ 출시 전 삭제 필수 (RELEASE BLOCKER)

beep.mp3 = myinstants.com 의 "F1 Radio" 클립 (F1 방송 원본 오디오).
- 출처: https://www.myinstants.com/ko/instant/f1-radio-36521/
- 문제: FOM(Formula One Management) 방송 오디오. myinstants는 밈 사운드보드로
  상업 배포 라이선스를 제공하지 않음. App Store 상업 배포 시 저작권 침해 리스크.
- 현재 상태: 개인 테스트 전용. PTT chirp 효과음으로 임시 사용 중.

App Store 제출 전 필수 조치 (택1):
1) 오리지널 합성 비프로 교체 (git 히스토리에 F1 스타일 사각파 합성본 있음: commit b8abd21)
2) chirp 기능 자체 제거 (lib/labs/walkie/walkie_ptt_controller.dart 의 BeepWalkieChirp)

관련 코드 마커: BeepWalkieChirp 클래스 상단 주석.
