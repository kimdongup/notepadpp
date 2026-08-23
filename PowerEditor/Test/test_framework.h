// PowerEditor/Test/test_framework.h
// Comprehensive test framework for Notepad++ macOS unit tests
// Provides test registration, assertions, timing, colored output, and summary stats

#pragma once
#ifndef TEST_FRAMEWORK_H
#define TEST_FRAMEWORK_H

#include <iostream>
#include <string>
#include <vector>
#include <functional>
#include <chrono>
#include <sstream>
#include <cmath>
#include <cstring>
#include <cwchar>

namespace NppTest {

// ANSI Terminal Colors
inline const char* COLOR_RESET   = "\033[0m";
inline const char* COLOR_RED     = "\033[1;31m";
inline const char* COLOR_GREEN   = "\033[1;32m";
inline const char* COLOR_YELLOW  = "\033[1;33m";
inline const char* COLOR_BLUE    = "\033[1;34m";
inline const char* COLOR_MAGENTA = "\033[1;35m";
inline const char* COLOR_CYAN    = "\033[1;36m";
inline const char* COLOR_WHITE   = "\033[1;37m";
inline const char* COLOR_GRAY    = "\033[0;90m";

struct TestFailure {
    std::string file;
    int line;
    std::string condition;
    std::string message;
};

struct TestCaseInfo {
    std::string suiteName;
    std::string testName;
    std::function<void()> testFunc;
    bool passed = true;
    int assertionsPassed = 0;
    std::vector<TestFailure> failures;
    double durationMs = 0.0;
};

class TestRunner {
public:
    static TestRunner& getInstance() {
        static TestRunner instance;
        return instance;
    }

    void registerTest(const std::string& suiteName, const std::string& testName, std::function<void()> func) {
        TestCaseInfo info;
        info.suiteName = suiteName;
        info.testName = testName;
        info.testFunc = func;
        m_tests.push_back(info);
    }

    TestCaseInfo* getCurrentTest() {
        return m_currentTest;
    }

    void recordAssertion(bool success, const char* file, int line, const char* condition, const std::string& msg = "") {
        m_totalAssertions++;
        if (m_currentTest) {
            if (success) {
                m_currentTest->assertionsPassed++;
            } else {
                m_currentTest->passed = false;
                TestFailure fail;
                fail.file = file ? file : "";
                fail.line = line;
                fail.condition = condition ? condition : "";
                fail.message = msg;
                m_currentTest->failures.push_back(fail);
            }
        }
    }

    int run(int argc, char* argv[]) {
        std::string filter = "";

        for (int i = 1; i < argc; ++i) {
            std::string arg = argv[i];
            if (arg == "-v" || arg == "--verbose") {
                // Verbose mode enabled
            } else if (arg == "-h" || arg == "--help") {
                std::cout << "Notepad++ macOS Test Runner\n";
                std::cout << "Usage: " << argv[0] << " [options] [filter]\n";
                std::cout << "Options:\n";
                std::cout << "  -v, --verbose    Show verbose output for every test\n";
                std::cout << "  -h, --help       Show this help message\n";
                std::cout << "  [filter]         Filter tests by suite or test name substring\n";
                return 0;
            } else if (arg[0] != '-') {
                filter = arg;
            }
        }

        std::cout << COLOR_CYAN << "================================================================================" << COLOR_RESET << "\n";
        std::cout << COLOR_WHITE << "  Notepad++ macOS Unit Test Suite" << COLOR_RESET << "\n";
        std::cout << COLOR_CYAN << "================================================================================" << COLOR_RESET << "\n";

        if (!filter.empty()) {
            std::cout << COLOR_YELLOW << "Running tests matching filter: '" << filter << "'" << COLOR_RESET << "\n\n";
        } else {
            std::cout << "Running all test suites (" << m_tests.size() << " test cases registered)...\n\n";
        }

        int passedCount = 0;
        int failedCount = 0;
        int skippedCount = 0;
        auto totalStart = std::chrono::high_resolution_clock::now();

        std::string currentSuite = "";

        for (auto& test : m_tests) {
            std::string fullName = test.suiteName + "." + test.testName;
            if (!filter.empty() && fullName.find(filter) == std::string::npos &&
                test.suiteName.find(filter) == std::string::npos &&
                test.testName.find(filter) == std::string::npos) {
                skippedCount++;
                continue;
            }

            if (test.suiteName != currentSuite) {
                currentSuite = test.suiteName;
                std::cout << COLOR_MAGENTA << "▶ Suite: " << currentSuite << COLOR_RESET << "\n" << std::flush;
            }

            m_currentTest = &test;
            auto start = std::chrono::high_resolution_clock::now();

            try {
                test.testFunc();
            } catch (const std::exception& e) {
                test.passed = false;
                TestFailure fail;
                fail.file = __FILE__;
                fail.line = __LINE__;
                fail.condition = "Exception caught";
                fail.message = std::string("std::exception: ") + e.what();
                test.failures.push_back(fail);
            } catch (...) {
                test.passed = false;
                TestFailure fail;
                fail.file = __FILE__;
                fail.line = __LINE__;
                fail.condition = "Unknown exception";
                fail.message = "Caught unknown exception during test execution";
                test.failures.push_back(fail);
            }

            auto end = std::chrono::high_resolution_clock::now();
            test.durationMs = std::chrono::duration<double, std::milli>(end - start).count();

            if (test.passed) {
                passedCount++;
                std::cout << "  " << COLOR_GREEN << "✔ PASS" << COLOR_RESET << " " << test.testName
                          << " " << COLOR_GRAY << "(" << test.assertionsPassed << " asserts, "
                          << test.durationMs << " ms)" << COLOR_RESET << "\n" << std::flush;
            } else {
                failedCount++;
                std::cout << "  " << COLOR_RED << "✖ FAIL" << COLOR_RESET << " " << test.testName
                          << " " << COLOR_GRAY << "(" << test.durationMs << " ms)" << COLOR_RESET << "\n" << std::flush;
                for (const auto& f : test.failures) {
                    std::cout << "    " << COLOR_RED << "→ " << f.file << ":" << f.line << ": Assertion failed: " << f.condition << COLOR_RESET << "\n";
                    if (!f.message.empty()) {
                        std::cout << "      " << COLOR_YELLOW << f.message << COLOR_RESET << "\n";
                    }
                }
                std::cout << std::flush;
            }
        }

        auto totalEnd = std::chrono::high_resolution_clock::now();
        double totalDurationMs = std::chrono::duration<double, std::milli>(totalEnd - totalStart).count();

        std::cout << "\n" << COLOR_CYAN << "================================================================================" << COLOR_RESET << "\n";
        std::cout << COLOR_WHITE << "  Test Execution Summary" << COLOR_RESET << "\n";
        std::cout << COLOR_CYAN << "================================================================================" << COLOR_RESET << "\n";
        std::cout << "  Total Tests:       " << (passedCount + failedCount) << "\n";
        std::cout << "  Passed:            " << COLOR_GREEN << passedCount << COLOR_RESET << "\n";
        std::cout << "  Failed:            " << (failedCount > 0 ? COLOR_RED : COLOR_GREEN) << failedCount << COLOR_RESET << "\n";
        if (skippedCount > 0) {
            std::cout << "  Skipped:           " << COLOR_YELLOW << skippedCount << COLOR_RESET << "\n";
        }
        std::cout << "  Total Assertions:  " << m_totalAssertions << "\n";
        std::cout << "  Total Time:        " << totalDurationMs << " ms\n";
        std::cout << COLOR_CYAN << "================================================================================" << COLOR_RESET << "\n";

        if (failedCount == 0) {
            std::cout << COLOR_GREEN << ">>> ALL TESTS PASSED SUCCESSFULLY! <<<" << COLOR_RESET << "\n\n";
            return 0;
        } else {
            std::cout << COLOR_RED << ">>> " << failedCount << " TEST(S) FAILED! <<<" << COLOR_RESET << "\n\n";
            return 1;
        }
    }

private:
    TestRunner() = default;
    std::vector<TestCaseInfo> m_tests;
    TestCaseInfo* m_currentTest = nullptr;
    int m_totalAssertions = 0;
};

struct AutoTestRegister {
    AutoTestRegister(const std::string& suiteName, const std::string& testName, std::function<void()> func) {
        TestRunner::getInstance().registerTest(suiteName, testName, func);
    }
};

} // namespace NppTest

#define TEST_CASE(SuiteName, TestName) \
    void Test_##SuiteName##_##TestName(); \
    static ::NppTest::AutoTestRegister g_reg_##SuiteName##_##TestName(#SuiteName, #TestName, Test_##SuiteName##_##TestName); \
    void Test_##SuiteName##_##TestName()

#define TEST_ASSERT(cond) \
    do { \
        bool _res = static_cast<bool>(cond); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #cond); \
    } while(0)

#define TEST_ASSERT_MSG(cond, msg) \
    do { \
        bool _res = static_cast<bool>(cond); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #cond, msg); \
    } while(0)

#define TEST_ASSERT_TRUE(cond) TEST_ASSERT(cond)
#define TEST_ASSERT_FALSE(cond) TEST_ASSERT(!(cond))

#define TEST_ASSERT_EQ(actual, expected) \
    do { \
        auto _a = (actual); \
        auto _e = (expected); \
        bool _res = (_a == _e); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected: " << _e << ", Actual: " << _a; \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #actual " == " #expected, _ss.str()); \
    } while(0)

#define TEST_ASSERT_NE(actual, expected) \
    do { \
        auto _a = (actual); \
        auto _e = (expected); \
        bool _res = (_a != _e); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected != " << _e << ", Actual: " << _a; \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #actual " != " #expected, _ss.str()); \
    } while(0)

#define TEST_ASSERT_LT(a, b) \
    do { \
        bool _res = ((a) < (b)); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected " << (a) << " < " << (b); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #a " < " #b, _ss.str()); \
    } while(0)

#define TEST_ASSERT_LE(a, b) \
    do { \
        bool _res = ((a) <= (b)); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected " << (a) << " <= " << (b); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #a " <= " #b, _ss.str()); \
    } while(0)

#define TEST_ASSERT_GT(a, b) \
    do { \
        bool _res = ((a) > (b)); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected " << (a) << " > " << (b); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #a " > " #b, _ss.str()); \
    } while(0)

#define TEST_ASSERT_GE(a, b) \
    do { \
        bool _res = ((a) >= (b)); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected " << (a) << " >= " << (b); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #a " >= " #b, _ss.str()); \
    } while(0)

#define TEST_ASSERT_STR_EQ(actual, expected) \
    do { \
        const char* _a = (actual); \
        const char* _e = (expected); \
        bool _res = (_a != nullptr && _e != nullptr && strcmp(_a, _e) == 0); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected string: \"" << (_e ? _e : "<null>") << "\", Actual: \"" << (_a ? _a : "<null>") << "\""; \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, "strcmp(" #actual ", " #expected ") == 0", _ss.str()); \
    } while(0)

#define TEST_ASSERT_STR_NE(actual, expected) \
    do { \
        const char* _a = (actual); \
        const char* _e = (expected); \
        bool _res = (_a == nullptr || _e == nullptr || strcmp(_a, _e) != 0); \
        std::stringstream _ss; \
        if (!_res) _ss << "Expected string != \"" << (_e ? _e : "<null>") << "\""; \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, "strcmp(" #actual ", " #expected ") != 0", _ss.str()); \
    } while(0)

#define TEST_ASSERT_WSTR_EQ(actual, expected) \
    do { \
        const wchar_t* _a = (actual); \
        const wchar_t* _e = (expected); \
        bool _res = (_a != nullptr && _e != nullptr && wcscmp(_a, _e) == 0); \
        std::stringstream _ss; \
        if (!_res) _ss << "Wide string equality failed"; \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, "wcscmp(" #actual ", " #expected ") == 0", _ss.str()); \
    } while(0)

#define TEST_ASSERT_NULL(ptr) \
    do { \
        bool _res = ((ptr) == nullptr); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #ptr " == nullptr"); \
    } while(0)

#define TEST_ASSERT_NOT_NULL(ptr) \
    do { \
        bool _res = ((ptr) != nullptr); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #ptr " != nullptr"); \
    } while(0)

#define TEST_ASSERT_CONTAINS(haystack, needle) \
    do { \
        std::string _s = (haystack); \
        std::string _sub = (needle); \
        bool _res = (_s.find(_sub) != std::string::npos); \
        std::stringstream _ss; \
        if (!_res) _ss << "String \"" << _s << "\" does not contain \"" << _sub << "\""; \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #haystack " contains " #needle, _ss.str()); \
    } while(0)

#define TEST_ASSERT_WCONTAINS(whaystack, wneedle) \
    do { \
        std::wstring _ws = (whaystack); \
        std::wstring _wsub = (wneedle); \
        bool _res = (_ws.find(_wsub) != std::wstring::npos); \
        ::NppTest::TestRunner::getInstance().recordAssertion(_res, __FILE__, __LINE__, #whaystack " contains " #wneedle); \
    } while(0)

#endif // TEST_FRAMEWORK_H
