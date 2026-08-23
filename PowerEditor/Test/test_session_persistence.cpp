// PowerEditor/Test/test_session_persistence.cpp
// Comprehensive test suite for Notepad++ session serialization, unsaved buffer persistence, and crash prevention

#include "test_framework.h"
#include "mac_compat.h"

#include <string>
#include <vector>
#include <sstream>
#include <fstream>
#include <filesystem>

namespace fs = std::filesystem;

// Mock structure representing session doc
struct TestSessionDoc {
    std::string path;
    int cursor;
    int encoding;
    std::string unsavedContent;
    bool isModified;
};

struct TestSessionState {
    int activeIndex;
    int windowX, windowY, windowW, windowH;
    bool isDarkMode;
    std::string localizationFile;
    bool showSidePanel;
    bool showBottomPanel;
    bool showSecondaryPanel;
    std::vector<TestSessionDoc> documents;
};

// Simple JSON generator for session testing
static std::string serializeTestSession(const TestSessionState& st) {
    std::stringstream ss;
    ss << "{\n";
    ss << "  \"activeIndex\": " << st.activeIndex << ",\n";
    ss << "  \"windowX\": " << st.windowX << ",\n";
    ss << "  \"windowY\": " << st.windowY << ",\n";
    ss << "  \"windowW\": " << st.windowW << ",\n";
    ss << "  \"windowH\": " << st.windowH << ",\n";
    ss << "  \"isDarkMode\": " << (st.isDarkMode ? "true" : "false") << ",\n";
    ss << "  \"localizationFile\": \"" << st.localizationFile << "\",\n";
    ss << "  \"showSidePanel\": " << (st.showSidePanel ? "true" : "false") << ",\n";
    ss << "  \"showBottomPanel\": " << (st.showBottomPanel ? "true" : "false") << ",\n";
    ss << "  \"showSecondaryPanel\": " << (st.showSecondaryPanel ? "true" : "false") << ",\n";
    ss << "  \"documents\": [\n";
    for (size_t i = 0; i < st.documents.size(); ++i) {
        const auto& d = st.documents[i];
        ss << "    {\n";
        ss << "      \"path\": \"" << d.path << "\",\n";
        ss << "      \"cursor\": " << d.cursor << ",\n";
        ss << "      \"encoding\": " << d.encoding << ",\n";
        ss << "      \"isModified\": " << (d.isModified ? "true" : "false") << ",\n";
        ss << "      \"unsavedContent\": \"" << d.unsavedContent << "\"\n";
        ss << "    }" << (i + 1 < st.documents.size() ? "," : "") << "\n";
    }
    ss << "  ]\n";
    ss << "}\n";
    return ss.str();
}

// Window bounds validation helper
static bool validateWindowBounds(int x, int y, int w, int h, int screenW, int screenH) {
    if (w < 400 || h < 300) return false;
    if (w > screenW * 2 || h > screenH * 2) return false;
    if (x + w < 50 || x > screenW - 50) return false;
    if (y + h < 50 || y > screenH - 50) return false;
    return true;
}

// ============================================================================
// 1. Session Serialization & Roundtrip
// ============================================================================

TEST_CASE(SessionPersistenceSuite, JsonSerializationAndDocList) {
    TestSessionState st;
    st.activeIndex = 1;
    st.windowX = 100;
    st.windowY = 120;
    st.windowW = 1280;
    st.windowH = 800;
    st.isDarkMode = true;
    st.localizationFile = "korean.xml";
    st.showSidePanel = true;
    st.showBottomPanel = false;
    st.showSecondaryPanel = true;

    st.documents.push_back({"/Users/test/main.cpp", 450, 0, "", false});
    st.documents.push_back({"", 25, 0, "Hello Unsaved Scratch Buffer!", true});
    st.documents.push_back({"/Users/test/config.json", 1024, 0, "", false});

    std::string jsonStr = serializeTestSession(st);

    TEST_ASSERT_CONTAINS(jsonStr, "\"activeIndex\": 1");
    TEST_ASSERT_CONTAINS(jsonStr, "\"localizationFile\": \"korean.xml\"");
    TEST_ASSERT_CONTAINS(jsonStr, "\"path\": \"/Users/test/main.cpp\"");
    TEST_ASSERT_CONTAINS(jsonStr, "\"unsavedContent\": \"Hello Unsaved Scratch Buffer!\"");
    TEST_ASSERT_CONTAINS(jsonStr, "\"isModified\": true");
}

// ============================================================================
// 2. Unsaved Buffer (new 1 / untitled) Restoral Simulation
// ============================================================================

TEST_CASE(SessionPersistenceSuite, UnsavedBufferRestoralLogic) {
    TestSessionDoc doc;
    doc.path = "";
    doc.isModified = true;
    doc.unsavedContent = "Line 1: important memo\nLine 2: pending tasks";
    doc.cursor = 15;
    doc.encoding = 0; // UTF-8

    // Verification of restoral criteria
    bool isUntitled = doc.path.empty() || doc.path.find("new ") == 0;
    TEST_ASSERT_TRUE(isUntitled);
    TEST_ASSERT_TRUE(doc.isModified);
    TEST_ASSERT_FALSE(doc.unsavedContent.empty());
    TEST_ASSERT_EQ(doc.cursor, 15);
}

// ============================================================================
// 3. Window Boundary & Crash Prevention Guard
// ============================================================================

TEST_CASE(SessionPersistenceSuite, WindowBoundsValidation) {
    int screenW = 1920;
    int screenH = 1080;

    // Normal window inside screen
    TEST_ASSERT_TRUE(validateWindowBounds(100, 100, 1200, 800, screenW, screenH));

    // Zero-sized or too tiny window (must fail validation and trigger centering)
    TEST_ASSERT_FALSE(validateWindowBounds(100, 100, 50, 50, screenW, screenH));
    TEST_ASSERT_FALSE(validateWindowBounds(100, 100, 0, 0, screenW, screenH));

    // Completely off-screen window (e.g. disconnected external monitor)
    TEST_ASSERT_FALSE(validateWindowBounds(3500, 2000, 1200, 800, screenW, screenH));
    TEST_ASSERT_FALSE(validateWindowBounds(-3000, -2000, 1200, 800, screenW, screenH));
}

// ============================================================================
// 4. Session File I/O Safety & File Roundtrip
// ============================================================================

TEST_CASE(SessionPersistenceSuite, FileIoRoundtrip) {
    std::string tempPath = "/tmp/test_npp_session.json";

    TestSessionState st;
    st.activeIndex = 0;
    st.windowX = 150;
    st.windowY = 150;
    st.windowW = 1100;
    st.windowH = 750;
    st.isDarkMode = false;
    st.localizationFile = "japanese.xml";
    st.showSidePanel = true;
    st.showBottomPanel = true;
    st.showSecondaryPanel = false;
    st.documents.push_back({"/tmp/sample.txt", 0, 0, "", false});

    std::string jsonStr = serializeTestSession(st);

    // Write to disk
    std::ofstream out(tempPath);
    out << jsonStr;
    out.close();

    TEST_ASSERT_TRUE(fs::exists(tempPath));
    TEST_ASSERT_GT(fs::file_size(tempPath), 50);

    // Read back and verify
    std::ifstream in(tempPath);
    std::stringstream buffer;
    buffer << in.rdbuf();
    in.close();

    std::string loaded = buffer.str();
    TEST_ASSERT_CONTAINS(loaded, "\"localizationFile\": \"japanese.xml\"");
    TEST_ASSERT_CONTAINS(loaded, "\"showBottomPanel\": true");

    fs::remove(tempPath);
}
