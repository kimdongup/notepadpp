// PowerEditor/Test/test_xml.cpp
// Comprehensive test suite for pugixml and NppXml configuration loading / serialization

#include "test_framework.h"
#include "NppXml.h"
#include "NppConstants.h"
#include "mac_compat.h"

#include <string>
#include <vector>
#include <sstream>

// ============================================================================
// 1. Pugixml & NppXml Core Operations
// ============================================================================

TEST_CASE(XmlSuite, CreateAndSerializeDocument) {
    pugi::xml_document rawDoc;
    NppXml::Document doc = &rawDoc;
    NppXml::createNewDeclaration(doc);

    // Create root element <NotepadPlus>
    NppXml::Element root = NppXml::createChildElement(doc, "NotepadPlus");
    TEST_ASSERT_FALSE(root.empty());

    // Add GUIConfig element
    NppXml::Element guiConfig = NppXml::createChildElement(root, "GUIConfig");
    NppXml::setAttribute(guiConfig, "name", "AppPosition");
    NppXml::setAttribute(guiConfig, "x", 100);
    NppXml::setAttribute(guiConfig, "y", 150);
    NppXml::setAttribute(guiConfig, "width", 1280);
    NppXml::setAttribute(guiConfig, "height", 800);
    NppXml::setAttribute(guiConfig, "isMaximized", "no");

    // Add another GUIConfig
    NppXml::Element darkConfig = NppXml::createChildElement(root, "GUIConfig");
    NppXml::setAttribute(darkConfig, "name", "DarkMode");
    NppXml::setAttribute(darkConfig, "enable", "yes");
    NppXml::setAttribute(darkConfig, "theme", 1);

    // Verify attributes
    TEST_ASSERT_STR_EQ(NppXml::attribute(guiConfig, "name"), "AppPosition");
    TEST_ASSERT_EQ(NppXml::intAttribute(guiConfig, "x"), 100);
    TEST_ASSERT_EQ(NppXml::intAttribute(guiConfig, "y"), 150);
    TEST_ASSERT_EQ(NppXml::intAttribute(guiConfig, "width"), 1280);
    TEST_ASSERT_EQ(NppXml::intAttribute(guiConfig, "height"), 800);

    TEST_ASSERT_STR_EQ(NppXml::attribute(darkConfig, "name"), "DarkMode");
    TEST_ASSERT_STR_EQ(NppXml::attribute(darkConfig, "enable"), "yes");
    TEST_ASSERT_EQ(NppXml::intAttribute(darkConfig, "theme"), 1);

    // Serialize to string
    std::stringstream ss;
    doc->save(ss, "    ");
    std::string xmlStr = ss.str();

    TEST_ASSERT_CONTAINS(xmlStr, "<NotepadPlus>");
    TEST_ASSERT_CONTAINS(xmlStr, "name=\"AppPosition\"");
    TEST_ASSERT_CONTAINS(xmlStr, "width=\"1280\"");
    TEST_ASSERT_CONTAINS(xmlStr, "name=\"DarkMode\"");
}

TEST_CASE(XmlSuite, EolNormalization) {
    pugi::string_t mixedEol = "Line 1\r\nLine 2\rLine 3\nLine 4\r\n";
    pugi::string_t normalized = NppXml::normalizeEOL(mixedEol);

    TEST_ASSERT_CONTAINS(normalized, "Line 1\n");
    TEST_ASSERT_CONTAINS(normalized, "Line 2\n");
    TEST_ASSERT_CONTAINS(normalized, "Line 3\n");
    TEST_ASSERT_CONTAINS(normalized, "Line 4\n");
    // Ensure no remaining '\r'
    TEST_ASSERT_EQ(normalized.find('\r'), pugi::string_t::npos);
}

TEST_CASE(XmlSuite, ShortcutXmlParsing) {
    pugi::xml_document doc;
    pugi::xml_parse_result result = doc.load_string(SHORTCUT_XML_CONTENT, pugi::parse_default | pugi::parse_comments);
    TEST_ASSERT_TRUE(result);
    TEST_ASSERT_EQ(result.status, pugi::status_ok);

    NppXml::Element root = NppXml::firstChildElement(&doc, "NotepadPlus");
    TEST_ASSERT_FALSE(root.empty());

    // Check Macros section
    NppXml::Element macros = NppXml::firstChildElement(root, "Macros");
    TEST_ASSERT_FALSE(macros.empty());

    NppXml::Element macro = NppXml::firstChildElement(macros, "Macro");
    TEST_ASSERT_FALSE(macro.empty());
    TEST_ASSERT_STR_EQ(NppXml::attribute(macro, "name"), "Trim Trailing Space and Save");
    TEST_ASSERT_STR_EQ(NppXml::attribute(macro, "Ctrl"), "no");
    TEST_ASSERT_STR_EQ(NppXml::attribute(macro, "Alt"), "yes");
    TEST_ASSERT_STR_EQ(NppXml::attribute(macro, "Shift"), "yes");
    TEST_ASSERT_EQ(NppXml::intAttribute(macro, "Key"), 83);

    // Check UserDefinedCommands section
    NppXml::Element userCmds = NppXml::firstChildElement(root, "UserDefinedCommands");
    TEST_ASSERT_FALSE(userCmds.empty());

    int cmdCount = 0;
    for (NppXml::Element cmd = NppXml::firstChildElement(userCmds, "Command"); !cmd.empty(); cmd = NppXml::nextSiblingElement(cmd, "Command")) {
        cmdCount++;
        const char* name = NppXml::attribute(cmd, "name");
        TEST_ASSERT_NOT_NULL(name);
    }
    TEST_ASSERT_GE(cmdCount, 3);
}

TEST_CASE(XmlSuite, ContextMenuXmlParsing) {
    pugi::xml_document doc;
    pugi::xml_parse_result res = doc.load_string(CONTEXTMENU_XML_CONTENT, pugi::parse_default | pugi::parse_comments);
    TEST_ASSERT_TRUE(res);

    NppXml::Element root = NppXml::firstChildElement(&doc, "NotepadPlus");
    TEST_ASSERT_FALSE(root.empty());

    NppXml::Element menu = NppXml::firstChildElement(root, "ScintillaContextMenu");
    TEST_ASSERT_FALSE(menu.empty());

    int itemCount = 0;
    int separatorCount = 0;

    for (NppXml::Element item = NppXml::firstChildElement(menu, "Item"); !item.empty(); item = NppXml::nextSiblingElement(item, "Item")) {
        itemCount++;
        int id = NppXml::intAttribute(item, "id", -1);
        if (id == 0) {
            separatorCount++;
        }
    }

    TEST_ASSERT_GT(itemCount, 15);
    TEST_ASSERT_GE(separatorCount, 2);
}

TEST_CASE(XmlSuite, FileLoadAndSaveRoundTrip) {
    std::wstring tempXmlFile = L"/tmp/npp_test_xml_" + std::to_wstring(GetTickCount()) + L".xml";

    // 1. Build document and save
    {
        pugi::xml_document rawDoc;
        NppXml::Document doc = &rawDoc;
        NppXml::createNewDeclaration(doc);
        NppXml::Element root = NppXml::createChildElement(doc, "NotepadPlus");
        NppXml::Element langs = NppXml::createChildElement(root, "Languages");

        NppXml::Element langCpp = NppXml::createChildElement(langs, "Language");
        NppXml::setAttribute(langCpp, "name", "cpp");
        NppXml::setAttribute(langCpp, "ext", "cpp cxx cc h hpp");

        NppXml::Element langPy = NppXml::createChildElement(langs, "Language");
        NppXml::setAttribute(langPy, "name", "python");
        NppXml::setAttribute(langPy, "ext", "py pyw");

        bool saveOk = NppXml::saveFile(doc, tempXmlFile.c_str());
        TEST_ASSERT_TRUE(saveOk);
    }

    // 2. Reload document and verify
    {
        pugi::xml_document loadedDoc;
        bool loadOk = NppXml::loadFile(&loadedDoc, tempXmlFile.c_str());
        TEST_ASSERT_TRUE(loadOk);

        NppXml::Element root = NppXml::firstChildElement(&loadedDoc, "NotepadPlus");
        TEST_ASSERT_FALSE(root.empty());

        NppXml::Element langs = NppXml::firstChildElement(root, "Languages");
        TEST_ASSERT_FALSE(langs.empty());

        NppXml::Element firstLang = NppXml::firstChildElement(langs, "Language");
        TEST_ASSERT_STR_EQ(NppXml::attribute(firstLang, "name"), "cpp");
        TEST_ASSERT_STR_EQ(NppXml::attribute(firstLang, "ext"), "cpp cxx cc h hpp");

        NppXml::Element secondLang = NppXml::nextSiblingElement(firstLang, "Language");
        TEST_ASSERT_STR_EQ(NppXml::attribute(secondLang, "name"), "python");
    }

    DeleteFileW(tempXmlFile.c_str());
}

TEST_CASE(XmlSuite, MalformedXmlHandling) {
    pugi::xml_document doc;

    // Unclosed tag
    const char* badXml1 = "<NotepadPlus><GUIConfig name=\"test\">Text</NotepadPlus>";
    pugi::xml_parse_result res1 = doc.load_string(badXml1);
    TEST_ASSERT_FALSE(res1);
    TEST_ASSERT_EQ(res1.status, pugi::status_end_element_mismatch);

    // Mismatched tag
    const char* badXml2 = "<Root><Child>Content</Other></Root>";
    pugi::xml_parse_result res2 = doc.load_string(badXml2);
    TEST_ASSERT_FALSE(res2);
    TEST_ASSERT_EQ(res2.status, pugi::status_end_element_mismatch);

    // Unclosed quote in attribute
    const char* badXml3 = "<Tag attr=\"unclosed string>data</Tag>";
    pugi::xml_parse_result res3 = doc.load_string(badXml3);
    TEST_ASSERT_FALSE(res3);
}
