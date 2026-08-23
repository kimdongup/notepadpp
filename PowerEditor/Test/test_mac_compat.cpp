// PowerEditor/Test/test_mac_compat.cpp
// Comprehensive test suite for macOS Win32 compatibility layer (mac_compat.cpp)

#include "test_framework.h"
#include "mac_compat.h"

#include <vector>
#include <string>
#include <atomic>
#include <thread>
#include <chrono>

// ============================================================================
// 1. String & Unicode Helper Tests
// ============================================================================

TEST_CASE(MacCompatString, Utf8WStringConversions) {
    // ASCII conversion
    std::string ascii = "Hello, Notepad++ macOS!";
    std::wstring wAscii = utf8_to_wstring(ascii);
    TEST_ASSERT_WSTR_EQ(wAscii.c_str(), L"Hello, Notepad++ macOS!");
    std::string backAscii = wstring_to_utf8(wAscii);
    TEST_ASSERT_STR_EQ(backAscii.c_str(), ascii.c_str());

    // Empty string
    TEST_ASSERT_TRUE(wstring_to_utf8(L"").empty());
    TEST_ASSERT_TRUE(utf8_to_wstring("").empty());

    // Multilingual UTF-8 (Greek, Cyrillic, Chinese, Japanese, Korean)
    std::string multiLang = "Ελληνικά | Русский | 中文测试 | 日本語テキスト | 한국어 테스트";
    std::wstring wMulti = utf8_to_wstring(multiLang);
    TEST_ASSERT_FALSE(wMulti.empty());
    std::string backMulti = wstring_to_utf8(wMulti);
    TEST_ASSERT_STR_EQ(backMulti.c_str(), multiLang.c_str());

    // 4-byte UTF-8 emojis (Code points > 0x10000)
    std::string emojiStr = "🚀 Notepad++ on Mac 💻 🎉 ✨";
    std::wstring wEmoji = utf8_to_wstring(emojiStr);
    std::string backEmoji = wstring_to_utf8(wEmoji);
    TEST_ASSERT_STR_EQ(backEmoji.c_str(), emojiStr.c_str());
}

TEST_CASE(MacCompatString, MultiByteToWideChar) {
    const char* utf8Text = "Notepad++ Mac Port";
    
    // Query required buffer length (including null terminator)
    int reqLen = MultiByteToWideChar(CP_UTF8, 0, utf8Text, -1, nullptr, 0);
    TEST_ASSERT_EQ(reqLen, static_cast<int>(strlen(utf8Text) + 1));

    // Convert with null termination
    wchar_t wbuf[64] = {0};
    int written = MultiByteToWideChar(CP_UTF8, 0, utf8Text, -1, wbuf, 64);
    TEST_ASSERT_EQ(written, reqLen);
    TEST_ASSERT_WSTR_EQ(wbuf, L"Notepad++ Mac Port");

    // Convert specific length without null terminator
    wchar_t wbuf2[64] = {0};
    int written2 = MultiByteToWideChar(CP_UTF8, 0, utf8Text, 7, wbuf2, 64);
    TEST_ASSERT_EQ(written2, 7);
    wbuf2[7] = L'\0';
    TEST_ASSERT_WSTR_EQ(wbuf2, L"Notepad");
}

TEST_CASE(MacCompatString, WideCharToMultiByte) {
    const wchar_t* wText = L"Native Cocoa Scintilla";

    // Query required length
    int reqLen = WideCharToMultiByte(CP_UTF8, 0, wText, -1, nullptr, 0, nullptr, nullptr);
    TEST_ASSERT_EQ(reqLen, static_cast<int>(wcslen(wText) + 1));

    // Convert with null termination
    char cbuf[64] = {0};
    int written = WideCharToMultiByte(CP_UTF8, 0, wText, -1, cbuf, 64, nullptr, nullptr);
    TEST_ASSERT_EQ(written, reqLen);
    TEST_ASSERT_STR_EQ(cbuf, "Native Cocoa Scintilla");

    // Convert specific length
    char cbuf2[64] = {0};
    int written2 = WideCharToMultiByte(CP_UTF8, 0, wText, 6, cbuf2, 64, nullptr, nullptr);
    TEST_ASSERT_EQ(written2, 6);
    cbuf2[6] = '\0';
    TEST_ASSERT_STR_EQ(cbuf2, "Native");
}

TEST_CASE(MacCompatString, CaseInsensitiveComparisons) {
    // _wcsicmp
    TEST_ASSERT_EQ(_wcsicmp(L"notepad++", L"NOTEPAD++"), 0);
    TEST_ASSERT_EQ(_wcsicmp(L"CaseSensitive", L"casesensitive"), 0);
    TEST_ASSERT_NE(_wcsicmp(L"apple", L"banana"), 0);

    // _wcsnicmp
    TEST_ASSERT_EQ(_wcsnicmp(L"Notepad_v8.8.0", L"NOTEPAD_v9.0.0", 8), 0);
    TEST_ASSERT_NE(_wcsnicmp(L"Notepad_v8", L"Notepad_v9", 10), 0);

    // _stricmp
    TEST_ASSERT_EQ(_stricmp("scintilla", "SCINTILLA"), 0);
    TEST_ASSERT_EQ(_stricmp("Document1.txt", "document1.txt"), 0);
    TEST_ASSERT_NE(_stricmp("alpha", "beta"), 0);

    // _strnicmp
    TEST_ASSERT_EQ(_strnicmp("LexillaLexer", "lexillalib", 7), 0);
    TEST_ASSERT_NE(_strnicmp("LexillaLexer", "lexillalib", 10), 0);
}

TEST_CASE(MacCompatString, SafeStringFunctions) {
    // wcscpy_s
    wchar_t dest[32] = {0};
    int err = wcscpy_s(dest, 32, L"Test String");
    TEST_ASSERT_EQ(err, 0);
    TEST_ASSERT_WSTR_EQ(dest, L"Test String");

    // Buffer overflow check
    wchar_t smallDest[5] = {0};
    int errOverflow = wcscpy_s(smallDest, 5, L"TooLongString");
    TEST_ASSERT_NE(errOverflow, 0);

    // wcscat_s
    wchar_t catDest[32] = L"Hello ";
    int errCat = wcscat_s(catDest, 32, L"World");
    TEST_ASSERT_EQ(errCat, 0);
    TEST_ASSERT_WSTR_EQ(catDest, L"Hello World");

    // wcsncpy_s
    wchar_t nDest[16] = {0};
    int errN = wcsncpy_s(nDest, 16, L"Universal", 4);
    TEST_ASSERT_EQ(errN, 0);
    TEST_ASSERT_WSTR_EQ(nDest, L"Univ");

    // swprintf_s & sprintf_s
    wchar_t swBuf[64] = {0};
    swprintf_s(swBuf, 64, L"Doc %d of %ls", 5, L"Total");
    TEST_ASSERT_WSTR_EQ(swBuf, L"Doc 5 of Total");

    char sBuf[64] = {0};
    sprintf_s(sBuf, 64, "Size: %zu bytes (0x%X)", (size_t)1024, 0x400);
    TEST_ASSERT_STR_EQ(sBuf, "Size: 1024 bytes (0x400)");

    // wsprintfW & wsprintfA
    wchar_t wout[64] = {0};
    wsprintfW(wout, L"Code: %d", 42);
    TEST_ASSERT_WSTR_EQ(wout, L"Code: 42");

    char aout[64] = {0};
    wsprintfA(aout, "Value: %s", "Pass");
    TEST_ASSERT_STR_EQ(aout, "Value: Pass");
}

TEST_CASE(MacCompatString, SplitPathAndMakePath) {
    const char* fullPathA = "/Users/developer/notepadpp/PowerEditor/src/mac_main.mm";
    char dirA[256] = {0}, fnameA[64] = {0}, extA[32] = {0};
    int resA = _splitpath_s(fullPathA, nullptr, 0, dirA, 256, fnameA, 64, extA, 32);
    TEST_ASSERT_EQ(resA, 0);
    TEST_ASSERT_STR_EQ(dirA, "/Users/developer/notepadpp/PowerEditor/src/");
    TEST_ASSERT_STR_EQ(fnameA, "mac_main");
    TEST_ASSERT_STR_EQ(extA, ".mm");

    const wchar_t* fullPathW = L"/tmp/test_dir/config.xml";
    wchar_t dirW[256] = {0}, fnameW[64] = {0}, extW[32] = {0};
    int resW = _wsplitpath_s(fullPathW, nullptr, 0, dirW, 256, fnameW, 64, extW, 32);
    TEST_ASSERT_EQ(resW, 0);
    TEST_ASSERT_WSTR_EQ(dirW, L"/tmp/test_dir/");
    TEST_ASSERT_WSTR_EQ(fnameW, L"config");
    TEST_ASSERT_WSTR_EQ(extW, L".xml");

    // Reconstruct with _wmakepath_s
    wchar_t combinedW[512] = {0};
    int resMake = _wmakepath_s(combinedW, 512, nullptr, dirW, fnameW, extW);
    TEST_ASSERT_EQ(resMake, 0);
    TEST_ASSERT_WSTR_EQ(combinedW, fullPathW);
}

// ============================================================================
// 2. Win32 File I/O Tests
// ============================================================================

TEST_CASE(MacCompatFileIO, CreateWriteReadFile) {
    std::wstring testFile = L"/tmp/npp_test_io_" + std::to_wstring(GetTickCount()) + L".tmp";

    // 1. Create and Write
    HANDLE hFile = CreateFileW(testFile.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    TEST_ASSERT_NOT_NULL(hFile);
    TEST_ASSERT_NE(hFile, INVALID_HANDLE_VALUE);

    const char* sampleData = "Hello Notepad++ macOS Win32 File I/O Test!\nLine 2 with data.";
    DWORD len = static_cast<DWORD>(strlen(sampleData));
    DWORD bytesWritten = 0;
    BOOL writeOk = WriteFile(hFile, sampleData, len, &bytesWritten, nullptr);
    TEST_ASSERT_TRUE(writeOk);
    TEST_ASSERT_EQ(bytesWritten, len);

    // Flush and Get Size
    FlushFileBuffers(hFile);
    DWORD fileSize = GetFileSize(hFile, nullptr);
    TEST_ASSERT_EQ(fileSize, len);

    LARGE_INTEGER liSize{};
    BOOL sizeExOk = GetFileSizeEx(hFile, &liSize);
    TEST_ASSERT_TRUE(sizeExOk);
    TEST_ASSERT_EQ(static_cast<DWORD>(liSize.QuadPart), len);

    CloseHandle(hFile);

    // 2. Open Existing and Read
    HANDLE hRead = CreateFileW(testFile.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    TEST_ASSERT_NE(hRead, INVALID_HANDLE_VALUE);

    char readBuf[128] = {0};
    DWORD bytesRead = 0;
    BOOL readOk = ReadFile(hRead, readBuf, sizeof(readBuf) - 1, &bytesRead, nullptr);
    TEST_ASSERT_TRUE(readOk);
    TEST_ASSERT_EQ(bytesRead, len);
    readBuf[bytesRead] = '\0';
    TEST_ASSERT_STR_EQ(readBuf, sampleData);

    // 3. SetFilePointer
    DWORD newPos = SetFilePointer(hRead, 6, nullptr, FILE_BEGIN);
    TEST_ASSERT_EQ(newPos, 6u);
    char partialBuf[16] = {0};
    ReadFile(hRead, partialBuf, 9, &bytesRead, nullptr);
    partialBuf[bytesRead] = '\0';
    TEST_ASSERT_STR_EQ(partialBuf, "Notepad++");

    CloseHandle(hRead);

    // Clean up
    DeleteFileW(testFile.c_str());
    TEST_ASSERT_FALSE(PathFileExistsW(testFile.c_str()));
}

TEST_CASE(MacCompatFileIO, CreationDispositions) {
    std::wstring tempFile = L"/tmp/npp_test_disp_" + std::to_wstring(GetTickCount()) + L".tmp";

    // CREATE_NEW on fresh file -> should succeed
    HANDLE h1 = CreateFileW(tempFile.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    TEST_ASSERT_NE(h1, INVALID_HANDLE_VALUE);
    CloseHandle(h1);

    // CREATE_NEW on existing file -> should fail with ERROR_ALREADY_EXISTS
    HANDLE h2 = CreateFileW(tempFile.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    TEST_ASSERT_EQ(h2, INVALID_HANDLE_VALUE);
    TEST_ASSERT_EQ(GetLastError(), static_cast<DWORD>(ERROR_ALREADY_EXISTS));

    // OPEN_ALWAYS on existing file -> should succeed
    HANDLE h3 = CreateFileW(tempFile.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    TEST_ASSERT_NE(h3, INVALID_HANDLE_VALUE);
    CloseHandle(h3);

    // OPEN_EXISTING on non-existent file -> should fail with ERROR_FILE_NOT_FOUND
    DeleteFileW(tempFile.c_str());
    HANDLE h4 = CreateFileW(tempFile.c_str(), GENERIC_READ, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    TEST_ASSERT_EQ(h4, INVALID_HANDLE_VALUE);
    TEST_ASSERT_EQ(GetLastError(), static_cast<DWORD>(ERROR_FILE_NOT_FOUND));
}

TEST_CASE(MacCompatFileIO, CopyAndMoveFile) {
    std::wstring src = L"/tmp/npp_test_src_" + std::to_wstring(GetTickCount()) + L".txt";
    std::wstring dst = L"/tmp/npp_test_dst_" + std::to_wstring(GetTickCount()) + L".txt";
    std::wstring moved = L"/tmp/npp_test_moved_" + std::to_wstring(GetTickCount()) + L".txt";

    // Create source file
    HANDLE hSrc = CreateFileW(src.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    const char* content = "Source file payload for copy/move testing";
    DWORD written = 0;
    WriteFile(hSrc, content, static_cast<DWORD>(strlen(content)), &written, nullptr);
    CloseHandle(hSrc);

    // Copy file
    BOOL copyRes = CopyFileW(src.c_str(), dst.c_str(), FALSE);
    TEST_ASSERT_TRUE(copyRes);
    TEST_ASSERT_TRUE(PathFileExistsW(dst.c_str()));

    // Move file
    BOOL moveRes = MoveFileW(dst.c_str(), moved.c_str());
    TEST_ASSERT_TRUE(moveRes);
    TEST_ASSERT_FALSE(PathFileExistsW(dst.c_str()));
    TEST_ASSERT_TRUE(PathFileExistsW(moved.c_str()));

    // Clean up
    DeleteFileW(src.c_str());
    DeleteFileW(moved.c_str());
}

// ============================================================================
// 3. File Attributes, Timestamps & Directory Operations
// ============================================================================

TEST_CASE(MacCompatFilesystem, FileAttributesAndTimestamps) {
    std::wstring testFile = L"/tmp/npp_test_attr_" + std::to_wstring(GetTickCount()) + L".txt";
    HANDLE h = CreateFileW(testFile.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    const char* dummy = "Attribute Test";
    DWORD bw = 0;
    WriteFile(h, dummy, static_cast<DWORD>(strlen(dummy)), &bw, nullptr);

    // FileTime
    FILETIME ftCreate{}, ftAccess{}, ftWrite{};
    BOOL gtRes = GetFileTime(h, &ftCreate, &ftAccess, &ftWrite);
    TEST_ASSERT_TRUE(gtRes);
    TEST_ASSERT_GT(ftWrite.dwLowDateTime, 0u);

    SYSTEMTIME st{};
    BOOL stRes = FileTimeToSystemTime(&ftWrite, &st);
    TEST_ASSERT_TRUE(stRes);
    TEST_ASSERT_GE(st.wYear, 2024);
    TEST_ASSERT_GE(st.wMonth, 1);
    TEST_ASSERT_LE(st.wMonth, 12);

    FILETIME ftBack{};
    BOOL ftRes = SystemTimeToFileTime(&st, &ftBack);
    TEST_ASSERT_TRUE(ftRes);

    CloseHandle(h);

    // GetFileAttributesW
    DWORD attrs = GetFileAttributesW(testFile.c_str());
    TEST_ASSERT_NE(attrs, INVALID_FILE_ATTRIBUTES);
    TEST_ASSERT_FALSE((attrs & FILE_ATTRIBUTE_DIRECTORY) != 0);

    // WIN32_FILE_ATTRIBUTE_DATA
    WIN32_FILE_ATTRIBUTE_DATA attrData{};
    BOOL gfaEx = GetFileAttributesExW(testFile.c_str(), 0, &attrData);
    TEST_ASSERT_TRUE(gfaEx);
    TEST_ASSERT_EQ(attrData.nFileSizeLow, static_cast<DWORD>(strlen(dummy)));

    DeleteFileW(testFile.c_str());
}

TEST_CASE(MacCompatFilesystem, DirectoryOperationsAndListing) {
    std::wstring tempDir = L"/tmp/npp_test_dir_" + std::to_wstring(GetTickCount());
    
    // CreateDirectoryW
    BOOL mkOk = CreateDirectoryW(tempDir.c_str(), nullptr);
    TEST_ASSERT_TRUE(mkOk);
    TEST_ASSERT_TRUE(PathIsDirectoryW(tempDir.c_str()));

    // Create 3 files in directory: test1.txt, test2.log, test3.txt
    std::wstring f1 = tempDir + L"/item1.txt";
    std::wstring f2 = tempDir + L"/item2.log";
    std::wstring f3 = tempDir + L"/item3.txt";

    HANDLE h1 = CreateFileW(f1.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    HANDLE h2 = CreateFileW(f2.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    HANDLE h3 = CreateFileW(f3.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    CloseHandle(h1);
    CloseHandle(h2);
    CloseHandle(h3);

    // FindFirstFileW / FindNextFileW with pattern *.txt
    std::wstring searchPattern = tempDir + L"/*.txt";
    WIN32_FIND_DATAW fd{};
    HANDLE hFind = FindFirstFileW(searchPattern.c_str(), &fd);
    TEST_ASSERT_NE(hFind, INVALID_HANDLE_VALUE);

    std::vector<std::wstring> foundTxtFiles;
    do {
        std::wstring name = fd.cFileName;
        if (name != L"." && name != L"..") {
            foundTxtFiles.push_back(name);
        }
    } while (FindNextFileW(hFind, &fd));

    FindClose(hFind);

    TEST_ASSERT_EQ(foundTxtFiles.size(), 2u);

    // Clean up files and directory
    DeleteFileW(f1.c_str());
    DeleteFileW(f2.c_str());
    DeleteFileW(f3.c_str());
    BOOL rmOk = RemoveDirectoryW(tempDir.c_str());
    TEST_ASSERT_TRUE(rmOk);
    TEST_ASSERT_FALSE(PathFileExistsW(tempDir.c_str()));
}

TEST_CASE(MacCompatFilesystem, ShlwapiPathUtilities) {
    // PathRemoveFileSpecW
    wchar_t path1[256] = L"/Users/test/workspace/file.txt";
    BOOL remRes = PathRemoveFileSpecW(path1);
    TEST_ASSERT_TRUE(remRes);
    TEST_ASSERT_WSTR_EQ(path1, L"/Users/test/workspace");

    // PathCombineW
    wchar_t combined[256] = {0};
    PathCombineW(combined, L"/usr/local", L"bin/notepad++");
    TEST_ASSERT_WSTR_EQ(combined, L"/usr/local/bin/notepad++");

    // PathFindFileNameW
    const wchar_t* fileName = PathFindFileNameW(L"/Applications/Notepad++.app/Contents/MacOS/notepad++");
    TEST_ASSERT_WSTR_EQ(fileName, L"notepad++");

    // PathFindExtensionW
    const wchar_t* ext1 = PathFindExtensionW(L"test_file.cpp");
    TEST_ASSERT_WSTR_EQ(ext1, L".cpp");
    const wchar_t* ext2 = PathFindExtensionW(L"no_ext_file");
    TEST_ASSERT_WSTR_EQ(ext2, L"");

    // PathIsRelativeW
    TEST_ASSERT_TRUE(PathIsRelativeW(L"relative/path/to/file.txt"));
    TEST_ASSERT_FALSE(PathIsRelativeW(L"/absolute/path/to/file.txt"));

    // PathAppendW
    wchar_t appendBuf[256] = L"/var/log";
    PathAppendW(appendBuf, L"notepad++.log");
    TEST_ASSERT_WSTR_EQ(appendBuf, L"/var/log/notepad++.log");

    // PathMatchSpecW
    TEST_ASSERT_TRUE(PathMatchSpecW(L"document.cpp", L"*.cpp"));
    TEST_ASSERT_TRUE(PathMatchSpecW(L"README.MD", L"*.md")); // Case insensitive
    TEST_ASSERT_TRUE(PathMatchSpecW(L"build_mac.sh", L"build_*"));
    TEST_ASSERT_FALSE(PathMatchSpecW(L"document.cpp", L"*.py"));

    // PathStripPathW
    wchar_t stripBuf[256] = L"/path/to/source.hpp";
    PathStripPathW(stripBuf);
    TEST_ASSERT_WSTR_EQ(stripBuf, L"source.hpp");

    // SHGetFolderPathW (macOS standard CSIDL mappings)
    wchar_t appDataPath[MAX_PATH] = {0};
    HRESULT hr1 = SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appDataPath);
    TEST_ASSERT_EQ(hr1, S_OK);
    std::string appDataStr = wstring_to_utf8(appDataPath);
    TEST_ASSERT_TRUE(appDataStr.find("Library/Application Support/Notepad++") != std::string::npos);

    wchar_t docsPath[MAX_PATH] = {0};
    HRESULT hr2 = SHGetFolderPathW(nullptr, CSIDL_PERSONAL, nullptr, 0, docsPath);
    TEST_ASSERT_EQ(hr2, S_OK);
    std::string docsStr = wstring_to_utf8(docsPath);
    TEST_ASSERT_TRUE(docsStr.find("Documents") != std::string::npos);

    wchar_t progPath[MAX_PATH] = {0};
    HRESULT hr3 = SHGetFolderPathW(nullptr, CSIDL_PROGRAM_FILES, nullptr, 0, progPath);
    TEST_ASSERT_EQ(hr3, S_OK);
    TEST_ASSERT_WSTR_EQ(progPath, L"/Applications");
}

// ============================================================================
// 4. Threading & Synchronization Tests
// ============================================================================

struct ThreadSyncData {
    CRITICAL_SECTION cs;
    int counter = 0;
};

static void* WorkerThreadFunc(void* param) {
    auto* data = reinterpret_cast<ThreadSyncData*>(param);
    for (int i = 0; i < 1000; ++i) {
        EnterCriticalSection(&data->cs);
        data->counter++;
        LeaveCriticalSection(&data->cs);
    }
    return nullptr;
}

TEST_CASE(MacCompatSync, CriticalSectionAndThreads) {
    ThreadSyncData data;
    InitializeCriticalSection(&data.cs);

    // TryEnterCriticalSection
    TEST_ASSERT_TRUE(TryEnterCriticalSection(&data.cs));
    LeaveCriticalSection(&data.cs);

    // Create 4 worker threads
    const int numThreads = 4;
    HANDLE threads[numThreads];
    DWORD threadIds[numThreads];

    for (int i = 0; i < numThreads; ++i) {
        threads[i] = CreateThread(nullptr, 0, reinterpret_cast<void*>(WorkerThreadFunc), &data, 0, &threadIds[i]);
        TEST_ASSERT_NOT_NULL(threads[i]);
    }

    for (int i = 0; i < numThreads; ++i) {
        DWORD waitRes = WaitForSingleObject(threads[i], INFINITE);
        TEST_ASSERT_EQ(waitRes, static_cast<DWORD>(WAIT_OBJECT_0));
    }

    TEST_ASSERT_EQ(data.counter, numThreads * 1000);
    DeleteCriticalSection(&data.cs);

    // Process & Thread IDs
    DWORD pid = GetCurrentProcessId();
    DWORD tid = GetCurrentThreadId();
    TEST_ASSERT_GT(pid, 0u);
    TEST_ASSERT_GT(tid, 0u);
}

// ============================================================================
// 5. Memory, Clipboard, Time & System Metrics
// ============================================================================

TEST_CASE(MacCompatMisc, GlobalMemory) {
    size_t size = 256;
    HGLOBAL hMem = GlobalAlloc(GMEM_ZEROINIT, size);
    TEST_ASSERT_NOT_NULL(hMem);

    char* ptr = reinterpret_cast<char*>(GlobalLock(hMem));
    TEST_ASSERT_NOT_NULL(ptr);
    TEST_ASSERT_EQ(ptr[0], 0);

    strcpy(ptr, "Notepad++ GlobalAlloc Test Buffer");
    GlobalUnlock(hMem);

    hMem = GlobalFree(hMem);
    TEST_ASSERT_NULL(hMem);
}

TEST_CASE(MacCompatMisc, ClipboardOperations) {
    BOOL openOk = OpenClipboard(nullptr);
    TEST_ASSERT_TRUE(openOk);

    EmptyClipboard();
    const char* clipText = "Notepad++ macOS Clipboard Content";
    SetClipboardData(CF_TEXT, const_cast<char*>(clipText));

    HANDLE hData = GetClipboardData(CF_TEXT);
    TEST_ASSERT_NOT_NULL(hData);
    const char* retrieved = reinterpret_cast<const char*>(hData);
    TEST_ASSERT_STR_EQ(retrieved, clipText);

    CloseClipboard();
}

TEST_CASE(MacCompatMisc, TimeAndPerformanceCounter) {
    DWORD tick1 = GetTickCount();
    ULONGLONG tick64 = GetTickCount64();
    TEST_ASSERT_GE(tick64, static_cast<ULONGLONG>(tick1));

    LARGE_INTEGER freq{}, counter1{}, counter2{};
    BOOL freqOk = QueryPerformanceFrequency(&freq);
    TEST_ASSERT_TRUE(freqOk);
    TEST_ASSERT_GT(freq.QuadPart, 0);

    QueryPerformanceCounter(&counter1);
    Sleep(10); // 10 ms
    QueryPerformanceCounter(&counter2);
    TEST_ASSERT_GT(counter2.QuadPart, counter1.QuadPart);

    SYSTEMTIME localTime{}, sysTime{};
    GetLocalTime(&localTime);
    GetSystemTime(&sysTime);
    TEST_ASSERT_GE(localTime.wYear, 2024);
    TEST_ASSERT_GE(sysTime.wYear, 2024);

    // System metrics
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    TEST_ASSERT_GT(screenWidth, 0);
    TEST_ASSERT_GT(screenHeight, 0);
}

TEST_CASE(MacCompatMisc, ModuleAndProcessInfo) {
    wchar_t modPath[MAX_PATH] = {0};
    DWORD len = GetModuleFileNameW(nullptr, modPath, MAX_PATH);
    TEST_ASSERT_GT(len, 0);
    TEST_ASSERT_TRUE(wcsstr(modPath, L"notepad++") != nullptr || wcsstr(modPath, L"npp_tests") != nullptr || wcsstr(modPath, L"Notepad++") != nullptr);
}

