// macOS platform compatibility implementation for Notepad++
// Implements Win32 APIs, string conversions, file I/O, timestamps, and windowing abstractions

#include "mac_compat.h"
#include "FileInterface.h"
#include <fnmatch.h>
#include <cstdarg>
#include <unordered_map>
#include <mutex>
#include <mach-o/dyld.h>

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#endif

static thread_local DWORD g_lastErrorCode = 0;

// ============================================================================
// String & Unicode Helpers
// ============================================================================

std::string wstring_to_utf8(const std::wstring& wstr)
{
    if (wstr.empty()) return std::string();
    std::string out;
    out.reserve(wstr.size() * 3);
    for (wchar_t wc : wstr)
    {
        uint32_t cp = static_cast<uint32_t>(wc);
        if (cp < 0x80)
        {
            out.push_back(static_cast<char>(cp));
        }
        else if (cp < 0x800)
        {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
        else if (cp < 0x10000)
        {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
        else
        {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    return out;
}

std::wstring utf8_to_wstring(const std::string& str)
{
    if (str.empty()) return std::wstring();
    std::wstring out;
    out.reserve(str.size());
    const uint8_t* p = reinterpret_cast<const uint8_t*>(str.data());
    const uint8_t* end = p + str.size();
    while (p < end)
    {
        uint32_t cp = 0;
        if (*p < 0x80)
        {
            cp = *p++;
        }
        else if ((*p & 0xE0) == 0xC0)
        {
            if (p + 1 >= end) break;
            cp = ((*p & 0x1F) << 6) | (p[1] & 0x3F);
            p += 2;
        }
        else if ((*p & 0xF0) == 0xE0)
        {
            if (p + 2 >= end) break;
            cp = ((*p & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
            p += 3;
        }
        else if ((*p & 0xF8) == 0xF0)
        {
            if (p + 3 >= end) break;
            cp = ((*p & 0x07) << 18) | ((p[1] & 0x3F) << 12) | ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
            p += 4;
        }
        else
        {
            p++;
            continue;
        }
        out.push_back(static_cast<wchar_t>(cp));
    }
    return out;
}

extern "C" {

// ============================================================================
// Error Handling
// ============================================================================

DWORD GetLastError(VOID)
{
    return g_lastErrorCode;
}

VOID SetLastError(DWORD dwErrCode)
{
    g_lastErrorCode = dwErrCode;
}

DWORD FormatMessageW(DWORD dwFlags, LPCVOID lpSource, DWORD dwMessageId, DWORD dwLanguageId, LPWSTR lpBuffer, DWORD nSize, void* Arguments)
{
    (void)dwFlags; (void)lpSource; (void)dwLanguageId; (void)Arguments;
    if (!lpBuffer || nSize == 0) return 0;
    const char* errStr = strerror(static_cast<int>(dwMessageId));
    std::wstring wErr = errStr ? utf8_to_wstring(errStr) : L"Unknown error";
    wcsncpy(lpBuffer, wErr.c_str(), nSize - 1);
    lpBuffer[nSize - 1] = L'\0';
    return static_cast<DWORD>(wcslen(lpBuffer));
}

// ============================================================================
// Codepage & MultiByte Conversions
// ============================================================================

UINT GetACP(VOID) { return CP_UTF8; }
UINT GetOEMCP(VOID) { return CP_UTF8; }
BOOL IsValidCodePage(UINT CodePage) { (void)CodePage; return TRUE; }

int MultiByteToWideChar(UINT CodePage, DWORD dwFlags, LPCSTR lpMultiByteStr, int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar)
{
    (void)CodePage; (void)dwFlags;
    if (!lpMultiByteStr) return 0;

    std::string s;
    if (cbMultiByte < 0)
    {
        s = lpMultiByteStr;
    }
    else
    {
        s.assign(lpMultiByteStr, static_cast<size_t>(cbMultiByte));
    }

    std::wstring ws = utf8_to_wstring(s);
    int requiredLen = static_cast<int>(ws.length());
    if (cbMultiByte < 0) requiredLen++; // include null terminator

    if (cchWideChar == 0)
    {
        return requiredLen;
    }

    if (!lpWideCharStr) return 0;

    int copyLen = std::min(requiredLen, cchWideChar);
    for (int i = 0; i < copyLen && i < static_cast<int>(ws.length()); ++i)
    {
        lpWideCharStr[i] = ws[i];
    }
    if (cbMultiByte < 0 && copyLen > static_cast<int>(ws.length()))
    {
        lpWideCharStr[ws.length()] = L'\0';
    }

    return copyLen;
}

int WideCharToMultiByte(UINT CodePage, DWORD dwFlags, LPCWSTR lpWideCharStr, int cchWideChar, LPSTR lpMultiByteStr, int cbMultiByte, LPCSTR lpDefaultChar, BOOL* lpUsedDefaultChar)
{
    (void)CodePage; (void)dwFlags; (void)lpDefaultChar;
    if (lpUsedDefaultChar) *lpUsedDefaultChar = FALSE;
    if (!lpWideCharStr) return 0;

    std::wstring ws;
    if (cchWideChar < 0)
    {
        ws = lpWideCharStr;
    }
    else
    {
        ws.assign(lpWideCharStr, static_cast<size_t>(cchWideChar));
    }

    std::string s = wstring_to_utf8(ws);
    int requiredLen = static_cast<int>(s.length());
    if (cchWideChar < 0) requiredLen++; // include null terminator

    if (cbMultiByte == 0)
    {
        return requiredLen;
    }

    if (!lpMultiByteStr) return 0;

    int copyLen = std::min(requiredLen, cbMultiByte);
    memcpy(lpMultiByteStr, s.c_str(), static_cast<size_t>(std::min(static_cast<int>(s.length()), copyLen)));
    if (cchWideChar < 0 && copyLen > static_cast<int>(s.length()))
    {
        lpMultiByteStr[s.length()] = '\0';
    }

    return copyLen;
}

BOOL IsTextUnicode(const void* lpv, int iSize, LPINT lpiResult)
{
    if (!lpv || iSize <= 0)
    {
        if (lpiResult) *lpiResult = 0;
        return FALSE;
    }

    const unsigned char* p = static_cast<const unsigned char*>(lpv);
    int nullOdd = 0;
    int nullEven = 0;
    int totalPairs = iSize / 2;

    for (int i = 0; i < iSize; ++i)
    {
        if (p[i] == 0)
        {
            if (i % 2 == 1) nullOdd++;
            else nullEven++;
        }
    }

    // Typical UTF-16LE text has null bytes at odd indices (for ASCII characters) and rarely at even indices
    bool isUnicode = (totalPairs > 0 && nullOdd >= (totalPairs / 3) && nullEven == 0);
    if (lpiResult)
    {
        *lpiResult = isUnicode ? (*lpiResult) : 0;
    }
    return isUnicode ? TRUE : FALSE;
}

// ============================================================================
// File Operations
// ============================================================================

struct MacFileDescriptor {
    int fd;
    std::string path;
    bool isDirectory;
};

HANDLE CreateFileW(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, void* lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile)
{
    (void)dwShareMode; (void)lpSecurityAttributes; (void)dwFlagsAndAttributes; (void)hTemplateFile;
    if (!lpFileName)
    {
        SetLastError(ERROR_PATH_NOT_FOUND);
        return INVALID_HANDLE_VALUE;
    }

    std::string path = wstring_to_utf8(lpFileName);
    int flags = 0;

    bool readAccess = (dwDesiredAccess & GENERIC_READ) != 0;
    bool writeAccess = (dwDesiredAccess & GENERIC_WRITE) != 0;

    if (readAccess && writeAccess)
        flags |= O_RDWR;
    else if (writeAccess)
        flags |= O_WRONLY;
    else
        flags |= O_RDONLY;

    switch (dwCreationDisposition)
    {
        case CREATE_ALWAYS:
            flags |= O_CREAT | O_TRUNC;
            break;
        case CREATE_NEW:
            flags |= O_CREAT | O_EXCL;
            break;
        case OPEN_ALWAYS:
            flags |= O_CREAT;
            break;
        case OPEN_EXISTING:
            break;
        case TRUNCATE_EXISTING:
            flags |= O_TRUNC;
            break;
        default:
            break;
    }

    int fd = ::open(path.c_str(), flags, 0666);
    if (fd < 0)
    {
        if (errno == ENOENT)
            SetLastError(ERROR_FILE_NOT_FOUND);
        else if (errno == EACCES)
            SetLastError(ERROR_ACCESS_DENIED);
        else if (errno == EEXIST)
            SetLastError(ERROR_ALREADY_EXISTS);
        else
            SetLastError(ERROR_INVALID_HANDLE);
        return INVALID_HANDLE_VALUE;
    }

    SetLastError(NO_ERROR);
    auto* desc = new MacFileDescriptor();
    desc->fd = fd;
    desc->path = path;
    desc->isDirectory = false;
    return reinterpret_cast<HANDLE>(desc);
}

BOOL ReadFile(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, DWORD* lpNumberOfBytesRead, void* lpOverlapped)
{
    (void)lpOverlapped;
    if (hFile == INVALID_HANDLE_VALUE || !hFile || !lpBuffer)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    ssize_t bytesRead = ::read(desc->fd, lpBuffer, nNumberOfBytesToRead);
    if (bytesRead < 0)
    {
        SetLastError(ERROR_ACCESS_DENIED);
        if (lpNumberOfBytesRead) *lpNumberOfBytesRead = 0;
        return FALSE;
    }

    if (lpNumberOfBytesRead) *lpNumberOfBytesRead = static_cast<DWORD>(bytesRead);
    SetLastError(NO_ERROR);
    return TRUE;
}

BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite, DWORD* lpNumberOfBytesWritten, void* lpOverlapped)
{
    (void)lpOverlapped;
    if (hFile == INVALID_HANDLE_VALUE || !hFile || !lpBuffer)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    ssize_t bytesWritten = ::write(desc->fd, lpBuffer, nNumberOfBytesToWrite);
    if (bytesWritten < 0)
    {
        SetLastError(ERROR_ACCESS_DENIED);
        if (lpNumberOfBytesWritten) *lpNumberOfBytesWritten = 0;
        return FALSE;
    }

    if (lpNumberOfBytesWritten) *lpNumberOfBytesWritten = static_cast<DWORD>(bytesWritten);
    SetLastError(NO_ERROR);
    return TRUE;
}

BOOL CloseHandle(HANDLE hObject)
{
    if (hObject == INVALID_HANDLE_VALUE || !hObject)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hObject);
    if (desc->fd >= 0)
    {
        ::close(desc->fd);
    }
    delete desc;
    SetLastError(NO_ERROR);
    return TRUE;
}

DWORD GetFileSize(HANDLE hFile, DWORD* lpFileSizeHigh)
{
    if (hFile == INVALID_HANDLE_VALUE || !hFile)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return static_cast<DWORD>(-1);
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    struct stat st{};
    if (::fstat(desc->fd, &st) != 0)
    {
        SetLastError(ERROR_ACCESS_DENIED);
        return static_cast<DWORD>(-1);
    }

    if (lpFileSizeHigh)
    {
        *lpFileSizeHigh = static_cast<DWORD>((st.st_size >> 32) & 0xFFFFFFFF);
    }
    return static_cast<DWORD>(st.st_size & 0xFFFFFFFF);
}

BOOL GetFileSizeEx(HANDLE hFile, LARGE_INTEGER* lpFileSize)
{
    if (hFile == INVALID_HANDLE_VALUE || !hFile || !lpFileSize)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    struct stat st{};
    if (::fstat(desc->fd, &st) != 0)
    {
        SetLastError(ERROR_ACCESS_DENIED);
        return FALSE;
    }

    lpFileSize->QuadPart = st.st_size;
    return TRUE;
}

DWORD SetFilePointer(HANDLE hFile, LONG lDistanceToMove, LONG* lpDistanceToMoveHigh, DWORD dwMoveMethod)
{
    if (hFile == INVALID_HANDLE_VALUE || !hFile)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return INVALID_SET_FILE_POINTER;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    int whence = SEEK_SET;
    if (dwMoveMethod == FILE_CURRENT) whence = SEEK_CUR;
    else if (dwMoveMethod == FILE_END) whence = SEEK_END;

    int64_t offset = lDistanceToMove;
    if (lpDistanceToMoveHigh)
    {
        offset |= (static_cast<int64_t>(*lpDistanceToMoveHigh) << 32);
    }

    off_t res = ::lseek(desc->fd, offset, whence);
    if (res == static_cast<off_t>(-1))
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return INVALID_SET_FILE_POINTER;
    }

    if (lpDistanceToMoveHigh)
    {
        *lpDistanceToMoveHigh = static_cast<LONG>((res >> 32) & 0xFFFFFFFF);
    }
    return static_cast<DWORD>(res & 0xFFFFFFFF);
}

BOOL SetFilePointerEx(HANDLE hFile, LARGE_INTEGER liDistanceToMove, LARGE_INTEGER* lpNewFilePointer, DWORD dwMoveMethod)
{
    if (hFile == INVALID_HANDLE_VALUE || !hFile)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    int whence = SEEK_SET;
    if (dwMoveMethod == FILE_CURRENT) whence = SEEK_CUR;
    else if (dwMoveMethod == FILE_END) whence = SEEK_END;

    off_t res = ::lseek(desc->fd, liDistanceToMove.QuadPart, whence);
    if (res == static_cast<off_t>(-1))
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    if (lpNewFilePointer)
    {
        lpNewFilePointer->QuadPart = res;
    }
    return TRUE;
}

BOOL SetEndOfFile(HANDLE hFile)
{
    if (hFile == INVALID_HANDLE_VALUE || !hFile)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    off_t current = ::lseek(desc->fd, 0, SEEK_CUR);
    if (current == static_cast<off_t>(-1)) return FALSE;
    return (::ftruncate(desc->fd, current) == 0) ? TRUE : FALSE;
}

BOOL FlushFileBuffers(HANDLE hFile)
{
    if (hFile == INVALID_HANDLE_VALUE || !hFile)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    return (::fsync(desc->fd) == 0) ? TRUE : FALSE;
}

// ============================================================================
// File Attributes & Timestamps
// ============================================================================

static void TimespecToFileTime(const struct timespec& ts, FILETIME* pft)
{
    if (!pft) return;
    uint64_t intervals = (static_cast<uint64_t>(ts.tv_sec) + 11644473600ULL) * 10000000ULL + (ts.tv_nsec / 100);
    pft->dwLowDateTime = static_cast<DWORD>(intervals & 0xFFFFFFFF);
    pft->dwHighDateTime = static_cast<DWORD>((intervals >> 32) & 0xFFFFFFFF);
}

DWORD GetFileAttributesW(LPCWSTR lpFileName)
{
    if (!lpFileName) return INVALID_FILE_ATTRIBUTES;
    std::string path = wstring_to_utf8(lpFileName);
    struct stat st{};
    if (::stat(path.c_str(), &st) != 0)
    {
        SetLastError(ERROR_FILE_NOT_FOUND);
        return INVALID_FILE_ATTRIBUTES;
    }

    DWORD attr = 0;
    if (S_ISDIR(st.st_mode))
    {
        attr |= FILE_ATTRIBUTE_DIRECTORY;
    }
    else
    {
        attr |= FILE_ATTRIBUTE_NORMAL;
    }

    if (::access(path.c_str(), W_OK) != 0)
    {
        attr |= FILE_ATTRIBUTE_READONLY;
    }

    return attr;
}

BOOL SetFileAttributesW(LPCWSTR lpFileName, DWORD dwFileAttributes)
{
    if (!lpFileName) return FALSE;
    std::string path = wstring_to_utf8(lpFileName);
    mode_t mode = (dwFileAttributes & FILE_ATTRIBUTE_READONLY) ? 0444 : 0644;
    return (::chmod(path.c_str(), mode) == 0) ? TRUE : FALSE;
}

BOOL GetFileAttributesExW(LPCWSTR lpFileName, int fInfoLevelId, LPVOID lpFileInformation)
{
    (void)fInfoLevelId;
    if (!lpFileName || !lpFileInformation) return FALSE;
    std::string path = wstring_to_utf8(lpFileName);
    struct stat st{};
    if (::stat(path.c_str(), &st) != 0)
    {
        SetLastError(ERROR_FILE_NOT_FOUND);
        return FALSE;
    }

    auto* data = reinterpret_cast<WIN32_FILE_ATTRIBUTE_DATA*>(lpFileInformation);
    data->dwFileAttributes = S_ISDIR(st.st_mode) ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
    if (::access(path.c_str(), W_OK) != 0) data->dwFileAttributes |= FILE_ATTRIBUTE_READONLY;

    TimespecToFileTime(st.st_birthtimespec, &data->ftCreationTime);
    TimespecToFileTime(st.st_atimespec, &data->ftLastAccessTime);
    TimespecToFileTime(st.st_mtimespec, &data->ftLastWriteTime);

    data->nFileSizeHigh = static_cast<DWORD>((st.st_size >> 32) & 0xFFFFFFFF);
    data->nFileSizeLow = static_cast<DWORD>(st.st_size & 0xFFFFFFFF);
    return TRUE;
}

BOOL GetFileTime(HANDLE hFile, LPFILETIME lpCreationTime, LPFILETIME lpLastAccessTime, LPFILETIME lpLastWriteTime)
{
    if (hFile == INVALID_HANDLE_VALUE || !hFile) return FALSE;
    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);
    struct stat st{};
    if (::fstat(desc->fd, &st) != 0) return FALSE;

    if (lpCreationTime) TimespecToFileTime(st.st_birthtimespec, lpCreationTime);
    if (lpLastAccessTime) TimespecToFileTime(st.st_atimespec, lpLastAccessTime);
    if (lpLastWriteTime) TimespecToFileTime(st.st_mtimespec, lpLastWriteTime);
    return TRUE;
}

BOOL SetFileTime(HANDLE hFile, const FILETIME* lpCreationTime, const FILETIME* lpLastAccessTime, const FILETIME* lpLastWriteTime)
{
    (void)lpCreationTime;
    if (hFile == INVALID_HANDLE_VALUE || !hFile) return FALSE;
    auto* desc = reinterpret_cast<MacFileDescriptor*>(hFile);

    struct timeval times[2];
    if (lpLastAccessTime)
    {
        uint64_t intervals = (static_cast<uint64_t>(lpLastAccessTime->dwHighDateTime) << 32) | lpLastAccessTime->dwLowDateTime;
        times[0].tv_sec = static_cast<time_t>((intervals / 10000000ULL) - 11644473600ULL);
        times[0].tv_usec = static_cast<suseconds_t>((intervals % 10000000ULL) / 10);
    }
    else
    {
        ::gettimeofday(&times[0], nullptr);
    }

    if (lpLastWriteTime)
    {
        uint64_t intervals = (static_cast<uint64_t>(lpLastWriteTime->dwHighDateTime) << 32) | lpLastWriteTime->dwLowDateTime;
        times[1].tv_sec = static_cast<time_t>((intervals / 10000000ULL) - 11644473600ULL);
        times[1].tv_usec = static_cast<suseconds_t>((intervals % 10000000ULL) / 10);
    }
    else
    {
        ::gettimeofday(&times[1], nullptr);
    }

    return (::futimes(desc->fd, times) == 0) ? TRUE : FALSE;
}

BOOL FileTimeToSystemTime(const FILETIME* lpFileTime, LPSYSTEMTIME lpSystemTime)
{
    if (!lpFileTime || !lpSystemTime) return FALSE;
    uint64_t intervals = (static_cast<uint64_t>(lpFileTime->dwHighDateTime) << 32) | lpFileTime->dwLowDateTime;
    time_t t = static_cast<time_t>((intervals / 10000000ULL) - 11644473600ULL);
    struct tm tm_val{};
    gmtime_r(&t, &tm_val);

    lpSystemTime->wYear = static_cast<WORD>(tm_val.tm_year + 1900);
    lpSystemTime->wMonth = static_cast<WORD>(tm_val.tm_mon + 1);
    lpSystemTime->wDayOfWeek = static_cast<WORD>(tm_val.tm_wday);
    lpSystemTime->wDay = static_cast<WORD>(tm_val.tm_mday);
    lpSystemTime->wHour = static_cast<WORD>(tm_val.tm_hour);
    lpSystemTime->wMinute = static_cast<WORD>(tm_val.tm_min);
    lpSystemTime->wSecond = static_cast<WORD>(tm_val.tm_sec);
    lpSystemTime->wMilliseconds = static_cast<WORD>((intervals % 10000000ULL) / 10000);
    return TRUE;
}

BOOL SystemTimeToFileTime(const SYSTEMTIME* lpSystemTime, LPFILETIME lpFileTime)
{
    if (!lpSystemTime || !lpFileTime) return FALSE;
    struct tm tm_val{};
    tm_val.tm_year = lpSystemTime->wYear - 1900;
    tm_val.tm_mon = lpSystemTime->wMonth - 1;
    tm_val.tm_mday = lpSystemTime->wDay;
    tm_val.tm_hour = lpSystemTime->wHour;
    tm_val.tm_min = lpSystemTime->wMinute;
    tm_val.tm_sec = lpSystemTime->wSecond;
    time_t t = timegm(&tm_val);

    uint64_t intervals = (static_cast<uint64_t>(t) + 11644473600ULL) * 10000000ULL + (lpSystemTime->wMilliseconds * 10000);
    lpFileTime->dwLowDateTime = static_cast<DWORD>(intervals & 0xFFFFFFFF);
    lpFileTime->dwHighDateTime = static_cast<DWORD>((intervals >> 32) & 0xFFFFFFFF);
    return TRUE;
}

BOOL FileTimeToLocalFileTime(const FILETIME* lpFileTime, LPFILETIME lpLocalFileTime)
{
    if (!lpFileTime || !lpLocalFileTime) return FALSE;
    *lpLocalFileTime = *lpFileTime;
    return TRUE;
}

BOOL LocalFileTimeToFileTime(const FILETIME* lpLocalFileTime, LPFILETIME lpFileTime)
{
    if (!lpLocalFileTime || !lpFileTime) return FALSE;
    *lpFileTime = *lpLocalFileTime;
    return TRUE;
}

LONG CompareFileTime(const FILETIME* lpFileTime1, const FILETIME* lpFileTime2)
{
    if (!lpFileTime1 || !lpFileTime2) return 0;
    uint64_t t1 = (static_cast<uint64_t>(lpFileTime1->dwHighDateTime) << 32) | lpFileTime1->dwLowDateTime;
    uint64_t t2 = (static_cast<uint64_t>(lpFileTime2->dwHighDateTime) << 32) | lpFileTime2->dwLowDateTime;
    if (t1 < t2) return -1;
    if (t1 > t2) return 1;
    return 0;
}

// ============================================================================
// Directory Search & Filesystem
// ============================================================================

struct MacFindData {
    DIR* dir;
    std::string dirPath;
    std::string pattern;
};

HANDLE FindFirstFileW(LPCWSTR lpFileName, LPWIN32_FIND_DATAW lpFindFileData)
{
    if (!lpFileName || !lpFindFileData)
    {
        SetLastError(ERROR_PATH_NOT_FOUND);
        return INVALID_HANDLE_VALUE;
    }

    std::string fullPath = wstring_to_utf8(lpFileName);
    std::string dirPath = ".";
    std::string pattern = "*";

    size_t lastSlash = fullPath.find_last_of("/\\");
    if (lastSlash != std::string::npos)
    {
        dirPath = fullPath.substr(0, lastSlash);
        pattern = fullPath.substr(lastSlash + 1);
        if (dirPath.empty()) dirPath = "/";
    }
    else
    {
        pattern = fullPath;
    }

    DIR* dir = ::opendir(dirPath.c_str());
    if (!dir)
    {
        SetLastError(ERROR_PATH_NOT_FOUND);
        return INVALID_HANDLE_VALUE;
    }

    auto* mfd = new MacFindData();
    mfd->dir = dir;
    mfd->dirPath = dirPath;
    mfd->pattern = pattern;

    if (!FindNextFileW(reinterpret_cast<HANDLE>(mfd), lpFindFileData))
    {
        ::closedir(dir);
        delete mfd;
        return INVALID_HANDLE_VALUE;
    }

    return reinterpret_cast<HANDLE>(mfd);
}

BOOL FindNextFileW(HANDLE hFindFile, LPWIN32_FIND_DATAW lpFindFileData)
{
    if (hFindFile == INVALID_HANDLE_VALUE || !hFindFile || !lpFindFileData)
    {
        SetLastError(ERROR_INVALID_HANDLE);
        return FALSE;
    }

    auto* mfd = reinterpret_cast<MacFindData*>(hFindFile);
    struct dirent* entry = nullptr;

    while ((entry = ::readdir(mfd->dir)) != nullptr)
    {
        if (mfd->pattern != "*" && ::fnmatch(mfd->pattern.c_str(), entry->d_name, 0) != 0)
        {
            continue;
        }

        std::string filePath = mfd->dirPath + "/" + entry->d_name;
        struct stat st{};
        ::stat(filePath.c_str(), &st);

        lpFindFileData->dwFileAttributes = S_ISDIR(st.st_mode) ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
        TimespecToFileTime(st.st_birthtimespec, &lpFindFileData->ftCreationTime);
        TimespecToFileTime(st.st_atimespec, &lpFindFileData->ftLastAccessTime);
        TimespecToFileTime(st.st_mtimespec, &lpFindFileData->ftLastWriteTime);

        lpFindFileData->nFileSizeHigh = static_cast<DWORD>((st.st_size >> 32) & 0xFFFFFFFF);
        lpFindFileData->nFileSizeLow = static_cast<DWORD>(st.st_size & 0xFFFFFFFF);

        std::wstring wName = utf8_to_wstring(entry->d_name);
        wcsncpy(lpFindFileData->cFileName, wName.c_str(), MAX_PATH - 1);
        lpFindFileData->cFileName[MAX_PATH - 1] = L'\0';
        lpFindFileData->cAlternateFileName[0] = L'\0';

        return TRUE;
    }

    SetLastError(ERROR_NO_MORE_FILES);
    return FALSE;
}

BOOL FindClose(HANDLE hFindFile)
{
    if (hFindFile == INVALID_HANDLE_VALUE || !hFindFile) return FALSE;
    auto* mfd = reinterpret_cast<MacFindData*>(hFindFile);
    if (mfd->dir) ::closedir(mfd->dir);
    delete mfd;
    return TRUE;
}

HANDLE FindFirstStreamW(LPCWSTR lpFileName, int InfoLevel, LPVOID lpFindStreamData, DWORD dwFlags)
{
    (void)lpFileName; (void)InfoLevel; (void)lpFindStreamData; (void)dwFlags;
    SetLastError(ERROR_FILE_NOT_FOUND);
    return INVALID_HANDLE_VALUE;
}

BOOL DeleteFileW(LPCWSTR lpFileName)
{
    if (!lpFileName) return FALSE;
    std::string path = wstring_to_utf8(lpFileName);
    return (::unlink(path.c_str()) == 0) ? TRUE : FALSE;
}

BOOL MoveFileW(LPCWSTR lpExistingFileName, LPCWSTR lpNewFileName)
{
    if (!lpExistingFileName || !lpNewFileName) return FALSE;
    std::string src = wstring_to_utf8(lpExistingFileName);
    std::string dst = wstring_to_utf8(lpNewFileName);
    return (::rename(src.c_str(), dst.c_str()) == 0) ? TRUE : FALSE;
}

BOOL MoveFileExW(LPCWSTR lpExistingFileName, LPCWSTR lpNewFileName, DWORD dwFlags)
{
    (void)dwFlags;
    return MoveFileW(lpExistingFileName, lpNewFileName);
}

BOOL CopyFileW(LPCWSTR lpExistingFileName, LPCWSTR lpNewFileName, BOOL bFailIfExists)
{
    if (!lpExistingFileName || !lpNewFileName) return FALSE;
    std::string src = wstring_to_utf8(lpExistingFileName);
    std::string dst = wstring_to_utf8(lpNewFileName);

    if (bFailIfExists && ::access(dst.c_str(), F_OK) == 0)
    {
        SetLastError(ERROR_FILE_EXISTS);
        return FALSE;
    }

    FILE* in = fopen(src.c_str(), "rb");
    if (!in) return FALSE;
    FILE* out = fopen(dst.c_str(), "wb");
    if (!out) { fclose(in); return FALSE; }

    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0)
    {
        fwrite(buf, 1, n, out);
    }
    fclose(in);
    fclose(out);
    return TRUE;
}

BOOL CreateDirectoryW(LPCWSTR lpPathName, void* lpSecurityAttributes)
{
    (void)lpSecurityAttributes;
    if (!lpPathName) return FALSE;
    std::string path = wstring_to_utf8(lpPathName);
    return (::mkdir(path.c_str(), 0755) == 0 || errno == EEXIST) ? TRUE : FALSE;
}

BOOL RemoveDirectoryW(LPCWSTR lpPathName)
{
    if (!lpPathName) return FALSE;
    std::string path = wstring_to_utf8(lpPathName);
    return (::rmdir(path.c_str()) == 0) ? TRUE : FALSE;
}

DWORD GetCurrentDirectoryW(DWORD nBufferLength, LPWSTR lpBuffer)
{
    char buf[1024];
    if (!::getcwd(buf, sizeof(buf))) return 0;
    std::wstring wDir = utf8_to_wstring(buf);
    if (nBufferLength == 0 || !lpBuffer) return static_cast<DWORD>(wDir.length() + 1);
    wcsncpy(lpBuffer, wDir.c_str(), nBufferLength - 1);
    lpBuffer[nBufferLength - 1] = L'\0';
    return static_cast<DWORD>(wcslen(lpBuffer));
}

BOOL SetCurrentDirectoryW(LPCWSTR lpPathName)
{
    if (!lpPathName) return FALSE;
    std::string path = wstring_to_utf8(lpPathName);
    return (::chdir(path.c_str()) == 0) ? TRUE : FALSE;
}

DWORD GetFullPathNameW(LPCWSTR lpFileName, DWORD nBufferLength, LPWSTR lpBuffer, LPWSTR* lpFilePart)
{
    if (!lpFileName || !lpBuffer || nBufferLength == 0) return 0;
    std::string path = wstring_to_utf8(lpFileName);
    char real[PATH_MAX];
    std::string full;
    if (::realpath(path.c_str(), real))
    {
        full = real;
    }
    else
    {
        if (path.empty() || path[0] != '/')
        {
            char cwd[PATH_MAX];
            if (::getcwd(cwd, sizeof(cwd)))
            {
                full = std::string(cwd) + "/" + path;
            }
            else
            {
                full = path;
            }
        }
        else
        {
            full = path;
        }
    }

    std::wstring wFull = utf8_to_wstring(full);
    wcsncpy(lpBuffer, wFull.c_str(), nBufferLength - 1);
    lpBuffer[nBufferLength - 1] = L'\0';

    if (lpFilePart)
    {
        wchar_t* lastSlash = wcsrchr(lpBuffer, L'/');
        *lpFilePart = lastSlash ? (lastSlash + 1) : lpBuffer;
    }

    return static_cast<DWORD>(wcslen(lpBuffer));
}

DWORD GetLongPathNameW(LPCWSTR lpszShortPath, LPWSTR lpszLongPath, DWORD cchBuffer)
{
    if (!lpszShortPath || !lpszLongPath || cchBuffer == 0) return 0;
    wcsncpy(lpszLongPath, lpszShortPath, cchBuffer - 1);
    lpszLongPath[cchBuffer - 1] = L'\0';
    return static_cast<DWORD>(wcslen(lpszLongPath));
}

DWORD GetShortPathNameW(LPCWSTR lpszLongPath, LPWSTR lpszShortPath, DWORD cchBuffer)
{
    if (!lpszLongPath || !lpszShortPath || cchBuffer == 0) return 0;
    wcsncpy(lpszShortPath, lpszLongPath, cchBuffer - 1);
    lpszShortPath[cchBuffer - 1] = L'\0';
    return static_cast<DWORD>(wcslen(lpszShortPath));
}

DWORD GetTempPathW(DWORD nBufferLength, LPWSTR lpBuffer)
{
    const char* tmp = getenv("TMPDIR");
    if (!tmp) tmp = "/tmp";
    std::wstring wTmp = utf8_to_wstring(tmp);
    if (!wTmp.empty() && wTmp.back() != L'/') wTmp += L'/';
    if (nBufferLength == 0 || !lpBuffer) return static_cast<DWORD>(wTmp.length());
    wcsncpy(lpBuffer, wTmp.c_str(), nBufferLength - 1);
    lpBuffer[nBufferLength - 1] = L'\0';
    return static_cast<DWORD>(wcslen(lpBuffer));
}

UINT GetTempFileNameW(LPCWSTR lpPathName, LPCWSTR lpPrefixString, UINT uUnique, LPWSTR lpTempFileName)
{
    (void)uUnique;
    std::wstring dir = lpPathName ? lpPathName : L"/tmp/";
    std::wstring pfx = lpPrefixString ? lpPrefixString : L"npp";
    std::string templateStr = wstring_to_utf8(dir) + "/" + wstring_to_utf8(pfx) + "XXXXXX";
    char* res = mktemp(&templateStr[0]);
    if (!res) return 0;
    std::wstring wRes = utf8_to_wstring(res);
    wcscpy(lpTempFileName, wRes.c_str());
    return 1;
}

// ============================================================================
// Path Utility Functions (shlwapi)
// ============================================================================

BOOL PathFileExistsW(LPCWSTR pszPath)
{
    if (!pszPath) return FALSE;
    std::string p = wstring_to_utf8(pszPath);
    return (::access(p.c_str(), F_OK) == 0) ? TRUE : FALSE;
}

BOOL PathIsDirectoryW(LPCWSTR pszPath)
{
    if (!pszPath) return FALSE;
    std::string p = wstring_to_utf8(pszPath);
    struct stat st{};
    if (::stat(p.c_str(), &st) != 0) return FALSE;
    return S_ISDIR(st.st_mode) ? TRUE : FALSE;
}

BOOL PathRemoveFileSpecW(LPWSTR pszPath)
{
    if (!pszPath) return FALSE;
    wchar_t* lastSlash = wcsrchr(pszPath, L'/');
    wchar_t* lastBack = wcsrchr(pszPath, L'\\');
    wchar_t* target = nullptr;
    if (lastSlash && lastBack) target = (lastSlash > lastBack) ? lastSlash : lastBack;
    else if (lastSlash) target = lastSlash;
    else if (lastBack) target = lastBack;

    if (target)
    {
        *target = L'\0';
        return TRUE;
    }
    return FALSE;
}

LPWSTR PathCombineW(LPWSTR pszDest, LPCWSTR pszDir, LPCWSTR pszFile)
{
    if (!pszDest) return nullptr;
    std::wstring d = pszDir ? pszDir : L"";
    std::wstring f = pszFile ? pszFile : L"";
    if (!d.empty() && d.back() != L'/' && d.back() != L'\\')
    {
        d += L'/';
    }
    std::wstring res = d + f;
    wcscpy(pszDest, res.c_str());
    return pszDest;
}

LPCWSTR PathFindFileNameW(LPCWSTR pszPath)
{
    if (!pszPath) return nullptr;
    const wchar_t* p1 = wcsrchr(pszPath, L'/');
    const wchar_t* p2 = wcsrchr(pszPath, L'\\');
    const wchar_t* p = nullptr;
    if (p1 && p2) p = (p1 > p2) ? p1 : p2;
    else if (p1) p = p1;
    else if (p2) p = p2;
    return p ? (p + 1) : pszPath;
}

LPCWSTR PathFindExtensionW(LPCWSTR pszPath)
{
    if (!pszPath) return nullptr;
    const wchar_t* lastDot = wcsrchr(pszPath, L'.');
    const wchar_t* lastSlash = wcsrchr(pszPath, L'/');
    const wchar_t* lastBack = wcsrchr(pszPath, L'\\');
    const wchar_t* sep = nullptr;
    if (lastSlash && lastBack) sep = (lastSlash > lastBack) ? lastSlash : lastBack;
    else if (lastSlash) sep = lastSlash;
    else if (lastBack) sep = lastBack;

    if (lastDot && (!sep || lastDot > sep))
    {
        return lastDot;
    }
    return pszPath + wcslen(pszPath);
}

BOOL PathIsNetworkPathW(LPCWSTR pszPath)
{
    (void)pszPath;
    return FALSE;
}

BOOL PathIsRelativeW(LPCWSTR pszPath)
{
    if (!pszPath || pszPath[0] == L'\0') return TRUE;
    return (pszPath[0] != L'/' && pszPath[0] != L'\\') ? TRUE : FALSE;
}

BOOL PathAppendW(LPWSTR pszPath, LPCWSTR pszMore)
{
    if (!pszPath || !pszMore) return FALSE;
    size_t len = wcslen(pszPath);
    if (len > 0 && pszPath[len - 1] != L'/' && pszPath[len - 1] != L'\\')
    {
        pszPath[len] = L'/';
        pszPath[len + 1] = L'\0';
    }
    wcscat(pszPath, pszMore);
    return TRUE;
}

BOOL PathMatchSpecW(LPCWSTR pszFile, LPCWSTR pszSpec)
{
    if (!pszFile || !pszSpec) return FALSE;
    std::string file = wstring_to_utf8(pszFile);
    std::string spec = wstring_to_utf8(pszSpec);
    for (char& c : file) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    for (char& c : spec) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    return (::fnmatch(spec.c_str(), file.c_str(), 0) == 0) ? TRUE : FALSE;
}

void PathStripPathW(LPWSTR pszPath)
{
    if (!pszPath) return;
    const wchar_t* fn = PathFindFileNameW(pszPath);
    if (fn && fn != pszPath)
    {
        std::wstring s = fn;
        wcscpy(pszPath, s.c_str());
    }
}

// ============================================================================
// Time & Synchronization
// ============================================================================

VOID GetLocalTime(LPSYSTEMTIME lpSystemTime)
{
    if (!lpSystemTime) return;
    struct timeval tv{};
    ::gettimeofday(&tv, nullptr);
    struct tm tm_val{};
    localtime_r(&tv.tv_sec, &tm_val);

    lpSystemTime->wYear = static_cast<WORD>(tm_val.tm_year + 1900);
    lpSystemTime->wMonth = static_cast<WORD>(tm_val.tm_mon + 1);
    lpSystemTime->wDayOfWeek = static_cast<WORD>(tm_val.tm_wday);
    lpSystemTime->wDay = static_cast<WORD>(tm_val.tm_mday);
    lpSystemTime->wHour = static_cast<WORD>(tm_val.tm_hour);
    lpSystemTime->wMinute = static_cast<WORD>(tm_val.tm_min);
    lpSystemTime->wSecond = static_cast<WORD>(tm_val.tm_sec);
    lpSystemTime->wMilliseconds = static_cast<WORD>(tv.tv_usec / 1000);
}

VOID GetSystemTime(LPSYSTEMTIME lpSystemTime)
{
    if (!lpSystemTime) return;
    struct timeval tv{};
    ::gettimeofday(&tv, nullptr);
    struct tm tm_val{};
    gmtime_r(&tv.tv_sec, &tm_val);

    lpSystemTime->wYear = static_cast<WORD>(tm_val.tm_year + 1900);
    lpSystemTime->wMonth = static_cast<WORD>(tm_val.tm_mon + 1);
    lpSystemTime->wDayOfWeek = static_cast<WORD>(tm_val.tm_wday);
    lpSystemTime->wDay = static_cast<WORD>(tm_val.tm_mday);
    lpSystemTime->wHour = static_cast<WORD>(tm_val.tm_hour);
    lpSystemTime->wMinute = static_cast<WORD>(tm_val.tm_min);
    lpSystemTime->wSecond = static_cast<WORD>(tm_val.tm_sec);
    lpSystemTime->wMilliseconds = static_cast<WORD>(tv.tv_usec / 1000);
}

static const auto g_tickStart = std::chrono::steady_clock::now();

DWORD GetTickCount(VOID)
{
    auto now = std::chrono::steady_clock::now();
    return static_cast<DWORD>(std::chrono::duration_cast<std::chrono::milliseconds>(now - g_tickStart).count());
}

ULONGLONG GetTickCount64(VOID)
{
    auto now = std::chrono::steady_clock::now();
    return static_cast<ULONGLONG>(std::chrono::duration_cast<std::chrono::milliseconds>(now - g_tickStart).count());
}

BOOL QueryPerformanceCounter(LARGE_INTEGER* lpPerformanceCount)
{
    if (!lpPerformanceCount) return FALSE;
    lpPerformanceCount->QuadPart = mach_absolute_time();
    return TRUE;
}

BOOL QueryPerformanceFrequency(LARGE_INTEGER* lpFrequency)
{
    if (!lpFrequency) return FALSE;
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    lpFrequency->QuadPart = (1000000000ULL * tb.denom) / tb.numer;
    return TRUE;
}

VOID Sleep(DWORD dwMilliseconds)
{
    usleep(dwMilliseconds * 1000);
}

VOID InitializeCriticalSection(LPCRITICAL_SECTION lpCriticalSection)
{
    if (!lpCriticalSection) return;
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&lpCriticalSection->mutex, &attr);
    pthread_mutexattr_destroy(&attr);
}

VOID DeleteCriticalSection(LPCRITICAL_SECTION lpCriticalSection)
{
    if (!lpCriticalSection) return;
    pthread_mutex_destroy(&lpCriticalSection->mutex);
}

VOID EnterCriticalSection(LPCRITICAL_SECTION lpCriticalSection)
{
    if (!lpCriticalSection) return;
    pthread_mutex_lock(&lpCriticalSection->mutex);
}

VOID LeaveCriticalSection(LPCRITICAL_SECTION lpCriticalSection)
{
    if (!lpCriticalSection) return;
    pthread_mutex_unlock(&lpCriticalSection->mutex);
}

BOOL TryEnterCriticalSection(LPCRITICAL_SECTION lpCriticalSection)
{
    if (!lpCriticalSection) return FALSE;
    return (pthread_mutex_trylock(&lpCriticalSection->mutex) == 0) ? TRUE : FALSE;
}

struct MacThreadInfo {
    pthread_t thread;
    void* (*func)(void*);
    void* param;
};

HANDLE CreateThread(void* lpThreadAttributes, size_t dwStackSize, void* lpStartAddress, void* lpParameter, DWORD dwCreationFlags, DWORD* lpThreadId)
{
    (void)lpThreadAttributes; (void)dwStackSize; (void)dwCreationFlags;
    auto* info = new MacThreadInfo();
    info->func = reinterpret_cast<void* (*)(void*)>(lpStartAddress);
    info->param = lpParameter;

    if (pthread_create(&info->thread, nullptr, info->func, info->param) != 0)
    {
        delete info;
        return nullptr;
    }

    if (lpThreadId) *lpThreadId = static_cast<DWORD>(reinterpret_cast<uintptr_t>(info->thread));
    return reinterpret_cast<HANDLE>(info);
}

DWORD WaitForSingleObject(HANDLE hHandle, DWORD dwMilliseconds)
{
    if (!hHandle) return WAIT_FAILED;
    auto* info = reinterpret_cast<MacThreadInfo*>(hHandle);
    if (dwMilliseconds == INFINITE)
    {
        pthread_join(info->thread, nullptr);
        return WAIT_OBJECT_0;
    }
    // Simple wait
    pthread_join(info->thread, nullptr);
    return WAIT_OBJECT_0;
}

BOOL TerminateThread(HANDLE hThread, DWORD dwExitCode)
{
    (void)dwExitCode;
    if (!hThread) return FALSE;
    auto* info = reinterpret_cast<MacThreadInfo*>(hThread);
    pthread_cancel(info->thread);
    return TRUE;
}

DWORD GetCurrentThreadId(VOID)
{
    return static_cast<DWORD>(reinterpret_cast<uintptr_t>(pthread_self()));
}

DWORD GetCurrentProcessId(VOID)
{
    return static_cast<DWORD>(getpid());
}

// ============================================================================
// Memory
// ============================================================================

HGLOBAL GlobalAlloc(UINT uFlags, size_t dwBytes)
{
    (void)uFlags;
    void* p = malloc(dwBytes);
    if (p && (uFlags & GMEM_ZEROINIT))
    {
        memset(p, 0, dwBytes);
    }
    return reinterpret_cast<HGLOBAL>(p);
}

LPVOID GlobalLock(HGLOBAL hMem) { return reinterpret_cast<LPVOID>(hMem); }
BOOL GlobalUnlock(HGLOBAL hMem) { (void)hMem; return TRUE; }
HGLOBAL GlobalFree(HGLOBAL hMem) { free(reinterpret_cast<void*>(hMem)); return nullptr; }
size_t GlobalSize(HGLOBAL hMem) { (void)hMem; return 0; }

// ============================================================================
// Windows / GUI / Messages
// ============================================================================

LRESULT SendMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
    (void)hWnd; (void)Msg; (void)wParam; (void)lParam;
    return 0;
}

BOOL PostMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
    (void)hWnd; (void)Msg; (void)wParam; (void)lParam;
    return TRUE;
}

BOOL PeekMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg)
{
    (void)lpMsg; (void)hWnd; (void)wMsgFilterMin; (void)wMsgFilterMax; (void)wRemoveMsg;
    return FALSE;
}

BOOL GetMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax)
{
    (void)lpMsg; (void)hWnd; (void)wMsgFilterMin; (void)wMsgFilterMax;
    return FALSE;
}

BOOL TranslateMessage(const MSG* lpMsg) { (void)lpMsg; return TRUE; }
LRESULT DispatchMessageW(const MSG* lpMsg) { (void)lpMsg; return 0; }
LRESULT DefWindowProcW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam) { (void)hWnd; (void)Msg; (void)wParam; (void)lParam; return 0; }
LRESULT CallWindowProcW(WNDPROC lpPrevWndFunc, HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam)
{
    if (lpPrevWndFunc) return lpPrevWndFunc(hWnd, Msg, wParam, lParam);
    return 0;
}

BOOL ShowWindow(HWND hWnd, int nCmdShow) { (void)hWnd; (void)nCmdShow; return TRUE; }
BOOL UpdateWindow(HWND hWnd) { (void)hWnd; return TRUE; }
BOOL InvalidateRect(HWND hWnd, const RECT* lpRect, BOOL bErase) { (void)hWnd; (void)lpRect; (void)bErase; return TRUE; }
BOOL GetClientRect(HWND hWnd, LPRECT lpRect)
{
    if (lpRect) { lpRect->left = 0; lpRect->top = 0; lpRect->right = 800; lpRect->bottom = 600; }
    (void)hWnd;
    return TRUE;
}
BOOL GetWindowRect(HWND hWnd, LPRECT lpRect)
{
    if (lpRect) { lpRect->left = 100; lpRect->top = 100; lpRect->right = 900; lpRect->bottom = 700; }
    (void)hWnd;
    return TRUE;
}
BOOL MoveWindow(HWND hWnd, int X, int Y, int nWidth, int nHeight, BOOL bRepaint) { (void)hWnd; (void)X; (void)Y; (void)nWidth; (void)nHeight; (void)bRepaint; return TRUE; }
BOOL SetWindowPos(HWND hWnd, HWND hWndInsertAfter, int X, int Y, int cx, int cy, UINT uFlags) { (void)hWnd; (void)hWndInsertAfter; (void)X; (void)Y; (void)cx; (void)cy; (void)uFlags; return TRUE; }
HWND SetFocus(HWND hWnd) { return hWnd; }
HWND GetFocus(VOID) { return nullptr; }
BOOL EnableWindow(HWND hWnd, BOOL bEnable) { (void)hWnd; (void)bEnable; return TRUE; }
BOOL IsWindowEnabled(HWND hWnd) { (void)hWnd; return TRUE; }
BOOL IsWindowVisible(HWND hWnd) { (void)hWnd; return TRUE; }
BOOL DestroyWindow(HWND hWnd) { (void)hWnd; return TRUE; }
HWND GetParent(HWND hWnd) { (void)hWnd; return nullptr; }
HWND SetParent(HWND hWndChild, HWND hWndNewParent) { (void)hWndChild; (void)hWndNewParent; return nullptr; }
LONG_PTR GetWindowLongPtrW(HWND hWnd, int nIndex) { (void)hWnd; (void)nIndex; return 0; }
LONG_PTR SetWindowLongPtrW(HWND hWnd, int nIndex, LONG_PTR dwNewLong) { (void)hWnd; (void)nIndex; (void)dwNewLong; return 0; }

UINT_PTR SetTimer(HWND hWnd, UINT_PTR nIDEvent, UINT uElapse, TIMERPROC lpTimerFunc) { (void)hWnd; (void)nIDEvent; (void)uElapse; (void)lpTimerFunc; return 1; }
BOOL KillTimer(HWND hWnd, UINT_PTR uIDEvent) { (void)hWnd; (void)uIDEvent; return TRUE; }
int GetSystemMetrics(int nIndex)
{
    switch (nIndex)
    {
        case SM_CXSCREEN: return 1920;
        case SM_CYSCREEN: return 1080;
        case SM_CXVSCROLL: return 15;
        case SM_CYHSCROLL: return 15;
        default: return 10;
    }
}

int MessageBoxW(HWND hWnd, LPCWSTR lpText, LPCWSTR lpCaption, UINT uType)
{
    (void)hWnd; (void)uType;
    std::string text = lpText ? wstring_to_utf8(lpText) : "";
    std::string caption = lpCaption ? wstring_to_utf8(lpCaption) : "Notepad++";
    fprintf(stderr, "[%s] %s\n", caption.c_str(), text.c_str());
    return IDOK;
}

int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType)
{
    (void)hWnd; (void)uType;
    fprintf(stderr, "[%s] %s\n", lpCaption ? lpCaption : "Notepad++", lpText ? lpText : "");
    return IDOK;
}

// ============================================================================
// Clipboard
// ============================================================================

static std::string g_clipboardText;

BOOL OpenClipboard(HWND hWndNewOwner) { (void)hWndNewOwner; return TRUE; }
BOOL CloseClipboard(VOID) { return TRUE; }
BOOL EmptyClipboard(VOID) { g_clipboardText.clear(); return TRUE; }

HANDLE GetClipboardData(UINT uFormat)
{
    (void)uFormat;
    return reinterpret_cast<HANDLE>(g_clipboardText.data());
}

HANDLE SetClipboardData(UINT uFormat, HANDLE hMem)
{
    (void)uFormat;
    if (hMem)
    {
        const char* p = reinterpret_cast<const char*>(hMem);
        g_clipboardText = p;
    }
    return hMem;
}

BOOL IsClipboardFormatAvailable(UINT format) { (void)format; return TRUE; }
UINT RegisterClipboardFormatW(LPCWSTR lpszFormat) { (void)lpszFormat; return 0xC001; }

// ============================================================================
// Module / Library
// ============================================================================

HMODULE GetModuleHandleW(LPCWSTR lpModuleName)
{
    (void)lpModuleName;
    return dlopen(nullptr, RTLD_LAZY);
}

HMODULE GetModuleHandleA(LPCSTR lpModuleName)
{
    (void)lpModuleName;
    return dlopen(nullptr, RTLD_LAZY);
}

DWORD GetModuleFileNameW(HMODULE hModule, LPWSTR lpFilename, DWORD nSize)
{
    (void)hModule;
    if (!lpFilename || nSize == 0) return 0;
    char path[PATH_MAX] = {0};
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) == 0)
    {
        char real[PATH_MAX] = {0};
        if (realpath(path, real) != nullptr)
        {
            std::wstring wpath = utf8_to_wstring(real);
            wcsncpy(lpFilename, wpath.c_str(), nSize - 1);
            lpFilename[nSize - 1] = L'\0';
            return static_cast<DWORD>(wcslen(lpFilename));
        }
    }
    wcsncpy(lpFilename, L"/Applications/Notepad++.app/Contents/MacOS/Notepad++", nSize - 1);
    lpFilename[nSize - 1] = L'\0';
    return static_cast<DWORD>(wcslen(lpFilename));
}

HMODULE LoadLibraryW(LPCWSTR lpLibFileName)
{
    if (!lpLibFileName) return nullptr;
    std::string path = wstring_to_utf8(lpLibFileName);
    return dlopen(path.c_str(), RTLD_LAZY);
}

BOOL FreeLibrary(HMODULE hLibModule)
{
    if (!hLibModule) return FALSE;
    return (dlclose(hLibModule) == 0) ? TRUE : FALSE;
}

void* GetProcAddress(HMODULE hModule, LPCSTR lpProcName)
{
    if (!lpProcName) return nullptr;
    void* handle = hModule ? hModule : RTLD_DEFAULT;
    return dlsym(handle, lpProcName);
}

// ============================================================================
// Shell & Registry
// ============================================================================

HINSTANCE ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile, LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd)
{
    (void)hwnd; (void)lpOperation; (void)lpParameters; (void)lpDirectory; (void)nShowCmd;
    if (lpFile)
    {
        std::string path = wstring_to_utf8(lpFile);
        std::string cmd = "open \"" + path + "\"";
        system(cmd.c_str());
    }
    return reinterpret_cast<HINSTANCE>(33);
}

HRESULT SHGetFolderPathW(HWND hwnd, int csidl, HANDLE hToken, DWORD dwFlags, LPWSTR pszPath)
{
    (void)hwnd; (void)hToken; (void)dwFlags;
    if (!pszPath) return E_INVALIDARG;
    const char* home = getenv("HOME");
    std::string homeStr = home ? home : "/tmp";
    std::string targetDir = homeStr;

    int folderId = csidl & 0x00ff;
    switch (folderId)
    {
        case CSIDL_APPDATA:
        case CSIDL_LOCAL_APPDATA:
        case CSIDL_COMMON_APPDATA:
            targetDir = homeStr + "/Library/Application Support/Notepad++";
            ::mkdir((homeStr + "/Library").c_str(), 0755);
            ::mkdir((homeStr + "/Library/Application Support").c_str(), 0755);
            ::mkdir(targetDir.c_str(), 0755);
            break;
        case CSIDL_PERSONAL:
            targetDir = homeStr + "/Documents";
            break;
        case CSIDL_DESKTOP:
            targetDir = homeStr + "/Desktop";
            break;
        case CSIDL_PROGRAM_FILES:
            targetDir = "/Applications";
            break;
        default:
            targetDir = homeStr;
            break;
    }

    std::wstring wRes = utf8_to_wstring(targetDir);
    wcscpy(pszPath, wRes.c_str());
    return S_OK;
}

LONG RegOpenKeyExW(HKEY hKey, LPCWSTR lpSubKey, DWORD ulOptions, DWORD samDesired, HKEY* phkResult) { (void)hKey; (void)lpSubKey; (void)ulOptions; (void)samDesired; if (phkResult) *phkResult = nullptr; return ERROR_FILE_NOT_FOUND; }
LONG RegQueryValueExW(HKEY hKey, LPCWSTR lpValueName, DWORD* lpReserved, DWORD* lpType, BYTE* lpData, DWORD* lpcbData) { (void)hKey; (void)lpValueName; (void)lpReserved; (void)lpType; (void)lpData; (void)lpcbData; return ERROR_FILE_NOT_FOUND; }
LONG RegSetValueExW(HKEY hKey, LPCWSTR lpValueName, DWORD Reserved, DWORD dwType, const BYTE* lpData, DWORD cbData) { (void)hKey; (void)lpValueName; (void)Reserved; (void)dwType; (void)lpData; (void)cbData; return ERROR_SUCCESS; }
LONG RegCloseKey(HKEY hKey) { (void)hKey; return ERROR_SUCCESS; }
LONG RegCreateKeyExW(HKEY hKey, LPCWSTR lpSubKey, DWORD Reserved, LPWSTR lpClass, DWORD dwOptions, DWORD samDesired, void* lpSecurityAttributes, HKEY* phkResult, DWORD* lpdwDisposition) { (void)hKey; (void)lpSubKey; (void)Reserved; (void)lpClass; (void)dwOptions; (void)samDesired; (void)lpSecurityAttributes; if (phkResult) *phkResult = nullptr; if (lpdwDisposition) *lpdwDisposition = 0; return ERROR_SUCCESS; }
LONG RegDeleteKeyW(HKEY hKey, LPCWSTR lpSubKey) { (void)hKey; (void)lpSubKey; return ERROR_SUCCESS; }
LONG RegDeleteValueW(HKEY hKey, LPCWSTR lpValueName) { (void)hKey; (void)lpValueName; return ERROR_SUCCESS; }

// ============================================================================
// String Helper Functions
// ============================================================================

int _wcsicmp(const wchar_t* s1, const wchar_t* s2)
{
    return wcscasecmp(s1, s2);
}

int _wcsnicmp(const wchar_t* s1, const wchar_t* s2, size_t n)
{
    return wcsncasecmp(s1, s2, n);
}

int _stricmp(const char* s1, const char* s2)
{
    return strcasecmp(s1, s2);
}

int _strnicmp(const char* s1, const char* s2, size_t n)
{
    return strncasecmp(s1, s2, n);
}

FILE* _wfopen(const wchar_t* filename, const wchar_t* mode)
{
    if (!filename || !mode) return nullptr;
    std::string fn = wstring_to_utf8(filename);
    std::string m = wstring_to_utf8(mode);
    return fopen(fn.c_str(), m.c_str());
}

int _wfopen_s(FILE** pFile, const wchar_t* filename, const wchar_t* mode)
{
    if (!pFile) return EINVAL;
    *pFile = _wfopen(filename, mode);
    return *pFile ? 0 : errno;
}

int wcscpy_s(wchar_t* dest, size_t destsz, const wchar_t* src)
{
    if (!dest || destsz == 0 || !src) return EINVAL;
    size_t srcLen = wcslen(src);
    if (srcLen >= destsz) { dest[0] = L'\0'; return ERANGE; }
    wcscpy(dest, src);
    return 0;
}

int wcscat_s(wchar_t* dest, size_t destsz, const wchar_t* src)
{
    if (!dest || destsz == 0 || !src) return EINVAL;
    size_t destLen = wcslen(dest);
    size_t srcLen = wcslen(src);
    if (destLen + srcLen >= destsz) return ERANGE;
    wcscat(dest, src);
    return 0;
}

int wcsncpy_s(wchar_t* dest, size_t destsz, const wchar_t* src, size_t count)
{
    if (!dest || destsz == 0 || !src) return EINVAL;
    size_t copyLen = std::min(count, wcslen(src));
    if (copyLen >= destsz) { dest[0] = L'\0'; return ERANGE; }
    wcsncpy(dest, src, copyLen);
    dest[copyLen] = L'\0';
    return 0;
}

int swprintf_s(wchar_t* buffer, size_t sizeOfBuffer, const wchar_t* format, ...)
{
    va_list args;
    va_start(args, format);
    int res = vswprintf(buffer, sizeOfBuffer, format, args);
    va_end(args);
    return res;
}

int sprintf_s(char* buffer, size_t sizeOfBuffer, const char* format, ...)
{
    va_list args;
    va_start(args, format);
    int res = vsnprintf(buffer, sizeOfBuffer, format, args);
    va_end(args);
    return res;
}

int _splitpath_s(const char* path, char* drive, size_t driveNumberOfElements, char* dir, size_t dirNumberOfElements, char* fname, size_t fnameNumberOfElements, char* ext, size_t extNumberOfElements)
{
    if (drive && driveNumberOfElements > 0) drive[0] = '\0';
    if (!path) return EINVAL;

    std::string p = path;
    size_t lastSlash = p.find_last_of("/\\");
    std::string directory;
    std::string filename;

    if (lastSlash != std::string::npos)
    {
        directory = p.substr(0, lastSlash + 1);
        filename = p.substr(lastSlash + 1);
    }
    else
    {
        filename = p;
    }

    size_t lastDot = filename.find_last_of('.');
    std::string baseName = filename;
    std::string extension;

    if (lastDot != std::string::npos)
    {
        baseName = filename.substr(0, lastDot);
        extension = filename.substr(lastDot);
    }

    if (dir && dirNumberOfElements > 0)
    {
        strncpy(dir, directory.c_str(), dirNumberOfElements - 1);
        dir[dirNumberOfElements - 1] = '\0';
    }
    if (fname && fnameNumberOfElements > 0)
    {
        strncpy(fname, baseName.c_str(), fnameNumberOfElements - 1);
        fname[fnameNumberOfElements - 1] = '\0';
    }
    if (ext && extNumberOfElements > 0)
    {
        strncpy(ext, extension.c_str(), extNumberOfElements - 1);
        ext[extNumberOfElements - 1] = '\0';
    }

    return 0;
}

int _wsplitpath_s(const wchar_t* path, wchar_t* drive, size_t driveNumberOfElements, wchar_t* dir, size_t dirNumberOfElements, wchar_t* fname, size_t fnameNumberOfElements, wchar_t* ext, size_t extNumberOfElements)
{
    if (drive && driveNumberOfElements > 0) drive[0] = L'\0';
    if (!path) return EINVAL;

    std::wstring p = path;
    size_t lastSlash = p.find_last_of(L"/\\");
    std::wstring directory;
    std::wstring filename;

    if (lastSlash != std::wstring::npos)
    {
        directory = p.substr(0, lastSlash + 1);
        filename = p.substr(lastSlash + 1);
    }
    else
    {
        filename = p;
    }

    size_t lastDot = filename.find_last_of(L'.');
    std::wstring baseName = filename;
    std::wstring extension;

    if (lastDot != std::wstring::npos)
    {
        baseName = filename.substr(0, lastDot);
        extension = filename.substr(lastDot);
    }

    if (dir && dirNumberOfElements > 0)
    {
        wcsncpy(dir, directory.c_str(), dirNumberOfElements - 1);
        dir[dirNumberOfElements - 1] = L'\0';
    }
    if (fname && fnameNumberOfElements > 0)
    {
        wcsncpy(fname, baseName.c_str(), fnameNumberOfElements - 1);
        fname[fnameNumberOfElements - 1] = L'\0';
    }
    if (ext && extNumberOfElements > 0)
    {
        wcsncpy(ext, extension.c_str(), extNumberOfElements - 1);
        ext[extNumberOfElements - 1] = L'\0';
    }

    return 0;
}

int _wmakepath_s(wchar_t* path, size_t sizeInWords, const wchar_t* drive, const wchar_t* dir, const wchar_t* fname, const wchar_t* ext)
{
    if (!path || sizeInWords == 0) return EINVAL;
    std::wstring res;
    if (drive) res += drive;
    if (dir) res += dir;
    if (fname) res += fname;
    if (ext) res += ext;
    wcsncpy(path, res.c_str(), sizeInWords - 1);
    path[sizeInWords - 1] = L'\0';
    return 0;
}

int wsprintfW(LPWSTR lpOut, LPCWSTR lpFmt, ...)
{
    va_list args;
    va_start(args, lpFmt);
    int res = vswprintf(lpOut, 1024, lpFmt, args);
    va_end(args);
    return res;
}

int wsprintfA(LPSTR lpOut, LPCSTR lpFmt, ...)
{
    va_list args;
    va_start(args, lpFmt);
    int res = vsprintf(lpOut, lpFmt, args);
    va_end(args);
    return res;
}

char* _itoa(int value, char* str, int radix)
{
    if (!str) return nullptr;
    if (radix == 10) {
        sprintf(str, "%d", value);
    } else if (radix == 16) {
        sprintf(str, "%x", value);
    } else if (radix == 8) {
        sprintf(str, "%o", value);
    } else {
        sprintf(str, "%d", value);
    }
    return str;
}

wchar_t* _itow(int value, wchar_t* str, int radix)
{
    if (!str) return nullptr;
    if (radix == 10) {
        swprintf(str, 32, L"%d", value);
    } else if (radix == 16) {
        swprintf(str, 32, L"%x", value);
    } else if (radix == 8) {
        swprintf(str, 32, L"%o", value);
    } else {
        swprintf(str, 32, L"%d", value);
    }
    return str;
}

char* _ltoa(long value, char* str, int radix)
{
    return _itoa(static_cast<int>(value), str, radix);
}

wchar_t* _ltow(long value, wchar_t* str, int radix)
{
    return _itow(static_cast<int>(value), str, radix);
}

} // extern "C"

// ============================================================================
// Win32_IO_File implementation for macOS
// ============================================================================

Win32_IO_File::Win32_IO_File(const wchar_t *fname)
{
    if (fname)
    {
        _path = wstring_to_utf8(fname);
        _hFile = ::CreateFileW(fname, _accessParam, _shareParam, NULL, CREATE_ALWAYS, _attribParam, NULL);
        if (_hFile == INVALID_HANDLE_VALUE)
        {
            _dwErrorCode = ::GetLastError();
        }
    }
}

void Win32_IO_File::close()
{
    _dwErrorCode = NO_ERROR;
    if (isOpened())
    {
        if (_written)
        {
            ::FlushFileBuffers(_hFile);
        }
        ::CloseHandle(_hFile);
        _hFile = INVALID_HANDLE_VALUE;
    }
}

bool Win32_IO_File::write(const void *wbuf, size_t buf_size)
{
    if (!isOpened() || !wbuf || buf_size == 0) return false;
    DWORD bytesWritten = 0;
    BOOL res = ::WriteFile(_hFile, wbuf, static_cast<DWORD>(buf_size), &bytesWritten, NULL);
    if (res && bytesWritten == buf_size)
    {
        _written = true;
        return true;
    }
    _dwErrorCode = ::GetLastError();
    return false;
}
