# Notepad++ for macOS

[![macOS Build](https://img.shields.io/badge/platform-macOS%2010.15+-brightgreen.svg)](BUILD_MAC.md)
[![C++20](https://img.shields.io/badge/C%2B%2B-20-blue.svg)](https://en.wikipedia.org/wiki/C%2B%2B20)
[![Unit Tests](https://img.shields.io/badge/tests-49%20passed%20(100%25)-success.svg)](BUILD_MAC.md)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**Notepad++ for macOS**는 대중적인 텍스트 및 소스 코드 에디터인 [Notepad++](https://github.com/notepad-plus-plus/notepad-plus-plus)를 macOS 환경에 맞추어 완벽하게 포팅한 네이티브 애플리케이션입니다. **Apple Clang C++20**, **Cocoa (AppKit/Foundation)**, **Scintilla Cocoa**, **Lexilla**, **WebKit**을 기반으로 구축되었으며, macOS Human Interface Guidelines (HIG) 표준을 준수하면서 Notepad++ 원본의 모든 핵심 기능을 제공합니다.

---

## 🌟 주요 핵심 기능

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
  - 툴바 상단 버튼(`sidebar.left`) 또는 `⌘B`로 토글
  - 기본 위치는 **`~/` (사용자 홈 디렉토리)**이며, 저장된 파일 탭 활성화 시 해당 파일의 폴더로 자동 연동
  - 네이티브 macOS Finder 시스템 아이콘 및 지연 로딩(Lazy Loading) 적용으로 멈춤 없는 고속 탐색 지원
- **Bottom Panel (하단 - 내장 터미널 분할 콘솔)**:
  - 툴바 상단 버튼(`dock.rectangle`) 또는 `⌃\`` (Control+Backtick)로 토글
  - 실시간 `/bin/zsh` 실행, 프롬프트 `$ `, 디렉토리 추적(`cd`), 명령어 히스토리 지원
  - 상단에 **`Open in Terminal.app`** 버튼을 제공하여 실제 외장 맥 터미널 창도 원클릭으로 실행 가능
- **Secondary Side Panel (우측 - 언어 가이드 & 실시간 WebKit 미리보기)**:
  - 툴바 상단 버튼(`sidebar.right`) 또는 `⇧⌘P`로 토글
  - **기본 화면**: 상단 메뉴의 **`Language`**에서 언어를 선택하도록 안내하는 가이드 카드 및 빠른 선택 칩 제공
  - **실시간 렌더링**: Markdown, HTML, JSON, XML/SVG, C++, Python, SQL 등을 에디터 타이핑과 실시간 동기화하여 렌더링

---

### 📑 11대 카테고리 풀 메뉴 시스템
1. **Notepad++**: 프로그램 정보, 환경설정 (`⌘,`), 서비스, 가리기 (`⌘H`), 기타 가리기 (`⌥⌘H`), 종료 (`⌘Q`)
2. **File (파일)**:
   - 새로 만들기 (`⌘N`), 열기 (`⌘O`), 디스크에서 다시 읽기 (`⌘R`), 저장 (`⌘S`), 다른 이름으로 저장 (`⇧⌘S`), 모두 저장 (`⌥⌘S`)
   - 파일 이름 변경, Finder에서 위치 열기 (`⇧⌘R`), 터미널에서 열기 (`⌥⌘T`), 전체 경로/파일명/디렉토리 경로 복사
   - 탭 닫기 (`⌘W`), 모두 닫기 (`⇧⌘W`), 현재 탭 외 모두 닫기, 좌측/우측 탭 모두 닫기
3. **Edit (편집)**:
   - 실행 취소 (`⌘Z`), 다시 실행 (`⇧⌘Z`), 잘라내기 (`⌘X`), 복사 (`⌘C`), 붙여넣기 (`⌘V`), 전체 선택 (`⌘A`)
   - **열 편집기... (`⌥⌘C`)**: 텍스트 및 자동 증가 번호 일괄 삽입
   - **줄 연산**: 줄 복제 (`⌘D`), 줄 나누기, 줄 합치기 (`⌃J`), 줄 위/아래로 이동 (`⌥↑`/`⌥↓`), 줄 오름차순/내림차순 정렬, 중복 줄 제거, 빈 줄 제거
   - **공백 연산**: 뒤쪽 공백 제거, 앞쪽 공백 제거
   - **대소문자 변환**: 대문자로 변환 (`⇧⌘U`), 소문자로 변환 (`⌘U`)
   - **날짜/시간 삽입**: 간단한 형식 (`yyyy-MM-dd HH:mm`), 자세한 형식
   - **주석**: 한 줄 주석 토글 (`⌘/`)
4. **Search (검색)**:
   - 찾기 (`⌘F`), 다음 찾기 (`⌘G`), 이전 찾기 (`⇧⌘G`), 바꾸기 (`⌥⌘F`), 선택 영역으로 찾기 (`⌘E`), **모두 표시(Mark All)**
   - 줄로 이동 (`⌘L`), 짝 맞춤 괄호로 이동 (`⌘B`)
   - **북마크**: 북마크 설정/해제 (`⌘F2`), 다음 북마크 (`F2`), 이전 북마크 (`⇧F2`), 모든 북마크 지우기
5. **View (보기)**:
   - 좌측 Finder 탐색기 패널 토글 (`⌘B`), 하단 내장 터미널 토글 (`⌃\``), 우측 실시간 렌더링 패널 토글 (`⇧⌘P`)
   - 확대 (`⌘+`), 축소 (`⌘-`), 기본 확대/축소 복원 (`⌘0`)
   - 자동 줄 바꿈 (`⌥⌘W`), 줄 번호 표시, 모든 문자 표시 (공백/줄바꿈 기호), 들여쓰기 가이드 표시
   - 모두 접기 (`⌥⌘0`), 모두 펼치기 (`⌥⇧⌘0`), 문서 통계 요약, 다크 모드 토글 (`⇧⌘D`)
6. **Encoding (인코딩)**:
   - UTF-8 (기본), UTF-8 BOM, UTF-16 LE, UTF-16 BE, ANSI (CP1252), 한국어 (EUC-KR), 일본어 (Shift-JIS), 중국어 (Big5, GB2312)
   - 줄바꿈 변환: Unix (LF), Windows (CRLF), Macintosh (CR)
7. **Language (언어)**: C/C++, Python, JavaScript/TypeScript, HTML, XML, JSON, CSS, Markdown, SQL, Rust, Go, Java, PHP, YAML, Shell 등 24개 이상 지원
8. **Settings (설정)**:
   - **환경설정... (`⌘,`)**: 11개 세부 설정 카테고리 마스터-디테일 창
   - **스타일 환경설정...**: 7대 테마 및 폰트 크기 직접 선택
9. **Tools (도구 & 암호화)**:
   - MD5 / SHA-256 해시 생성 (클립보드 자동 복사)
   - Base64 인코드 / 디코드, URL 인코드 / 디코드
10. **Macro (매크로)**: 기록 시작/종료 (`⌃⌘R`, 상태 표시줄 `REC ●`), 재생 (`⌃⌘P`)
11. **Window & Help (창 및 도움말)**: 창 관리 및 macOS 표준 프로그램 정보 창

---

## 🚀 빠른 시작 및 빌드 방법

### [Edition 1] 네이티브 C++/Scintilla 초경량 빌드
```bash
# 1. 실행 파일 빌드 (bin/notepad++)
make -f Makefile.mac all

# 2. 49개 자동 단위 테스트 실행 (394 assertions)
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

단위 테스트 러너(`bin/npp_tests`)는 문자열 변환, POSIX 파일 I/O, UTF-8/UTF-16/BOM 코덱, `uchardet` 인코딩 감지, `pugixml` 파싱, Lexilla 신택스 렉서, 문서 버퍼 연산 등 49개 테스트를 실행합니다:

```
================================================================================
  Test Execution Summary
================================================================================
  Total Tests:       49
  Passed:            49 (100% PASS)
  Failed:            0
  Total Assertions:  394
  Total Time:        17.27 ms
================================================================================
>>> ALL TESTS PASSED SUCCESSFULLY! <<<
```

---

## 📄 라이선스 (License)

Notepad++는 [GNU General Public License v3](LICENSE) 하에 배포됩니다.
macOS 네이티브 Cocoa 프론트엔드로 포팅되었습니다.
