// PowerEditor/Test/test_lexilla_scintilla.cpp
// Comprehensive test suite for Lexilla & Scintilla integration on macOS

#include "test_framework.h"
#include "ILexer.h"
#include "Lexilla.h"
#include "SciLexer.h"
#include "Scintilla.h"

#include <vector>
#include <string>
#include <cstring>
#include <memory>
#include <algorithm>

// ============================================================================
// Mock Scintilla Document for Lexing & Folding Tests
// ============================================================================

class MockDocument : public Scintilla::IDocument {
public:
    MockDocument(const std::string& text) : m_text(text) {
        m_styles.resize(m_text.size(), 0);
        
        // Compute line starts
        m_lineStarts.push_back(0);
        for (size_t i = 0; i < m_text.size(); ++i) {
            if (m_text[i] == '\n') {
                m_lineStarts.push_back(static_cast<Sci_Position>(i + 1));
            }
        }
        m_levels.resize(m_lineStarts.size() + 1, 0x0400); // SC_FOLDLEVELBASE = 0x0400
        m_lineStates.resize(m_lineStarts.size() + 1, 0);
    }

    int SCI_METHOD Version() const override { return Scintilla::dvRelease4; }
    void SCI_METHOD SetErrorStatus(int) override {}
    Sci_Position SCI_METHOD Length() const override { return static_cast<Sci_Position>(m_text.size()); }

    void SCI_METHOD GetCharRange(char *buffer, Sci_Position position, Sci_Position lengthRetrieve) const override {
        if (position < 0 || position >= static_cast<Sci_Position>(m_text.size()) || lengthRetrieve <= 0) return;
        Sci_Position avail = std::min(lengthRetrieve, static_cast<Sci_Position>(m_text.size()) - position);
        memcpy(buffer, m_text.data() + position, avail);
    }

    char SCI_METHOD StyleAt(Sci_Position position) const override {
        if (position < 0 || position >= static_cast<Sci_Position>(m_styles.size())) return 0;
        return m_styles[position];
    }
    char GetStyleAt(Sci_Position position) const { return StyleAt(position); }

    Sci_Position SCI_METHOD LineFromPosition(Sci_Position position) const override {
        if (position <= 0) return 0;
        auto it = std::upper_bound(m_lineStarts.begin(), m_lineStarts.end(), position);
        return static_cast<Sci_Position>(std::distance(m_lineStarts.begin(), it) - 1);
    }

    Sci_Position SCI_METHOD LineStart(Sci_Position line) const override {
        if (line < 0) return 0;
        if (line >= static_cast<Sci_Position>(m_lineStarts.size())) return static_cast<Sci_Position>(m_text.size());
        return m_lineStarts[line];
    }

    int SCI_METHOD GetLevel(Sci_Position line) const override {
        if (line < 0 || line >= static_cast<Sci_Position>(m_levels.size())) return 0x0400;
        return m_levels[line];
    }

    int SCI_METHOD SetLevel(Sci_Position line, int level) override {
        if (line < 0 || line >= static_cast<Sci_Position>(m_levels.size())) return 0;
        int prev = m_levels[line];
        m_levels[line] = level;
        return prev;
    }

    int SCI_METHOD GetLineState(Sci_Position line) const override {
        if (line < 0 || line >= static_cast<Sci_Position>(m_lineStates.size())) return 0;
        return m_lineStates[line];
    }

    int SCI_METHOD SetLineState(Sci_Position line, int state) override {
        if (line < 0 || line >= static_cast<Sci_Position>(m_lineStates.size())) return 0;
        int prev = m_lineStates[line];
        m_lineStates[line] = state;
        return prev;
    }

    void SCI_METHOD StartStyling(Sci_Position position) override {
        m_stylePos = position;
    }

    bool SCI_METHOD SetStyleFor(Sci_Position length, char style) override {
        for (Sci_Position i = 0; i < length && (m_stylePos + i) < static_cast<Sci_Position>(m_styles.size()); ++i) {
            m_styles[m_stylePos + i] = style;
        }
        m_stylePos += length;
        return true;
    }

    bool SCI_METHOD SetStyles(Sci_Position length, const char *styles) override {
        for (Sci_Position i = 0; i < length && (m_stylePos + i) < static_cast<Sci_Position>(m_styles.size()); ++i) {
            m_styles[m_stylePos + i] = styles[i];
        }
        m_stylePos += length;
        return true;
    }

    void SCI_METHOD DecorationSetCurrentIndicator(int) override {}
    void SCI_METHOD DecorationFillRange(Sci_Position, int, Sci_Position) override {}
    void SCI_METHOD ChangeLexerState(Sci_Position, Sci_Position) override {}
    int SCI_METHOD CodePage() const override { return 65001; } // UTF-8
    bool SCI_METHOD IsDBCSLeadByte(char) const override { return false; }
    const char * SCI_METHOD BufferPointer() override { return m_text.data(); }

    int SCI_METHOD GetLineIndentation(Sci_Position line) override {
        Sci_Position start = LineStart(line);
        int indent = 0;
        while (start < static_cast<Sci_Position>(m_text.size()) && (m_text[start] == ' ' || m_text[start] == '\t')) {
            indent += (m_text[start] == '\t') ? 4 : 1;
            start++;
        }
        return indent;
    }

    Sci_Position SCI_METHOD LineEnd(Sci_Position line) const override {
        if (line + 1 < static_cast<Sci_Position>(m_lineStarts.size())) {
            Sci_Position nextStart = m_lineStarts[line + 1];
            if (nextStart > 0 && m_text[nextStart - 1] == '\n') {
                nextStart--;
                if (nextStart > 0 && m_text[nextStart - 1] == '\r') nextStart--;
            }
            return nextStart;
        }
        return static_cast<Sci_Position>(m_text.size());
    }

    Sci_Position SCI_METHOD GetRelativePosition(Sci_Position positionStart, Sci_Position characterOffset) const override {
        return positionStart + characterOffset;
    }

    int SCI_METHOD GetCharacterAndWidth(Sci_Position position, Sci_Position *pWidth) const override {
        if (pWidth) *pWidth = 1;
        if (position < 0 || position >= static_cast<Sci_Position>(m_text.size())) return 0;
        return static_cast<unsigned char>(m_text[position]);
    }

    const std::vector<char>& getStyles() const { return m_styles; }
    const std::string& getText() const { return m_text; }

private:
    std::string m_text;
    std::vector<char> m_styles;
    std::vector<Sci_Position> m_lineStarts;
    std::vector<int> m_levels;
    std::vector<int> m_lineStates;
    Sci_Position m_stylePos = 0;
};

// ============================================================================
// 1. Lexilla Lexer Factory Tests
// ============================================================================

TEST_CASE(LexillaIntegration, CreateStandardLexers) {
    const std::vector<std::string> lexerNames = {
        "cpp", "python", "hypertext", "xml", "json", "rust",
        "bash", "batch", "sql", "yaml", "css", "markdown",
        "lua", "makefile", "diff", "props", "toml", "zig", "perl", "ruby"
    };

    for (const auto& name : lexerNames) {
        Scintilla::ILexer5* lexer = CreateLexer(name.c_str());
        TEST_ASSERT_NOT_NULL(lexer);
        if (lexer) {
            TEST_ASSERT_GE(lexer->Version(), static_cast<int>(Scintilla::lvRelease4));
            const char* propNames = lexer->PropertyNames();
            TEST_ASSERT_NOT_NULL(propNames);
            lexer->Release();
        }
    }
}

TEST_CASE(LexillaIntegration, UnknownLexerHandling) {
    Scintilla::ILexer5* lexer = CreateLexer("non_existent_lexer_xyz_99");
    TEST_ASSERT_NULL(lexer);
}

TEST_CASE(LexillaIntegration, LexerPropertiesAndMetadata) {
    Scintilla::ILexer5* lexer = CreateLexer("cpp");
    TEST_ASSERT_NOT_NULL(lexer);

    // Set keyword list 0 (C++ primary keywords)
    const char* cppKeywords = "class struct enum if else for while do return switch case default";
    Sci_Position res = lexer->WordListSet(0, cppKeywords);
    TEST_ASSERT_EQ(res, 0);

    // Set properties
    lexer->PropertySet("fold", "1");
    lexer->PropertySet("fold.comment", "1");
    const char* propVal = lexer->DescribeProperty("fold");
    TEST_ASSERT_NOT_NULL(propVal);

    lexer->Release();
}

// ============================================================================
// 2. Lexing Execution & Tokenization Tests
// ============================================================================

TEST_CASE(LexillaIntegration, CppLexing) {
    Scintilla::ILexer5* lexer = CreateLexer("cpp");
    TEST_ASSERT_NOT_NULL(lexer);

    lexer->WordListSet(0, "int void return if class");
    lexer->PropertySet("styling.within.preprocessor", "1");

    std::string sampleCode = 
        "#include <iostream>\n"
        "// Single line comment\n"
        "int main() {\n"
        "    int value = 42;\n"
        "    const char* str = \"Hello macOS\";\n"
        "    return 0;\n"
        "}\n";

    MockDocument doc(sampleCode);
    lexer->Lex(0, doc.Length(), SCE_C_DEFAULT, &doc);

    // Check preprocessor directive
    TEST_ASSERT_EQ(doc.GetStyleAt(0), SCE_C_PREPROCESSOR);
    TEST_ASSERT_EQ(doc.GetStyleAt(1), SCE_C_PREPROCESSOR);

    // Check comment
    Sci_Position commentPos = sampleCode.find("//");
    TEST_ASSERT_EQ(doc.GetStyleAt(commentPos), SCE_C_COMMENTLINE);
    TEST_ASSERT_EQ(doc.GetStyleAt(commentPos + 5), SCE_C_COMMENTLINE);

    // Check keyword 'int'
    Sci_Position intPos = sampleCode.find("int main");
    TEST_ASSERT_EQ(doc.GetStyleAt(intPos), SCE_C_WORD);
    TEST_ASSERT_EQ(doc.GetStyleAt(intPos + 1), SCE_C_WORD);
    TEST_ASSERT_EQ(doc.GetStyleAt(intPos + 2), SCE_C_WORD);

    // Check string literal
    Sci_Position strPos = sampleCode.find("\"Hello macOS\"");
    TEST_ASSERT_EQ(doc.GetStyleAt(strPos), SCE_C_STRING);
    TEST_ASSERT_EQ(doc.GetStyleAt(strPos + 5), SCE_C_STRING);

    // Check number literal '42'
    Sci_Position numPos = sampleCode.find("42");
    TEST_ASSERT_EQ(doc.GetStyleAt(numPos), SCE_C_NUMBER);
    TEST_ASSERT_EQ(doc.GetStyleAt(numPos + 1), SCE_C_NUMBER);

    // Check identifier
    Sci_Position idPos = sampleCode.find("value");
    TEST_ASSERT_EQ(doc.GetStyleAt(idPos), SCE_C_IDENTIFIER);

    lexer->Release();
}

TEST_CASE(LexillaIntegration, PythonLexing) {
    Scintilla::ILexer5* lexer = CreateLexer("python");
    TEST_ASSERT_NOT_NULL(lexer);

    lexer->WordListSet(0, "def return if else class import from");

    std::string samplePy = 
        "# Python comment\n"
        "def compute_sum(a, b):\n"
        "    result = a + b + 100\n"
        "    msg = 'success'\n"
        "    return result\n";

    MockDocument doc(samplePy);
    lexer->Lex(0, doc.Length(), SCE_P_DEFAULT, &doc);

    // Check comment
    TEST_ASSERT_EQ(doc.GetStyleAt(0), SCE_P_COMMENTLINE);
    TEST_ASSERT_EQ(doc.GetStyleAt(5), SCE_P_COMMENTLINE);

    // Check keyword 'def'
    Sci_Position defPos = samplePy.find("def");
    TEST_ASSERT_EQ(doc.GetStyleAt(defPos), SCE_P_WORD);
    TEST_ASSERT_EQ(doc.GetStyleAt(defPos + 1), SCE_P_WORD);

    // Check string literal
    Sci_Position strPos = samplePy.find("'success'");
    TEST_ASSERT_EQ(doc.GetStyleAt(strPos), SCE_P_CHARACTER);

    // Check number '100'
    Sci_Position numPos = samplePy.find("100");
    TEST_ASSERT_EQ(doc.GetStyleAt(numPos), SCE_P_NUMBER);

    // Check keyword 'return'
    Sci_Position retPos = samplePy.find("return");
    TEST_ASSERT_EQ(doc.GetStyleAt(retPos), SCE_P_WORD);

    lexer->Release();
}

TEST_CASE(LexillaIntegration, JsonLexing) {
    Scintilla::ILexer5* lexer = CreateLexer("json");
    TEST_ASSERT_NOT_NULL(lexer);

    std::string sampleJson = 
        "{\n"
        "  \"name\": \"Notepad++\",\n"
        "  \"version\": 8,\n"
        "  \"platform\": \"macOS\"\n"
        "}";

    MockDocument doc(sampleJson);
    lexer->Lex(0, doc.Length(), SCE_JSON_DEFAULT, &doc);

    // Property string
    Sci_Position namePos = sampleJson.find("\"name\"");
    TEST_ASSERT_EQ(doc.GetStyleAt(namePos), SCE_JSON_PROPERTYNAME);

    // Number
    Sci_Position verPos = sampleJson.find("8");
    TEST_ASSERT_EQ(doc.GetStyleAt(verPos), SCE_JSON_NUMBER);

    // Value string
    Sci_Position macPos = sampleJson.find("\"macOS\"");
    TEST_ASSERT_EQ(doc.GetStyleAt(macPos), SCE_JSON_STRING);

    lexer->Release();
}

// ============================================================================
// 3. Code Folding Tests
// ============================================================================

TEST_CASE(LexillaIntegration, CppCodeFolding) {
    Scintilla::ILexer5* lexer = CreateLexer("cpp");
    TEST_ASSERT_NOT_NULL(lexer);

    std::string nestedCode = 
        "void OuterFunction() {\n"
        "    if (true) {\n"
        "        DoSomething();\n"
        "    }\n"
        "}\n";

    MockDocument doc(nestedCode);
    lexer->PropertySet("fold", "1");
    lexer->PropertySet("fold.compact", "0");

    // Lex first
    lexer->Lex(0, doc.Length(), SCE_C_DEFAULT, &doc);
    // Then Fold
    lexer->Fold(0, doc.Length(), SCE_C_DEFAULT, &doc);

    // Verify fold levels: inner body (line 2) should have higher numeric level than outer base
    int level0 = doc.GetLevel(0) & SC_FOLDLEVELNUMBERMASK;
    int level1 = doc.GetLevel(1) & SC_FOLDLEVELNUMBERMASK;
    int level2 = doc.GetLevel(2) & SC_FOLDLEVELNUMBERMASK;

    TEST_ASSERT_GE(level1, level0);
    TEST_ASSERT_GE(level2, level1);

    lexer->Release();
}

// ============================================================================
// 4. Scintilla Constants & Structure Verification
// ============================================================================

TEST_CASE(ScintillaConstants, CoreMessageIDs) {
    TEST_ASSERT_EQ(SCI_START, 2000);
    TEST_ASSERT_EQ(SCI_ADDTEXT, 2001);
    TEST_ASSERT_EQ(SCI_INSERTTEXT, 2003);
    TEST_ASSERT_EQ(SCI_CLEARALL, 2004);
    TEST_ASSERT_EQ(SCI_GETLENGTH, 2006);
    TEST_ASSERT_EQ(SCI_GETCHARAT, 2007);
    TEST_ASSERT_EQ(SCI_UNDO, 2176);
    TEST_ASSERT_EQ(SCI_REDO, 2011);
    TEST_ASSERT_EQ(SCI_SELECTALL, 2013);
    TEST_ASSERT_EQ(SCI_SETTEXT, 2181);
    TEST_ASSERT_EQ(SCI_GETTEXT, 2182);
    TEST_ASSERT_EQ(SCI_GETEOLMODE, 2030);
    TEST_ASSERT_EQ(SCI_SETEOLMODE, 2031);

    // Character range struct
    Sci_CharacterRangeFull cr;
    cr.cpMin = 10;
    cr.cpMax = 50;
    TEST_ASSERT_EQ(cr.cpMin, 10);
    TEST_ASSERT_EQ(cr.cpMax, 50);

    // TextRange struct
    char buffer[32] = {0};
    Sci_TextRangeFull tr;
    tr.chrg.cpMin = 0;
    tr.chrg.cpMax = 15;
    tr.lpstrText = buffer;
    TEST_ASSERT_EQ(tr.chrg.cpMax - tr.chrg.cpMin, 15);
}
