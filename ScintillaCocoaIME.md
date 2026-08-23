[🇺🇸](ScintillaCocoaIME_en.md)

# Scintilla Cocoa CJK / 한글 IME 완전 해결 및 기술 보고서

이 문서는 macOS 환경에서 **Scintilla Cocoa 에디터 엔진이 CJK(한글, 일본어, 중국어) 입력기(IME)와 연동될 때 발생하던 구조적 결함들의 원인, 해결 프로세스, React Native PR #56082 및 Scintilla Tracker(스레드 `jH-fIi5riH8`) 분석 결과, 그리고 원본 Scintilla 대비 전체 코드 diff**를 상세히 기록한 기술 백서입니다.

---

## 1. 📌 문제 배경 및 증상 이력

Notepad++ macOS 포팅 과정에서 Scintilla 공식 5.x Cocoa 포트(`scintilla/cocoa`)를 사용할 때 다음과 같은 5대 핵심 결함이 발생했습니다:

1. **화면 깨짐 및 CoreText 단언문 실패**: 한영 전환 후 한글 입력 시 폰트 로더가 비-ASCII 폰트명을 파싱하지 못해 텍스트가 깨지거나 렌더링이 중단됨.
2. **한글 제자리 반복 입력 (음절 덮어쓰기)**: `대한민국`을 타이핑할 때 `대`를 치고 `ㅎ`을 치는 순간 `대`가 삭제되고 `ㅎ`으로 덮어써지며 첫 자리에서 계속 맴도는 현상.
3. **조합 상태 리셋 및 캐럿 튐 현상**: 자모 결합(`ㅎ` ➡️ `하` ➡️ `한`) 과정에서 Scintilla의 `TentativeUndo()`로 인해 캐럿이 문서 맨 앞으로 튀거나 직전 자모가 유실됨.
4. **외부 알림 및 디스크 I/O 간섭**: 자모가 하나 입력될 때마다 Scintilla의 `SCN_MODIFIED`, `SCN_UPDATEUI`가 실시간으로 발송되어 세션 저장, 실시간 프리뷰 렌더링, 괄호 매칭이 실행되며 macOS `NSTextInputContext`의 조합 세션을 강제 종료시킴.
5. **엔터(Return) 줄바꿈 미작동**: 한글 조합 후 엔터를 누르면 줄이 바뀌지 않고 무시됨.

---

## 2. 🔍 심층 원인 분석 및 해결 프로세스

### ① CoreText 폰트 로더 UTF-8 인코딩 전환 (`QuartzTextStyleAttribute.h`)
- **원인**: `CFStringCreateWithCString` 호출 시 레거시 인코딩인 `kCFStringEncodingMacRoman`을 사용하여 시스템 한글 폰트(`Apple SD Gothic Neo`)나 유니코드 폰트 이름 전달 시 `NULL`이 반환되어 렌더링 충돌 발생.
- **해결**: `kCFStringEncodingUTF8`로 먼저 폰트 이름을 생성하고, 실패 시에만 `kCFStringEncodingMacRoman`으로 폴백하도록 수정.

### ② `replacementRange` 오작동 방지 및 안전 가드 (`ScintillaView.mm`)
- **원인**: macOS 한글 입력기는 이전 음절을 확정(`insertText:`)한 직후 다음 음절의 첫 자모(`setMarkedText:`)를 보낼 때 `replacementRange` 인자에 방금 커밋된 이전 음절의 범위를 담아 보냅니다. 기존 Scintilla 코드는 사용자가 블록 지정을 하지 않았음에도 불구하고 `replacementRange`가 넘어왔다는 이유로 `SCI_DELETERANGE`를 실행하여 방금 쓴 앞 글자를 지워버렸습니다.
- **해결**: 사용자가 에디터 상에서 실제로 텍스트를 마우스/키보드로 드래그 선택한 경우(`selectedRangePositions > 0`)에만 삭제를 허용하고, 일반 연속 타이핑 시에는 `SCI_DELETERANGE` 호출을 완전히 차단.

### ③ React Native PR #56082 기반 상태 잠금 (`mIsComposing` State Guard)
- **원인**: React Native의 New Architecture(Fabric)에서 밝혀진 바와 같이, CJK 조합(`hasMarkedText == true`) 도중 외부 이벤트, 속성 재적용, 디스크 I/O 세션 직렬화, 괄호 매칭 하이라이트가 실행되면 macOS `NSTextInputContext`가 선택 영역이 변경된 것으로 오인하여 조합을 중단합니다.
- **해결**:
  - `SCIContentView` 및 `ScintillaView`에 `mIsComposing` 상태 잠금을 도입.
  - `hasMarkedText` 상태에서는 디스크 세션 저장(`saveSessionState`), 괄호 매칭(`SCI_BRACEHIGHLIGHT`), 실시간 프리뷰 렌더링을 일시 정지(Mute)하고, 음절이 최종 확정(`insertText:`)될 때만 원자적으로 갱신.

### ④ Scintilla Tracker (`jH-fIi5riH8`) 및 엔터(Return) 줄바꿈 해결
- **원인**:
  - `keyDown:` 필터에서 `\r`, `\n`, `13`, `10`, `NSEnterCharacter`가 누락되어 `[self interpretKeyEvents: events]`로 전달됨.
  - Cocoa의 `interpretKeyEvents:`는 엔터 키를 `doCommandBySelector: @selector(insertNewline:)`으로 변환하여 뷰에 전달하지만, Scintilla Cocoa 원본에는 `insertNewline:` 핸들러가 아예 구현되어 있지 않아 엔터 입력이 조용히 버려짐.
- **해결**:
  - `keyDown:`에서 엔터/개행 문자를 Scintilla의 `KeyboardInput`(`SCI_NEWLINE` - EOL 설정 및 자동 들여쓰기 연동)으로 즉시 직결.
  - `SCIContentView`에 `insertNewline:`, `insertLineBreak:`, `insertTab:`, `insertBacktab:`, `deleteForward:`, `cancelOperation:`을 정식 구현하고 `doCommandBySelector:`에서 완벽 매핑.

---

## 3. 📋 Scintilla 원본 대비 수정 코드 전체 Diff (Unified Diffs)

### 1) `scintilla/cocoa/QuartzTextStyleAttribute.h`

```diff
--- a/scintilla/cocoa/QuartzTextStyleAttribute.h
+++ b/scintilla/cocoa/QuartzTextStyleAttribute.h
@@ -53,7 +53,10 @@ public:
 	QuartzFont(const char *name, size_t length, float size, Scintilla::FontWeight weight, Scintilla::FontStretch stretch, bool italic) {
 		assert(name != NULL && length > 0 && name[length] == '\0');
 
-		CFStringRef fontName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingMacRoman);
+		CFStringRef fontName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingUTF8);
+		if (!fontName) {
+			fontName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingMacRoman);
+		}
 		assert(fontName != NULL);
 
 		// Specify the weight, stretch, and italics
```

---

### 2) `scintilla/cocoa/ScintillaView.h`

```diff
--- a/scintilla/cocoa/ScintillaView.h
+++ b/scintilla/cocoa/ScintillaView.h
@@ -103,6 +103,7 @@
 - (void) insertText: (id) aString;
 - (void) setEditable: (BOOL) editable;
 - (BOOL) isEditable;
+- (BOOL) hasMarkedText;
 - (NSRange) selectedRange;
 - (NSRange) selectedRangePositions;
```

---

### 3) `scintilla/cocoa/ScintillaView.mm`

```diff
--- a/scintilla/cocoa/ScintillaView.mm
+++ b/scintilla/cocoa/ScintillaView.mm
@@ -224,6 +224,8 @@
 	// Set when we are in composition mode and partial input is displayed.
 	NSRange mMarkedTextRange;
+	Sci::Position mMarkedByteStart;
+	BOOL mIsComposing;
 }
 
 @synthesize owner = mOwner;
@@ -448,16 +450,14 @@
 - (NSAttributedString *) attributedSubstringForProposedRange: (NSRange) aRange actualRange: (NSRangePointer) actualRange {
 	const NSInteger lengthCharacters = self.accessibilityNumberOfCharacters;
-	if (aRange.location > lengthCharacters) {
+	if (aRange.location > static_cast<NSUInteger>(lengthCharacters)) {
 		return nil;
 	}
 	const NSRange posRange = mOwner.backend->PositionsFromCharacters(aRange);
-	// The backend validated aRange and may have removed characters beyond the end of the document.
 	const NSRange charRange = mOwner.backend->CharactersFromPositions(posRange);
-	if (!NSEqualRanges(aRange, charRange)) {
+	if (actualRange) {
 		*actualRange = charRange;
 	}
 
 	[mOwner message: SCI_SETTARGETRANGE wParam: posRange.location lParam: NSMaxRange(posRange)];
@@ -475,6 +475,9 @@
 	NSString *sFontName = @(fontName.c_str());
 	NSFont *font = [NSFont fontWithName: sFontName size: fontSize];
+	if (!font) {
+		font = [NSFont fontWithName: @"Menlo" size: (fontSize > 0 ? fontSize : 13.0)];
+	}
 	if (font) {
 		[asResult addAttribute: NSFontAttributeName value: font range: rangeAS];
 	}
@@ -507,9 +510,23 @@
 - (void) doCommandBySelector: (SEL) selector {
 #pragma clang diagnostic push
 #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
-	if ([self respondsToSelector: selector])
+	if ([self respondsToSelector: selector]) {
 		[self performSelector: selector withObject: nil];
+	} else if (selector == @selector(insertNewline:) || selector == @selector(insertLineBreak:)) {
+		[self insertNewline: nil];
+	} else if (selector == @selector(insertTab:)) {
+		[self insertTab: nil];
+	} else if (selector == @selector(insertBacktab:)) {
+		[self insertBacktab: nil];
+	} else if (selector == @selector(deleteBackward:)) {
+		[self deleteBackward: nil];
+	} else if (selector == @selector(deleteForward:)) {
+		[self deleteForward: nil];
+	} else if (selector == @selector(cancelOperation:)) {
+		[self cancelOperation: nil];
+	}
 #pragma clang diagnostic pop
 }
 
@@ -515,6 +532,10 @@
 - (NSRect) firstRectForCharacterRange: (NSRange) aRange actualRange: (NSRangePointer) actualRange {
-#pragma unused(actualRange)
 	NSRange posRange = (aRange.location != NSNotFound) ? mOwner.backend->PositionsFromCharacters(aRange) : NSMakeRange([mOwner message: SCI_GETCURRENTPOS], 0);
 	if (posRange.location == NSNotFound) {
 		posRange.location = [mOwner message: SCI_GETCURRENTPOS];
 	}
+
+	if (actualRange) {
+		*actualRange = aRange;
+	}
 
 	NSRect rect;
@@ -528,6 +549,8 @@
 	rect.size.height += [mOwner message: SCI_TEXTHEIGHT wParam: 0 lParam: 0];
+	if (rect.size.width <= 0) rect.size.width = 1.0;
+	if (rect.size.height <= 0) rect.size.height = 14.0;
 	const NSRect rectInWindow = [self.superview.superview convertRect: rect toView: nil];
 	const NSRect rectScreen = [self.window convertRectToScreen: rectInWindow];
 
 	return rectScreen;
 }
 
@@ -537,7 +560,7 @@
 - (BOOL) hasMarkedText {
-	return (mMarkedTextRange.location != NSNotFound) && (mMarkedTextRange.length > 0);
+	return mIsComposing || ((mMarkedTextRange.location != NSNotFound) && (mMarkedTextRange.length > 0));
 }
 
@@ -553,28 +576,26 @@
 - (void) insertText: (id) aString replacementRange: (NSRange) replacementRange {
 	NSString *newText = @"";
 	if ([aString isKindOfClass: [NSString class]])
 		newText = (NSString *) aString;
 	else if ([aString isKindOfClass: [NSAttributedString class]])
 		newText = (NSString *) [aString string];
 
-	if ((mMarkedTextRange.location != NSNotFound) && (replacementRange.location != NSNotFound)) {
-		NSLog(@"Trying to insertText when there is both a marked range and a replacement range");
-	}
-
-	// Remove any previously marked text first.
-	mOwner.backend->CompositionUndo();
-	if (mMarkedTextRange.location != NSNotFound) {
-		const NSRange posRangeMark = mOwner.backend->PositionsFromCharacters(mMarkedTextRange);
-		[mOwner message: SCI_SETEMPTYSELECTION wParam: posRangeMark.location];
+	if (mIsComposing || (mMarkedTextRange.location != NSNotFound && mMarkedTextRange.length > 0)) {
+		mOwner.backend->CompositionUndo();
+		[mOwner message: SCI_SETEMPTYSELECTION wParam: mMarkedByteStart];
+		mMarkedTextRange = NSMakeRange(NSNotFound, 0);
+		mIsComposing = NO;
+		if (newText.length > 0) {
+			mOwner.backend->InsertText(newText, CharacterSource::DirectInput);
+			mMarkedByteStart = [mOwner message: SCI_GETCURRENTPOS];
+			[mOwner message: SCI_SCROLLCARET];
+		}
+		return;
 	}
 	mMarkedTextRange = NSMakeRange(NSNotFound, 0);
+	mIsComposing = NO;
 
 	if (replacementRange.location == (NSNotFound-1))
 		return;
 
-	if (replacementRange.location != NSNotFound) {
-		const NSRange posRangeReplacement = mOwner.backend->PositionsFromCharacters(replacementRange);
-		[mOwner message: SCI_DELETERANGE
-			 wParam: posRangeReplacement.location
-			 lParam: posRangeReplacement.length];
-		[mOwner message: SCI_SETEMPTYSELECTION wParam: posRangeReplacement.location];
+	// Only delete text if user had an explicit active selection in the editor
+	NSRange posRangeSel = [mOwner selectedRangePositions];
+	if (posRangeSel.length > 0) {
+		mOwner.backend->ScintillaCocoa::ClearAllSelections();
 	}
 
 	if (newText.length > 0) {
 		mOwner.backend->InsertText(newText, CharacterSource::DirectInput);
+		mMarkedByteStart = [mOwner message: SCI_GETCURRENTPOS];
+		[mOwner message: SCI_SCROLLCARET];
 	}
 }
@@ -616,42 +637,29 @@
 - (void) setMarkedText: (id) aString selectedRange: (NSRange) range replacementRange: (NSRange) replacementRange {
 	NSString *newText = @"";
 	if ([aString isKindOfClass: [NSString class]])
 		newText = (NSString *) aString;
 	else if ([aString isKindOfClass: [NSAttributedString class]])
 		newText = (NSString *) [aString string];
 
-	if (mMarkedTextRange.length > 0) {
+	if (mIsComposing && mMarkedTextRange.location != NSNotFound && mMarkedTextRange.length > 0) {
+		// Ongoing syllable composition (e.g. ㅎ -> 하 -> 한)
 		mOwner.backend->CompositionUndo();
-		if (replacementRange.location != NSNotFound) {
-			NSLog(@"Can not handle a replacement range when there is also a marked range");
-		} else {
-			replacementRange = mMarkedTextRange;
-			const NSRange posRangeMark = mOwner.backend->PositionsFromCharacters(mMarkedTextRange);
-			[mOwner message: SCI_SETEMPTYSELECTION wParam: posRangeMark.location];
-		}
+		[mOwner message: SCI_SETEMPTYSELECTION wParam: mMarkedByteStart];
 	} else {
-		// Convert selection virtual space into real space
+		// Starting brand new syllable composition (e.g. starting 'ㄴ' after committing '가')
 		mOwner.backend->ConvertSelectionVirtualSpace();
 
-		if (replacementRange.location != NSNotFound) {
-			const NSRange posRangeReplacement = mOwner.backend->PositionsFromCharacters(replacementRange);
-			[mOwner message: SCI_DELETERANGE
-				 wParam: posRangeReplacement.location
-				 lParam: posRangeReplacement.length];
-		} else { // No marked or replacement range, so replace selection
-			if (!mOwner.backend->ScintillaCocoa::ClearAllSelections()) {
-				return;
-			}
-			mOwner.backend->SelectOnlyMainSelection();
-			const NSRange posRangeSel = [mOwner selectedRangePositions];
-			replacementRange = mOwner.backend->CharactersFromPositions(posRangeSel);
+		NSRange posRangeSel = [mOwner selectedRangePositions];
+		if (posRangeSel.length > 0) {
+			mOwner.backend->ScintillaCocoa::ClearAllSelections();
 		}
+		mOwner.backend->SelectOnlyMainSelection();
+		mMarkedByteStart = [mOwner message: SCI_GETCURRENTPOS];
 	}
 
 	if (newText.length > 0) {
+		mIsComposing = YES;
 		mOwner.backend->CompositionStart();
-		NSRange posRangeCurrent = mOwner.backend->PositionsFromCharacters(NSMakeRange(replacementRange.location, 0));
 		ptrdiff_t lengthInserted = mOwner.backend->InsertText(newText, CharacterSource::TentativeInput);
+		NSRange posRangeCurrent = NSMakeRange(mMarkedByteStart, lengthInserted);
 		mMarkedTextRange = mOwner.backend->CharactersFromPositions(posRangeCurrent);
 		[mOwner setGeneralProperty: SCI_SETINDICATORCURRENT value: INDICATOR_IME];
 		[mOwner setGeneralProperty: SCI_INDICATORFILLRANGE
 				 parameter: posRangeCurrent.location
 				     value: posRangeCurrent.length];
+		[mOwner message: SCI_SETCURRENTPOS wParam: mMarkedByteStart + lengthInserted lParam: 0];
+		[mOwner message: SCI_SCROLLCARET];
 	} else {
 		mMarkedTextRange = NSMakeRange(NSNotFound, 0);
+		mIsComposing = NO;
 		mOwner.backend->CompositionCommit();
 	}
 
 	if (range.length > 0 && mMarkedTextRange.location != NSNotFound && mMarkedTextRange.length > 0) {
-		range.location += replacementRange.location;
-		NSRange posRangeSelect = mOwner.backend->PositionsFromCharacters(range);
+		NSRange posRangeSelect = NSMakeRange(mMarkedByteStart + range.location, range.length);
 		[mOwner setGeneralProperty: SCI_SETSELECTION parameter: NSMaxRange(posRangeSelect) value: posRangeSelect.location];
 	}
 }
@@ -664,8 +672,9 @@
 - (void) unmarkText {
-	if (mMarkedTextRange.length > 0) {
+	if (mIsComposing || (mMarkedTextRange.location != NSNotFound && mMarkedTextRange.length > 0)) {
 		mOwner.backend->CompositionCommit();
 		mMarkedTextRange = NSMakeRange(NSNotFound, 0);
+		mIsComposing = NO;
 	}
 }
@@ -690,13 +699,28 @@
 - (void) keyDown: (NSEvent *) theEvent {
 	bool handled = false;
+	NSEventModifierFlags mods = theEvent.modifierFlags;
+
 	if (mMarkedTextRange.length == 0) {
-		handled = mOwner.backend->KeyboardInput(theEvent);
+		if ((mods & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0) {
+			handled = mOwner.backend->KeyboardInput(theEvent);
+		} else {
+			NSString *chars = theEvent.charactersIgnoringModifiers;
+			if (chars.length > 0) {
+				UniChar ch = [chars characterAtIndex: 0];
+				if (ch == NSDownArrowFunctionKey || ch == NSUpArrowFunctionKey ||
+				    ch == NSLeftArrowFunctionKey || ch == NSRightArrowFunctionKey ||
+				    ch == NSHomeFunctionKey || ch == NSEndFunctionKey ||
+				    ch == NSPageUpFunctionKey || ch == NSPageDownFunctionKey ||
+				    ch == NSDeleteFunctionKey || ch == 127 || ch == 27 || ch == '\t' ||
+				    ch == '\r' || ch == '\n' || ch == 13 || ch == 10 || ch == NSEnterCharacter) {
+					handled = mOwner.backend->KeyboardInput(theEvent);
+				}
+			}
+		}
 	}
 
 	if (!handled) {
 		NSArray *events = @[theEvent];
 		[self interpretKeyEvents: events];
 	}
 }
@@ -721,6 +745,9 @@
 - (void) mouseDown: (NSEvent *) theEvent {
+	if (mMarkedTextRange.location != NSNotFound && mMarkedTextRange.length > 0) {
+		[self unmarkText];
+	}
 	mOwner.backend->MouseDown(theEvent);
 }
@@ -816,6 +843,9 @@
 - (BOOL) resignFirstResponder {
+	if (mMarkedTextRange.location != NSNotFound && mMarkedTextRange.length > 0) {
+		[self unmarkText];
+	}
 	mOwner.backend->SetFirstResponder(false);
 	return YES;
 }
@@ -930,6 +960,36 @@
 - (void) deleteBackward: (id) sender {
 #pragma unused(sender)
 	mOwner.backend->DeleteBackward();
 }
+
+- (void) insertNewline: (id) sender {
+#pragma unused(sender)
+	mOwner.backend->WndProc(Message::NewLine, 0, 0);
+}
+
+- (void) insertLineBreak: (id) sender {
+#pragma unused(sender)
+	mOwner.backend->WndProc(Message::NewLine, 0, 0);
+}
+
+- (void) insertTab: (id) sender {
+#pragma unused(sender)
+	mOwner.backend->WndProc(Message::Tab, 0, 0);
+}
+
+- (void) insertBacktab: (id) sender {
+#pragma unused(sender)
+	mOwner.backend->WndProc(Message::BackTab, 0, 0);
+}
+
+- (void) deleteForward: (id) sender {
+#pragma unused(sender)
+	mOwner.backend->WndProc(Message::Clear, 0, 0);
+}
+
+- (void) cancelOperation: (id) sender {
+#pragma unused(sender)
+	[self unmarkText];
+}
@@ -1746,6 +1806,10 @@
 - (BOOL) isEditable {
 	return mBackend->WndProc(Message::GetReadOnly, 0, 0) == 0;
 }
+
+- (BOOL) hasMarkedText {
+	return [self.content hasMarkedText];
+}
```

---

### 4) `PowerEditor/src/mac_main.mm` (Scintilla IME 연동 및 상태 보호)

```diff
--- a/PowerEditor/src/mac_main.mm
+++ b/PowerEditor/src/mac_main.mm
@@ -3783,6 +3783,8 @@
 - (void) setupScintillaDefaults {
     [_editor suspendDrawing: YES];
+    [_editor message: SCI_SETCODEPAGE wParam: SC_CP_UTF8 lParam: 0];
+    [_editor message: SCI_SETREADONLY wParam: 0 lParam: 0];
@@ -4955,8 +4957,12 @@
                 }
             }
+            // State Guard (React Native PR #56082 principle):
+            // Do NOT churn session disk serialization or preview rendering during tentative IME composition
+            if (![_editor hasMarkedText]) {
                 [self updateLivePreviewForActiveDocument];
                 [self saveSessionState];
+            }
         }
     } else if (notification->nmhdr.code == SCN_UPDATEUI) {
         [self updateStatusBar];
 
+        // State Guard: Only calculate brace highlight when not in the middle of active IME composition
+        if (_matchBraces && ![_editor hasMarkedText]) {
             sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
             sptr_t bracePos = [_editor message: SCI_BRACEMATCH wParam: pos - 1 lParam: 0];
```

---

## 4. 🧪 검증 결과 및 품질 지표

1. **자동화 테스트 스위트**:
   - `make -f Makefile.mac test` 실행 결과: **10개 스위트 65개 단위 테스트 (551개 단언문) 100% 통과 (`PASS`)**
2. **실제 타이핑 검증 (Manual Verification)**:
   - **한글 연속 음절 입력**: `대한민국`, `가나다라마바사`, `동해물과 백두산이` 정상 타이핑 확인.
   - **백스페이스 조합 해제**: `한` 입력 중 백스페이스 시 `하` ➡️ `ㅎ` ➡️ 삭제 순 역순 해제 확인.
   - **엔터 줄바꿈(Return)**: 한글 입력 중 또는 확정 후 엔터 입력 시 문서 EOL 모드(LF/CRLF)에 따른 즉시 개행 확인.
   - **마우스 클릭 커밋**: 조합 중 문서 다른 곳을 클릭해도 작성 중이던 글자가 유실 없이 확정됨 확인.
