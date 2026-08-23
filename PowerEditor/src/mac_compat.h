// macOS platform compatibility header for Notepad++
// Maps Win32 types, structures, macros, constants, and APIs to macOS / POSIX / Cocoa

#pragma once
#ifndef MAC_COMPAT_H
#define MAC_COMPAT_H

#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <cassert>
#include <assert.h>
#include <string>
#include <vector>
#include <memory>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <iostream>
#include <sstream>

#ifndef _byteswap_ushort
#define _byteswap_ushort(x) __builtin_bswap16(x)
#endif
#ifndef _byteswap_ulong
#define _byteswap_ulong(x) __builtin_bswap32(x)
#endif
#ifndef _byteswap_uint64
#define _byteswap_uint64(x) __builtin_bswap64(x)
#endif

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <dlfcn.h>
#include <pthread.h>
#include <mach/mach_time.h>

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#endif

// ============================================================================
// 1. Basic Win32 Types & Primitive Aliases
// ============================================================================

typedef uint8_t   BYTE;
typedef uint8_t   UCHAR;
typedef uint8_t   byte;
typedef uint16_t  WORD;
typedef uint16_t  USHORT;
typedef uint32_t  DWORD;
typedef uint32_t  UINT;
typedef uint32_t  ULONG;
typedef int32_t   LONG;
typedef int32_t   INT;
typedef int16_t   SHORT;
typedef int64_t   LONGLONG;
typedef uint64_t  ULONGLONG;
#ifndef __OBJC__
typedef int32_t   BOOL;
typedef int32_t*  LPBOOL;
#else
typedef BOOL*     LPBOOL;
#endif
typedef float     FLOAT;
typedef double    DOUBLE;

typedef int*       LPINT;
typedef int*       PINT;
typedef int32_t*   LPLONG;
typedef uint32_t*  LPDWORD;
typedef uint8_t*   LPBYTE;
typedef uint16_t*  LPWORD;

#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

typedef void* LPVOID;
typedef const void* LPCVOID;
typedef void* PVOID;
typedef char* LPSTR;
typedef const char* LPCSTR;
typedef char* PSTR;
typedef const char* PCSTR;

typedef wchar_t WCHAR;
typedef wchar_t* LPWSTR;
typedef const wchar_t* LPCWSTR;
typedef wchar_t* PWSTR;
typedef const wchar_t* PCWSTR;

typedef wchar_t TCHAR;
typedef wchar_t* LPTSTR;
typedef const wchar_t* LPCTSTR;
typedef wchar_t _TCHAR;

typedef uint32_t COLORREF;
typedef intptr_t INT_PTR;
typedef uintptr_t UINT_PTR;
typedef intptr_t LONG_PTR;
typedef uintptr_t ULONG_PTR;
typedef uintptr_t DWORD_PTR;
typedef intptr_t LRESULT;
typedef uintptr_t WPARAM;
typedef intptr_t LPARAM;
typedef int32_t HRESULT;

typedef void* HANDLE;
typedef void* HWND;
typedef void* HINSTANCE;
typedef void* HMODULE;
typedef void* HDC;
typedef void* HMENU;
typedef void* HICON;
typedef void* HCURSOR;
typedef void* HBITMAP;
typedef void* HBRUSH;
typedef void* HFONT;
typedef void* HRGN;
typedef void* HIMAGELIST;
typedef void* HMONITOR;
typedef void* HGLOBAL;
typedef void* HKEY;
typedef void* HTREEITEM;
typedef void* HIMC;
typedef void* HACCEL;
typedef void* HPEN;
typedef void* HRSRC;
typedef void* HGDIOBJ;

#define INVALID_HANDLE_VALUE ((HANDLE)(intptr_t)-1)

typedef DWORD LCID;
typedef DWORD LGRPID;
typedef DWORD LCTYPE;
typedef DWORD CALID;
typedef DWORD CALTYPE;

typedef LRESULT (*WNDPROC)(HWND, UINT, WPARAM, LPARAM);
typedef INT_PTR (*DLGPROC)(HWND, UINT, WPARAM, LPARAM);
typedef void (*TIMERPROC)(HWND, UINT, UINT_PTR, DWORD);

// ============================================================================
// 2. Calling Conventions & Attributes
// ============================================================================

#define CALLBACK
#define WINAPI
#define APIENTRY
#define CONST const
#define VOID void
#define STDMETHODCALLTYPE
#define STDAPICALLTYPE
#ifndef __stdcall
#define __stdcall
#endif
#ifndef __cdecl
#define __cdecl
#endif
#ifndef __fastcall
#define __fastcall
#endif
#ifndef __forceinline
#define __forceinline inline __attribute__((always_inline))
#endif

#ifndef _MSC_VER
#ifndef __try
#define __try try
#endif
#ifndef __except
#define __except(x) catch(...)
#endif
#ifndef EXCEPTION_EXECUTE_HANDLER
#define EXCEPTION_EXECUTE_HANDLER 1
#endif
#ifndef EXCEPTION_CONTINUE_SEARCH
#define EXCEPTION_CONTINUE_SEARCH 0
#endif
#ifndef GetExceptionCode
#define GetExceptionCode() 0
#endif
#endif

// ============================================================================
// 3. Macros & Utilities
// ============================================================================

#define RGB(r,g,b) ((COLORREF)(((BYTE)(r)|((WORD)((BYTE)(g))<<8))|(((DWORD)(BYTE)(b))<<16)))
#define GetRValue(rgb) ((BYTE)(rgb))
#define GetGValue(rgb) ((BYTE)(((WORD)(rgb)) >> 8))
#define GetBValue(rgb) ((BYTE)((rgb)>>16))

#define LOWORD(l) ((WORD)(((DWORD_PTR)(l)) & 0xffff))
#define HIWORD(l) ((WORD)((((DWORD_PTR)(l)) >> 16) & 0xffff))
#define LOBYTE(w) ((BYTE)(((DWORD_PTR)(w)) & 0xff))
#define HIBYTE(w) ((BYTE)((((DWORD_PTR)(w)) >> 8) & 0xff))

#define MAKELONG(a, b) ((LONG)(((WORD)(((DWORD_PTR)(a)) & 0xffff)) | ((DWORD)((WORD)(((DWORD_PTR)(b)) & 0xffff))) << 16))
#define MAKEWPARAM(l, h) ((WPARAM)(DWORD)MAKELONG(l, h))
#define MAKELPARAM(l, h) ((LPARAM)(DWORD)MAKELONG(l, h))
#define MAKELRESULT(l, h) ((LRESULT)(DWORD)MAKELONG(l, h))
#define MAKEWORD(a, b) ((WORD)(((BYTE)(((DWORD_PTR)(a)) & 0xff)) | ((WORD)((BYTE)(((DWORD_PTR)(b)) & 0xff))) << 8))

#ifndef _countof
#define _countof(array) (sizeof(array) / sizeof((array)[0]))
#endif

#ifndef ARRAYSIZE
#define ARRAYSIZE(array) _countof(array)
#endif

#define TEXT(quote) L##quote
#ifndef _T
#define _T(quote) L##quote
#endif

#define ZeroMemory(Destination,Length) memset((Destination),0,(Length))
#define CopyMemory(Destination,Source,Length) memcpy((Destination),(Source),(Length))
#define MoveMemory(Destination,Source,Length) memmove((Destination),(Source),(Length))
#define FillMemory(Destination,Length,Fill) memset((Destination),(Fill),(Length))

#define UNREFERENCED_PARAMETER(P) (void)(P)

// ============================================================================
// 4. Win32 Structs
// ============================================================================

struct RECT {
    LONG left;
    LONG top;
    LONG right;
    LONG bottom;
};
typedef RECT* LPRECT;
typedef const RECT* LPCRECT;

struct POINT {
    LONG x;
    LONG y;
};
typedef POINT* LPPOINT;
typedef POINT POINTL;

struct SIZE {
    LONG cx;
    LONG cy;
};
typedef SIZE* LPSIZE;
typedef SIZE SIZEL;

struct FILETIME {
    DWORD dwLowDateTime;
    DWORD dwHighDateTime;
};
typedef FILETIME* LPFILETIME;

struct SYSTEMTIME {
    WORD wYear;
    WORD wMonth;
    WORD wDayOfWeek;
    WORD wDay;
    WORD wHour;
    WORD wMinute;
    WORD wSecond;
    WORD wMilliseconds;
};
typedef SYSTEMTIME* LPSYSTEMTIME;

union LARGE_INTEGER {
    struct {
        DWORD LowPart;
        LONG HighPart;
    };
    struct {
        DWORD LowPart;
        LONG HighPart;
    } u;
    LONGLONG QuadPart;
};
typedef LARGE_INTEGER* LPLARGE_INTEGER;

union ULARGE_INTEGER {
    struct {
        DWORD LowPart;
        DWORD HighPart;
    };
    struct {
        DWORD LowPart;
        DWORD HighPart;
    } u;
    ULONGLONG QuadPart;
};
typedef ULARGE_INTEGER* LPULARGE_INTEGER;

#ifndef MAX_PATH
#define MAX_PATH 1024
#endif
#ifndef _MAX_PATH
#define _MAX_PATH 1024
#endif
#ifndef _MAX_DRIVE
#define _MAX_DRIVE 3
#endif
#ifndef _MAX_DIR
#define _MAX_DIR 1024
#endif
#ifndef _MAX_FNAME
#define _MAX_FNAME 256
#endif
#ifndef _MAX_EXT
#define _MAX_EXT 256
#endif

struct WIN32_FIND_DATAW {
    DWORD dwFileAttributes;
    FILETIME ftCreationTime;
    FILETIME ftLastAccessTime;
    FILETIME ftLastWriteTime;
    DWORD nFileSizeHigh;
    DWORD nFileSizeLow;
    DWORD dwReserved0;
    DWORD dwReserved1;
    WCHAR cFileName[MAX_PATH];
    WCHAR cAlternateFileName[14];
};
typedef WIN32_FIND_DATAW* LPWIN32_FIND_DATAW;
typedef WIN32_FIND_DATAW WIN32_FIND_DATA;
typedef WIN32_FIND_DATAW* LPWIN32_FIND_DATA;

struct WIN32_FILE_ATTRIBUTE_DATA {
    DWORD dwFileAttributes;
    FILETIME ftCreationTime;
    FILETIME ftLastAccessTime;
    FILETIME ftLastWriteTime;
    DWORD nFileSizeHigh;
    DWORD nFileSizeLow;
};
typedef WIN32_FILE_ATTRIBUTE_DATA* LPWIN32_FILE_ATTRIBUTE_DATA;

enum STREAM_INFO_LEVELS {
    FindStreamInfoStandard = 0,
    FindStreamInfoMaxInfoLevel
};

struct WIN32_FIND_STREAM_DATA {
    LARGE_INTEGER StreamSize;
    WCHAR cStreamName[MAX_PATH + 36];
};
typedef WIN32_FIND_STREAM_DATA* LPWIN32_FIND_STREAM_DATA;

struct MSG {
    HWND hwnd;
    UINT message;
    WPARAM wParam;
    LPARAM lParam;
    DWORD time;
    POINT pt;
};
typedef MSG* LPMSG;

struct NMHDR {
    HWND hwndFrom;
    UINT_PTR idFrom;
    UINT code;
};
typedef NMHDR* LPNMHDR;

struct PAINTSTRUCT {
    HDC hdc;
    BOOL fErase;
    RECT rcPaint;
    BOOL fRestore;
    BOOL fIncUpdate;
    BYTE rgbReserved[32];
};
typedef PAINTSTRUCT* LPPAINTSTRUCT;

struct LOGFONTW {
    LONG lfHeight;
    LONG lfWidth;
    LONG lfEscapement;
    LONG lfOrientation;
    LONG lfWeight;
    BYTE lfItalic;
    BYTE lfUnderline;
    BYTE lfStrikeOut;
    BYTE lfCharSet;
    BYTE lfOutPrecision;
    BYTE lfClipPrecision;
    BYTE lfQuality;
    BYTE lfPitchAndFamily;
    WCHAR lfFaceName[32];
};
typedef LOGFONTW* LPLOGFONTW;
typedef LOGFONTW LOGFONT;
typedef LOGFONTW* LPLOGFONT;

struct TEXTMETRICW {
    LONG tmHeight;
    LONG tmAscent;
    LONG tmDescent;
    LONG tmInternalLeading;
    LONG tmExternalLeading;
    LONG tmAveCharWidth;
    LONG tmMaxCharWidth;
    LONG tmWeight;
    LONG tmOverhang;
    LONG tmDigitizedAspectX;
    LONG tmDigitizedAspectY;
    WCHAR tmFirstChar;
    WCHAR tmLastChar;
    WCHAR tmDefaultChar;
    WCHAR tmBreakChar;
    BYTE tmItalic;
    BYTE tmUnderlined;
    BYTE tmStruckOut;
    BYTE tmPitchAndFamily;
    BYTE tmCharSet;
};
typedef TEXTMETRICW* LPTEXTMETRICW;
typedef TEXTMETRICW TEXTMETRIC;

struct WINDOWPOS {
    HWND hwnd;
    HWND hwndInsertAfter;
    int x;
    int y;
    int cx;
    int cy;
    UINT flags;
};
typedef WINDOWPOS* LPWINDOWPOS;

struct CREATESTRUCTW {
    LPVOID lpCreateParams;
    HINSTANCE hInstance;
    HMENU hMenu;
    HWND hwndParent;
    int cy;
    int cx;
    int y;
    int x;
    LONG style;
    LPCWSTR lpszName;
    LPCWSTR lpszClass;
    DWORD dwExStyle;
};
typedef CREATESTRUCTW* LPCREATESTRUCTW;
typedef CREATESTRUCTW CREATESTRUCT;

struct DRAWITEMSTRUCT {
    UINT CtlType;
    UINT CtlID;
    UINT itemID;
    UINT itemAction;
    UINT itemState;
    HWND hwndItem;
    HDC hDC;
    RECT rcItem;
    ULONG_PTR itemData;
};
typedef DRAWITEMSTRUCT* LPDRAWITEMSTRUCT;

struct MEASUREITEMSTRUCT {
    UINT CtlType;
    UINT CtlID;
    UINT itemID;
    UINT itemWidth;
    UINT itemHeight;
    ULONG_PTR itemData;
};
typedef MEASUREITEMSTRUCT* LPMEASUREITEMSTRUCT;

struct DELETEITEMSTRUCT {
    UINT CtlType;
    UINT CtlID;
    UINT itemID;
    HWND hwndItem;
    ULONG_PTR itemData;
};
typedef DELETEITEMSTRUCT* LPDELETEITEMSTRUCT;

struct COMPAREITEMSTRUCT {
    UINT CtlType;
    UINT CtlID;
    HWND hwndItem;
    UINT itemID1;
    ULONG_PTR itemData1;
    UINT itemID2;
    ULONG_PTR itemData2;
    DWORD dwLocaleId;
};
typedef COMPAREITEMSTRUCT* LPCOMPAREITEMSTRUCT;

struct COPYDATASTRUCT {
    ULONG_PTR dwData;
    DWORD cbData;
    PVOID lpData;
};
typedef COPYDATASTRUCT* PCOPYDATASTRUCT;

struct CRITICAL_SECTION {
    pthread_mutex_t mutex;
};
typedef CRITICAL_SECTION* LPCRITICAL_SECTION;

// ============================================================================
// 5. Constants & Flags
// ============================================================================

#define S_OK                            ((HRESULT)0L)
#define S_FALSE                         ((HRESULT)1L)
#define E_FAIL                          ((HRESULT)0x80004005L)
#define E_INVALIDARG                    ((HRESULT)0x80070057L)
#define E_OUTOFMEMORY                   ((HRESULT)0x8007000EL)
#define E_NOTIMPL                       ((HRESULT)0x80004001L)
#define E_NOINTERFACE                   ((HRESULT)0x80004002L)
#define SUCCEEDED(hr)                   (((HRESULT)(hr)) >= 0)
#define FAILED(hr)                      (((HRESULT)(hr)) < 0)

#define NO_ERROR                        0L
#define ERROR_SUCCESS                   0L
#define ERROR_FILE_NOT_FOUND            2L
#define ERROR_PATH_NOT_FOUND            3L
#define ERROR_ACCESS_DENIED             5L
#define ERROR_INVALID_HANDLE            6L
#define ERROR_NOT_ENOUGH_MEMORY         8L
#define ERROR_OUTOFMEMORY               14L
#define ERROR_SHARING_VIOLATION         32L
#define ERROR_FILE_EXISTS               80L
#define ERROR_INSUFFICIENT_BUFFER       122L
#define ERROR_ALREADY_EXISTS            183L
#define ERROR_NO_MORE_FILES             18L
#define ERROR_OPERATION_ABORTED         995L

#define GENERIC_READ                    0x80000000
#define GENERIC_WRITE                   0x40000000
#define GENERIC_EXECUTE                 0x20000000
#define GENERIC_ALL                     0x10000000

#define FILE_SHARE_READ                 0x00000001
#define FILE_SHARE_WRITE                0x00000002
#define FILE_SHARE_DELETE               0x00000004

#define CREATE_NEW                      1
#define CREATE_ALWAYS                   2
#define OPEN_EXISTING                   3
#define OPEN_ALWAYS                     4
#define TRUNCATE_EXISTING               5

#define FILE_ATTRIBUTE_READONLY         0x00000001
#define FILE_ATTRIBUTE_HIDDEN           0x00000002
#define FILE_ATTRIBUTE_SYSTEM           0x00000004
#define FILE_ATTRIBUTE_DIRECTORY        0x00000010
#define FILE_ATTRIBUTE_ARCHIVE          0x00000020
#define FILE_ATTRIBUTE_DEVICE           0x00000040
#define FILE_ATTRIBUTE_NORMAL           0x00000080
#define FILE_ATTRIBUTE_TEMPORARY        0x00000100
#define INVALID_FILE_ATTRIBUTES         ((DWORD)-1)

#define FILE_BEGIN                      0
#define FILE_CURRENT                    1
#define FILE_END                        2
#define INVALID_SET_FILE_POINTER        ((DWORD)-1)

#define SW_HIDE                         0
#define SW_SHOWNORMAL                   1
#define SW_NORMAL                       1
#define SW_SHOWMINIMIZED                2
#define SW_SHOWMAXIMIZED                3
#define SW_MAXIMIZE                     3
#define SW_SHOWNOACTIVATE               4
#define SW_SHOW                         5
#define SW_MINIMIZE                     6
#define SW_SHOWMINNOACTIVE              7
#define SW_SHOWNA                       8
#define SW_RESTORE                      9
#define SW_SHOWDEFAULT                  10

#define WS_OVERLAPPED                   0x00000000L
#define WS_POPUP                        0x80000000L
#define WS_CHILD                        0x40000000L
#define WS_MINIMIZE                     0x20000000L
#define WS_VISIBLE                      0x10000000L
#define WS_DISABLED                     0x08000000L
#define WS_CLIPSIBLINGS                 0x04000000L
#define WS_CLIPCHILDREN                 0x02000000L
#define WS_MAXIMIZE                     0x01000000L
#define WS_CAPTION                      0x00C00000L
#define WS_BORDER                       0x00800000L
#define WS_DLGFRAME                     0x00400000L
#define WS_VSCROLL                      0x00200000L
#define WS_HSCROLL                      0x00100000L
#define WS_SYSMENU                      0x00080000L
#define WS_THICKFRAME                   0x00040000L
#define WS_GROUP                        0x00020000L
#define WS_TABSTOP                      0x00010000L
#define WS_MINIMIZEBOX                  0x00020000L
#define WS_MAXIMIZEBOX                  0x00010000L
#define WS_OVERLAPPEDWINDOW             (WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)
#define WS_POPUPWINDOW                  (WS_POPUP | WS_BORDER | WS_SYSMENU)
#define WS_CHILDWINDOW                  (WS_CHILD)

#define WS_EX_CLIENTEDGE                0x00000200L
#define WS_EX_TOOLWINDOW                0x00000080L
#define WS_EX_TOPMOST                   0x00000008L
#define WS_EX_LAYERED                   0x00080000L
#define WS_EX_NOACTIVATE                0x08000000L

#define MB_OK                           0x00000000L
#define MB_OKCANCEL                     0x00000001L
#define MB_ABORTRETRYIGNORE             0x00000002L
#define MB_YESNOCANCEL                  0x00000003L
#define MB_YESNO                        0x00000004L
#define MB_RETRYCANCEL                  0x00000005L
#define MB_ICONHAND                     0x00000010L
#define MB_ICONQUESTION                 0x00000020L
#define MB_ICONEXCLAMATION              0x00000030L
#define MB_ICONASTERISK                 0x00000040L
#define MB_ICONWARNING                  MB_ICONEXCLAMATION
#define MB_ICONERROR                    MB_ICONHAND
#define MB_ICONINFORMATION              MB_ICONASTERISK
#define MB_ICONSTOP                     MB_ICONHAND

#define IS_TEXT_UNICODE_ASCII16              0x0001
#define IS_TEXT_UNICODE_REVERSE_ASCII16      0x0010
#define IS_TEXT_UNICODE_STATISTICS           0x0002
#define IS_TEXT_UNICODE_REVERSE_STATISTICS   0x0020
#define IS_TEXT_UNICODE_CONTROLS             0x0004
#define IS_TEXT_UNICODE_REVERSE_CONTROLS     0x0040
#define IS_TEXT_UNICODE_SIGNATURE            0x0008
#define IS_TEXT_UNICODE_REVERSE_SIGNATURE    0x0080
#define IS_TEXT_UNICODE_ILLEGAL_CHARS        0x0100
#define IS_TEXT_UNICODE_ODD_LENGTH           0x0200
#define IS_TEXT_UNICODE_DBCS_LEADBYTE        0x0400
#define IS_TEXT_UNICODE_NULL_BYTES           0x1000
#define IS_TEXT_UNICODE_UNICODE_MASK         0x000F
#define IS_TEXT_UNICODE_REVERSE_MASK         0x00F0
#define IS_TEXT_UNICODE_NOT_UNICODE_MASK     0x0F00
#define IS_TEXT_UNICODE_NOT_ASCII_MASK       0xF000

#define IDOK                            1
#define IDCANCEL                        2
#define IDABORT                         3
#define IDRETRY                         4
#define IDIGNORE                        5
#define IDYES                           6
#define IDNO                            7
#define IDCLOSE                         8
#define IDHELP                          9

#define CP_ACP                          0
#define CP_OEMCP                        1
#define CP_MACCP                        2
#define CP_THREAD_ACP                   3
#define CP_SYMBOL                       42
#define CP_UTF7                         65000
#define CP_UTF8                         65001

#define MB_PRECOMPOSED                  0x00000001
#define MB_COMPOSITE                    0x00000002
#define MB_USEGLYPHCHARS                0x00000004
#define MB_ERR_INVALID_CHARS            0x00000008
#define WC_COMPOSITECHECK               0x00000200
#define WC_DISCARDNS                    0x00000010
#define WC_SEPCHARS                     0x00000020
#define WC_DEFAULTCHAR                  0x00000040
#define WC_ERR_INVALID_CHARS            0x00000080
#define WC_NO_BEST_FIT_CHARS            0x00000400

#define CSIDL_DESKTOP                   0x0000
#define CSIDL_PERSONAL                  0x0005
#define CSIDL_MYDOCUMENTS               0x0005
#define CSIDL_FAVORITES                 0x0006
#define CSIDL_APPDATA                   0x001a
#define CSIDL_LOCAL_APPDATA             0x001c
#define CSIDL_COMMON_APPDATA            0x0023
#define CSIDL_PROGRAM_FILES             0x0026
#define CSIDL_MYPICTURES                0x0027
#define CSIDL_PROFILE                   0x0028

#define CF_TEXT                         1
#define CF_BITMAP                       2
#define CF_UNICODETEXT                  13
#define CF_HDROP                        15

#define GMEM_FIXED                      0x0000
#define GMEM_MOVEABLE                   0x0002
#define GMEM_ZEROINIT                   0x0040
#define GHND                            (GMEM_MOVEABLE | GMEM_ZEROINIT)
#define GPTR                            (GMEM_FIXED | GMEM_ZEROINIT)

#define SM_CXSCREEN                     0
#define SM_CYSCREEN                     1
#define SM_CXVSCROLL                    2
#define SM_CYHSCROLL                    3
#define SM_CYCAPTION                    4
#define SM_CXBORDER                     5
#define SM_CYBORDER                     6
#define SM_CXFRAME                      32
#define SM_CYFRAME                      33

#define GWL_STYLE                       (-16)
#define GWL_EXSTYLE                     (-20)
#define GWL_WNDPROC                     (-4)
#define GWL_HINSTANCE                   (-6)
#define GWL_HWNDPARENT                  (-8)
#define GWL_ID                          (-12)
#define GWL_USERDATA                    (-21)
#define GWLP_USERDATA                   (-21)
#define GWLP_WNDPROC                    (-4)
#define GWLP_HINSTANCE                  (-6)
#define GWLP_HWNDPARENT                 (-8)
#define GWLP_ID                         (-12)

#define SWP_NOSIZE                      0x0001
#define SWP_NOMOVE                      0x0002
#define SWP_NOZORDER                    0x0004
#define SWP_NOREDRAW                    0x0008
#define SWP_NOACTIVATE                  0x0010
#define SWP_FRAMECHANGED                0x0020
#define SWP_SHOWWINDOW                  0x0040
#define SWP_HIDEWINDOW                  0x0080
#define SWP_NOCOPYBITS                  0x0100
#define SWP_NOOWNERZORDER               0x0200
#define SWP_NOSENDCHANGING              0x0400

#define HWND_TOP                        ((HWND)0)
#define HWND_BOTTOM                     ((HWND)1)
#define HWND_TOPMOST                    ((HWND)-1)
#define HWND_NOTOPMOST                  ((HWND)-2)

#define WAIT_OBJECT_0                   0
#define WAIT_ABANDONED                  0x00000080L
#define WAIT_TIMEOUT                    0x00000102L
#define WAIT_FAILED                     ((DWORD)0xFFFFFFFF)
#define INFINITE                        0xFFFFFFFF

// Windows Messages
#define WM_NULL                         0x0000
#define WM_CREATE                       0x0001
#define WM_DESTROY                      0x0002
#define WM_MOVE                         0x0003
#define WM_SIZE                         0x0005
#define WM_ACTIVATE                     0x0006
#define WM_SETFOCUS                     0x0007
#define WM_KILLFOCUS                    0x0008
#define WM_ENABLE                       0x000A
#define WM_SETREDRAW                    0x000B
#define WM_SETTEXT                      0x000C
#define WM_GETTEXT                      0x000D
#define WM_GETTEXTLENGTH                0x000E
#define WM_PAINT                        0x000F
#define WM_CLOSE                        0x0010
#define WM_QUERYENDSESSION              0x0011
#define WM_QUERYOPEN                    0x0013
#define WM_ENDSESSION                   0x0016
#define WM_QUIT                         0x0012
#define WM_ERASEBKGND                   0x0014
#define WM_SYSCOLORCHANGE               0x0015
#define WM_SHOWWINDOW                   0x0018
#define WM_SETCURSOR                    0x0020
#define WM_MOUSEACTIVATE                0x0021
#define WM_DRAWITEM                     0x002B
#define WM_MEASUREITEM                  0x002C
#define WM_DELETEITEM                   0x002D
#define WM_VKEYTOITEM                   0x002E
#define WM_CHARTOITEM                   0x002F
#define WM_SETFONT                      0x0030
#define WM_GETFONT                      0x0031
#define WM_WINDOWPOSCHANGING            0x0046
#define WM_WINDOWPOSCHANGED             0x0047
#ifndef WM_NOTIFY
#define WM_NOTIFY                       0x004E
#endif
#define WM_CONTEXTMENU                  0x007B
#define WM_NCCREATE                     0x0081
#define WM_NCDESTROY                    0x0082
#define WM_NCCALCSIZE                   0x0083
#define WM_NCHITTEST                    0x0084
#define WM_NCPAINT                      0x0085
#define WM_GETDLGCODE                   0x0087
#define WM_KEYDOWN                      0x0100
#define WM_KEYUP                        0x0101
#define WM_CHAR                         0x0102
#define WM_DEADCHAR                     0x0103
#define WM_SYSKEYDOWN                   0x0104
#define WM_SYSKEYUP                     0x0105
#define WM_SYSCHAR                      0x0106
#define WM_SYSDEADCHAR                  0x0107
#define WM_INITDIALOG                   0x0110
#ifndef WM_COMMAND
#define WM_COMMAND                      0x0111
#endif
#define WM_SYSCOMMAND                   0x0112
#define WM_TIMER                        0x0113
#define WM_HSCROLL                      0x0114
#define WM_VSCROLL                      0x0115
#define WM_MOUSEMOVE                    0x0200
#define WM_LBUTTONDOWN                  0x0201
#define WM_LBUTTONUP                    0x0202
#define WM_LBUTTONDBLCLK                0x0203
#define WM_RBUTTONDOWN                  0x0204
#define WM_RBUTTONUP                    0x0205
#define WM_RBUTTONDBLCLK                0x0206
#define WM_MBUTTONDOWN                  0x0207
#define WM_MBUTTONUP                    0x0208
#define WM_MBUTTONDBLCLK                0x0209
#define WM_MOUSEWHEEL                   0x020A
#define WM_COPYDATA                     0x004A
#define WM_USER                         0x0400
#define WM_APP                          0x8000

#define MF_BYCOMMAND                    0x00000000L
#define MF_BYPOSITION                   0x00000400L
#define MF_ENABLED                      0x00000000L
#define MF_GRAYED                       0x00000001L
#define MF_DISABLED                     0x00000002L
#define MF_UNCHECKED                    0x00000000L
#define MF_CHECKED                      0x00000008L
#define MF_STRING                       0x00000000L
#define MF_SEPARATOR                    0x00000800L
#define MF_POPUP                        0x00000010L

// ============================================================================
// 6. Win32 Function Prototypes (implemented in mac_compat.cpp)
// ============================================================================

#ifdef __cplusplus
extern "C" {
#endif

// Error handling
DWORD GetLastError(VOID);
VOID SetLastError(DWORD dwErrCode);
DWORD FormatMessageW(DWORD dwFlags, LPCVOID lpSource, DWORD dwMessageId, DWORD dwLanguageId, LPWSTR lpBuffer, DWORD nSize, void* Arguments);

// Codepage and Unicode conversions
UINT GetACP(VOID);
UINT GetOEMCP(VOID);
BOOL IsValidCodePage(UINT CodePage);
int MultiByteToWideChar(UINT CodePage, DWORD dwFlags, LPCSTR lpMultiByteStr, int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar);
int WideCharToMultiByte(UINT CodePage, DWORD dwFlags, LPCWSTR lpWideCharStr, int cchWideChar, LPSTR lpMultiByteStr, int cbMultiByte, LPCSTR lpDefaultChar, BOOL* lpUsedDefaultChar);
BOOL IsTextUnicode(const void* lpv, int iSize, LPINT lpiResult);

// File I/O
HANDLE CreateFileW(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, void* lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
BOOL ReadFile(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, DWORD* lpNumberOfBytesRead, void* lpOverlapped);
BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite, DWORD* lpNumberOfBytesWritten, void* lpOverlapped);
BOOL CloseHandle(HANDLE hObject);
DWORD GetFileSize(HANDLE hFile, DWORD* lpFileSizeHigh);
BOOL GetFileSizeEx(HANDLE hFile, LARGE_INTEGER* lpFileSize);
DWORD SetFilePointer(HANDLE hFile, LONG lDistanceToMove, LONG* lpDistanceToMoveHigh, DWORD dwMoveMethod);
BOOL SetFilePointerEx(HANDLE hFile, LARGE_INTEGER liDistanceToMove, LARGE_INTEGER* lpNewFilePointer, DWORD dwMoveMethod);
BOOL SetEndOfFile(HANDLE hFile);
BOOL FlushFileBuffers(HANDLE hFile);

// File attributes and timestamps
DWORD GetFileAttributesW(LPCWSTR lpFileName);
BOOL SetFileAttributesW(LPCWSTR lpFileName, DWORD dwFileAttributes);
BOOL GetFileAttributesExW(LPCWSTR lpFileName, int fInfoLevelId, LPVOID lpFileInformation);
BOOL GetFileTime(HANDLE hFile, LPFILETIME lpCreationTime, LPFILETIME lpLastAccessTime, LPFILETIME lpLastWriteTime);
BOOL SetFileTime(HANDLE hFile, const FILETIME* lpCreationTime, const FILETIME* lpLastAccessTime, const FILETIME* lpLastWriteTime);
BOOL FileTimeToSystemTime(const FILETIME* lpFileTime, LPSYSTEMTIME lpSystemTime);
BOOL SystemTimeToFileTime(const SYSTEMTIME* lpSystemTime, LPFILETIME lpFileTime);
BOOL FileTimeToLocalFileTime(const FILETIME* lpFileTime, LPFILETIME lpLocalFileTime);
BOOL LocalFileTimeToFileTime(const FILETIME* lpLocalFileTime, LPFILETIME lpFileTime);
LONG CompareFileTime(const FILETIME* lpFileTime1, const FILETIME* lpFileTime2);

// Directory and filesystem searching
HANDLE FindFirstFileW(LPCWSTR lpFileName, LPWIN32_FIND_DATAW lpFindFileData);
BOOL FindNextFileW(HANDLE hFindFile, LPWIN32_FIND_DATAW lpFindFileData);
BOOL FindClose(HANDLE hFindFile);
HANDLE FindFirstStreamW(LPCWSTR lpFileName, int InfoLevel, LPVOID lpFindStreamData, DWORD dwFlags);

BOOL DeleteFileW(LPCWSTR lpFileName);
BOOL MoveFileW(LPCWSTR lpExistingFileName, LPCWSTR lpNewFileName);
BOOL MoveFileExW(LPCWSTR lpExistingFileName, LPCWSTR lpNewFileName, DWORD dwFlags);
BOOL CopyFileW(LPCWSTR lpExistingFileName, LPCWSTR lpNewFileName, BOOL bFailIfExists);
BOOL CreateDirectoryW(LPCWSTR lpPathName, void* lpSecurityAttributes);
BOOL RemoveDirectoryW(LPCWSTR lpPathName);
DWORD GetCurrentDirectoryW(DWORD nBufferLength, LPWSTR lpBuffer);
BOOL SetCurrentDirectoryW(LPCWSTR lpPathName);
DWORD GetFullPathNameW(LPCWSTR lpFileName, DWORD nBufferLength, LPWSTR lpBuffer, LPWSTR* lpFilePart);
DWORD GetLongPathNameW(LPCWSTR lpszShortPath, LPWSTR lpszLongPath, DWORD cchBuffer);
DWORD GetShortPathNameW(LPCWSTR lpszLongPath, LPWSTR lpszShortPath, DWORD cchBuffer);
DWORD GetTempPathW(DWORD nBufferLength, LPWSTR lpBuffer);
UINT GetTempFileNameW(LPCWSTR lpPathName, LPCWSTR lpPrefixString, UINT uUnique, LPWSTR lpTempFileName);

// Path utility functions (shlwapi)
BOOL PathFileExistsW(LPCWSTR pszPath);
BOOL PathIsDirectoryW(LPCWSTR pszPath);
BOOL PathRemoveFileSpecW(LPWSTR pszPath);
LPWSTR PathCombineW(LPWSTR pszDest, LPCWSTR pszDir, LPCWSTR pszFile);
LPCWSTR PathFindFileNameW(LPCWSTR pszPath);
LPCWSTR PathFindExtensionW(LPCWSTR pszPath);
BOOL PathIsNetworkPathW(LPCWSTR pszPath);
BOOL PathIsRelativeW(LPCWSTR pszPath);
BOOL PathAppendW(LPWSTR pszPath, LPCWSTR pszMore);
BOOL PathMatchSpecW(LPCWSTR pszFile, LPCWSTR pszSpec);
void PathStripPathW(LPWSTR pszPath);

// Time and Clock
VOID GetLocalTime(LPSYSTEMTIME lpSystemTime);
VOID GetSystemTime(LPSYSTEMTIME lpSystemTime);
DWORD GetTickCount(VOID);
ULONGLONG GetTickCount64(VOID);
BOOL QueryPerformanceCounter(LARGE_INTEGER* lpPerformanceCount);
BOOL QueryPerformanceFrequency(LARGE_INTEGER* lpFrequency);
VOID Sleep(DWORD dwMilliseconds);

// Synchronization & Threads
VOID InitializeCriticalSection(LPCRITICAL_SECTION lpCriticalSection);
VOID DeleteCriticalSection(LPCRITICAL_SECTION lpCriticalSection);
VOID EnterCriticalSection(LPCRITICAL_SECTION lpCriticalSection);
VOID LeaveCriticalSection(LPCRITICAL_SECTION lpCriticalSection);
BOOL TryEnterCriticalSection(LPCRITICAL_SECTION lpCriticalSection);
HANDLE CreateThread(void* lpThreadAttributes, size_t dwStackSize, void* lpStartAddress, void* lpParameter, DWORD dwCreationFlags, DWORD* lpThreadId);
DWORD WaitForSingleObject(HANDLE hHandle, DWORD dwMilliseconds);
BOOL TerminateThread(HANDLE hThread, DWORD dwExitCode);
DWORD GetCurrentThreadId(VOID);
DWORD GetCurrentProcessId(VOID);

// Memory
HGLOBAL GlobalAlloc(UINT uFlags, size_t dwBytes);
LPVOID GlobalLock(HGLOBAL hMem);
BOOL GlobalUnlock(HGLOBAL hMem);
HGLOBAL GlobalFree(HGLOBAL hMem);
size_t GlobalSize(HGLOBAL hMem);

// Windows / GUI / Messages
LRESULT SendMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
BOOL PostMessageW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
BOOL PeekMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg);
BOOL GetMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax);
BOOL TranslateMessage(const MSG* lpMsg);
LRESULT DispatchMessageW(const MSG* lpMsg);
LRESULT DefWindowProcW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);
LRESULT CallWindowProcW(WNDPROC lpPrevWndFunc, HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam);

BOOL ShowWindow(HWND hWnd, int nCmdShow);
BOOL UpdateWindow(HWND hWnd);
BOOL InvalidateRect(HWND hWnd, const RECT* lpRect, BOOL bErase);
BOOL GetClientRect(HWND hWnd, LPRECT lpRect);
BOOL GetWindowRect(HWND hWnd, LPRECT lpRect);
BOOL MoveWindow(HWND hWnd, int X, int Y, int nWidth, int nHeight, BOOL bRepaint);
BOOL SetWindowPos(HWND hWnd, HWND hWndInsertAfter, int X, int Y, int cx, int cy, UINT uFlags);
HWND SetFocus(HWND hWnd);
HWND GetFocus(VOID);
BOOL EnableWindow(HWND hWnd, BOOL bEnable);
BOOL IsWindowEnabled(HWND hWnd);
BOOL IsWindowVisible(HWND hWnd);
BOOL DestroyWindow(HWND hWnd);
HWND GetParent(HWND hWnd);
HWND SetParent(HWND hWndChild, HWND hWndNewParent);
LONG_PTR GetWindowLongPtrW(HWND hWnd, int nIndex);
LONG_PTR SetWindowLongPtrW(HWND hWnd, int nIndex, LONG_PTR dwNewLong);

UINT_PTR SetTimer(HWND hWnd, UINT_PTR nIDEvent, UINT uElapse, TIMERPROC lpTimerFunc);
BOOL KillTimer(HWND hWnd, UINT_PTR uIDEvent);
int GetSystemMetrics(int nIndex);
int MessageBoxW(HWND hWnd, LPCWSTR lpText, LPCWSTR lpCaption, UINT uType);
int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);

// Clipboard
BOOL OpenClipboard(HWND hWndNewOwner);
BOOL CloseClipboard(VOID);
BOOL EmptyClipboard(VOID);
HANDLE GetClipboardData(UINT uFormat);
HANDLE SetClipboardData(UINT uFormat, HANDLE hMem);
BOOL IsClipboardFormatAvailable(UINT format);
UINT RegisterClipboardFormatW(LPCWSTR lpszFormat);

// Module / Library
HMODULE GetModuleHandleW(LPCWSTR lpModuleName);
HMODULE GetModuleHandleA(LPCSTR lpModuleName);
DWORD GetModuleFileNameW(HMODULE hModule, LPWSTR lpFilename, DWORD nSize);
HMODULE LoadLibraryW(LPCWSTR lpLibFileName);
BOOL FreeLibrary(HMODULE hLibModule);
void* GetProcAddress(HMODULE hModule, LPCSTR lpProcName);

// Shell & Registry stubs
HINSTANCE ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile, LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd);
HRESULT SHGetFolderPathW(HWND hwnd, int csidl, HANDLE hToken, DWORD dwFlags, LPWSTR pszPath);

LONG RegOpenKeyExW(HKEY hKey, LPCWSTR lpSubKey, DWORD ulOptions, DWORD samDesired, HKEY* phkResult);
LONG RegQueryValueExW(HKEY hKey, LPCWSTR lpValueName, DWORD* lpReserved, DWORD* lpType, BYTE* lpData, DWORD* lpcbData);
LONG RegSetValueExW(HKEY hKey, LPCWSTR lpValueName, DWORD Reserved, DWORD dwType, const BYTE* lpData, DWORD cbData);
LONG RegCloseKey(HKEY hKey);
LONG RegCreateKeyExW(HKEY hKey, LPCWSTR lpSubKey, DWORD Reserved, LPWSTR lpClass, DWORD dwOptions, DWORD samDesired, void* lpSecurityAttributes, HKEY* phkResult, DWORD* lpdwDisposition);
LONG RegDeleteKeyW(HKEY hKey, LPCWSTR lpSubKey);
LONG RegDeleteValueW(HKEY hKey, LPCWSTR lpValueName);

// String helpers
int _wcsicmp(const wchar_t* s1, const wchar_t* s2);
int _wcsnicmp(const wchar_t* s1, const wchar_t* s2, size_t n);
int _stricmp(const char* s1, const char* s2);
int _strnicmp(const char* s1, const char* s2, size_t n);
FILE* _wfopen(const wchar_t* filename, const wchar_t* mode);
int _wfopen_s(FILE** pFile, const wchar_t* filename, const wchar_t* mode);
int wcscpy_s(wchar_t* dest, size_t destsz, const wchar_t* src);
int wcscat_s(wchar_t* dest, size_t destsz, const wchar_t* src);
int wcsncpy_s(wchar_t* dest, size_t destsz, const wchar_t* src, size_t count);
int swprintf_s(wchar_t* buffer, size_t sizeOfBuffer, const wchar_t* format, ...);
int sprintf_s(char* buffer, size_t sizeOfBuffer, const char* format, ...);
int _splitpath_s(const char* path, char* drive, size_t driveNumberOfElements, char* dir, size_t dirNumberOfElements, char* fname, size_t fnameNumberOfElements, char* ext, size_t extNumberOfElements);
int _wsplitpath_s(const wchar_t* path, wchar_t* drive, size_t driveNumberOfElements, wchar_t* dir, size_t dirNumberOfElements, wchar_t* fname, size_t fnameNumberOfElements, wchar_t* ext, size_t extNumberOfElements);
int _wmakepath_s(wchar_t* path, size_t sizeInWords, const wchar_t* drive, const wchar_t* dir, const wchar_t* fname, const wchar_t* ext);
int wsprintfW(LPWSTR lpOut, LPCWSTR lpFmt, ...);
int wsprintfA(LPSTR lpOut, LPCSTR lpFmt, ...);
char* _itoa(int value, char* str, int radix);
wchar_t* _itow(int value, wchar_t* str, int radix);
char* _ltoa(long value, char* str, int radix);
wchar_t* _ltow(long value, wchar_t* str, int radix);

#ifdef __cplusplus
}
#endif

// Helper C++ utilities
std::string wstring_to_utf8(const std::wstring& wstr);
std::wstring utf8_to_wstring(const std::string& str);

#endif // MAC_COMPAT_H
