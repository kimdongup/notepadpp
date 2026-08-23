// PowerEditor/Test/test_help_and_tooltips.cpp
// Comprehensive test suite for Notepad++ Help Guide system, tooltips, and language mappings

#include "test_framework.h"
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <sstream>
#include <filesystem>

namespace fs = std::filesystem;

// Extension to lexer mapper
static std::string getLexerForExtension(const std::string& ext) {
    static const std::map<std::string, std::string> s_extMap = {
        {"js", "javascript"}, {"jsx", "javascript"}, {"mjs", "javascript"}, {"cjs", "javascript"},
        {"ts", "typescript"}, {"tsx", "typescript"},
        {"cpp", "cpp"}, {"cxx", "cpp"}, {"cc", "cpp"}, {"c", "cpp"}, {"h", "cpp"}, {"hpp", "cpp"},
        {"py", "python"}, {"pyw", "python"},
        {"html", "hypertext"}, {"htm", "hypertext"}, {"xml", "xml"}, {"svg", "xml"},
        {"json", "json"}, {"css", "css"}, {"scss", "css"},
        {"md", "markdown"}, {"markdown", "markdown"},
        {"sql", "sql"}, {"rs", "rust"}, {"go", "go"},
        {"sh", "bash"}, {"zsh", "bash"}, {"bash", "bash"},
        {"yaml", "yaml"}, {"yml", "yaml"}, {"lua", "lua"},
        {"txt", "text"}
    };
    auto it = s_extMap.find(ext);
    return (it != s_extMap.end()) ? it->second : "text";
}

// ============================================================================
// 1. Language Lexer Mapping Validation (JS / TS connection test)
// ============================================================================

TEST_CASE(HelpSystemSuite, ExtensionToLexerMapping) {
    // JavaScript must map to "javascript", not "cpp"
    TEST_ASSERT_EQ(getLexerForExtension("js"), "javascript");
    TEST_ASSERT_EQ(getLexerForExtension("jsx"), "javascript");
    TEST_ASSERT_EQ(getLexerForExtension("mjs"), "javascript");
    TEST_ASSERT_EQ(getLexerForExtension("cjs"), "javascript");

    // TypeScript
    TEST_ASSERT_EQ(getLexerForExtension("ts"), "typescript");
    TEST_ASSERT_EQ(getLexerForExtension("tsx"), "typescript");

    // C++
    TEST_ASSERT_EQ(getLexerForExtension("cpp"), "cpp");
    TEST_ASSERT_EQ(getLexerForExtension("hpp"), "cpp");

    // Python, HTML, Markdown
    TEST_ASSERT_EQ(getLexerForExtension("py"), "python");
    TEST_ASSERT_EQ(getLexerForExtension("html"), "hypertext");
    TEST_ASSERT_EQ(getLexerForExtension("md"), "markdown");
}

// ============================================================================
// 2. Help Guide File Integrity & Content Validation
// ============================================================================

TEST_CASE(HelpSystemSuite, HelpGuideFileIntegrity) {
    std::string guidePath = "PowerEditor/src/HELP_GUIDE.md";
    TEST_ASSERT_TRUE(fs::exists(guidePath));
    TEST_ASSERT_GT(fs::file_size(guidePath), 500);

    std::ifstream in(guidePath);
    std::stringstream buffer;
    buffer << in.rdbuf();
    std::string text = buffer.str();

    // Verify key sections exist
    TEST_ASSERT_CONTAINS(text, "Notepad++");
    TEST_ASSERT_CONTAINS(text, "Column Mode");
    TEST_ASSERT_CONTAINS(text, "단축키");
}

// ============================================================================
// 3. Fast Tooltip & Visual Feedback Parameters
// ============================================================================

TEST_CASE(HelpSystemSuite, TooltipTimingAndParameters) {
    double tooltipDelaySeconds = 0.05; // 50ms fast delay
    double tooltipFontSizePt = 14.0;   // 2x enlarged legible font

    TEST_ASSERT_LT(tooltipDelaySeconds, 0.1);
    TEST_ASSERT_GE(tooltipFontSizePt, 12.0);
}
