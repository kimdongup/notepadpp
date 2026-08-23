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

// ============================================================================
// 5. Next Untitled Number Calculation Logic (Max Number + 1)
// ============================================================================

static int computeTestNextUntitledNumber(const std::vector<std::string>& titles) {
    int maxNum = 0;
    for (const auto& t : titles) {
        int n = 0;
        if (sscanf(t.c_str(), "new %d", &n) == 1) {
            if (n > maxNum) maxNum = n;
        }
    }
    return maxNum + 1;
}

TEST_CASE(SessionPersistenceSuite, MaxUntitledTabRecountLogic) {
    // 1. Multiple tabs with new 1, new 2, new 18 -> next must be 19
    std::vector<std::string> tabList1 = {"new 1", "main.cpp", "new 18", "new 3"};
    TEST_ASSERT_EQ(computeTestNextUntitledNumber(tabList1), 19);

    // 2. Only saved files -> next must be 1 (new 1)
    std::vector<std::string> tabList2 = {"main.cpp", "config.json", "README.md"};
    TEST_ASSERT_EQ(computeTestNextUntitledNumber(tabList2), 1);

    // 3. Single new 5 -> next must be 6
    std::vector<std::string> tabList3 = {"new 5"};
    TEST_ASSERT_EQ(computeTestNextUntitledNumber(tabList3), 6);

    // 4. Empty list -> next must be 1
    std::vector<std::string> tabList4 = {};
    TEST_ASSERT_EQ(computeTestNextUntitledNumber(tabList4), 1);
}

// ============================================================================
// 6. Tab Reordering and Smart Pin Tab Grouping
// ============================================================================

struct SimpleTestDoc {
    std::string title;
    bool isPinned;
};

static void moveTestDoc(std::vector<SimpleTestDoc>& docs, int from, int to, int& active) {
    if (from == to || from < 0 || to < 0 || from >= (int)docs.size() || to >= (int)docs.size()) return;
    SimpleTestDoc d = docs[from];
    docs.erase(docs.begin() + from);
    docs.insert(docs.begin() + to, d);

    if (active == from) {
        active = to;
    } else if (from < active && to >= active) {
        active--;
    } else if (from > active && to <= active) {
        active++;
    }
}

static void togglePinTestDoc(std::vector<SimpleTestDoc>& docs, int& active) {
    if (active < 0 || active >= (int)docs.size()) return;
    docs[active].isPinned = !docs[active].isPinned;

    std::vector<SimpleTestDoc> pinned;
    std::vector<SimpleTestDoc> unpinned;
    int newActive = 0;

    for (size_t i = 0; i < docs.size(); ++i) {
        if (docs[i].isPinned) {
            if ((int)i == active) newActive = (int)pinned.size();
            pinned.push_back(docs[i]);
        } else {
            if ((int)i == active) newActive = (int)(pinned.size() + unpinned.size());
            unpinned.push_back(docs[i]);
        }
    }

    docs.clear();
    docs.insert(docs.end(), pinned.begin(), pinned.end());
    docs.insert(docs.end(), unpinned.begin(), unpinned.end());
    active = newActive;
}

TEST_CASE(SessionPersistenceSuite, TabReorderAndPinGrouping) {
    // 1. Test Tab Move
    std::vector<SimpleTestDoc> docs = {{"A", false}, {"B", false}, {"C", false}, {"D", false}};
    int active = 1; // "B" is active

    // Move "B" from index 1 to index 3 -> list becomes A, C, D, B and active becomes 3
    moveTestDoc(docs, 1, 3, active);
    TEST_ASSERT_EQ(docs[0].title, "A");
    TEST_ASSERT_EQ(docs[1].title, "C");
    TEST_ASSERT_EQ(docs[2].title, "D");
    TEST_ASSERT_EQ(docs[3].title, "B");
    TEST_ASSERT_EQ(active, 3);

    // 2. Test Smart Pin Grouping
    // Pin "D" (index 2)
    active = 2; // "D"
    togglePinTestDoc(docs, active);
    // Pinned "D" must move to front: D(pinned), A, C, B
    TEST_ASSERT_EQ(docs[0].title, "D");
    TEST_ASSERT_TRUE(docs[0].isPinned);
    TEST_ASSERT_EQ(docs[1].title, "A");
    TEST_ASSERT_EQ(docs[2].title, "C");
    TEST_ASSERT_EQ(docs[3].title, "B");
    TEST_ASSERT_EQ(active, 0); // "D" is now at index 0 and active

    // Pin "C" (index 2)
    active = 2; // "C"
    togglePinTestDoc(docs, active);
    // Pinned group is D, C. List: D, C, A, B
    TEST_ASSERT_EQ(docs[0].title, "D");
    TEST_ASSERT_EQ(docs[1].title, "C");
    TEST_ASSERT_TRUE(docs[1].isPinned);
    TEST_ASSERT_EQ(docs[2].title, "A");
    TEST_ASSERT_EQ(docs[3].title, "B");
    TEST_ASSERT_EQ(active, 1);
}


