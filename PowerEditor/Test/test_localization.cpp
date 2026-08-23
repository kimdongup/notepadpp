// PowerEditor/Test/test_localization.cpp
// Comprehensive test suite for Notepad++ macOS 94-language live localization engine

#include "test_framework.h"
#include "pugixml/pugixml.hpp"
#include "mac_compat.h"

#include <string>
#include <vector>
#include <map>
#include <regex>
#include <functional>
#include <filesystem>

namespace fs = std::filesystem;

// Helper to strip Windows accelerator keys matching mac_main.mm logic
static std::string cleanLocalizedName(const std::string& raw) {
    if (raw.empty()) return "";
    std::string s = raw;

    // First replace &amp; with &
    std::regex ampRegex("&amp;");
    s = std::regex_replace(s, ampRegex, "&");

    // Strip accelerator pattern like (&F), (&N), (&E), (&P)
    std::regex accRegex(R"(\(&[A-Za-z0-9]\))");
    s = std::regex_replace(s, accRegex, "");

    // Strip any remaining standalone &
    std::regex singleAmp("&");
    s = std::regex_replace(s, singleAmp, "");

    // Trim leading/trailing whitespace
    size_t first = s.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return "";
    size_t last = s.find_last_not_of(" \t\r\n");
    return s.substr(first, (last - first + 1));
}

// ============================================================================
// 1. Accelerator Key Sanitization Tests
// ============================================================================

TEST_CASE(LocalizationSuite, AcceleratorKeyStripper) {
    TEST_ASSERT_EQ(cleanLocalizedName("파일(&F)"), "파일");
    TEST_ASSERT_EQ(cleanLocalizedName("새 파일(&N)"), "새 파일");
    TEST_ASSERT_EQ(cleanLocalizedName("Save &As..."), "Save As...");
    TEST_ASSERT_EQ(cleanLocalizedName("Cut (&amp;X)"), "Cut");
    TEST_ASSERT_EQ(cleanLocalizedName("Preferences(&amp;P)..."), "Preferences...");
    TEST_ASSERT_EQ(cleanLocalizedName("Fichier(&F)"), "Fichier");
    TEST_ASSERT_EQ(cleanLocalizedName("Datei(&D)"), "Datei");
    TEST_ASSERT_EQ(cleanLocalizedName("ファイル(&F)"), "ファイル");
    TEST_ASSERT_EQ(cleanLocalizedName(""), "");
}

// ============================================================================
// 2. Official 94 Language Packs Discovery & Validation
// ============================================================================

TEST_CASE(LocalizationSuite, All94LanguagesPresenceAndStructure) {
    std::string nativeLangDir = "PowerEditor/installer/nativeLang";
    TEST_ASSERT_TRUE(fs::exists(nativeLangDir));

    int validXmlCount = 0;
    std::vector<std::string> sampleLanguages = {
        "korean.xml", "english.xml", "japanese.xml", "chineseSimplified.xml",
        "taiwaneseMandarin.xml", "hongKongCantonese.xml", "french.xml", "german.xml", "spanish.xml",
        "italian.xml", "russian.xml", "portuguese.xml", "brazilian_portuguese.xml",
        "dutch.xml", "polish.xml", "turkish.xml", "vietnamese.xml"
    };

    for (const auto& entry : fs::directory_iterator(nativeLangDir)) {
        if (entry.path().extension() == ".xml") {
            pugi::xml_document doc;
            pugi::xml_parse_result result = doc.load_file(entry.path().c_str());
            if (result.status == pugi::status_ok) {
                pugi::xml_node nativeLang = doc.child("NotepadPlus").child("Native-Langue");
                if (!nativeLang) nativeLang = doc.child("Native-Langue");
                if (nativeLang) {
                    validXmlCount++;
                }
            }
        }
    }

    // Must have at least 90 valid language packages
    TEST_ASSERT_GE(validXmlCount, 90);

    // Verify critical languages exist and parse cleanly
    for (const auto& lang : sampleLanguages) {
        std::string fullPath = nativeLangDir + "/" + lang;
        TEST_ASSERT_MSG(fs::exists(fullPath), ("Language pack missing: " + lang).c_str());

        pugi::xml_document doc;
        pugi::xml_parse_result res = doc.load_file(fullPath.c_str());
        TEST_ASSERT_EQ(res.status, pugi::status_ok);
    }
}

// ============================================================================
// 3. Korean Language Pack Key Resolution
// ============================================================================

TEST_CASE(LocalizationSuite, KoreanLanguagePackResolution) {
    std::string path = "PowerEditor/installer/nativeLang/korean.xml";
    pugi::xml_document doc;
    pugi::xml_parse_result res = doc.load_file(path.c_str());
    TEST_ASSERT_EQ(res.status, pugi::status_ok);

    pugi::xml_node nativeLang = doc.child("NotepadPlus").child("Native-Langue");
    TEST_ASSERT_FALSE(nativeLang.empty());

    // 1. Menu Entries
    std::map<std::string, std::string> dict;
    pugi::xml_node menuMain = nativeLang.child("Menu").child("Main");
    for (pugi::xml_node item : menuMain.child("Entries").children("Item")) {
        const char* menuId = item.attribute("menuId").as_string();
        const char* name = item.attribute("name").as_string();
        if (menuId && name) {
            dict[menuId] = cleanLocalizedName(name);
        }
    }

    TEST_ASSERT_EQ(dict["file"], "파일");
    TEST_ASSERT_EQ(dict["edit"], "편집");
    TEST_ASSERT_EQ(dict["search"], "찾기");
    TEST_ASSERT_EQ(dict["view"], "보기");
    TEST_ASSERT_EQ(dict["encoding"], "인코딩");
    TEST_ASSERT_EQ(dict["language"], "언어");
    TEST_ASSERT_EQ(dict["settings"], "설정");

    // 2. Command IDs
    for (pugi::xml_node item : menuMain.child("Commands").children("Item")) {
        const char* idStr = item.attribute("id").as_string();
        const char* name = item.attribute("name").as_string();
        if (idStr && name) {
            dict[std::string("cmd_") + idStr] = cleanLocalizedName(name);
        }
    }

    TEST_ASSERT_EQ(dict["cmd_41001"], "새 파일");
    TEST_ASSERT_EQ(dict["cmd_41002"], "열기...");
    TEST_ASSERT_EQ(dict["cmd_41006"], "저장");
    TEST_ASSERT_EQ(dict["cmd_41008"], "다른 이름으로 저장...");
    TEST_ASSERT_EQ(dict["cmd_42001"], "잘라내기");
    TEST_ASSERT_EQ(dict["cmd_42002"], "복사");

    // 3. Dialog Items (Recursive)
    std::function<void(pugi::xml_node)> indexNode = [&](pugi::xml_node node) {
        for (pugi::xml_node child : node.children()) {
            if (strcmp(child.name(), "Item") == 0) {
                const char* idStr = child.attribute("id").as_string();
                const char* name = child.attribute("name").as_string();
                if (idStr && name && strlen(idStr) > 0) {
                    dict[std::string("dlg_") + idStr] = cleanLocalizedName(name);
                }
            } else {
                const char* title = child.attribute("title").as_string();
                if (title && strlen(title) > 0) {
                    dict[std::string("dlg_title_") + child.name()] = cleanLocalizedName(title);
                }
            }
            indexNode(child);
        }
    };

    for (pugi::xml_node dlg : nativeLang.child("Dialog").children()) {
        const char* dlgTitle = dlg.attribute("title").as_string();
        if (dlgTitle && strlen(dlgTitle) > 0) {
            dict[std::string("dlg_title_") + dlg.name()] = cleanLocalizedName(dlgTitle);
        }
        indexNode(dlg);
    }

    TEST_ASSERT_EQ(dict["dlg_1"], "확인");
    TEST_ASSERT_EQ(dict["dlg_2"], "취소");
    TEST_ASSERT_EQ(dict["dlg_1608"], "바꾸기");
    TEST_ASSERT_EQ(dict["dlg_1609"], "모두 바꾸기");
    TEST_ASSERT_EQ(dict["dlg_title_Global"], "일반");
    TEST_ASSERT_EQ(dict["dlg_title_Preference"], "환경설정");
}

// ============================================================================
// 4. English & Japanese Language Resolution
// ============================================================================

TEST_CASE(LocalizationSuite, EnglishAndJapaneseResolution) {
    // English
    {
        pugi::xml_document doc;
        TEST_ASSERT_EQ(doc.load_file("PowerEditor/installer/nativeLang/english.xml").status, pugi::status_ok);
        pugi::xml_node root = doc.child("NotepadPlus").child("Native-Langue");
        pugi::xml_node menu = root.child("Menu").child("Main");
        pugi::xml_node fileItem = menu.child("Entries").find_child_by_attribute("Item", "menuId", "file");
        TEST_ASSERT_EQ(cleanLocalizedName(fileItem.attribute("name").as_string()), "File");
    }

    // Japanese
    {
        pugi::xml_document doc;
        TEST_ASSERT_EQ(doc.load_file("PowerEditor/installer/nativeLang/japanese.xml").status, pugi::status_ok);
        pugi::xml_node root = doc.child("NotepadPlus").child("Native-Langue");
        pugi::xml_node menu = root.child("Menu").child("Main");
        pugi::xml_node fileItem = menu.child("Entries").find_child_by_attribute("Item", "menuId", "file");
        TEST_ASSERT_EQ(cleanLocalizedName(fileItem.attribute("name").as_string()), "ファイル");
    }
}
