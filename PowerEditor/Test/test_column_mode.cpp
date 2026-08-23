// PowerEditor/Test/test_column_mode.cpp
// Comprehensive test suite for Notepad++ Column Mode & Column Editor algorithms

#include "test_framework.h"
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <bitset>

enum class NumFormat { Dec, Hex, Oct, Bin };
enum class NumLeading { None, Zeros, Spaces };

static std::string formatColumnNumber(long long val, NumFormat fmt, NumLeading leading, int width) {
    std::string raw;
    switch (fmt) {
        case NumFormat::Dec:
            raw = std::to_string(val);
            break;
        case NumFormat::Hex: {
            std::stringstream ss;
            ss << std::uppercase << std::hex << val;
            raw = ss.str();
            break;
        }
        case NumFormat::Oct: {
            std::stringstream ss;
            ss << std::oct << val;
            raw = ss.str();
            break;
        }
        case NumFormat::Bin: {
            std::string b = std::bitset<64>(val).to_string();
            size_t firstOne = b.find('1');
            raw = (firstOne != std::string::npos) ? b.substr(firstOne) : "0";
            break;
        }
    }

    if (leading == NumLeading::None || (int)raw.length() >= width) {
        return raw;
    }

    int padLen = width - (int)raw.length();
    char padChar = (leading == NumLeading::Zeros) ? '0' : ' ';
    return std::string(padLen, padChar) + raw;
}

// Generate sequence of numbers
static std::vector<std::string> generateColumnSequence(long long start, long long inc, int repeat, int count, NumFormat fmt, NumLeading leading, int width) {
    std::vector<std::string> res;
    long long current = start;
    int repCounter = 0;

    for (int i = 0; i < count; ++i) {
        res.push_back(formatColumnNumber(current, fmt, leading, width));
        repCounter++;
        if (repCounter >= repeat) {
            repCounter = 0;
            current += inc;
        }
    }
    return res;
}

// Simulate multi-line rectangular column insertion
static std::vector<std::string> insertTextAtColumn(const std::vector<std::string>& lines, int col, const std::string& insertText) {
    std::vector<std::string> out;
    for (const auto& line : lines) {
        if ((int)line.length() < col) {
            std::string padded = line + std::string(col - line.length(), ' ') + insertText;
            out.push_back(padded);
        } else {
            std::string modified = line.substr(0, col) + insertText + line.substr(col);
            out.push_back(modified);
        }
    }
    return out;
}

// ============================================================================
// 1. Decimal Number Formatting & Step
// ============================================================================

TEST_CASE(ColumnModeSuite, DecimalSequenceGeneration) {
    auto seq = generateColumnSequence(1, 1, 1, 5, NumFormat::Dec, NumLeading::None, 0);
    TEST_ASSERT_EQ(seq.size(), 5);
    TEST_ASSERT_STR_EQ(seq[0].c_str(), "1");
    TEST_ASSERT_STR_EQ(seq[1].c_str(), "2");
    TEST_ASSERT_STR_EQ(seq[2].c_str(), "3");
    TEST_ASSERT_STR_EQ(seq[3].c_str(), "4");
    TEST_ASSERT_STR_EQ(seq[4].c_str(), "5");

    // Start 100, Step 10
    auto seqStep = generateColumnSequence(100, 10, 1, 3, NumFormat::Dec, NumLeading::None, 0);
    TEST_ASSERT_STR_EQ(seqStep[0].c_str(), "100");
    TEST_ASSERT_STR_EQ(seqStep[1].c_str(), "110");
    TEST_ASSERT_STR_EQ(seqStep[2].c_str(), "120");
}

// ============================================================================
// 2. Hexadecimal, Octal & Binary Formats
// ============================================================================

TEST_CASE(ColumnModeSuite, HexOctBinFormats) {
    // Hex (start=10 -> A, step=2 -> C, E, 10)
    auto hexSeq = generateColumnSequence(10, 2, 1, 4, NumFormat::Hex, NumLeading::None, 0);
    TEST_ASSERT_STR_EQ(hexSeq[0].c_str(), "A");
    TEST_ASSERT_STR_EQ(hexSeq[1].c_str(), "C");
    TEST_ASSERT_STR_EQ(hexSeq[2].c_str(), "E");
    TEST_ASSERT_STR_EQ(hexSeq[3].c_str(), "10");

    // Octal (start=7, step=1 -> 7, 10, 11)
    auto octSeq = generateColumnSequence(7, 1, 1, 3, NumFormat::Oct, NumLeading::None, 0);
    TEST_ASSERT_STR_EQ(octSeq[0].c_str(), "7");
    TEST_ASSERT_STR_EQ(octSeq[1].c_str(), "10");
    TEST_ASSERT_STR_EQ(octSeq[2].c_str(), "11");

    // Binary (start=1, step=1 -> 1, 10, 11, 100)
    auto binSeq = generateColumnSequence(1, 1, 1, 4, NumFormat::Bin, NumLeading::None, 0);
    TEST_ASSERT_STR_EQ(binSeq[0].c_str(), "1");
    TEST_ASSERT_STR_EQ(binSeq[1].c_str(), "10");
    TEST_ASSERT_STR_EQ(binSeq[2].c_str(), "11");
    TEST_ASSERT_STR_EQ(binSeq[3].c_str(), "100");
}

// ============================================================================
// 3. Leading Padding & Repeat Count
// ============================================================================

TEST_CASE(ColumnModeSuite, PaddingAndRepeat) {
    // Leading Zeros (width=4, val=5 -> 0005)
    auto padZero = generateColumnSequence(5, 5, 1, 3, NumFormat::Dec, NumLeading::Zeros, 4);
    TEST_ASSERT_STR_EQ(padZero[0].c_str(), "0005");
    TEST_ASSERT_STR_EQ(padZero[1].c_str(), "0010");
    TEST_ASSERT_STR_EQ(padZero[2].c_str(), "0015");

    // Leading Spaces (width=4, val=5 -> "   5")
    auto padSpace = generateColumnSequence(5, 5, 1, 2, NumFormat::Dec, NumLeading::Spaces, 4);
    TEST_ASSERT_STR_EQ(padSpace[0].c_str(), "   5");
    TEST_ASSERT_STR_EQ(padSpace[1].c_str(), "  10");

    // Repeat count = 2 (1, 1, 2, 2, 3, 3)
    auto repSeq = generateColumnSequence(1, 1, 2, 6, NumFormat::Dec, NumLeading::None, 0);
    TEST_ASSERT_STR_EQ(repSeq[0].c_str(), "1");
    TEST_ASSERT_STR_EQ(repSeq[1].c_str(), "1");
    TEST_ASSERT_STR_EQ(repSeq[2].c_str(), "2");
    TEST_ASSERT_STR_EQ(repSeq[3].c_str(), "2");
    TEST_ASSERT_STR_EQ(repSeq[4].c_str(), "3");
    TEST_ASSERT_STR_EQ(repSeq[5].c_str(), "3");
}

// ============================================================================
// 4. Rectangular Multi-Line Text Insertion
// ============================================================================

TEST_CASE(ColumnModeSuite, RectangularColumnInsertion) {
    std::vector<std::string> lines = {
        "apple",
        "banana",
        "cherry"
    };

    // Prefix insertion at column 0
    auto resPrefix = insertTextAtColumn(lines, 0, "FRUIT_");
    TEST_ASSERT_STR_EQ(resPrefix[0].c_str(), "FRUIT_apple");
    TEST_ASSERT_STR_EQ(resPrefix[1].c_str(), "FRUIT_banana");
    TEST_ASSERT_STR_EQ(resPrefix[2].c_str(), "FRUIT_cherry");

    // Insertion at column 3
    auto resCol3 = insertTextAtColumn(lines, 3, "[#]");
    TEST_ASSERT_STR_EQ(resCol3[0].c_str(), "app[#]le");
    TEST_ASSERT_STR_EQ(resCol3[1].c_str(), "ban[#]ana");
    TEST_ASSERT_STR_EQ(resCol3[2].c_str(), "che[#]rry");
}
