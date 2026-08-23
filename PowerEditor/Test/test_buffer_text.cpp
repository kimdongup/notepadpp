// PowerEditor/Test/test_buffer_text.cpp
// Comprehensive test suite for Buffer, Text Operations, Line Endings, and Undo/Redo simulation

#include "test_framework.h"
#include "NppConstants.h"
#include <string>
#include <vector>
#include <sstream>
#include <algorithm>
#include <cctype>

// ============================================================================
// Helper Functions for Text & Buffer Operations
// ============================================================================

namespace TextOps {

// Line Ending Conversion
enum class LineEnding { CRLF, LF, CR, Mixed, None };

inline LineEnding detectDominantEOL(const std::string& text) {
    size_t crlf = 0, lf = 0, cr = 0;
    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '\r') {
            if (i + 1 < text.size() && text[i + 1] == '\n') {
                crlf++;
                i++;
            } else {
                cr++;
            }
        } else if (text[i] == '\n') {
            lf++;
        }
    }
    if (crlf == 0 && lf == 0 && cr == 0) return LineEnding::None;
    if (crlf >= lf && crlf >= cr) return LineEnding::CRLF;
    if (lf >= crlf && lf >= cr) return LineEnding::LF;
    return LineEnding::CR;
}

inline std::string convertEOL(const std::string& text, LineEnding target) {
    std::string out;
    out.reserve(text.size());
    std::string eolStr = (target == LineEnding::CRLF) ? "\r\n" : (target == LineEnding::CR ? "\r" : "\n");

    for (size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '\r') {
            if (i + 1 < text.size() && text[i + 1] == '\n') {
                i++;
            }
            out += eolStr;
        } else if (text[i] == '\n') {
            out += eolStr;
        } else {
            out += text[i];
        }
    }
    return out;
}

// Text Case Transformations
inline std::string toUpperCase(const std::string& s) {
    std::string out = s;
    for (char& c : out) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return out;
}

inline std::string toLowerCase(const std::string& s) {
    std::string out = s;
    for (char& c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return out;
}

inline std::string toProperCase(const std::string& s) {
    std::string out = s;
    bool inWord = false;
    for (char& c : out) {
        if (std::isalpha(static_cast<unsigned char>(c))) {
            if (!inWord) {
                c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
                inWord = true;
            } else {
                c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
            }
        } else {
            inWord = false;
        }
    }
    return out;
}

inline std::string invertCase(const std::string& s) {
    std::string out = s;
    for (char& c : out) {
        if (std::isupper(static_cast<unsigned char>(c))) {
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        } else if (std::islower(static_cast<unsigned char>(c))) {
            c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        }
    }
    return out;
}

// Tab / Space Conversions
inline std::string tabsToSpaces(const std::string& text, int tabWidth = 4) {
    std::string out;
    int col = 0;
    for (char c : text) {
        if (c == '\t') {
            int spaces = tabWidth - (col % tabWidth);
            out.append(spaces, ' ');
            col += spaces;
        } else if (c == '\n' || c == '\r') {
            out += c;
            col = 0;
        } else {
            out += c;
            col++;
        }
    }
    return out;
}

inline std::string spacesToTabs(const std::string& text, int tabWidth = 4) {
    std::string out;
    size_t i = 0;
    while (i < text.size()) {
        if (text[i] == ' ') {
            size_t spaceCount = 0;
            while (i + spaceCount < text.size() && text[i + spaceCount] == ' ') {
                spaceCount++;
            }
            size_t tabs = spaceCount / tabWidth;
            size_t remSpaces = spaceCount % tabWidth;
            out.append(tabs, '\t');
            out.append(remSpaces, ' ');
            i += spaceCount;
        } else {
            out += text[i++];
        }
    }
    return out;
}

// UTF-8 Validation and Navigation
inline size_t utf8CodepointCount(const std::string& s) {
    size_t count = 0;
    const uint8_t* p = reinterpret_cast<const uint8_t*>(s.data());
    const uint8_t* end = p + s.size();
    while (p < end) {
        if (*p < 0x80) { p += 1; }
        else if ((*p & 0xE0) == 0xC0) { p += 2; }
        else if ((*p & 0xF0) == 0xE0) { p += 3; }
        else if ((*p & 0xF8) == 0xF0) { p += 4; }
        else { p += 1; }
        count++;
    }
    return count;
}

inline bool isValidUTF8(const std::string& s) {
    const uint8_t* p = reinterpret_cast<const uint8_t*>(s.data());
    const uint8_t* end = p + s.size();
    while (p < end) {
        if (*p < 0x80) {
            p++;
        } else if ((*p & 0xE0) == 0xC0) {
            if (p + 1 >= end || (p[1] & 0xC0) != 0x80 || *p < 0xC2) return false;
            p += 2;
        } else if ((*p & 0xF0) == 0xE0) {
            if (p + 2 >= end || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80) return false;
            p += 3;
        } else if ((*p & 0xF8) == 0xF0) {
            if (p + 3 >= end || (p[1] & 0xC0) != 0x80 || (p[2] & 0xC0) != 0x80 || (p[3] & 0xC0) != 0x80) return false;
            p += 4;
        } else {
            return false;
        }
    }
    return true;
}

// Undo / Redo Simulator
struct UndoAction {
    enum Type { Insert, Delete } type;
    size_t position;
    std::string text;
};

class SimpleTextBuffer {
public:
    std::string text;
    std::vector<UndoAction> undoStack;
    std::vector<UndoAction> redoStack;

    void insert(size_t pos, const std::string& s) {
        if (pos > text.size()) pos = text.size();
        text.insert(pos, s);
        undoStack.push_back({UndoAction::Insert, pos, s});
        redoStack.clear();
    }

    void remove(size_t pos, size_t len) {
        if (pos >= text.size()) return;
        len = std::min(len, text.size() - pos);
        std::string deleted = text.substr(pos, len);
        text.erase(pos, len);
        undoStack.push_back({UndoAction::Delete, pos, deleted});
        redoStack.clear();
    }

    bool undo() {
        if (undoStack.empty()) return false;
        UndoAction action = undoStack.back();
        undoStack.pop_back();

        if (action.type == UndoAction::Insert) {
            text.erase(action.position, action.text.size());
            redoStack.push_back(action);
        } else if (action.type == UndoAction::Delete) {
            text.insert(action.position, action.text);
            redoStack.push_back(action);
        }
        return true;
    }

    bool redo() {
        if (redoStack.empty()) return false;
        UndoAction action = redoStack.back();
        redoStack.pop_back();

        if (action.type == UndoAction::Insert) {
            text.insert(action.position, action.text);
            undoStack.push_back(action);
        } else if (action.type == UndoAction::Delete) {
            text.erase(action.position, action.text.size());
            undoStack.push_back(action);
        }
        return true;
    }
};

} // namespace TextOps

// ============================================================================
// 1. Line Ending Operations Tests
// ============================================================================

TEST_CASE(BufferTextSuite, LineEndingConversions) {
    std::string crlfText = "Line1\r\nLine2\r\nLine3\r\n";
    std::string lfText = "Line1\nLine2\nLine3\n";
    std::string crText = "Line1\rLine2\rLine3\r";
    std::string mixedText = "Line1\r\nLine2\nLine3\r";

    // Detect dominant EOL
    TEST_ASSERT_EQ(static_cast<int>(TextOps::detectDominantEOL(crlfText)), static_cast<int>(TextOps::LineEnding::CRLF));
    TEST_ASSERT_EQ(static_cast<int>(TextOps::detectDominantEOL(lfText)), static_cast<int>(TextOps::LineEnding::LF));
    TEST_ASSERT_EQ(static_cast<int>(TextOps::detectDominantEOL(crText)), static_cast<int>(TextOps::LineEnding::CR));

    // Convert CRLF -> LF
    std::string toLf = TextOps::convertEOL(crlfText, TextOps::LineEnding::LF);
    TEST_ASSERT_STR_EQ(toLf.c_str(), lfText.c_str());

    // Convert LF -> CRLF
    std::string toCrlf = TextOps::convertEOL(lfText, TextOps::LineEnding::CRLF);
    TEST_ASSERT_STR_EQ(toCrlf.c_str(), crlfText.c_str());

    // Convert Mixed -> LF
    std::string mixedToLf = TextOps::convertEOL(mixedText, TextOps::LineEnding::LF);
    TEST_ASSERT_STR_EQ(mixedToLf.c_str(), lfText.c_str());
}

// ============================================================================
// 2. Text Case Transformations
// ============================================================================

TEST_CASE(BufferTextSuite, TextCaseConversions) {
    std::string original = "Notepad++ macOs Native Build";

    // UPPERCASE
    std::string upper = TextOps::toUpperCase(original);
    TEST_ASSERT_STR_EQ(upper.c_str(), "NOTEPAD++ MACOS NATIVE BUILD");

    // LOWERCASE
    std::string lower = TextOps::toLowerCase(original);
    TEST_ASSERT_STR_EQ(lower.c_str(), "notepad++ macos native build");

    // PROPERCASE / Title Case
    std::string proper = TextOps::toProperCase("the quick BROWN fox JUMPS");
    TEST_ASSERT_STR_EQ(proper.c_str(), "The Quick Brown Fox Jumps");

    // INVERTCASE / Toggle Case
    std::string inverted = TextOps::invertCase("Notepad++ 2026");
    TEST_ASSERT_STR_EQ(inverted.c_str(), "nOTEPAD++ 2026");
}

// ============================================================================
// 3. Tab and Space Operations
// ============================================================================

TEST_CASE(BufferTextSuite, TabSpaceConversions) {
    // Tabs to spaces with tab width 4
    std::string tabbed = "\tline1\n\t\tline2\n";
    std::string spaced = TextOps::tabsToSpaces(tabbed, 4);
    TEST_ASSERT_STR_EQ(spaced.c_str(), "    line1\n        line2\n");

    // Spaces to tabs
    std::string backToTabs = TextOps::spacesToTabs(spaced, 4);
    TEST_ASSERT_STR_EQ(backToTabs.c_str(), tabbed.c_str());

    // Custom tab width 2
    std::string spaced2 = TextOps::tabsToSpaces("\tCode", 2);
    TEST_ASSERT_STR_EQ(spaced2.c_str(), "  Code");
}

// ============================================================================
// 4. UTF-8 Validation and Navigation
// ============================================================================

TEST_CASE(BufferTextSuite, Utf8ValidationAndCounts) {
    // Valid UTF-8: ASCII + 2-byte + 3-byte + 4-byte emoji
    std::string validText = "ASCII | π (Greek) | 日本語 | 🚀 (Rocket)";
    TEST_ASSERT_TRUE(TextOps::isValidUTF8(validText));

    // Codepoint count: "Hello 🚀" -> 5 + 1 + 1 = 7 codepoints (byte length is 10)
    std::string emojiText = "Hello 🚀";
    TEST_ASSERT_EQ(emojiText.size(), 10u);
    TEST_ASSERT_EQ(TextOps::utf8CodepointCount(emojiText), 7u);

    // Invalid UTF-8: standalone continuation byte
    std::string invalid1 = "Bad \x80 Byte";
    TEST_ASSERT_FALSE(TextOps::isValidUTF8(invalid1));

    // Invalid UTF-8: incomplete multi-byte sequence at end
    std::string invalid2 = "Incomplete \xE2\x82";
    TEST_ASSERT_FALSE(TextOps::isValidUTF8(invalid2));
}

// ============================================================================
// 5. Undo / Redo Sequence Simulation
// ============================================================================

TEST_CASE(BufferTextSuite, UndoRedoBufferSimulation) {
    TextOps::SimpleTextBuffer buffer;
    buffer.text = "Initial Text";

    // Action 1: Append " - Added Content"
    buffer.insert(12, " - Added Content");
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "Initial Text - Added Content");

    // Action 2: Remove "Initial "
    buffer.remove(0, 8);
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "Text - Added Content");

    // Action 3: Insert "[Prefix] " at start
    buffer.insert(0, "[Prefix] ");
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "[Prefix] Text - Added Content");

    // Undo 3: Revert "[Prefix] "
    BOOL undoOk3 = buffer.undo();
    TEST_ASSERT_TRUE(undoOk3);
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "Text - Added Content");

    // Undo 2: Restore "Initial "
    BOOL undoOk2 = buffer.undo();
    TEST_ASSERT_TRUE(undoOk2);
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "Initial Text - Added Content");

    // Undo 1: Revert added content
    BOOL undoOk1 = buffer.undo();
    TEST_ASSERT_TRUE(undoOk1);
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "Initial Text");

    // No more undo
    TEST_ASSERT_FALSE(buffer.undo());

    // Redo 1: Re-apply added content
    BOOL redoOk1 = buffer.redo();
    TEST_ASSERT_TRUE(redoOk1);
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "Initial Text - Added Content");

    // Redo 2: Re-apply remove "Initial "
    BOOL redoOk2 = buffer.redo();
    TEST_ASSERT_TRUE(redoOk2);
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "Text - Added Content");

    // Redo 3: Re-apply "[Prefix] "
    BOOL redoOk3 = buffer.redo();
    TEST_ASSERT_TRUE(redoOk3);
    TEST_ASSERT_STR_EQ(buffer.text.c_str(), "[Prefix] Text - Added Content");

    // No more redo
    TEST_ASSERT_FALSE(buffer.redo());
}
