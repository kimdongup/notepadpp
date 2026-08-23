# Notepad++ for macOS

[![macOS Build](https://img.shields.io/badge/platform-macOS%2010.15+-brightgreen.svg)](BUILD_MAC.md)
[![C++20](https://img.shields.io/badge/C%2B%2B-20-blue.svg)](https://en.wikipedia.org/wiki/C%2B%2B20)
[![Localization](https://img.shields.io/badge/languages-94%20countries-orange.svg)](#-94개국-글로벌-다국어-지원-global-ui-localization)
[![Unit Tests](https://img.shields.io/badge/tests-64%20passed%20(100%25)-success.svg)](BUILD_MAC.md)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**Notepad++ for macOS**는 전 세계에서 가장 사랑받는 텍스트 및 소스 코드 에디터인 [Notepad++](https://github.com/notepad-plus-plus/notepad-plus-plus)를 macOS 환경에 맞추어 완벽하게 포팅한 네이티브 애플리케이션입니다. **Apple Clang C++20**, **Cocoa (AppKit/Foundation)**, **Scintilla Cocoa**, **Lexilla**, **WebKit**을 기반으로 구축되었으며, macOS Human Interface Guidelines (HIG) 표준을 준수하면서 Notepad++ 원본의 강력한 편집 기능과 94개국 다국어 환경을 완벽하게 제공합니다.

---

## 🌟 주요 핵심 기능

### 🌐 94개국 글로벌 다국어 지원 (Global UI Localization)
- **공식 94개국 로컬라이제이션 완벽 내장**:
  - Notepad++ 원본의 94개국 공식 언어 팩 XML(`PowerEditor/installer/nativeLang/*.xml`)을 네이티브 파서(`pugixml`)와 연동하여 실시간 제공합니다.
  - **환경설정 (`⌘,`) > 일반(General) > 표시 언어(Display Language)** 드롭다운에서 클릭 한 번으로 앱의 모든 언어를 즉시 전환할 수 있습니다.
  - 주요 인기 16개국 언어(`한국어`, `English`, `日本語`, `简体中文`, `繁體中文`, `Français`, `Deutsch`, `Español`, `Italiano`, `Русский`, `Português`, `Brazilian Portuguese`, `Nederlands`, `Polski`, `Türkçe`, `Tiếng Việt`)를 상단에 우선 배치하고 구분선 이후 나머지 78개국 언어를 가나다/알파벳 순으로 편리하게 선택할 수 있습니다.
- **앱 전체 UI 실시간 동적 반영**:
  - **macOS 상단 메뉴바**: 11개 대메뉴 및 모든 서브메뉴/명령어 실시간 번역
  - **찾기 & 바꾸기 바 (`NppFindBarView`)**: 라벨, 버튼, 옵션 체크박스 완벽 번역
  - **사이드/하단 3대 패널**: 탐색기, 터미널, 미리보기 패널 헤더 및 툴팁
  - **열 편집기 대화상자 (`NppColumnEditor`)**: 모든 그룹박스, 라벨, 진법 및 버튼
  - **환경설정 창 (`NppPreferences`)**: 좌측 11개 카테고리 탭 목록 및 내부 모든 세부 옵션
  - **상태 표시줄 (`StatusBar`)**: 줄/열, 선택 범위, 인코딩, 줄바꿈 포맷
- **macOS 최적화 정제 & 세션 지속성**:
  - 윈도우 전용 가속기 키(`(&F)`, `(&E)`, `&amp;`)를 자동으로 정제하여 깔끔한 macOS 네이티브 텍스트로 렌더링합니다.
  - 선택된 언어 설정은 `session.json`에 실시간 기록되어 다음 앱 실행 시에도 100% 자동 유지됩니다.

---

### 📖 도움말 시스템 및 가이드 (Help & Documentation System)
- **Notepad++ Help Guide 대화상자 (`⇧⌘/` 또는 F1)**:
  - 상단 메뉴의 **도움말(Help) > Notepad++ Help Guide (사용자 가이드 & 예시)** 또는 단축키 **`⇧⌘/`** (F1)를 통해 언제든지 인터랙티브 가이드를 호출할 수 있습니다.
  - **열 모드(Column Mode)** 단축키 조합 및 사각형 블록 편집 방법
  - **3대 분할 패널(탐색기/터미널/실시간 미리보기)** 활용 팁
  - **인코딩 감지(uchardet) 및 줄바꿈(CRLF/LF) 변환** 가이드
  - **매크로 기록/재생** 및 **해시/인코딩 도구** 상세 설명과 예시 수록
- **고속 시각적 풍선 도움말 (Enhanced Quick Tooltips)**:
  - 툴바 및 주요 인터랙티브 버튼에 **0.05초 초고속 반응** 및 **2배 확대(14pt) 가독성 극대화** 풍선 도움말을 적용하여 각 기능의 이름과 단축키를 직관적으로 확인할 수 있습니다.
- **체계적인 프로젝트 개발 및 기술 문서**:
  - [BUILD_MAC.md](BUILD_MAC.md): macOS 네이티브 아키텍처 구조, 빌드 파이프라인 및 테스트 스위트 상세 안내
  - [ScintillaCocoaIME.md](ScintillaCocoaIME.md): Scintilla Cocoa CJK/한글 IME 입력기 연동 결함 분석 및 완벽 해결 기술 백서 (전체 코드 diff 수록)
  - [CONTRIBUTING.md](CONTRIBUTING.md): 프로젝트 기여 가이드라인 및 코드 스타일 표준


---

### 🔲 열 모드 (Column Mode) & 열 편집기 (`⌥⌘C` / Option+Drag)
- **열 모드 (Column Mode)**:
  - **사각형 블록 선택**: `⌥` (Option) 키를 누른 채 마우스 드래그 또는 `⌥⇧` (Option+Shift) + 방향키로 다중 라인 열 영역 블록 선택
  - **다중 커서 동시 입력 & 열 다중 붙여넣기**: `⌘` + 클릭으로 여러 위치에 커서를 두고 동시 타이핑, 각 열 라인에 대응한 다중 붙여넣기 지원
- **열 편집기 대화상자 (Column Editor Dialog)**:
  - 단축키: **`⌥⌘C`** (또는 Edit 메뉴 > `Column Editor... (열 편집기)`) 및 툴바 버튼
  - **텍스트 삽입 (Text to Insert)**: 선택된 열의 모든 라인에 접두어 또는 문자열 일괄 삽입
  - **숫자 증가 삽입 (Number to Insert)**: 시작 숫자, 증가치, 반복 횟수, 진법(**10진수/16진수/8진수/2진수**), 패딩 문자(**None/0 채우기/공백 채우기**)

---

### 🍏 모던 IDE 3분할 가변 패널 (VS Code 스타일 레이아웃)
- **Primary Side Panel (좌측 - Finder 스타일 탐색기)**:
  - 툴바 상단 버튼(`sidebar.left`) 또는 `⌥⌘1`로 토글
  - 기본 위치는 **`~/` (사용자 홈 디렉토리)**이며, 저장된 파일 탭 활성화 시 해당 파일의 폴더로 자동 연동
  - 네이티브 macOS Finder 시스템 아이콘 및 지연 로딩(Lazy Loading) 적용으로 멈춤 없는 고속 탐색 지원
- **Bottom Panel (하단 - 내장 터미널 분할 콘솔)**:
  - 툴바 상단 버튼(`dock.rectangle`) 또는 `⌥⌘2`로 토글
  - 실시간 `/bin/zsh` 실행, 프롬프트 `$ `, 디렉토리 추적(`cd`), 명령어 히스토리 지원
  - 상단에 **`Open in Terminal.app`** 버튼을 제공하여 실제 외장 맥 터미널 창도 원클릭으로 실행 가능
- **Secondary Side Panel (우측 - 언어 가이드 & 실시간 WebKit 미리보기)**:
  - 툴바 상단 버튼(`sidebar.right`) 또는 `⌥⌘3`으로 토글
  - **기본 화면**: 상단 메뉴의 **`Language`**에서 언어를 선택하도록 안내하는 가이드 카드 및 빠른 선택 칩 제공
  - **실시간 렌더링**: Markdown, HTML, JSON, XML/SVG, C++, Python, SQL 등을 에디터 타이핑과 실시간 동기화하여 렌더링

---

### 🔄 세션 무손실 자동 복원 (Live Snapshot & Session Restore)
- **실시간 지속 저장 체계**:
  - 파일 열기, 탭 전환, 탭 닫기, 창 이동/크기 조절 시 실시간으로 `session.json`에 최신 작업 상태 즉시 기록
- **오픈 시 완전 복원**:
  - 앱 재실행 시 이전에 열려 있던 파일 경로들과 커서/스크롤 위치, 활성 탭 인덱스, 3대 패널(탐색기/터미널/미리보기) 상태 및 미저장 버퍼 내용까지 100% 안전하게 복원

---

### 🇰🇷 Scintilla Cocoa CJK/한글 IME 완전 지원 (CJK IME & Syllable Composition)
- **자모 조합 및 음절 연속 전진 무결성 보장**:
  - React Native PR #56082의 상태 잠금(State Guard / `mIsComposing`) 아키텍처를 적용하여, 한글(2벌식/3벌식) 및 CJK 입력 도중 외부 알림이나 UI 재렌더링이 조합 상태를 파괴하지 않도록 격리 보호합니다.
  - 음절 덮어쓰기 방지, 백스페이스 역순 해제, 엔터(Return) 줄바꿈 및 마우스 클릭 시 자동 커밋을 100% 네이티브 Cocoa 수준으로 완벽 지원합니다.
  - 상세한 기술 분석 및 원본 대비 코드 변경점은 [ScintillaCocoaIME.md](ScintillaCocoaIME.md)를 참고하십시오.

---

### 📑 11대 카테고리 풀 메뉴 시스템
1. **Notepad++**: 프로그램 정보, 환경설정 (`⌘,`), 서비스, 가리기 (`⌘H`), 기타 가리기 (`⌥⌘H`), 종료 (`⌘Q`)
2. **File (파일)**:
   - 새로 만들기 (`⌘N`), 열기 (`⌘O`), 디스크에서 다시 읽기 (`⌘R`), 저장 (`⌘S`), 다른 이름으로 저장 (`⇧⌘S`), 모두 저장 (`⌥⌘S`)
   - 파일 이름 변경, Finder에서 위치 열기 (`⇧⌘R`), 터미널에서 열기 (`⌥⌘T`), 전체 경로/파일명/디렉토리 경로 복사
   - 탭 닫기 (`⌘W`), 모두 닫기 (`⇧⌘W`), 현재 탭 외 모두 닫기
3. **Edit (편집)**:
   - 실행 취소 (`⌘Z`), 다시 실행 (`⇧⌘Z`), 잘라내기 (`⌘X`), 복사 (`⌘C`), 붙여넣기 (`⌘V`), 전체 선택 (`⌘A`)
   - **열 편집기... (`⌥⌘C`)**: 텍스트 및 자동 증가 번호 일괄 삽입
   - **줄 연산**: 줄 복제 (`⌘D`), 줄 나누기, 줄 합치기 (`⌃J`), 줄 위/아래로 이동 (`⌥↑`/`⌥↓`), 줄 오름차순/내림차순 정렬, 중복 줄 제거, 빈 줄 제거
   - **공백 연산**: 뒤쪽 공백 제거, 앞쪽 공백 제거, 양쪽 공백 제거, TAB을 공백으로, 공백을 TAB으로
   - **대소문자 변환**: 대문자로 변환 (`⇧⌘U`), 소문자로 변환 (`⌘U`)
   - **주석**: 한 줄 주석 토글 (`⌘/`)
4. **Search (검색)**:
   - 찾기 (`⌘F`), 다음 찾기 (`⌘G`), 이전 찾기 (`⇧⌘G`), 바꾸기 (`⌥⌘F`), 선택 영역으로 찾기 (`⌘E`)
   - 줄로 이동 (`⌘L`), 짝 맞춤 괄호로 이동 (`⌘B`)
   - **북마크**: 북마크 설정/해제 (`⌘F2`), 다음 북마크 (`F2`), 이전 북마크 (`⇧F2`), 모든 북마크 지우기
5. **View (보기)**:
   - 좌측 Finder 탐색기 패널 토글 (`⌥⌘1`), 하단 내장 터미널 토글 (`⌥⌘2`), 우측 실시간 렌더링 패널 토글 (`⌥⌘3`)
   - 확대 (`⌘+`), 축소 (`⌘-`), 기본 확대/축소 복원 (`⌘0`)
   - 자동 줄 바꿈 (`⌥⌘W`), 줄 번호 표시, 모든 문자 표시 (공백/줄바꿈 기호), 들여쓰기 가이드 표시
   - 다크 모드 토글 (`⇧⌘D`)
6. **Encoding (인코딩)**:
   - UTF-8 (기본), UTF-8 BOM, UTF-16 LE, UTF-16 BE, ANSI (CP1252), 한국어 (EUC-KR), 일본어 (Shift-JIS), 중국어 (Big5, GB2312)
   - 줄바꿈 변환: Unix (LF), Windows (CRLF), Macintosh (CR)
7. **Language (언어)**: C/C++, Python, JavaScript/TypeScript, HTML, XML, JSON, CSS, Markdown, SQL, Rust, Go, Java, Swift, Kotlin, PHP, YAML, Shell 등 24개 이상 지원
8. **Settings (설정)**:
   - **환경설정... (`⌘,`)**: 11개 세부 설정 카테고리 마스터-디테일 창
   - **스타일 환경설정...**: 7대 테마 및 폰트 크기 직접 선택
9. **Tools (도구 & 암호화)**:
   - MD5 / SHA-256 해시 생성 (클립보드 자동 복사)
10. **Window (창)**: 창 최소화, 확대, 창 관리
11. **Help (도움말)**: Notepad++ Help Guide (`⇧⌘/` 또는 F1), About Notepad++

---

## 🚀 빠른 시작 및 빌드 방법

### [Edition 1] 네이티브 C++/Scintilla 초경량 빌드
```bash
# 1. 실행 파일 빌드 (bin/notepad++)
make -f Makefile.mac all

# 2. 64개 자동 단위 테스트 실행 (537 assertions)
make -f Makefile.mac test

# 3. 독립형 macOS 애플리케이션 번들 생성 (bin/Notepad++.app)
make -f Makefile.mac bundle

# 4. 애플리케이션 실행
open bin/Notepad++.app
```

### [Edition 2] VS Code 아키텍처 빌드 (`vscode/`)
```bash
# 1. VS Code 에디션 전체 컴파일
make -f Makefile.mac vscode-all

# 2. Electron 독립 모드 실행
make -f Makefile.mac vscode-run
```

---

## 🧪 테스트 및 검증 결과

단위 테스트 러너(`bin/npp_tests`)는 문자열 변환, POSIX 파일 I/O, UTF-8/UTF-16/BOM 코덱, `uchardet` 인코딩 감지, `pugixml` 파싱, Lexilla 신택스 렉서, 문서 버퍼 연산 등 64개 테스트를 실행합니다:

```
================================================================================
  Test Execution Summary
================================================================================
  Total Tests:       64
  Passed:            64 (100% PASS)
  Failed:            0
  Total Assertions:  537
  Total Time:        46.79 ms
================================================================================
>>> ALL TESTS PASSED SUCCESSFULLY! <<<
```

---

## 📄 라이선스 (License)

Notepad++는 [GNU General Public License v3](LICENSE) 하에 배포됩니다.
macOS 네이티브 Cocoa 프론트엔드로 포팅되었습니다.
