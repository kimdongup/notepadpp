# 📘 Notepad++ for macOS 사용자 가이드 & 기능 명세서

[![Notepad++ macOS](https://img.shields.io/badge/Notepad%2B%2B-macOS%20Native-brightgreen.svg)](https://github.com/notepad-plus-plus/notepad-plus-plus)
[![Engine](https://img.shields.io/badge/Editor-Scintilla%20%2B%20Lexilla-blue.svg)](https://www.scintilla.org/)
[![UI](https://img.shields.io/badge/GUI-Apple%20Cocoa%20%2B%20WebKit-orange.svg)](https://developer.apple.com/)

**Notepad++ for macOS**는 고성능 Scintilla/Lexilla C++20 에디터 코어와 현대적인 Apple Cocoa 및 WebKit 프리뷰 엔진을 결합한 macOS 네이티브 텍스트/소스 코드 에디터입니다.

---

## 🚀 빠른 단축키 요약 (macOS Shortcut Cheatsheet)

| 기능 분류 | 주요 기능 | macOS 단축키 | 설명 |
| :--- | :--- | :--- | :--- |
| **파일 (File)** | 새 파일 / 파일 열기 | `⌘N` / `⌘O` | 새 탭 생성 또는 기존 문서 열기 |
| | 저장 / 모두 저장 | `⌘S` / `⌥⌘S` | 현재 문서 또는 열린 모든 문서 일괄 저장 |
| | 탭 닫기 / 탭 전환 | `⌘W` / `⌥⌘←` `⌥⌘→` | 현재 탭 닫기 또는 좌우 탭 전환 |
| | Finder에서 보기 | `⌘R` | 현재 파일이 위치한 폴더를 Finder에서 선택 |
| **편집 (Edit)** | 사각형 열 모드 선택 | `⌥` (Option) + 마우스 드래그 | 다중 행 사각형 영역 동시 편집 |
| | 열 편집기 (Column Editor) | `⌥⌘C` | 연속 번호 및 텍스트 일괄 삽입 |
| | 줄 합치기 (Join Lines) | `⌘J` | 현재 줄과 다음 줄 결합 |
| | 줄 분할 (Split Lines) | `⌥⌘J` | 지정된 너비로 줄 바꿈 분할 |
| | 줄 복제 / 주석 토글 | `⌘D` / `⌘/` | 현재 행 복제 및 `//` 주석 토글 |
| | 대소문자 변환 | `⇧⌘U` / `⌘U` | 대문자 변환 / 소문자 변환 |
| **검색 (Search)** | 찾기 / 바꾸기 바 | `⌘F` / `⌥⌘F` | 하단 인터랙티브 검색/치환 패널 토글 |
| | 다음 / 이전 찾기 | `⌘G` / `⇧⌘G` (또는 `Enter`/`⇧Enter`) | 검색어 다음/이전 항목 탐색 |
| | 북마크 토글 | `⌘F2` (또는 마진 클릭) | 현재 줄 북마크 지정 및 해제 |
| | 다음 / 이전 북마크 | `F2` / `⇧F2` | 북마크된 행으로 빠른 점프 |
| | 북마크 전체 해제 | `⇧⌘F2` | 현재 문서의 모든 북마크 초기화 |
| **패널 (Panels)** | 좌측 파일 탐색기 트리 | `⌘B` | 프로젝트 파일 탐색기 토글 |
| | 하단 임베디드 터미널 | `⌃\`` 또는 `⌘\` | zsh/bash 실시간 명령 터미널 토글 |
| | 우측 실시간 렌더링 | `⇧⌘P` | 마크다운/HTML/JSON 실시간 뷰어 토글 |
| **보기 (View)** | 다크 모드 토글 | `⇧⌘D` | 시스템 다크 모드 연동 및 수동 전환 |
| | 자동 줄바꿈 토글 | `⌥⌘W` | 긴 문장의 화면 내 자동 줄바꿈 |
| | 코드 전체 접기 / 펴기 | `⌥⌘[` / `⌥⌘]` | 함수 및 블록 전체 Fold/Unfold |
| | 현재 블록 접기 | `⌘[` | 현재 커서 위치의 코드 블록 Fold 토글 |

---

## 📌 상단 메뉴별 상세 안내 및 실전 예제

### 1. 📁 File (파일 메뉴)
- **New (`⌘N`)**: 새로운 빈 편집 탭(`new 1`, `new 2`...)을 생성합니다.
- **Open... (`⌘O`)**: 시스템 파일 열기 대화상자를 엽니다.
- **Save (`⌘S`) / Save As... (`⇧⌘S`) / Save All (`⌥⌘S`)**: 편집 내용을 파일로 디스크에 저장합니다.
- **Close (`⌘W`) / Close All**: 탭을 닫습니다. 수정 중인 문서는 저장 여부를 묻습니다.
- **Reveal in Finder (`⌘R`)**: 현재 작업 중인 파일(또는 탭의 기본 디렉터리)을 macOS Finder에서 즉시 열어 보여줍니다.
- **Copy Full Path / Copy Filename / Copy Directory Path**: 현재 파일의 절대 경로, 파일명, 폴더 경로를 클립보드에 복사합니다.

---

### 2. ✏️ Edit (편집 메뉴)
- **Line Operations (줄 작업)**:
  - **Duplicate Current Line (`⌘D`)**: 커서가 위치한 줄을 아래로 복제합니다.
  - **Toggle Line Comment (`⌘/`)**: 선택 영역 또는 현재 행에 주석(`//`)을 추가/제거합니다.
  - **Join Lines (`⌘J`)**: 현재 줄과 다음 줄(또는 선택한 여러 줄)을 한 줄로 합칩니다.
  - **Split Lines (`⌥⌘J`)**: 긴 행을 지정된 너비로 분할합니다.
  - **Remove Empty Lines**: 문서 내 불필요한 빈 줄을 일괄 삭제합니다.
  - **Trim Trailing Space**: 모든 행 끝의 불필요한 공백/탭을 정리합니다.
- **Column Editor (`⌥⌘C`)**:
  - 다중 행에 동일한 접두사 문자열을 삽입하거나 `1, 2, 3...` 형태의 연속 번호를 일괄 입력합니다.
- **Convert Case**:
  - **UPPERCASE (`⇧⌘U`)**: 선택한 텍스트를 대문자로 변환합니다.
  - **lowercase (`⌘U`)**: 선택한 텍스트를 소문자로 변환합니다.

> [!TIP]
> **열 모드(Column Mode) 실전 팁**: `⌥` (Option) 키를 누른 상태에서 마우스로 드래그하면 직사각형 영역이 선택되며, 타이핑 시 선택된 모든 행에 글자가 동시에 입력됩니다!

---

### 3. 🔍 Search (검색 메뉴)
- **Find (`⌘F`) / Replace (`⌥⌘F`)**:
  - 하단에 모던 검색/바꾸기 바가 열립니다.
  - `Match Case` (대소문자 구분), `Whole Word` (단어 단위), `Regex` (정규표현식) 지원.
  - 검색창에서 `Enter` 키를 누르면 다음 일치 항목으로, `Shift+Enter`를 누르면 이전 일치 항목으로 이동합니다.
  - `Esc` 키를 누르면 검색 바가 닫히고 에디터로 포커스가 복귀합니다.
- **Bookmark (북마크 기능)**:
  - **Toggle Bookmark (`⌘F2`)**: 에디터 좌측의 마진(Margin 1)을 클릭하거나 단축키를 눌러 파란색 화살표 북마크를 설정/해제합니다.
  - **Next / Previous Bookmark (`F2` / `⇧F2`)**: 긴 코드나 로그 파일에서 북마크된 위치로 빠르게 순환 이동합니다.
  - **Clear All Bookmarks (`⇧⌘F2`)**: 모든 북마크를 일괄 제거합니다.

---

### 4. 👁️ View (보기 메뉴)
- **3대 VS Code 스타일 도킹 패널 토글**:
  - **Primary Side Bar (좌측 탐색기 `⌘B`)**: 프로젝트 폴더 디렉터리 트리 브라우징, 파일 생성, 이름 변경, 삭제 지원.
  - **Bottom Panel (하단 터미널 `⌃\`` 또는 `⌘\`)**: 내장 zsh 터미널. 명령어 히스토리(`↑`/`↓`), 실시간 ANSI 색상 출력, 실행 상태 LED 제공.
  - **Secondary Side Bar (우측 실시간 렌더링 `⇧⌘P`)**: 마크다운, HTML, JSON, XML 문서의 네이티브 GFM 라이브 렌더링.
- **Code Folding (코드 접기)**:
  - **Toggle Fold Current Level (`⌘[`)**: 커서가 위치한 블록을 접거나 폅니다 (에디터 좌측 `[-]`/`[+]` 마진 클릭 가능).
  - **Fold All (`⌥⌘[`) / Unfold All (`⌥⌘]`)**: 문서 내 모든 함수/클래스 블록을 한 번에 접거나 폅니다.
- **다크 모드 (`⇧⌘D`)**:
  - Monokai, Dracula, Solarized Dark, Solarized Light, Obsidian 등 다양한 테마와 어두운/밝은 모드를 지원합니다.

---

### 5. 🌐 Encoding (인코딩 메뉴)
- **문서 인코딩 자동 감지 및 변환**:
  - UTF-8 (기본), UTF-8 with BOM, UTF-16 LE/BE, ANSI / Windows-1252
  - **한국어 (EUC-KR / CP949)**, **일본어 (Shift-JIS)**, **중국어 (Big5 / GB2312)** 완벽 지원
- **줄바꿈(EOL) 형식 변환**:
  - **Unix (LF)**, **Windows (CRLF)**, **Macintosh (CR)** 상호 변환

---

### 6. 💻 Language (언어 및 실시간 렌더링 연동)
- **지원 언어 (Lexilla Lexer 연동)**:
  - Plain Text, C/C++, Python, JavaScript/TypeScript, HTML, XML, JSON, CSS, Markdown, SQL, Rust, Go, Java, PHP, YAML, Shell/Bash, INI, Makefile 등
- **실시간 렌더링 연동**:
  - `Language` 메뉴에서 언어를 변경하거나 `.md`, `.html`, `.json`, `.svg` 파일을 열면 우측 실시간 렌더링 패널이 해당 언어 서식에 맞춰 즉시 갱신됩니다.

---

## 💾 세션 및 작업 상태 자동 복원 안내

- **자동 상태 저장**: 앱을 종료할 때 현재 열려 있는 모든 탭의 파일 경로, 활성 탭 번호, 커서 위치, 3대 패널의 열림/닫힘 상태 및 크기 정보가 자동으로 저장됩니다.
- **완벽한 복원**: 앱을 다시 실행하면 마지막으로 작업하던 파일들과 레이아웃 상태가 100% 그대로 복원됩니다.

---

> [!NOTE]
> 본 도움말은 Notepad++의 상단 메뉴 `Help` -> `Notepad++ Help Guide`를 선택하면 언제든지 우측 실시간 렌더링 창에서 다시 확인하실 수 있습니다.
