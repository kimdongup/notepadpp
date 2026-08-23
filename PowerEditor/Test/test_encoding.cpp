// PowerEditor/Test/test_encoding.cpp
// Comprehensive test suite for Utf8_16, uchardet, and EncodingMapper

#include "test_framework.h"
#include "Utf8_16.h"
#include "uchardet/uchardet.h"
#include "EncodingMapper.h"
#include "NppConstants.h"

#include <vector>
#include <string>
#include <cstring>

// ============================================================================
// 1. Utf8_16 BOM Detection & Conversion Tests
// ============================================================================

TEST_CASE(Utf8_16Encoding, BOMDetection) {
    // 1. UTF-8 BOM (\xEF\xBB\xBF)
    const unsigned char utf8BOM[] = {0xEF, 0xBB, 0xBF, 'H', 'e', 'l', 'l', 'o'};
    UniMode modeUtf8 = Utf8_16_Read::determineEncodingFromBOM(utf8BOM, sizeof(utf8BOM));
    TEST_ASSERT_EQ(modeUtf8, uniUTF8);

    // 2. UTF-16 LE BOM (\xFF\xFE)
    const unsigned char utf16LE[] = {0xFF, 0xFE, 'H', 0x00, 'i', 0x00};
    UniMode mode16LE = Utf8_16_Read::determineEncodingFromBOM(utf16LE, sizeof(utf16LE));
    TEST_ASSERT_EQ(mode16LE, uni16LE);

    // 3. UTF-16 BE BOM (\xFE\xFF)
    const unsigned char utf16BE[] = {0xFE, 0xFF, 0x00, 'H', 0x00, 'i'};
    UniMode mode16BE = Utf8_16_Read::determineEncodingFromBOM(utf16BE, sizeof(utf16BE));
    TEST_ASSERT_EQ(mode16BE, uni16BE);

    // 4. Plain text without BOM
    const unsigned char plainText[] = "Just standard ASCII without BOM";
    UniMode modePlain = Utf8_16_Read::determineEncodingFromBOM(plainText, strlen((const char*)plainText));
    TEST_ASSERT_EQ(modePlain, uni8Bit);

    // 5. Short buffers
    const unsigned char singleByte[] = {0xEF};
    UniMode modeSingle = Utf8_16_Read::determineEncodingFromBOM(singleByte, 1);
    TEST_ASSERT_EQ(modeSingle, uni8Bit);
}

TEST_CASE(Utf8_16Encoding, Utf8_16_Read_UTF16LE) {
    // UTF-16 LE text: "Notepad++ Mac" with BOM
    std::vector<unsigned char> utf16leData = {0xFF, 0xFE}; // BOM
    const wchar_t* srcText = L"Notepad++ Mac UTF-16 LE Test";
    size_t charCount = wcslen(srcText);
    for (size_t i = 0; i < charCount; ++i) {
        wchar_t wc = srcText[i];
        utf16leData.push_back(static_cast<unsigned char>(wc & 0xFF));
        utf16leData.push_back(static_cast<unsigned char>((wc >> 8) & 0xFF));
    }

    Utf8_16_Read reader;
    size_t convertedSize = reader.convert(reinterpret_cast<char*>(utf16leData.data()), utf16leData.size());
    TEST_ASSERT_GT(convertedSize, 0u);
    TEST_ASSERT_EQ(reader.getEncoding(), uni16LE);

    std::string result(reader.getNewBuf(), reader.getNewSize());
    TEST_ASSERT_STR_EQ(result.c_str(), "Notepad++ Mac UTF-16 LE Test");
}

TEST_CASE(Utf8_16Encoding, Utf8_16_Read_UTF16BE) {
    // UTF-16 BE text: "Hello UTF-16 BE" with BOM
    std::vector<unsigned char> utf16beData = {0xFE, 0xFF}; // BOM
    const char* asciiSource = "Hello UTF-16 BE";
    for (size_t i = 0; i < strlen(asciiSource); ++i) {
        utf16beData.push_back(0x00);
        utf16beData.push_back(static_cast<unsigned char>(asciiSource[i]));
    }

    Utf8_16_Read reader;
    size_t convertedSize = reader.convert(reinterpret_cast<char*>(utf16beData.data()), utf16beData.size());
    TEST_ASSERT_GT(convertedSize, 0u);
    TEST_ASSERT_EQ(reader.getEncoding(), uni16BE);

    std::string result(reader.getNewBuf(), reader.getNewSize());
    TEST_ASSERT_STR_EQ(result.c_str(), "Hello UTF-16 BE");
}

TEST_CASE(Utf8_16Encoding, Utf8_16_Read_UTF8BOM) {
    // UTF-8 with BOM: strips the 3 BOM bytes and preserves the content
    const char* utf8WithBOM = "\xEF\xBB\xBFNotepad++ UTF-8 with BOM content";
    size_t inLen = strlen(utf8WithBOM);
    char buf[128];
    memcpy(buf, utf8WithBOM, inLen);

    Utf8_16_Read reader;
    size_t convertedSize = reader.convert(buf, inLen);
    TEST_ASSERT_EQ(reader.getEncoding(), uniUTF8);
    TEST_ASSERT_EQ(convertedSize, inLen - 3);

    std::string result(reader.getNewBuf(), reader.getNewSize());
    TEST_ASSERT_STR_EQ(result.c_str(), "Notepad++ UTF-8 with BOM content");
}

TEST_CASE(Utf8_16Encoding, Utf8_16_Write_Convert) {
    const char* utf8Input = "Write Test String 123";
    size_t inputLen = strlen(utf8Input);
    char inBuf[128];
    memcpy(inBuf, utf8Input, inputLen);

    // 1. Write as UTF-16 LE
    {
        Utf8_16_Write writer;
        writer.setEncoding(uni16LE);
        size_t writtenSize = writer.convert(inBuf, inputLen);
        TEST_ASSERT_EQ(writtenSize, 2 + inputLen * 2); // 2 bytes BOM + 2 bytes per char
        const unsigned char* out = reinterpret_cast<const unsigned char*>(writer.getNewBuf());
        // Verify BOM
        TEST_ASSERT_EQ(out[0], 0xFF);
        TEST_ASSERT_EQ(out[1], 0xFE);
        // Verify first char 'W' (0x0057)
        TEST_ASSERT_EQ(out[2], 'W');
        TEST_ASSERT_EQ(out[3], 0x00);
    }

    // 2. Write as UTF-16 BE
    {
        Utf8_16_Write writer;
        writer.setEncoding(uni16BE);
        size_t writtenSize = writer.convert(inBuf, inputLen);
        TEST_ASSERT_EQ(writtenSize, 2 + inputLen * 2);
        const unsigned char* out = reinterpret_cast<const unsigned char*>(writer.getNewBuf());
        // Verify BOM
        TEST_ASSERT_EQ(out[0], 0xFE);
        TEST_ASSERT_EQ(out[1], 0xFF);
        // Verify first char 'W'
        TEST_ASSERT_EQ(out[2], 0x00);
        TEST_ASSERT_EQ(out[3], 'W');
    }

    // 3. Write as UTF-8 with BOM
    {
        Utf8_16_Write writer;
        writer.setEncoding(uniUTF8);
        size_t writtenSize = writer.convert(inBuf, inputLen);
        TEST_ASSERT_EQ(writtenSize, 3 + inputLen);
        const unsigned char* out = reinterpret_cast<const unsigned char*>(writer.getNewBuf());
        TEST_ASSERT_EQ(out[0], 0xEF);
        TEST_ASSERT_EQ(out[1], 0xBB);
        TEST_ASSERT_EQ(out[2], 0xBF);
        TEST_ASSERT_STR_EQ(reinterpret_cast<const char*>(out + 3), utf8Input);
    }
}

TEST_CASE(Utf8_16Encoding, Iterators) {
    // Utf8_Iter: reads UTF-8 and generates UTF-16 code units
    const unsigned char utf8Text[] = "A\xC3\xA9\xE2\x82\xAC"; // 'A' (1 byte), 'é' (2 bytes), '€' (3 bytes)
    Utf8_Iter iter8;
    iter8.set(utf8Text, sizeof(utf8Text) - 1, uniUTF8_NoBOM);

    std::vector<Utf8_16::utf16> units16;
    while (iter8) {
        Utf8_16::utf16 u16 = 0;
        if (iter8.get(&u16)) {
            units16.push_back(u16);
        }
        ++iter8;
    }

    TEST_ASSERT_EQ(units16.size(), 3u);
    TEST_ASSERT_EQ(units16[0], static_cast<Utf8_16::utf16>('A'));
    TEST_ASSERT_EQ(units16[1], static_cast<Utf8_16::utf16>(0x00E9)); // é
    TEST_ASSERT_EQ(units16[2], static_cast<Utf8_16::utf16>(0x20AC)); // €
}

// ============================================================================
// 2. uchardet Charset Detection Tests
// ============================================================================

TEST_CASE(UchardetDetection, UTF8Detection) {
    uchardet_t ud = uchardet_new();
    TEST_ASSERT_NOT_NULL(ud);

    // Multilingual UTF-8 text
    std::string text = "Notepad++ for macOS supports native rendering, text buffers, and UTF-8 encoding. "
                       "Voici du texte en français avec des accents: été, naïve, où, château. "
                       "Русский текст для проверки кодировки Юникод UTF-8. "
                       "这是一段用于测试字符集检测的简体中文文本。";

    int res = uchardet_handle_data(ud, text.data(), text.size());
    TEST_ASSERT_EQ(res, 0);
    uchardet_data_end(ud);

    const char* charset = uchardet_get_charset(ud);
    TEST_ASSERT_NOT_NULL(charset);
    TEST_ASSERT_STR_EQ(charset, "UTF-8");

    uchardet_delete(ud);
}

TEST_CASE(UchardetDetection, JapaneseShiftJISDetection) {
    uchardet_t ud = uchardet_new();
    TEST_ASSERT_NOT_NULL(ud);

    // Japanese Shift-JIS encoded bytes for "日本語のテスト文章です。Notepad++ macOS移植版"
    const unsigned char sjisData[] = {
        0x93, 0xfa, 0x96, 0x7b, 0x8c, 0xea, 0x8e, 0x9e, 0x82, 0xcc, 0x83, 0x65, 0x83, 0x58,
        0x83, 0x67, 0x95, 0xb6, 0x8f, 0xcd, 0x82, 0xc5, 0x82, 0xb7, 0x81, 0x42,
        'N', 'o', 't', 'e', 'p', 'a', 'd', '+', '+', ' ',
        0x88, 0xda, 0x90, 0x41, 0x94, 0xc5, 0x82, 0xcc, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67
    };

    uchardet_handle_data(ud, reinterpret_cast<const char*>(sjisData), sizeof(sjisData));
    uchardet_data_end(ud);

    const char* charset = uchardet_get_charset(ud);
    TEST_ASSERT_NOT_NULL(charset);
    TEST_ASSERT_TRUE(strcmp(charset, "Shift_JIS") == 0 || strcmp(charset, "Shift-JIS") == 0 || strcmp(charset, "CP932") == 0 || strcmp(charset, "SJIS") == 0);

    uchardet_delete(ud);
}

TEST_CASE(UchardetDetection, KoreanEUC_KRDetection) {
    uchardet_t ud = uchardet_new();
    TEST_ASSERT_NOT_NULL(ud);

    // Korean EUC-KR encoded bytes for "안녕하세요 노드패드++ 맥OS 포팅 버전입니다."
    const unsigned char euckrData[] = {
        0xbe, 0xc8, 0xb3, 0xe7, 0xc7, 0xcf, 0xbc, 0xbc, 0xbf, 0xe4, ' ',
        0xb3, 0xeb, 0xc6, 0xd0, 0xb5, 0xe5, '+', '+', ' ',
        0xb8, 0xcf, 0x4f, 0x53, ' ', 0xc6, 0xf7, 0xc3, 0xc3, ' ',
        0xb9, 0xf6, 0xc0, 0xfc, 0xc0, 0xd4, 0xb4, 0xcf, 0xb4, 0xd9, 0xa1, 0xa4
    };

    uchardet_handle_data(ud, reinterpret_cast<const char*>(euckrData), sizeof(euckrData));
    uchardet_data_end(ud);

    const char* charset = uchardet_get_charset(ud);
    TEST_ASSERT_NOT_NULL(charset);
    TEST_ASSERT_TRUE(strcmp(charset, "EUC-KR") == 0 || strcmp(charset, "windows-949") == 0 || strcmp(charset, "CP949") == 0 || strcmp(charset, "EUC_KR") == 0);

    uchardet_delete(ud);
}

TEST_CASE(UchardetDetection, Big5Detection) {
    uchardet_t ud = uchardet_new();
    TEST_ASSERT_NOT_NULL(ud);

    // Traditional Chinese Big5 encoded bytes
    const unsigned char big5Data[] = {
        0xb3, 0x6f, 0xac, 0x4f, 0xb4, 0xfa, 0xb8, 0xd5, 0xa4, 0xa4, 0xa4, 0xe5,
        0xa7, 0xb9, 0xbe, 0xe3, 0xbc, 0xd0, 0xb7, 0xc7, 0xaa, 0xa9, 0xa5, 0xbb,
        0xa4, 0xba, 0xae, 0x65, 0xa1, 0x41, 0xa5, 0xce, 0xa9, 0xf3, 0xb4, 0xfa,
        0xb8, 0xd5, 0xb1, 0x60, 0xa5, 0xce, 0xaa, 0xba, 0x62, 0x69, 0x67, 0x35
    };

    uchardet_handle_data(ud, reinterpret_cast<const char*>(big5Data), sizeof(big5Data));
    uchardet_data_end(ud);

    const char* charset = uchardet_get_charset(ud);
    TEST_ASSERT_NOT_NULL(charset);
    TEST_ASSERT_TRUE(strcmp(charset, "Big5") == 0 || strcmp(charset, "BIG5") == 0 || strcmp(charset, "CP950") == 0);

    uchardet_delete(ud);
}

TEST_CASE(UchardetDetection, ResetAndReuse) {
    uchardet_t ud = uchardet_new();
    TEST_ASSERT_NOT_NULL(ud);

    // First run: UTF-8
    std::string utf8Str = "Première exécution en français avec caractères UTF-8.";
    uchardet_handle_data(ud, utf8Str.data(), utf8Str.size());
    uchardet_data_end(ud);
    TEST_ASSERT_STR_EQ(uchardet_get_charset(ud), "UTF-8");

    // Reset detector
    uchardet_reset(ud);

    // Second run: Pure ASCII
    const char* asciiStr = "Plain simple ASCII text without non-ascii bytes.";
    uchardet_handle_data(ud, asciiStr, strlen(asciiStr));
    uchardet_data_end(ud);
    const char* asciiCharset = uchardet_get_charset(ud);
    // uchardet returns "" or "ASCII" for pure ASCII
    TEST_ASSERT_TRUE(asciiCharset[0] == '\0' || strcmp(asciiCharset, "ASCII") == 0 || strcmp(asciiCharset, "UTF-8") == 0);

    uchardet_delete(ud);
}

// ============================================================================
// 3. EncodingMapper Tests
// ============================================================================

TEST_CASE(EncodingMapperSuite, AliasLookups) {
    EncodingMapper& mapper = EncodingMapper::getInstance();

    // Standard UTF-8 lookup
    int cpUtf8 = mapper.getEncodingFromString("UTF-8");
    TEST_ASSERT_EQ(cpUtf8, 65001);

    // Windows-1252 / ANSI lookup
    int cp1252 = mapper.getEncodingFromString("windows-1252");
    TEST_ASSERT_EQ(cp1252, 1252);

    // Shift_JIS lookup
    int cp932 = mapper.getEncodingFromString("Shift_JIS");
    TEST_ASSERT_EQ(cp932, 932);

    // Big5 lookup
    int cp950 = mapper.getEncodingFromString("Big5");
    TEST_ASSERT_EQ(cp950, 950);

    // EUC-KR lookup
    int cp949 = mapper.getEncodingFromString("EUC-KR");
    TEST_ASSERT_EQ(cp949, 51949);

    // GB2312 lookup
    int cp936 = mapper.getEncodingFromString("GB2312");
    TEST_ASSERT_EQ(cp936, 936);

    // ISO-8859-1 lookup
    int cp28591 = mapper.getEncodingFromString("ISO-8859-1");
    TEST_ASSERT_EQ(cp28591, 28591);

    // Windows-1251 (Cyrillic) lookup
    int cp1251 = mapper.getEncodingFromString("windows-1251");
    TEST_ASSERT_EQ(cp1251, 1251);

    // Case insensitivity of alias search
    int cpLowerUtf8 = mapper.getEncodingFromString("utf-8");
    TEST_ASSERT_EQ(cpLowerUtf8, 65001);

    // Unknown alias returns -1 or 0
    int cpUnknown = mapper.getEncodingFromString("non_existent_charset_xyz");
    TEST_ASSERT_EQ(cpUnknown, -1);
}

TEST_CASE(EncodingMapperSuite, IndexAndEncodingMapping) {
    EncodingMapper& mapper = EncodingMapper::getInstance();

    int enc0 = mapper.getEncodingFromIndex(0);
    TEST_ASSERT_GT(enc0, 0);

    int idx = mapper.getIndexFromEncoding(enc0);
    TEST_ASSERT_EQ(idx, 0);

    // Bidirectional consistency for several standard codepages
    int idx1252 = mapper.getIndexFromEncoding(1252);
    if (idx1252 >= 0) {
        TEST_ASSERT_EQ(mapper.getEncodingFromIndex(idx1252), 1252);
    }

    int idxUtf8 = mapper.getIndexFromEncoding(65001);
    if (idxUtf8 >= 0) {
        TEST_ASSERT_EQ(mapper.getEncodingFromIndex(idxUtf8), 65001);
    }
}
