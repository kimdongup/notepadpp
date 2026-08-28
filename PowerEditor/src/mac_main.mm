// Notepad++ for macOS
// Complete Native Cocoa Frontend with:
// 1. Fully Resizable Panels (NSSplitView with draggable splitters for Left Finder, Bottom Terminal, and Right Preview)
// 2. Tab-Contextual Directory Routing (Active tab's parent folder on existing files, ~/ Home on new/untitled tabs)
// 3. Authentic macOS Terminal-style embedded console (ANSI color parsing, zsh execution, host title, history, Terminal.app button)
// 4. Column Mode & Column Editor (Edit -> Column Editor... ⌥⌘C, Option+Drag, Multi-Caret typing)
// 5. Secondary Side Panel Language Selection Guide & Live WebKit rendering

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <util.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <fcntl.h>
#include <string>
#include <vector>
#include <memory>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <map>
#include <set>
#include <ctime>
#include <iomanip>

#include "Scintilla.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"

#import "ScintillaView.h"
#include "mac_compat.h"
#include "uchardet/uchardet.h"
#include "Utf8_16.h"
#include "pugixml/pugixml.hpp"

extern "C" Scintilla::ILexer5* CreateLexer(const char *name);

// ============================================================================
// Document Structure
// ============================================================================

struct NppDocument {
    std::wstring filePath;
    std::wstring title;
    void* pDoc = nullptr;
    bool isModified = false;
    bool isUntitled = true;
    bool isReadOnly = false;
    bool isPinned = false;
    int encoding = 0;     // 0: UTF-8, 1: UTF-8 BOM, 2: UTF-16 LE, 3: UTF-16 BE, 4: ANSI, 5: EUC-KR, 6: Shift-JIS, 7: Big5, 8: GB2312
    int eolMode = 2;      // 2: Unix (LF), 0: Windows (CRLF), 1: Mac (CR)
    std::string lexerName = "text";
    int cursorPosition = 0;
    int scrollPosition = 0;
    std::string cachedContent = "";
};

struct MacroStep {
    unsigned int msg;
    uptr_t wParam;
    sptr_t lParam;
    std::string textParam;
};

@class NotepadPlusAppController;

// ============================================================================
// Custom Tab Bar View
// ============================================================================

@protocol NppTabBarDelegate <NSObject>
- (void) tabSelectedAtIndex: (NSInteger) index;
- (void) tabClosedAtIndex: (NSInteger) index;
- (void) tabMovedFromIndex: (NSInteger) fromIndex toIndex: (NSInteger) toIndex;
- (void) newTabRequested;
- (void) tabContextMenuRequestedAtIndex: (NSInteger) index event: (NSEvent *) event;
@end

@interface NppTabBarView : NSView
@property (nonatomic, weak) id<NppTabBarDelegate> delegate;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL isDarkMode;
- (void) updateTabs: (const std::vector<NppDocument>&) docs selectedIndex: (NSInteger) sel;
@end

@implementation NppTabBarView {
    std::vector<std::tuple<std::wstring, bool, bool>> mTabs;
    std::vector<NSRect> mTabRects;
    NSRect mNewButtonRect;
    NSInteger mDragSourceIndex;
    NSPoint mDragStartPoint;
    BOOL mIsDragging;
}

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _selectedIndex = 0;
        _isDarkMode = NO;
        mDragSourceIndex = -1;
        mIsDragging = NO;
    }
    return self;
}

- (void) updateTabs: (const std::vector<NppDocument>&) docs selectedIndex: (NSInteger) sel {
    mTabs.clear();
    for (const auto& d : docs) {
        mTabs.push_back({d.title, d.isModified, d.isPinned});
    }
    _selectedIndex = sel;
    [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) dirtyRect {
    [super drawRect: dirtyRect];
    NSRect bounds = self.bounds;

    NSColor* bgColor = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.14 green: 0.14 blue: 0.14 alpha: 1.0]
                                   : [NSColor colorWithCalibratedRed: 0.88 green: 0.88 blue: 0.89 alpha: 1.0];
    [bgColor setFill];
    NSRectFill(bounds);

    NSColor* borderColor = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.10 green: 0.10 blue: 0.10 alpha: 1.0]
                                       : [NSColor colorWithCalibratedRed: 0.72 green: 0.72 blue: 0.74 alpha: 1.0];
    [borderColor setFill];
    NSRectFill(NSMakeRect(0, bounds.size.height - 1, bounds.size.width, 1));

    mTabRects.clear();
    CGFloat x = 6.0;
    CGFloat tabHeight = bounds.size.height - 2.0;

    NSDictionary* titleAttrsActive = @{
        NSFontAttributeName: [NSFont systemFontOfSize: 12.0 weight: NSFontWeightMedium],
        NSForegroundColorAttributeName: _isDarkMode ? [NSColor whiteColor] : [NSColor blackColor]
    };
    NSDictionary* titleAttrsInactive = @{
        NSFontAttributeName: [NSFont systemFontOfSize: 12.0 weight: NSFontWeightRegular],
        NSForegroundColorAttributeName: _isDarkMode ? [NSColor colorWithCalibratedWhite: 0.7 alpha: 1.0]
                                                     : [NSColor colorWithCalibratedWhite: 0.3 alpha: 1.0]
    };

    for (size_t i = 0; i < mTabs.size(); ++i) {
        std::string titleUtf8 = wstring_to_utf8(std::get<0>(mTabs[i]));
        if (std::get<1>(mTabs[i])) titleUtf8 = "● " + titleUtf8;
        if (std::get<2>(mTabs[i])) titleUtf8 = "📌 " + titleUtf8;

        NSString* nsTitle = [NSString stringWithUTF8String: titleUtf8.c_str()];
        NSSize textSize = [nsTitle sizeWithAttributes: titleAttrsActive];
        CGFloat tabWidth = std::max<CGFloat>(85.0, textSize.width + 38.0);

        NSRect tabRect = NSMakeRect(x, 1, tabWidth, tabHeight);
        mTabRects.push_back(tabRect);

        BOOL isActive = (static_cast<NSInteger>(i) == _selectedIndex);
        NSColor* tabBg = isActive ? (_isDarkMode ? [NSColor colorWithCalibratedRed: 0.22 green: 0.22 blue: 0.24 alpha: 1.0]
                                                 : [NSColor colorWithCalibratedRed: 0.98 green: 0.98 blue: 0.99 alpha: 1.0])
                                  : (_isDarkMode ? [NSColor colorWithCalibratedRed: 0.16 green: 0.16 blue: 0.17 alpha: 1.0]
                                                 : [NSColor colorWithCalibratedRed: 0.82 green: 0.82 blue: 0.84 alpha: 1.0]);

        NSBezierPath* path = [NSBezierPath bezierPathWithRoundedRect: tabRect xRadius: 4 yRadius: 4];
        [tabBg setFill];
        [path fill];

        if (isActive) {
            NSColor* accentColor = [NSColor colorWithCalibratedRed: 0.22 green: 0.58 blue: 0.98 alpha: 1.0];
            [accentColor setFill];
            NSRectFill(NSMakeRect(x + 2, 0, tabWidth - 4, 2));
        }

        NSRect textRect = NSMakeRect(x + 8, (tabHeight - textSize.height) / 2.0 + 1, tabWidth - 30, textSize.height);
        [nsTitle drawInRect: textRect withAttributes: isActive ? titleAttrsActive : titleAttrsInactive];

        NSRect closeRect = NSMakeRect(x + tabWidth - 18, (tabHeight - 14) / 2.0 + 1, 14, 14);
        NSDictionary* closeAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize: 11.0 weight: NSFontWeightBold],
            NSForegroundColorAttributeName: _isDarkMode ? [NSColor colorWithCalibratedWhite: 0.65 alpha: 1.0]
                                                         : [NSColor colorWithCalibratedWhite: 0.35 alpha: 1.0]
        };
        [@"×" drawInRect: closeRect withAttributes: closeAttrs];

        x += tabWidth + 4.0;
    }

    mNewButtonRect = NSMakeRect(x + 2, (tabHeight - 20) / 2.0 + 1, 22, 20);
    NSBezierPath* newPath = [NSBezierPath bezierPathWithRoundedRect: mNewButtonRect xRadius: 3 yRadius: 3];
    NSColor* newBtnBg = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.22 green: 0.22 blue: 0.22 alpha: 1.0]
                                    : [NSColor colorWithCalibratedRed: 0.78 green: 0.78 blue: 0.80 alpha: 1.0];
    [newBtnBg setFill];
    [newPath fill];

    NSDictionary* plusAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize: 13.0 weight: NSFontWeightRegular],
        NSForegroundColorAttributeName: _isDarkMode ? [NSColor whiteColor] : [NSColor blackColor]
    };
    [@"+" drawInRect: NSMakeRect(mNewButtonRect.origin.x + 6, mNewButtonRect.origin.y + 1, 12, 16) withAttributes: plusAttrs];
}

- (void) mouseDown: (NSEvent *) event {
    NSPoint loc = [self convertPoint: event.locationInWindow fromView: nil];
    mDragSourceIndex = -1;
    mIsDragging = NO;

    if (NSPointInRect(loc, mNewButtonRect)) {
        if ([_delegate respondsToSelector: @selector(newTabRequested)]) {
            [_delegate newTabRequested];
        }
        return;
    }

    for (size_t i = 0; i < mTabRects.size(); ++i) {
        if (NSPointInRect(loc, mTabRects[i])) {
            NSRect tabRect = mTabRects[i];
            NSRect closeRect = NSMakeRect(tabRect.origin.x + tabRect.size.width - 20, tabRect.origin.y, 20, tabRect.size.height);
            if (NSPointInRect(loc, closeRect)) {
                if ([_delegate respondsToSelector: @selector(tabClosedAtIndex:)]) {
                    [_delegate tabClosedAtIndex: i];
                }
            } else {
                mDragSourceIndex = static_cast<NSInteger>(i);
                mDragStartPoint = loc;
                if ([_delegate respondsToSelector: @selector(tabSelectedAtIndex:)]) {
                    [_delegate tabSelectedAtIndex: i];
                }
            }
            break;
        }
    }
}

- (void) mouseDragged: (NSEvent *) event {
    if (mDragSourceIndex < 0 || mDragSourceIndex >= static_cast<NSInteger>(mTabs.size())) {
        return;
    }

    NSPoint loc = [self convertPoint: event.locationInWindow fromView: nil];
    if (!mIsDragging) {
        if (fabs(loc.x - mDragStartPoint.x) > 4.0) {
            mIsDragging = YES;
        }
    }

    if (mIsDragging) {
        NSInteger targetIndex = -1;
        for (size_t i = 0; i < mTabRects.size(); ++i) {
            NSRect r = mTabRects[i];
            CGFloat midX = r.origin.x + r.size.width / 2.0;

            if (static_cast<NSInteger>(i) < mDragSourceIndex) {
                if (loc.x < midX + 10.0) {
                    targetIndex = static_cast<NSInteger>(i);
                    break;
                }
            } else if (static_cast<NSInteger>(i) > mDragSourceIndex) {
                if (loc.x > midX - 10.0) {
                    targetIndex = static_cast<NSInteger>(i);
                }
            }
        }

        if (targetIndex >= 0 && targetIndex != mDragSourceIndex &&
            targetIndex < static_cast<NSInteger>(mTabs.size())) {
            if ([_delegate respondsToSelector: @selector(tabMovedFromIndex:toIndex:)]) {
                NSInteger oldSrc = mDragSourceIndex;
                mDragSourceIndex = targetIndex;
                [_delegate tabMovedFromIndex: oldSrc toIndex: targetIndex];
            }
        }
    }
}

- (void) mouseUp: (NSEvent *) event {
    mIsDragging = NO;
    mDragSourceIndex = -1;
    [self setNeedsDisplay: YES];
}

- (void) rightMouseDown: (NSEvent *) event {
    NSPoint loc = [self convertPoint: event.locationInWindow fromView: nil];
    for (size_t i = 0; i < mTabRects.size(); ++i) {
        if (NSPointInRect(loc, mTabRects[i])) {
            if ([_delegate respondsToSelector: @selector(tabContextMenuRequestedAtIndex:event:)]) {
                [_delegate tabContextMenuRequestedAtIndex: i event: event];
            }
            return;
        }
    }
    [super rightMouseDown: event];
}

@end

// ============================================================================
// Custom Status Bar View
// ============================================================================

@interface NppStatusBarView : NSView
@property (nonatomic, assign) BOOL isDarkMode;
@property (nonatomic, strong) NSString* posText;
@property (nonatomic, strong) NSString* lengthText;
@property (nonatomic, strong) NSString* eolText;
@property (nonatomic, strong) NSString* encodingText;
@property (nonatomic, strong) NSString* langText;
@property (nonatomic, strong) NSString* statusText;
@property (nonatomic, strong) NSString* insText;
@property (nonatomic, strong) NSString* macroText;
@end

@implementation NppStatusBarView

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _isDarkMode = NO;
        _posText = @"Ln: 1  Col: 1  Pos: 1";
        _lengthText = @"Length: 0  Lines: 1";
        _eolText = @"Unix (LF)";
        _encodingText = @"UTF-8";
        _langText = @"Plain Text";
        _statusText = @"Ready";
        _insText = @"INS";
        _macroText = @"";
    }
    return self;
}

- (void) drawRect: (NSRect) dirtyRect {
    [super drawRect: dirtyRect];
    NSRect bounds = self.bounds;

    NSColor* bg = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.13 green: 0.13 blue: 0.14 alpha: 1.0]
                              : [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];
    [bg setFill];
    NSRectFill(bounds);

    NSColor* border = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.10 green: 0.10 blue: 0.10 alpha: 1.0]
                                  : [NSColor colorWithCalibratedRed: 0.78 green: 0.78 blue: 0.80 alpha: 1.0];
    [border setFill];
    NSRectFill(NSMakeRect(0, 0, bounds.size.width, 1));

    NSColor* cellBorder = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.20 green: 0.20 blue: 0.22 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.82 green: 0.82 blue: 0.84 alpha: 1.0];

    NSDictionary* textAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize: 11.0 weight: NSFontWeightRegular],
        NSForegroundColorAttributeName: _isDarkMode ? [NSColor colorWithCalibratedWhite: 0.85 alpha: 1.0]
                                                     : [NSColor colorWithCalibratedWhite: 0.20 alpha: 1.0]
    };

    auto drawCell = [&](NSRect rect, NSString* text, NSTextAlignment align) {
        [cellBorder setFill];
        NSRectFill(NSMakeRect(rect.origin.x, 2, 1, bounds.size.height - 4));
        NSRectFill(NSMakeRect(rect.origin.x + rect.size.width - 1, 2, 1, bounds.size.height - 4));

        NSMutableParagraphStyle* pStyle = [[NSMutableParagraphStyle alloc] init];
        pStyle.alignment = align;
        NSMutableDictionary* attrs = [textAttrs mutableCopy];
        attrs[NSParagraphStyleAttributeName] = pStyle;

        NSSize tSize = [text sizeWithAttributes: attrs];
        CGFloat y = (bounds.size.height - tSize.height) / 2.0;
        NSRect textRect = NSMakeRect(rect.origin.x + 4, y, rect.size.width - 8, tSize.height);
        [text drawInRect: textRect withAttributes: attrs];
    };

    CGFloat w = bounds.size.width;
    CGFloat cellH = bounds.size.height;

    CGFloat wMacro = (_macroText && _macroText.length > 0) ? 60.0 : 0.0;
    CGFloat wIns = 36.0;
    CGFloat wLang = 110.0;
    CGFloat wEnc = 100.0;
    CGFloat wEol = 110.0;
    CGFloat wPos = 160.0;
    CGFloat wLen = 160.0;

    CGFloat r = w - 4.0;

    if (wMacro > 0) {
        r -= wMacro;
        drawCell(NSMakeRect(r, 0, wMacro, cellH), _macroText, NSTextAlignmentCenter);
    }

    r -= wIns;
    drawCell(NSMakeRect(r, 0, wIns, cellH), _insText, NSTextAlignmentCenter);

    r -= (wLang + 2.0);
    drawCell(NSMakeRect(r, 0, wLang, cellH), _langText, NSTextAlignmentCenter);

    r -= (wEnc + 2.0);
    drawCell(NSMakeRect(r, 0, wEnc, cellH), _encodingText, NSTextAlignmentCenter);

    r -= (wEol + 2.0);
    drawCell(NSMakeRect(r, 0, wEol, cellH), _eolText, NSTextAlignmentCenter);

    r -= (wPos + 2.0);
    drawCell(NSMakeRect(r, 0, wPos, cellH), _posText, NSTextAlignmentCenter);

    r -= (wLen + 2.0);
    drawCell(NSMakeRect(r, 0, wLen, cellH), _lengthText, NSTextAlignmentCenter);

    CGFloat leftW = std::max<CGFloat>(60.0, r - 6.0);
    drawCell(NSMakeRect(4.0, 0, leftW, cellH), _statusText, NSTextAlignmentLeft);
}

@end

// ============================================================================
// Find & Replace View Panel
// ============================================================================

@protocol NppFindReplaceDelegate <NSObject>
- (void) findNext: (NSString *) query matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex;
- (void) findPrev: (NSString *) query matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex;
- (void) replaceOne: (NSString *) query withText: (NSString *) rep matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex;
- (void) replaceAll: (NSString *) query withText: (NSString *) rep matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex;
- (void) markAll: (NSString *) query matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex;
- (void) closeFindBar;
@end

// ============================================================================
// Find & Replace Floating Window Controller Interface
// ============================================================================

@class NotepadPlusAppController;

@interface NppFindReplaceWindowController : NSWindowController <NSTextFieldDelegate, NSWindowDelegate>
@property (nonatomic, weak) NotepadPlusAppController* appController;
@property (nonatomic, strong) NSTextField* findField;
@property (nonatomic, strong) NSTextField* replaceField;
@property (nonatomic, strong) NSButton* matchCaseCheck;
@property (nonatomic, strong) NSButton* wholeWordCheck;
@property (nonatomic, strong) NSButton* regexCheck;

- (instancetype) initWithAppController: (NotepadPlusAppController *) appCtrl;
- (void) showFindWindow;
- (void) showReplaceWindow;
- (void) setSearchPattern: (NSString *) pattern;
- (void) updateAppearance: (BOOL) isDark;
- (void) onFindNext: (id) sender;
- (void) onFindPrev: (id) sender;
- (void) onReplace: (id) sender;
- (void) onReplaceAll: (id) sender;
- (void) onMarkAll: (id) sender;
@end

// ============================================================================
// Panel 1: Primary Side Panel (Left) - macOS Finder Style Tree starting at ~/
// ============================================================================

@protocol NppFileExplorerDelegate <NSObject>
- (void) fileExplorerOpenFile: (NSString *) filePath;
@end

@interface NppFileNode : NSObject
@property (nonatomic, strong) NSString* path;
@property (nonatomic, strong) NSString* name;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, strong) NSImage* icon;
@property (nonatomic, strong) NSMutableArray<NppFileNode *>* children;
@property (nonatomic, assign) BOOL childrenLoaded;
@property (nonatomic, assign) NSInteger fileSize;
@property (nonatomic, strong) NSString* ext;
- (void) loadChildrenIfNeeded;
@end

@implementation NppFileNode
- (instancetype) init {
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
        _childrenLoaded = NO;
        _fileSize = 0;
        _ext = @"";
    }
    return self;
}

- (void) loadChildrenIfNeeded {
    if (!_isDirectory || _childrenLoaded) return;
    _childrenLoaded = YES;
    [_children removeAllObjects];

    NSError* err = nil;
    NSArray<NSString *>* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _path error: &err];
    if (!err && contents) {
        for (NSString* item in contents) {
            if ([item hasPrefix: @"."]) continue; // Skip hidden files (.DS_Store, .git, etc.)
            NSString* subPath = [_path stringByAppendingPathComponent: item];
            BOOL isSubDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath: subPath isDirectory: &isSubDir]) {
                NppFileNode* subNode = [[NppFileNode alloc] init];
                subNode.path = subPath;
                subNode.name = item;
                subNode.isDirectory = isSubDir;
                subNode.ext = [[item pathExtension] lowercaseString];

                if (isSubDir) {
                    if (@available(macOS 11.0, *)) {
                        subNode.icon = [NSImage imageWithSystemSymbolName: @"folder.fill" accessibilityDescription: @"Folder"];
                    } else {
                        subNode.icon = [[NSWorkspace sharedWorkspace] iconForFile: subPath];
                    }
                } else {
                    subNode.icon = [[NSWorkspace sharedWorkspace] iconForFile: subPath];
                }
                [subNode.icon setSize: NSMakeSize(16, 16)];

                NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath: subPath error: nil];
                if (attrs) {
                    subNode.fileSize = [attrs[NSFileSize] integerValue];
                }
                [_children addObject: subNode];
            }
        }
        [_children sortUsingComparator: ^NSComparisonResult(NppFileNode* a, NppFileNode* b) {
            if (a.isDirectory != b.isDirectory) return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
            return [a.name localizedCaseInsensitiveCompare: b.name];
        }];
    }
}
@end

@interface NppFileExplorerView : NSView <NSOutlineViewDelegate, NSOutlineViewDataSource, NSSearchFieldDelegate, NSMenuDelegate>
@property (nonatomic, weak) id<NppFileExplorerDelegate> delegate;
@property (nonatomic, strong) NSString* rootDirectory;
@property (nonatomic, strong) NSOutlineView* outlineView;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSSearchField* searchField;
@property (nonatomic, strong) NSString* filterQuery;
@property (nonatomic, assign) BOOL isDarkMode;
- (void) setDirectoryPath: (NSString *) dirPath;
- (void) refreshDirectory;
- (void) setIsDarkMode: (BOOL) isDark;
@end

@implementation NppFileExplorerView {
    NppFileNode* mRootNode;
    NSMutableArray<NppFileNode *>* mFilteredList;
}

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _isDarkMode = NO;
        _filterQuery = @"";
        _rootDirectory = NSHomeDirectory();
        mFilteredList = [NSMutableArray array];
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    // 1. Header View (Title & Actions)
    NSView* header = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, self.bounds.size.width, 32)];
    header.autoresizingMask = NSViewWidthSizable;
    [self addSubview: header];

    _titleLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(8, 7, self.bounds.size.width - 80, 18)];
    _titleLabel.stringValue = @"EXPLORER: ~";
    _titleLabel.bezeled = NO; _titleLabel.drawsBackground = NO; _titleLabel.editable = NO;
    _titleLabel.font = [NSFont systemFontOfSize: 11 weight: NSFontWeightBold];
    [header addSubview: _titleLabel];

    // New File Button
    NSButton* btnNewFile = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 68, 6, 20, 20)];
    btnNewFile.bezelStyle = NSBezelStyleInline;
    btnNewFile.title = @"+";
    btnNewFile.toolTip = @"New File in Directory";
    btnNewFile.target = self;
    btnNewFile.action = @selector(onNewFileInDir:);
    btnNewFile.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnNewFile];

    // New Folder Button
    NSButton* btnNewFolder = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 46, 6, 20, 20)];
    btnNewFolder.bezelStyle = NSBezelStyleInline;
    if (@available(macOS 11.0, *)) {
        btnNewFolder.image = [NSImage imageWithSystemSymbolName: @"folder.badge.plus" accessibilityDescription: @"New Folder"];
    } else {
        btnNewFolder.title = @"📁+";
    }
    btnNewFolder.toolTip = @"New Folder in Directory";
    btnNewFolder.target = self;
    btnNewFolder.action = @selector(onNewFolderInDir:);
    btnNewFolder.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnNewFolder];

    // Back Button (Go to Parent Directory / 뒤로가기)
    NSButton* btnBack = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 24, 6, 20, 20)];
    btnBack.bezelStyle = NSBezelStyleInline;
    if (@available(macOS 11.0, *)) {
        btnBack.image = [NSImage imageWithSystemSymbolName: @"chevron.backward" accessibilityDescription: @"Go to Parent Directory"];
    } else {
        btnBack.title = @"◀";
    }
    btnBack.toolTip = @"Go to Parent Directory";
    btnBack.target = self;
    btnBack.action = @selector(onBackClicked:);
    btnBack.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnBack];

    // 2. Search Filter Field
    _searchField = [[NSSearchField alloc] initWithFrame: NSMakeRect(6, 32, self.bounds.size.width - 12, 22)];
    _searchField.placeholderString = @"Filter files...";
    _searchField.font = [NSFont systemFontOfSize: 11];
    _searchField.delegate = self;
    _searchField.autoresizingMask = NSViewWidthSizable;
    [self addSubview: _searchField];

    // 3. Outline ScrollView
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 58, self.bounds.size.width, self.bounds.size.height - 58)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview: scroll];

    _outlineView = [[NSOutlineView alloc] initWithFrame: scroll.bounds];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier: @"FinderCol"];
    col.title = @"Files";
    col.width = self.bounds.size.width - 10;
    [_outlineView addTableColumn: col];
    _outlineView.outlineTableColumn = col;
    _outlineView.headerView = nil;
    _outlineView.delegate = self;
    _outlineView.dataSource = self;
    _outlineView.target = self;
    _outlineView.doubleAction = @selector(onItemDoubleClicked:);
    _outlineView.indentationPerLevel = 14.0;
    _outlineView.rowHeight = 22.0;

    // Context Menu Setup
    NSMenu* contextMenu = [[NSMenu alloc] initWithTitle: @"FileActions"];
    [contextMenu addItemWithTitle: @"Open in Editor" action: @selector(onContextOpen:) keyEquivalent: @""];
    [contextMenu addItem: [NSMenuItem separatorItem]];
    [contextMenu addItemWithTitle: @"Reveal in Finder" action: @selector(onContextReveal:) keyEquivalent: @""];
    [contextMenu addItemWithTitle: @"Open in Terminal" action: @selector(onContextTerminal:) keyEquivalent: @""];
    [contextMenu addItemWithTitle: @"Copy Full Path" action: @selector(onContextCopyPath:) keyEquivalent: @""];
    [contextMenu addItem: [NSMenuItem separatorItem]];
    [contextMenu addItemWithTitle: @"Rename..." action: @selector(onContextRename:) keyEquivalent: @""];
    [contextMenu addItemWithTitle: @"Move to Trash" action: @selector(onContextTrash:) keyEquivalent: @""];
    _outlineView.menu = contextMenu;

    scroll.documentView = _outlineView;
    [self refreshDirectory];
}

- (void) setDirectoryPath: (NSString *) dirPath {
    if (!dirPath || dirPath.length == 0) dirPath = NSHomeDirectory();
    if ([_rootDirectory isEqualToString: dirPath]) return;

    _rootDirectory = dirPath;
    NSString* display = [dirPath isEqualToString: NSHomeDirectory()] ? @"~" : [dirPath lastPathComponent];
    _titleLabel.stringValue = [NSString stringWithFormat: @"EXPLORER: %@", display];
    [self refreshDirectory];
}

- (void) refreshDirectory {
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath: _rootDirectory isDirectory: &isDir] && isDir) {
        mRootNode = [[NppFileNode alloc] init];
        mRootNode.path = _rootDirectory;
        mRootNode.name = [_rootDirectory isEqualToString: NSHomeDirectory()] ? @"Home (~)" : [_rootDirectory lastPathComponent];
        mRootNode.isDirectory = YES;
        mRootNode.icon = [[NSWorkspace sharedWorkspace] iconForFile: _rootDirectory];
        [mRootNode.icon setSize: NSMakeSize(16, 16)];
        [mRootNode loadChildrenIfNeeded];
    } else {
        mRootNode = nil;
    }
    [self applyFilter];
}

- (void) setIsDarkMode: (BOOL) isDark {
    _isDarkMode = isDark;
    if (_outlineView) {
        _outlineView.backgroundColor = isDark ? [NSColor colorWithCalibratedRed: 0.13 green: 0.13 blue: 0.14 alpha: 1.0]
                                             : [NSColor colorWithCalibratedRed: 0.96 green: 0.96 blue: 0.97 alpha: 1.0];
        _outlineView.appearance = isDark ? [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]
                                         : [NSAppearance appearanceNamed: NSAppearanceNameAqua];
        [_outlineView reloadData];
    }
    if (_searchField) {
        _searchField.appearance = isDark ? [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]
                                         : [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    }
    if (_titleLabel) {
        _titleLabel.textColor = isDark ? [NSColor whiteColor] : [NSColor blackColor];
    }
    [self setNeedsDisplay: YES];
}

- (void) controlTextDidChange: (NSNotification *) obj {
    if (obj.object == _searchField) {
        _filterQuery = [_searchField.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self applyFilter];
    }
}

- (void) collectMatchingNodes: (NppFileNode *) node query: (NSString *) query outList: (NSMutableArray<NppFileNode *> *) outList {
    if (!node) return;
    [node loadChildrenIfNeeded];
    for (NppFileNode* child in node.children) {
        if ([child.name rangeOfString: query options: NSCaseInsensitiveSearch].location != NSNotFound) {
            [outList addObject: child];
        }
        if (child.isDirectory) {
            [self collectMatchingNodes: child query: query outList: outList];
        }
    }
}

- (void) applyFilter {
    if (_filterQuery.length > 0) {
        [mFilteredList removeAllObjects];
        [self collectMatchingNodes: mRootNode query: _filterQuery outList: mFilteredList];
    }
    [_outlineView reloadData];
    if (_filterQuery.length == 0 && mRootNode) {
        [_outlineView expandItem: mRootNode];
    }
}

- (void) onBackClicked: (id) sender {
    if (_rootDirectory && _rootDirectory.length > 1 && ![_rootDirectory isEqualToString: @"/"]) {
        NSString* parentDir = [_rootDirectory stringByDeletingLastPathComponent];
        if (parentDir.length > 0) {
            self.rootDirectory = parentDir;
            [self refreshDirectory];
        }
    }
}

- (void) onRefreshClicked: (id) sender {
    [self refreshDirectory];
}

- (void) onNewFileInDir: (id) sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Create New File";
    alert.informativeText = @"Enter filename:";
    [alert addButtonWithTitle: @"Create"];
    [alert addButtonWithTitle: @"Cancel"];

    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 240, 24)];
    input.placeholderString = @"untitled.txt";
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString* fname = [input.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (fname.length > 0) {
            NSString* fullPath = [_rootDirectory stringByAppendingPathComponent: fname];
            [[NSFileManager defaultManager] createFileAtPath: fullPath contents: [NSData data] attributes: nil];
            [self refreshDirectory];
            if ([_delegate respondsToSelector: @selector(fileExplorerOpenFile:)]) {
                [_delegate fileExplorerOpenFile: fullPath];
            }
        }
    }
}

- (void) onNewFolderInDir: (id) sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Create New Folder";
    alert.informativeText = @"Enter folder name:";
    [alert addButtonWithTitle: @"Create"];
    [alert addButtonWithTitle: @"Cancel"];

    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 240, 24)];
    input.placeholderString = @"NewFolder";
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString* fname = [input.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (fname.length > 0) {
            NSString* fullPath = [_rootDirectory stringByAppendingPathComponent: fname];
            [[NSFileManager defaultManager] createDirectoryAtPath: fullPath withIntermediateDirectories: YES attributes: nil error: nil];
            [self refreshDirectory];
        }
    }
}

- (NppFileNode *) selectedNode {
    NSInteger row = _outlineView.clickedRow;
    if (row < 0) row = _outlineView.selectedRow;
    if (row >= 0) return (NppFileNode *)[_outlineView itemAtRow: row];
    return nil;
}

- (void) onContextOpen: (id) sender {
    NppFileNode* node = [self selectedNode];
    if (node && !node.isDirectory) {
        if ([_delegate respondsToSelector: @selector(fileExplorerOpenFile:)]) {
            [_delegate fileExplorerOpenFile: node.path];
        }
    }
}

- (void) onContextReveal: (id) sender {
    NppFileNode* node = [self selectedNode];
    if (node) {
        [[NSWorkspace sharedWorkspace] selectFile: node.path inFileViewerRootedAtPath: @""];
    }
}

- (void) onContextTerminal: (id) sender {
    NppFileNode* node = [self selectedNode];
    NSString* dir = node.isDirectory ? node.path : [node.path stringByDeletingLastPathComponent];
    if (dir) {
        [[NSWorkspace sharedWorkspace] openURLs: @[[NSURL fileURLWithPath: dir]]
                       withApplicationAtURL: [NSURL fileURLWithPath: @"/System/Applications/Utilities/Terminal.app"]
                              configuration: [NSWorkspaceOpenConfiguration configuration]
                          completionHandler: nil];
    }
}

- (void) onContextCopyPath: (id) sender {
    NppFileNode* node = [self selectedNode];
    if (node) {
        NSPasteboard* pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString: node.path forType: NSPasteboardTypeString];
    }
}

- (void) onContextRename: (id) sender {
    NppFileNode* node = [self selectedNode];
    if (!node) return;

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Item";
    alert.informativeText = @"Enter new name:";
    [alert addButtonWithTitle: @"Rename"];
    [alert addButtonWithTitle: @"Cancel"];

    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 240, 24)];
    input.stringValue = node.name;
    alert.accessoryView = input;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString* newName = [input.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newName.length > 0 && ![newName isEqualToString: node.name]) {
            NSString* newPath = [[node.path stringByDeletingLastPathComponent] stringByAppendingPathComponent: newName];
            [[NSFileManager defaultManager] moveItemAtPath: node.path toPath: newPath error: nil];
            [self refreshDirectory];
        }
    }
}

- (void) onContextTrash: (id) sender {
    NppFileNode* node = [self selectedNode];
    if (node) {
        NSURL* resultingURL = nil;
        [[NSFileManager defaultManager] trashItemAtURL: [NSURL fileURLWithPath: node.path] resultingItemURL: &resultingURL error: nil];
        [self refreshDirectory];
    }
}

- (NSInteger) outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem: (id) item {
    if (_filterQuery.length > 0) {
        return item == nil ? mFilteredList.count : 0;
    }
    if (!item) {
        if (!mRootNode) return 0;
        [mRootNode loadChildrenIfNeeded];
        return mRootNode.children.count;
    }
    NppFileNode* node = (NppFileNode *)item;
    if (node.isDirectory) {
        [node loadChildrenIfNeeded];
        return node.children.count;
    }
    return 0;
}

- (id) outlineView: (NSOutlineView *) outlineView child: (NSInteger) index ofItem: (id) item {
    if (_filterQuery.length > 0) {
        return mFilteredList[index];
    }
    if (!item) {
        [mRootNode loadChildrenIfNeeded];
        return mRootNode.children[index];
    }
    NppFileNode* node = (NppFileNode *)item;
    [node loadChildrenIfNeeded];
    return node.children[index];
}

- (BOOL) outlineView: (NSOutlineView *) outlineView isItemExpandable: (id) item {
    if (_filterQuery.length > 0) return NO;
    NppFileNode* node = (NppFileNode *)item;
    return node.isDirectory;
}

- (NSView *) outlineView: (NSOutlineView *) outlineView viewForTableColumn: (NSTableColumn *) tableColumn item: (id) item {
    NppFileNode* node = (NppFileNode *)item;
    NSTableCellView* cell = [outlineView makeViewWithIdentifier: @"ExplorerCell" owner: self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, tableColumn.width, 22)];
        cell.identifier = @"ExplorerCell";

        NSImageView* iv = [[NSImageView alloc] initWithFrame: NSMakeRect(2, 3, 16, 16)];
        cell.imageView = iv;
        [cell addSubview: iv];

        NSTextField* tf = [[NSTextField alloc] initWithFrame: NSMakeRect(22, 2, tableColumn.width - 24, 18)];
        tf.bezeled = NO; tf.drawsBackground = NO; tf.editable = NO;
        tf.font = [NSFont systemFontOfSize: 12 weight: NSFontWeightRegular];
        cell.textField = tf;
        [cell addSubview: tf];
    }

    cell.imageView.image = node.icon;
    cell.textField.stringValue = node.name;
    cell.textField.textColor = _isDarkMode ? [NSColor colorWithCalibratedWhite: 0.90 alpha: 1.0] : [NSColor blackColor];
    return cell;
}

- (void) onItemDoubleClicked: (id) sender {
    NSInteger row = _outlineView.clickedRow;
    if (row >= 0) {
        NppFileNode* node = (NppFileNode *)[_outlineView itemAtRow: row];
        if (node) {
            if (node.isDirectory) {
                if ([_outlineView isItemExpanded: node]) [_outlineView collapseItem: node];
                else [_outlineView expandItem: node];
            } else {
                if ([_delegate respondsToSelector: @selector(fileExplorerOpenFile:)]) {
                    [_delegate fileExplorerOpenFile: node.path];
                }
            }
        }
    }
}

- (void) drawRect: (NSRect) dirtyRect {
    [super drawRect: dirtyRect];
    NSColor* bg = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.13 green: 0.13 blue: 0.14 alpha: 1.0]
                              : [NSColor colorWithCalibratedRed: 0.96 green: 0.96 blue: 0.97 alpha: 1.0];
    [bg setFill];
    NSRectFill(self.bounds);

    NSColor* border = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.20 green: 0.20 blue: 0.22 alpha: 1.0]
                                  : [NSColor colorWithCalibratedRed: 0.82 green: 0.82 blue: 0.84 alpha: 1.0];
    [border setFill];
    NSRectFill(NSMakeRect(self.bounds.size.width - 1, 0, 1, self.bounds.size.height));
}
@end

@protocol NppTerminalPanelDelegate <NSObject>
- (void) terminalPanelCloseRequested;
- (void) terminalPanelOpenExternalRequested: (NSString *) dirPath;
@end

@class NppTerminalPanelView;

@interface NppTerminalTextView : NSTextView <NSTextInputClient>
@property (nonatomic, weak) NppTerminalPanelView* terminalPanel;
@end

@interface NppTerminalPanelView : NSView <NSTextFieldDelegate>
@property (nonatomic, weak) id<NppTerminalPanelDelegate> delegate;
@property (nonatomic, strong) NSString* workingDirectory;
@property (nonatomic, strong) NppTerminalTextView* outputTextView;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSView* statusIndicator;
@property (nonatomic, assign) BOOL isDarkMode;
@property (nonatomic, assign) BOOL isExecuting;

- (void) setWorkingDirectoryPath: (NSString *) dirPath;
- (void) appendOutput: (NSString *) text;
- (void) sendSigInt;
- (void) sendSigTstp;
- (void) sendEof;
- (void) onClearClicked: (id) sender;
- (void) cut: (id) sender;
- (void) copy: (id) sender;
- (void) paste: (id) sender;
- (void) selectAll: (id) sender;
- (void) startPtySession;
- (void) stopPtySession;
- (void) sendBytesToPty: (const void *) bytes length: (size_t) len;
@end
@implementation NppTerminalTextView {
    NSString* mMarkedTextString;
}

- (instancetype) initWithFrame: (NSRect) frameRect textContainer: (NSTextContainer *) container {
    self = [super initWithFrame: frameRect textContainer: container];
    if (self) {
        mMarkedTextString = nil;
    }
    return self;
}

- (BOOL) acceptsFirstResponder { return YES; }

#pragma mark - NSTextInputClient (Native Korean IME Support)

- (BOOL) hasMarkedText {
    return (mMarkedTextString != nil && mMarkedTextString.length > 0);
}

- (NSRange) markedRange {
    if ([self hasMarkedText]) {
        return NSMakeRange(self.textStorage.length, mMarkedTextString.length);
    }
    return NSMakeRange(NSNotFound, 0);
}

- (NSRange) selectedRange {
    return [super selectedRange];
}

- (void) setMarkedText: (id) string selectedRange: (NSRange) selectedRange replacementRange: (NSRange) replacementRange {
    if ([string isKindOfClass: [NSString class]]) {
        mMarkedTextString = (NSString *) string;
    } else if ([string isKindOfClass: [NSAttributedString class]]) {
        mMarkedTextString = [(NSAttributedString *) string string];
    } else {
        mMarkedTextString = nil;
    }
}

- (void) unmarkText {
    mMarkedTextString = nil;
}

- (void) insertText: (id) string replacementRange: (NSRange) replacementRange {
    mMarkedTextString = nil;

    NSString* str = nil;
    if ([string isKindOfClass: [NSString class]]) {
        str = (NSString *) string;
    } else if ([string isKindOfClass: [NSAttributedString class]]) {
        str = [(NSAttributedString *) string string];
    }

    if (str && str.length > 0) {
        const char* bytes = [str UTF8String];
        size_t len = strlen(bytes);
        [_terminalPanel sendBytesToPty: bytes length: len];
    }
}

- (NSAttributedString *) attributedSubstringForProposedRange: (NSRange) range actualRange: (NSRangePointer) actualRange {
    if (actualRange) *actualRange = range;
    return [[NSAttributedString alloc] init];
}

- (NSArray<NSAttributedStringKey> *) validAttributesForMarkedText {
    return @[NSUnderlineStyleAttributeName, NSForegroundColorAttributeName];
}

- (NSRect) firstRectForCharacterRange: (NSRange) range actualRange: (NSRangePointer) actualRange {
    if (actualRange) *actualRange = range;
    NSRect viewRect = self.bounds;
    if (self.window) {
        NSRect windowRect = [self convertRect: viewRect toView: nil];
        return [self.window convertRectToScreen: windowRect];
    }
    return viewRect;
}

- (NSUInteger) characterIndexForPoint: (NSPoint) point {
    return self.textStorage.length;
}

#pragma mark - Keyboard Event Interception

- (void) keyDown: (NSEvent *) event {
    unsigned short keyCode = event.keyCode;
    NSEventModifierFlags rawFlags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSEventModifierFlags flags = rawFlags & ~NSEventModifierFlagFunction;

    if ([self hasMarkedText]) {
        [self interpretKeyEvents: @[event]];
        return;
    }

    if (flags == 0 || flags == NSEventModifierFlagNumericPad || flags == NSEventModifierFlagShift) {
        if (keyCode == 36 || keyCode == 76) { // Return / Enter
            char c = '\r';
            [_terminalPanel sendBytesToPty: &c length: 1];
            return;
        } else if (keyCode == 51 || keyCode == 117) { // Delete / Backspace
            char c = 0x7F;
            [_terminalPanel sendBytesToPty: &c length: 1];
            return;
        } else if (keyCode == 48) { // Tab
            char c = '\t';
            [_terminalPanel sendBytesToPty: &c length: 1];
            return;
        } else if (keyCode == 53) { // Escape
            char c = 0x1B;
            [_terminalPanel sendBytesToPty: &c length: 1];
            return;
        } else if (keyCode == 126) { // Up Arrow
            const char* seq = "\033[A";
            [_terminalPanel sendBytesToPty: seq length: 3];
            return;
        } else if (keyCode == 125) { // Down Arrow
            const char* seq = "\033[B";
            [_terminalPanel sendBytesToPty: seq length: 3];
            return;
        } else if (keyCode == 124) { // Right Arrow
            const char* seq = "\033[C";
            [_terminalPanel sendBytesToPty: seq length: 3];
            return;
        } else if (keyCode == 123) { // Left Arrow
            const char* seq = "\033[D";
            [_terminalPanel sendBytesToPty: seq length: 3];
            return;
        }
    }

    if (flags & NSEventModifierFlagControl) {
        NSString* chars = event.charactersIgnoringModifiers.lowercaseString;
        if (chars.length > 0) {
            unichar ch = [chars characterAtIndex: 0];
            if (ch >= 'a' && ch <= 'z') {
                if (ch == 'c') { [_terminalPanel sendSigInt]; return; }
                if (ch == 'z') { [_terminalPanel sendSigTstp]; return; }
                if (ch == 'd') { [_terminalPanel sendEof]; return; }
                if (ch == 'l') { [_terminalPanel onClearClicked: self]; return; }
                char ctrlByte = (char)(ch - 'a' + 1);
                [_terminalPanel sendBytesToPty: &ctrlByte length: 1];
                return;
            }
        }
    }

    [self interpretKeyEvents: @[event]];
}

- (BOOL) performKeyEquivalent: (NSEvent *) event {
    NSResponder* fr = self.window.firstResponder;
    BOOL isTerminalFocused = (fr == self || (fr && [fr isKindOfClass: [NSView class]] && [(NSView *)fr isDescendantOf: _terminalPanel]));
    if (!isTerminalFocused) return NO;

    NSEventModifierFlags rawFlags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSEventModifierFlags flags = rawFlags & ~NSEventModifierFlagFunction;

    if (flags == NSEventModifierFlagCommand) {
        NSString* chars = event.charactersIgnoringModifiers.lowercaseString;
        if ([chars isEqualToString: @"c"]) {
            if (self.selectedRange.length > 0) {
                [self copy: nil];
            } else {
                [_terminalPanel sendSigInt];
            }
            return YES;
        } else if ([chars isEqualToString: @"v"]) {
            [_terminalPanel paste: nil];
            return YES;
        } else if ([chars isEqualToString: @"a"]) {
            [self selectAll: nil];
            return YES;
        } else if ([chars isEqualToString: @"k"]) {
            [_terminalPanel onClearClicked: nil];
            return YES;
        } else if ([chars isEqualToString: @"d"]) {
            [_terminalPanel sendEof];
            return YES;
        }
        return NO;
    }
    return [super performKeyEquivalent: event];
}

@end

@implementation NppTerminalPanelView {
    int mMasterFd;
    pid_t mPtyPid;
    dispatch_source_t mReadSource;
}

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _isDarkMode = NO;
        _isExecuting = NO;
        _workingDirectory = NSHomeDirectory();
        mMasterFd = -1;
        mPtyPid = 0;
        mReadSource = NULL;
        [self buildUI];
        [self startPtySession];
    }
    return self;
}

- (void) dealloc {
    [self stopPtySession];
}

- (void) buildUI {
    // 1. Terminal Title Bar
    NSView* header = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, self.bounds.size.width, 28)];
    header.autoresizingMask = NSViewWidthSizable;
    [self addSubview: header];

    _statusIndicator = [[NSView alloc] initWithFrame: NSMakeRect(8, 9, 10, 10)];
    _statusIndicator.wantsLayer = YES;
    _statusIndicator.layer.cornerRadius = 5;
    _statusIndicator.layer.backgroundColor = [NSColor colorWithCalibratedRed: 0.20 green: 0.85 blue: 0.30 alpha: 1.0].CGColor;
    [header addSubview: _statusIndicator];

    _titleLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(24, 5, self.bounds.size.width - 255, 18)];
    _titleLabel.stringValue = [NSString stringWithFormat: @"TERMINAL (zsh PTY) — 📁 ~"];
    _titleLabel.bezeled = NO; _titleLabel.drawsBackground = NO; _titleLabel.editable = NO;
    _titleLabel.font = [NSFont systemFontOfSize: 11 weight: NSFontWeightBold];
    [header addSubview: _titleLabel];

    NSButton* btnExt = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 225, 4, 135, 20)];
    btnExt.bezelStyle = NSBezelStyleInline;
    btnExt.title = @"Open in Terminal.app";
    btnExt.toolTip = @"Open current directory in macOS Terminal";
    btnExt.target = self;
    btnExt.action = @selector(onOpenExternalClicked:);
    btnExt.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnExt];

    NSButton* btnClear = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 82, 4, 52, 20)];
    btnClear.bezelStyle = NSBezelStyleInline;
    btnClear.title = @"Clear";
    btnClear.toolTip = @"Clear screen (⌘K)";
    btnClear.target = self;
    btnClear.action = @selector(onClearClicked:);
    btnClear.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClear];

    NSButton* btnClose = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 25, 4, 20, 20)];
    btnClose.bezelStyle = NSBezelStyleInline;
    btnClose.title = @"×";
    btnClose.toolTip = @"Close Terminal Panel (⌘D)";
    btnClose.target = self;
    btnClose.action = @selector(onCloseClicked:);
    btnClose.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClose];

    // 2. Full Unified Interactive Terminal Canvas (Fills rest of height, no separate input bar!)
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 28, self.bounds.size.width, self.bounds.size.height - 28)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview: scroll];

    _outputTextView = [[NppTerminalTextView alloc] initWithFrame: scroll.bounds];
    _outputTextView.terminalPanel = self;
    _outputTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _outputTextView.editable = YES;
    _outputTextView.selectable = YES;
    _outputTextView.textContainerInset = NSMakeSize(4, 4);
    _outputTextView.textContainer.lineFragmentPadding = 2.0;
    _outputTextView.backgroundColor = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.09 green: 0.09 blue: 0.10 alpha: 1.0]
                                                  : [NSColor colorWithCalibratedWhite: 1.0 alpha: 1.0];
    _outputTextView.textColor = _isDarkMode ? [NSColor colorWithCalibratedWhite: 0.94 alpha: 1.0]
                                            : [NSColor colorWithCalibratedWhite: 0.10 alpha: 1.0];
    _outputTextView.font = [NSFont fontWithName: @"SF Mono" size: 11.5]
                        ?: [NSFont fontWithName: @"Menlo" size: 11.5]
                        ?: [NSFont monospacedSystemFontOfSize: 11.5 weight: NSFontWeightRegular];
    _outputTextView.insertionPointColor = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.30 green: 0.85 blue: 0.95 alpha: 1.0]
                                                       : [NSColor colorWithCalibratedRed: 0.05 green: 0.45 blue: 0.90 alpha: 1.0];
    scroll.documentView = _outputTextView;
}

- (void) startPtySession {
    [self stopPtySession];

    struct winsize ws;
    CGFloat fontW = 7.5;
    CGFloat fontH = 14.0;
    ws.ws_col = (unsigned short)std::max<int>(20, (self.bounds.size.width - 16) / fontW);
    ws.ws_row = (unsigned short)std::max<int>(5, (self.bounds.size.height - 36) / fontH);
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    int master = -1, slave = -1;
    if (openpty(&master, &slave, NULL, NULL, &ws) < 0) {
        [self appendOutput: @"Failed to allocate PTY device.\n"];
        return;
    }

    fcntl(master, F_SETFL, O_NONBLOCK);
    mMasterFd = master;

    pid_t pid = fork();
    if (pid == 0) {
        close(master);
        login_tty(slave);
        if (_workingDirectory && _workingDirectory.length > 0) {
            chdir([_workingDirectory UTF8String]);
        }
        setenv("TERM", "xterm-256color", 1);
        setenv("CLICOLOR", "1", 1);
        setenv("CLICOLOR_FORCE", "1", 1);
        setenv("FORCE_COLOR", "1", 1);
        setenv("LSCOLORS", "Gxfxcxdxbxegedabagacad", 1);
        setenv("LANG", "en_US.UTF-8", 1);
        setenv("LC_ALL", "en_US.UTF-8", 1);

        char* const args[] = {(char *)"/bin/zsh", (char *)"-l", NULL};
        execv("/bin/zsh", args);
        _exit(1);
    }

    close(slave);
    mPtyPid = pid;
    _isExecuting = YES;
    _statusIndicator.layer.backgroundColor = [NSColor colorWithCalibratedRed: 0.20 green: 0.85 blue: 0.30 alpha: 1.0].CGColor;

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    mReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, mMasterFd, 0, queue);

    __weak NppTerminalPanelView* weakSelf = self;
    dispatch_source_set_event_handler(mReadSource, ^{
        char buf[4096];
        ssize_t n = read(master, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            NSString* str = [[NSString alloc] initWithBytes: buf length: n encoding: NSUTF8StringEncoding];
            if (!str) str = [[NSString alloc] initWithBytes: buf length: n encoding: NSISOLatin1StringEncoding];
            if (str) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf processRawPtyOutput: str];
                });
            }
        } else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            // Non-blocking read retry
        } else {
            dispatch_source_cancel(self->mReadSource);
        }
    });

    dispatch_source_set_cancel_handler(mReadSource, ^{
        if (master != -1) {
            close(master);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf) {
                NppTerminalPanelView* strongSelf = weakSelf;
                strongSelf->mMasterFd = -1;
                strongSelf->_isExecuting = NO;
                strongSelf->_statusIndicator.layer.backgroundColor = [NSColor colorWithCalibratedRed: 0.85 green: 0.20 blue: 0.20 alpha: 1.0].CGColor;
            }
        });
    });

    dispatch_resume(mReadSource);
}

- (void) stopPtySession {
    if (mReadSource) {
        dispatch_source_cancel(mReadSource);
        mReadSource = NULL;
    }
    if (mMasterFd != -1) {
        close(mMasterFd);
        mMasterFd = -1;
    }
    if (mPtyPid > 0) {
        kill(mPtyPid, SIGKILL);
        mPtyPid = 0;
    }
}

- (void) sendBytesToPty: (const void *) bytes length: (size_t) len {
    if (mMasterFd != -1 && bytes && len > 0) {
        write(mMasterFd, bytes, len);
    }
}

- (void) processRawPtyOutput: (NSString *) rawText {
    if ([rawText containsString: @"\033[2J"] || [rawText containsString: @"\033c"]) {
        _outputTextView.string = @"";
    }
    [self appendOutput: rawText];
}

- (void) layout {
    [super layout];
    if (mMasterFd != -1) {
        struct winsize ws;
        CGFloat fontW = 7.5;
        CGFloat fontH = 14.0;
        ws.ws_col = (unsigned short)std::max<int>(20, (self.bounds.size.width - 16) / fontW);
        ws.ws_row = (unsigned short)std::max<int>(5, (self.bounds.size.height - 36) / fontH);
        ws.ws_xpixel = 0;
        ws.ws_ypixel = 0;
        ioctl(mMasterFd, TIOCSWINSZ, &ws);
    }
}

- (void) setWorkingDirectoryPath: (NSString *) dirPath {
    if (!dirPath || dirPath.length == 0) dirPath = NSHomeDirectory();
    _workingDirectory = dirPath;

    NSString* display = [dirPath isEqualToString: NSHomeDirectory()] ? @"~" : [dirPath lastPathComponent];
    _titleLabel.stringValue = [NSString stringWithFormat: @"TERMINAL (zsh PTY) — 📁 %@", display];

    if (mMasterFd != -1) {
        NSString* cdCmd = [NSString stringWithFormat: @"cd \"%@\"\n", dirPath];
        [self sendBytesToPty: cdCmd.UTF8String length: [cdCmd lengthOfBytesUsingEncoding: NSUTF8StringEncoding]];
    }
}

- (void) sendSigInt {
    if (mMasterFd != -1) {
        char c = 0x03; // ^C
        [self sendBytesToPty: &c length: 1];
    }
}

- (void) sendSigTstp {
    if (mMasterFd != -1) {
        char c = 0x1A; // ^Z
        [self sendBytesToPty: &c length: 1];
    }
}

- (void) sendEof {
    if (mMasterFd != -1) {
        char c = 0x04; // ^D
        [self sendBytesToPty: &c length: 1];
    }
}

- (void) copy: (id) sender {
    if (_outputTextView && _outputTextView.selectedRange.length > 0) {
        [_outputTextView copy: sender];
    } else {
        [self sendSigInt];
    }
}

- (void) cut: (id) sender {
    [self copy: sender];
}

- (void) paste: (id) sender {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSString* clipStr = [pb stringForType: NSPasteboardTypeString];
    if (!clipStr || clipStr.length == 0) {
        clipStr = [pb stringForType: NSStringPboardType];
    }
    if (!clipStr || clipStr.length == 0) return;
    const char* bytes = [clipStr UTF8String];
    [self sendBytesToPty: bytes length: strlen(bytes)];
}

- (void) selectAll: (id) sender {
    if (_outputTextView) {
        [_outputTextView selectAll: sender];
    }
}

- (NSAttributedString *) parseAnsiText: (NSString *) rawText isDarkMode: (BOOL) isDark {
    NSMutableAttributedString* result = [[NSMutableAttributedString alloc] init];

    NSColor* defaultFg = isDark ? [NSColor colorWithCalibratedWhite: 0.94 alpha: 1.0]
                                : [NSColor colorWithCalibratedWhite: 0.10 alpha: 1.0];

    NSFont* regularFont = [NSFont fontWithName: @"SF Mono" size: 11.5]
                       ?: [NSFont fontWithName: @"Menlo" size: 11.5]
                       ?: [NSFont monospacedSystemFontOfSize: 11.5 weight: NSFontWeightRegular];

    NSFont* boldFont = [NSFont fontWithName: @"SF Mono Bold" size: 11.5]
                    ?: [NSFont fontWithName: @"Menlo-Bold" size: 11.5]
                    ?: [NSFont monospacedSystemFontOfSize: 11.5 weight: NSFontWeightBold];

    NSMutableParagraphStyle* pStyle = [[NSMutableParagraphStyle alloc] init];
    pStyle.lineSpacing = 0.0;
    pStyle.paragraphSpacing = 0.0;
    pStyle.maximumLineHeight = 14.5;
    pStyle.minimumLineHeight = 14.5;

    NSArray<NSColor *>* stdColorsLight = @[
        [NSColor colorWithCalibratedWhite: 0.15 alpha: 1.0],                       // Black (0)
        [NSColor colorWithCalibratedRed: 0.85 green: 0.12 blue: 0.12 alpha: 1.0], // Red (1 - error)
        [NSColor colorWithCalibratedRed: 0.08 green: 0.60 blue: 0.18 alpha: 1.0], // Green (2)
        [NSColor colorWithCalibratedRed: 0.75 green: 0.48 blue: 0.00 alpha: 1.0], // Yellow/Gold (3 - warning)
        [NSColor colorWithCalibratedRed: 0.05 green: 0.42 blue: 0.82 alpha: 1.0], // Blue (4)
        [NSColor colorWithCalibratedRed: 0.65 green: 0.18 blue: 0.65 alpha: 1.0], // Magenta (5)
        [NSColor colorWithCalibratedRed: 0.00 green: 0.52 blue: 0.58 alpha: 1.0], // Cyan (6)
        [NSColor colorWithCalibratedWhite: 0.90 alpha: 1.0]                       // White (7)
    ];

    NSArray<NSColor *>* stdColorsDark = @[
        [NSColor colorWithCalibratedWhite: 0.25 alpha: 1.0],                       // Black (0)
        [NSColor colorWithCalibratedRed: 0.95 green: 0.32 blue: 0.32 alpha: 1.0], // Red (1 - error)
        [NSColor colorWithCalibratedRed: 0.30 green: 0.85 blue: 0.40 alpha: 1.0], // Green (2)
        [NSColor colorWithCalibratedRed: 0.95 green: 0.78 blue: 0.20 alpha: 1.0], // Yellow/Gold (3 - warning)
        [NSColor colorWithCalibratedRed: 0.35 green: 0.70 blue: 0.98 alpha: 1.0], // Blue (4)
        [NSColor colorWithCalibratedRed: 0.90 green: 0.45 blue: 0.95 alpha: 1.0], // Magenta (5)
        [NSColor colorWithCalibratedRed: 0.30 green: 0.85 blue: 0.95 alpha: 1.0], // Cyan (6)
        [NSColor colorWithCalibratedWhite: 0.98 alpha: 1.0]                       // White (7)
    ];

    NSArray<NSColor *>* palette = isDark ? stdColorsDark : stdColorsLight;

    NSColor* currentFg = defaultFg;
    NSColor* currentBg = nil;
    BOOL isBold = NO;
    BOOL isUnderline = NO;

    NSScanner* scanner = [NSScanner scannerWithString: rawText];
    scanner.charactersToBeSkipped = nil;

    while (!scanner.isAtEnd) {
        NSString* textChunk = nil;
        if ([scanner scanUpToString: @"\033" intoString: &textChunk]) {
            if (textChunk.length > 0) {
                NSMutableDictionary* attrs = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    (isBold ? boldFont : regularFont), NSFontAttributeName,
                    currentFg, NSForegroundColorAttributeName,
                    pStyle, NSParagraphStyleAttributeName,
                    nil];
                if (currentBg) attrs[NSBackgroundColorAttributeName] = currentBg;
                if (isUnderline) attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);

                [result appendAttributedString: [[NSAttributedString alloc] initWithString: textChunk attributes: attrs]];
            }
        }

        if ([scanner scanString: @"\033" intoString: nil]) {
            if ([scanner scanString: @"[" intoString: nil]) {
                NSString* seqStr = nil;
                if ([scanner scanUpToCharactersFromSet: [NSCharacterSet characterSetWithCharactersInString: @"mKHAJBCDfhls"] intoString: &seqStr]) {
                    NSString* terminator = nil;
                    if (!scanner.isAtEnd) {
                        terminator = [rawText substringWithRange: NSMakeRange(scanner.scanLocation, 1)];
                        scanner.scanLocation++;
                    }
                    if ([terminator isEqualToString: @"m"]) {
                        NSArray<NSString *>* codes = [seqStr componentsSeparatedByString: @";"];
                        for (NSUInteger i = 0; i < codes.count; ++i) {
                            int code = [codes[i] intValue];
                            if (code == 0) {
                                currentFg = defaultFg; currentBg = nil; isBold = NO; isUnderline = NO;
                            } else if (code == 1) {
                                isBold = YES;
                            } else if (code == 4) {
                                isUnderline = YES;
                            } else if (code == 22) {
                                isBold = NO;
                            } else if (code == 24) {
                                isUnderline = NO;
                            } else if (code >= 30 && code <= 37) {
                                currentFg = palette[code - 30];
                            } else if (code >= 90 && code <= 97) {
                                currentFg = palette[code - 90];
                            } else if (code == 39) {
                                currentFg = defaultFg;
                            } else if (code >= 40 && code <= 47) {
                                currentBg = palette[code - 40];
                            } else if (code == 49) {
                                currentBg = nil;
                            } else if (code == 38 && i + 2 < codes.count && [codes[i+1] intValue] == 5) {
                                int colorIdx = [codes[i+2] intValue];
                                if (colorIdx >= 0 && colorIdx < 8) currentFg = palette[colorIdx];
                                i += 2;
                            }
                        }
                    }
                }
            }
        }
    }

    if (result.length == 0 && rawText.length > 0) {
        NSDictionary* attrs = @{
            NSFontAttributeName: regularFont,
            NSForegroundColorAttributeName: defaultFg,
            NSParagraphStyleAttributeName: pStyle
        };
        return [[NSAttributedString alloc] initWithString: rawText attributes: attrs];
    }
    return result;
}

- (void) appendOutput: (NSString *) text {
    if (!text || text.length == 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSTextStorage* storage = self->_outputTextView.textStorage;

        NSArray<NSString *>* lines = [text componentsSeparatedByString: @"\r"];
        for (NSUInteger i = 0; i < lines.count; ++i) {
            NSString* segment = lines[i];
            if (i > 0) {
                NSString* currentStr = storage.string;
                NSRange lastNewline = [currentStr rangeOfString: @"\n" options: NSBackwardsSearch];
                NSUInteger lineStartPos = (lastNewline.location != NSNotFound) ? lastNewline.location + 1 : 0;
                NSRange lineRange = NSMakeRange(lineStartPos, storage.length - lineStartPos);
                [storage deleteCharactersInRange: lineRange];
            }
            if (segment.length > 0) {
                NSAttributedString* attrStr = [self parseAnsiText: segment isDarkMode: self->_isDarkMode];
                [storage appendAttributedString: attrStr];
            }
        }
        [self->_outputTextView scrollRangeToVisible: NSMakeRange(storage.length, 0)];
    });
}

- (void) onClearClicked: (id) sender {
    _outputTextView.string = @"";
    const char* clearSeq = "\033[2J\033[H";
    [self sendBytesToPty: clearSeq length: strlen(clearSeq)];
}

- (void) onOpenExternalClicked: (id) sender {
    if ([_delegate respondsToSelector: @selector(terminalPanelOpenExternalRequested:)]) {
        [_delegate terminalPanelOpenExternalRequested: _workingDirectory];
    }
}

- (void) onCloseClicked: (id) sender {
    if ([_delegate respondsToSelector: @selector(terminalPanelCloseRequested)]) {
        [_delegate terminalPanelCloseRequested];
    }
}

- (void) setIsDarkMode: (BOOL) isDark {
    _isDarkMode = isDark;
    if (_outputTextView) {
        _outputTextView.backgroundColor = isDark ? [NSColor colorWithCalibratedRed: 0.09 green: 0.09 blue: 0.10 alpha: 1.0]
                                                : [NSColor colorWithCalibratedWhite: 1.0 alpha: 1.0];
        _outputTextView.textColor = isDark ? [NSColor colorWithCalibratedWhite: 0.94 alpha: 1.0]
                                          : [NSColor colorWithCalibratedWhite: 0.10 alpha: 1.0];
        _outputTextView.insertionPointColor = isDark ? [NSColor colorWithCalibratedRed: 0.30 green: 0.85 blue: 0.95 alpha: 1.0]
                                                     : [NSColor colorWithCalibratedRed: 0.05 green: 0.45 blue: 0.90 alpha: 1.0];
    }
    if (_titleLabel) {
        _titleLabel.textColor = isDark ? [NSColor whiteColor] : [NSColor blackColor];
    }
    [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) dirtyRect {
    [super drawRect: dirtyRect];
    NSColor* bg = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.14 green: 0.14 blue: 0.15 alpha: 1.0]
                              : [NSColor colorWithCalibratedRed: 0.93 green: 0.93 blue: 0.94 alpha: 1.0];
    [bg setFill];
    NSRectFill(self.bounds);

    NSColor* border = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.20 green: 0.20 blue: 0.22 alpha: 1.0]
                                  : [NSColor colorWithCalibratedRed: 0.80 green: 0.80 blue: 0.82 alpha: 1.0];
    [border setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));
}
@end

@protocol NppSecondaryPreviewDelegate <NSObject>
- (void) secondaryPreviewCloseRequested;
- (void) secondaryPreviewLanguageSelected: (NSString *) lexerName;
@end

static NSString* parseMarkdownInline(NSString* text) {
    if (!text || text.length == 0) return @"";
    NSMutableString* str = [text mutableCopy];

    // 1. Linked Badges: [![alt](img)](url)
    NSRegularExpression* reBadge = [NSRegularExpression regularExpressionWithPattern: @"\\[!\\[(.*?)\\]\\((.*?)\\)\\]\\((.*?)\\)" options: 0 error: nil];
    [reBadge replaceMatchesInString: str options: 0 range: NSMakeRange(0, str.length) withTemplate: @"<a href=\"$3\" target=\"_blank\"><img src=\"$2\" alt=\"$1\" style=\"vertical-align:middle; margin:2px 4px 2px 0; height:20px; border-radius:3px;\"></a>"];

    // 2. Images: ![alt](url)
    NSRegularExpression* reImg = [NSRegularExpression regularExpressionWithPattern: @"!\\[(.*?)\\]\\((.*?)\\)" options: 0 error: nil];
    [reImg replaceMatchesInString: str options: 0 range: NSMakeRange(0, str.length) withTemplate: @"<img src=\"$2\" alt=\"$1\" style=\"max-width:100%; border-radius:4px; margin:6px 0;\">"];

    // 3. Links: [text](url)
    NSRegularExpression* reLink = [NSRegularExpression regularExpressionWithPattern: @"\\[(.*?)\\]\\((.*?)\\)" options: 0 error: nil];
    [reLink replaceMatchesInString: str options: 0 range: NSMakeRange(0, str.length) withTemplate: @"<a href=\"$2\" target=\"_blank\" style=\"color:#007aff; text-decoration:none;\">$1</a>"];

    // 4. Bold: **text**
    NSRegularExpression* reBold = [NSRegularExpression regularExpressionWithPattern: @"\\*\\*(.*?)\\*\\*" options: 0 error: nil];
    [reBold replaceMatchesInString: str options: 0 range: NSMakeRange(0, str.length) withTemplate: @"<strong>$1</strong>"];

    // 5. Italic: *text* (not double asterisk)
    NSRegularExpression* reItalic = [NSRegularExpression regularExpressionWithPattern: @"(?<!\\*)\\*([^*]+)\\*(?!\\*)" options: 0 error: nil];
    [reItalic replaceMatchesInString: str options: 0 range: NSMakeRange(0, str.length) withTemplate: @"<em>$1</em>"];

    // 6. Inline code: `code`
    NSRegularExpression* reCode = [NSRegularExpression regularExpressionWithPattern: @"`([^`]+)`" options: 0 error: nil];
    [reCode replaceMatchesInString: str options: 0 range: NSMakeRange(0, str.length) withTemplate: @"<code style=\"font-family:'SF Mono',Menlo,monospace; font-size:12px; background:rgba(128,128,128,0.15); padding:2px 5px; border-radius:4px;\">$1</code>"];

    // 7. Strikethrough: ~~text~~
    NSRegularExpression* reDel = [NSRegularExpression regularExpressionWithPattern: @"~~(.*?)~~" options: 0 error: nil];
    [reDel replaceMatchesInString: str options: 0 range: NSMakeRange(0, str.length) withTemplate: @"<del>$1</del>"];

    return str;
}

static NSString* renderMarkdownToHtmlBody(NSString* content, BOOL isDark) {
    if (!content || content.length == 0) return @"";
    NSMutableString* html = [NSMutableString string];

    NSString* badgeBg = isDark ? @"#005fb8" : @"#e1effe";
    NSString* badgeFg = isDark ? @"#ffffff" : @"#1e429f";
    NSString* codeBg = isDark ? @"#222225" : @"#f5f5f7";

    [html appendFormat: @"<div style='margin-bottom: 12px;'><span style='background:%@; color:%@; padding: 3px 8px; border-radius: 4px; font-size: 11px; font-weight: bold;'>GFM Markdown Render</span></div>", badgeBg, badgeFg];

    NSArray<NSString *>* lines = [content componentsSeparatedByString: @"\n"];
    BOOL inCodeBlock = NO;
    NSString* codeLang = @"";
    BOOL inList = NO;
    BOOL inTable = NO;
    BOOL inAlert = NO;

    for (NSString* rawLine in lines) {
        NSString* line = rawLine;

        // Code block toggle
        if ([line hasPrefix: @"```"]) {
            inCodeBlock = !inCodeBlock;
            if (inCodeBlock) {
                codeLang = [line substringFromIndex: 3];
                if (codeLang.length == 0) codeLang = @"code";
                [html appendFormat: @"<div style='background:%@; border:1px solid rgba(128,128,128,0.2); border-radius:6px; margin:12px 0; overflow:hidden;'><div style='padding:4px 10px; font-size:11px; background:rgba(128,128,128,0.08); border-bottom:1px solid rgba(128,128,128,0.15); opacity:0.8;'>%@</div><pre style='margin:0; padding:12px; font-family:Menlo,SF Mono,monospace; font-size:12px; overflow-x:auto;'><code>", codeBg, codeLang];
            } else {
                [html appendString: @"</code></pre></div>"];
            }
            continue;
        }

        if (inCodeBlock) {
            NSString* esc = [[line stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                   stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
            [html appendFormat: @"%@\n", esc];
            continue;
        }

        // Alert Callouts
        if ([line hasPrefix: @"> [!NOTE]"]) {
            if (inAlert) [html appendString: @"</div>"];
            [html appendString: @"<div style='border-left:4px solid #007aff; background:rgba(0,122,255,0.08); padding:10px 14px; margin:12px 0; border-radius:4px;'><div style='font-weight:bold; margin-bottom:4px; font-size:12px;'>ℹ️ NOTE</div>"];
            inAlert = YES;
            continue;
        } else if ([line hasPrefix: @"> [!TIP]"]) {
            if (inAlert) [html appendString: @"</div>"];
            [html appendString: @"<div style='border-left:4px solid #34c759; background:rgba(52,199,89,0.08); padding:10px 14px; margin:12px 0; border-radius:4px;'><div style='font-weight:bold; margin-bottom:4px; font-size:12px;'>💡 TIP</div>"];
            inAlert = YES;
            continue;
        } else if ([line hasPrefix: @"> [!IMPORTANT]"]) {
            if (inAlert) [html appendString: @"</div>"];
            [html appendString: @"<div style='border-left:4px solid #af52de; background:rgba(175,82,222,0.08); padding:10px 14px; margin:12px 0; border-radius:4px;'><div style='font-weight:bold; margin-bottom:4px; font-size:12px;'>🟣 IMPORTANT</div>"];
            inAlert = YES;
            continue;
        } else if ([line hasPrefix: @"> [!WARNING]"]) {
            if (inAlert) [html appendString: @"</div>"];
            [html appendString: @"<div style='border-left:4px solid #ff9500; background:rgba(255,149,0,0.08); padding:10px 14px; margin:12px 0; border-radius:4px;'><div style='font-weight:bold; margin-bottom:4px; font-size:12px;'>⚠️ WARNING</div>"];
            inAlert = YES;
            continue;
        } else if ([line hasPrefix: @"> [!CAUTION]"]) {
            if (inAlert) [html appendString: @"</div>"];
            [html appendString: @"<div style='border-left:4px solid #ff3b30; background:rgba(255,59,48,0.08); padding:10px 14px; margin:12px 0; border-radius:4px;'><div style='font-weight:bold; margin-bottom:4px; font-size:12px;'>🔴 CAUTION</div>"];
            inAlert = YES;
            continue;
        } else if (inAlert && [line hasPrefix: @"> "]) {
            [html appendFormat: @"<div>%@</div>", parseMarkdownInline([line substringFromIndex: 2])];
            continue;
        } else if (inAlert && line.length == 0) {
            [html appendString: @"</div>"];
            inAlert = NO;
        }

        // Table Parsing
        if ([line hasPrefix: @"|"] && [line hasSuffix: @"|"]) {
            if (!inTable) {
                [html appendString: @"<div style='overflow-x:auto; margin:12px 0;'><table style='border-collapse:collapse; width:100%; font-size:12.5px;'>"];
                inTable = YES;
            }
            if ([line containsString: @"---"]) continue; // separator

            NSArray<NSString *>* cells = [line componentsSeparatedByString: @"|"];
            [html appendString: @"<tr>"];
            for (size_t c = 1; c + 1 < cells.count; ++c) {
                NSString* cellVal = [cells[c] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
                [html appendFormat: @"<td style='border:1px solid rgba(128,128,128,0.3); padding:6px 10px;'>%@</td>", parseMarkdownInline(cellVal)];
            }
            [html appendString: @"</tr>"];
            continue;
        } else if (inTable) {
            [html appendString: @"</table></div>"];
            inTable = NO;
        }

        // Headers
        if ([line hasPrefix: @"###### "]) [html appendFormat: @"<h6>%@</h6>", parseMarkdownInline([line substringFromIndex: 7])];
        else if ([line hasPrefix: @"##### "]) [html appendFormat: @"<h5>%@</h5>", parseMarkdownInline([line substringFromIndex: 6])];
        else if ([line hasPrefix: @"#### "]) [html appendFormat: @"<h4>%@</h4>", parseMarkdownInline([line substringFromIndex: 5])];
        else if ([line hasPrefix: @"### "]) [html appendFormat: @"<h3>%@</h3>", parseMarkdownInline([line substringFromIndex: 4])];
        else if ([line hasPrefix: @"## "]) [html appendFormat: @"<h2 style='border-bottom:1px solid rgba(128,128,128,0.2); padding-bottom:4px; margin-top:16px;'>%@</h2>", parseMarkdownInline([line substringFromIndex: 3])];
        else if ([line hasPrefix: @"# "]) [html appendFormat: @"<h1 style='border-bottom:1px solid rgba(128,128,128,0.25); padding-bottom:6px; margin-top:18px;'>%@</h1>", parseMarkdownInline([line substringFromIndex: 2])];
        // Task lists & Lists
        else if ([line hasPrefix: @"- [x] "] || [line hasPrefix: @"* [x] "]) [html appendFormat: @"<div style='margin:4px 0;'><input type='checkbox' checked disabled> <strike>%@</strike></div>", parseMarkdownInline([line substringFromIndex: 6])];
        else if ([line hasPrefix: @"- [ ] "] || [line hasPrefix: @"* [ ] "]) [html appendFormat: @"<div style='margin:4px 0;'><input type='checkbox' disabled> %@</div>", parseMarkdownInline([line substringFromIndex: 6])];
        else if ([line hasPrefix: @"- "] || [line hasPrefix: @"* "]) {
            if (!inList) { [html appendString: @"<ul style='padding-left:20px; margin:6px 0;'>"]; inList = YES; }
            [html appendFormat: @"<li>%@</li>", parseMarkdownInline([line substringFromIndex: 2])];
        }
        else if ([line hasPrefix: @"> "]) [html appendFormat: @"<blockquote style='border-left:4px solid #007aff; margin:8px 0; padding-left:12px; opacity:0.85;'>%@</blockquote>", parseMarkdownInline([line substringFromIndex: 2])];
        else if ([line hasPrefix: @"---"] || [line hasPrefix: @"***"]) [html appendString: @"<hr style='height:1px; border:0; background:rgba(128,128,128,0.25); margin:16px 0;'>"];
        else {
            if (inList) { [html appendString: @"</ul>"]; inList = NO; }
            if (line.length == 0) [html appendString: @"<p style='margin:6px 0;'></p>"];
            else [html appendFormat: @"<p style='margin:6px 0;'>%@</p>", parseMarkdownInline(line)];
        }
    }
    if (inList) [html appendString: @"</ul>"];
    if (inTable) [html appendString: @"</table></div>"];
    if (inAlert) [html appendString: @"</div>"];

    return html;
}

@interface NppSecondaryPreviewView : NSView <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, weak) id<NppSecondaryPreviewDelegate> delegate;
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSSegmentedControl* modeSegment;
@property (nonatomic, strong) NSString* currentRawContent;
@property (nonatomic, strong) NSString* currentFileName;
@property (nonatomic, strong) NSString* currentLexer;
@property (nonatomic, assign) NSInteger currentViewMode; // 0: Formatted, 1: Raw, 2: Structure/Stats
@property (nonatomic, assign) BOOL isDarkMode;
@property (nonatomic, assign) CGFloat zoomLevel;
- (void) renderDocumentContent: (NSString *) content fileName: (NSString *) fileName lexerName: (NSString *) lexer;
@end

@implementation NppSecondaryPreviewView

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _isDarkMode = NO;
        _zoomLevel = 1.0;
        _currentViewMode = 0;
        _currentRawContent = @"";
        _currentFileName = @"";
        _currentLexer = @"text";
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    // 1. Header Toolbar
    NSView* header = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, self.bounds.size.width, 32)];
    header.autoresizingMask = NSViewWidthSizable;
    [self addSubview: header];

    _titleLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(8, 7, self.bounds.size.width - 205, 18)];
    _titleLabel.stringValue = @"PREVIEW";
    _titleLabel.bezeled = NO; _titleLabel.drawsBackground = NO; _titleLabel.editable = NO;
    _titleLabel.font = [NSFont systemFontOfSize: 11 weight: NSFontWeightBold];
    [header addSubview: _titleLabel];

    // 2-Step Mode Switcher (Render / Info)
    _modeSegment = [NSSegmentedControl segmentedControlWithLabels: @[@"Render", @"Info"] trackingMode: NSSegmentSwitchTrackingSelectOne target: self action: @selector(onModeChanged:)];
    _modeSegment.frame = NSMakeRect(self.bounds.size.width - 195, 5, 86, 22);
    _modeSegment.selectedSegment = 0;
    _modeSegment.autoresizingMask = NSViewMinXMargin;
    if (@available(macOS 10.13, *)) {
        _modeSegment.segmentStyle = NSSegmentStyleRounded;
    }
    [header addSubview: _modeSegment];

    // Copy Button
    NSButton* btnCopy = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 105, 5, 30, 22)];
    btnCopy.bezelStyle = NSBezelStyleInline;
    btnCopy.title = @"📋";
    btnCopy.toolTip = @"Copy Preview Content / HTML";
    btnCopy.target = self;
    btnCopy.action = @selector(onCopyHtml:);
    btnCopy.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnCopy];

    // Open in Browser Button
    NSButton* btnBrowser = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 72, 5, 30, 22)];
    btnBrowser.bezelStyle = NSBezelStyleInline;
    btnBrowser.title = @"🌐";
    btnBrowser.toolTip = @"Open Preview in Default Browser";
    btnBrowser.target = self;
    btnBrowser.action = @selector(onOpenInBrowser:);
    btnBrowser.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnBrowser];

    // Zoom Controls (+ / -)
    NSButton* btnZoom = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 40, 5, 18, 22)];
    btnZoom.bezelStyle = NSBezelStyleInline;
    btnZoom.title = @"+";
    btnZoom.toolTip = @"Zoom In / Out";
    btnZoom.target = self;
    btnZoom.action = @selector(onZoomIn:);
    btnZoom.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnZoom];

    // Close Button
    NSButton* btnClose = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 20, 5, 16, 22)];
    btnClose.bezelStyle = NSBezelStyleInline;
    btnClose.title = @"×";
    btnClose.toolTip = @"Close Preview Panel";
    btnClose.target = self;
    btnClose.action = @selector(onCloseClicked:);
    btnClose.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClose];

    // 2. WebKit View
    WKUserContentController* userContent = [[WKUserContentController alloc] init];
    [userContent addScriptMessageHandler: self name: @"selectLang"];
    [userContent addScriptMessageHandler: self name: @"copyCode"];

    WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userContent;

    _webView = [[WKWebView alloc] initWithFrame: NSMakeRect(0, 32, self.bounds.size.width, self.bounds.size.height - 32) configuration: config];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.navigationDelegate = self;
    [self addSubview: _webView];
}

- (void) userContentController: (WKUserContentController *) userContentController didReceiveScriptMessage: (WKScriptMessage *) message {
    if ([message.name isEqualToString: @"selectLang"] && [message.body isKindOfClass: [NSString class]]) {
        if ([_delegate respondsToSelector: @selector(secondaryPreviewLanguageSelected:)]) {
            [_delegate secondaryPreviewLanguageSelected: message.body];
        }
    } else if ([message.name isEqualToString: @"copyCode"] && [message.body isKindOfClass: [NSString class]]) {
        NSPasteboard* pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString: message.body forType: NSPasteboardTypeString];
    }
}

- (void) onModeChanged: (id) sender {
    _currentViewMode = _modeSegment.selectedSegment;
    [self renderDocumentContent: _currentRawContent fileName: _currentFileName lexerName: _currentLexer];
}

- (void) onZoomIn: (id) sender {
    _zoomLevel += 0.15;
    if (_zoomLevel > 2.5) _zoomLevel = 1.0;
    [_webView evaluateJavaScript: [NSString stringWithFormat: @"document.body.style.zoom = '%.2f';", _zoomLevel] completionHandler: nil];
}

- (void) onCopyHtml: (id) sender {
    [_webView evaluateJavaScript: @"document.documentElement.outerHTML" completionHandler: ^(id result, NSError *error) {
        if ([result isKindOfClass: [NSString class]]) {
            NSPasteboard* pb = [NSPasteboard generalPasteboard];
            [pb clearContents];
            [pb setString: result forType: NSPasteboardTypeString];
        }
    }];
}

- (void) onOpenInBrowser: (id) sender {
    [_webView evaluateJavaScript: @"document.documentElement.outerHTML" completionHandler: ^(id result, NSError *error) {
        if ([result isKindOfClass: [NSString class]]) {
            NSString* tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent: @"npp_preview.html"];
            [result writeToFile: tempPath atomically: YES encoding: NSUTF8StringEncoding error: nil];
            [[NSWorkspace sharedWorkspace] openURL: [NSURL fileURLWithPath: tempPath]];
        }
    }];
}

- (void) renderDocumentContent: (NSString *) content fileName: (NSString *) fileName lexerName: (NSString *) lexer {
    if (!content) content = @"";
    _currentRawContent = content;
    _currentFileName = fileName ?: @"";
    _currentLexer = lexer ?: @"text";

    NSString* ext = [[fileName pathExtension] lowercaseString];
    NSString* bodyHtml = @"";
    NSString* modeTitle = @"";

    // Info/Stats mode (Segment 1)
    if (_currentViewMode == 1) {
        modeTitle = @"[File Metrics & Structure]";
        NSArray<NSString *>* lines = [content componentsSeparatedByString: @"\n"];
        NSUInteger lineCount = lines.count;
        NSUInteger charCount = content.length;
        NSUInteger wordCount = [[content componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] filteredArrayUsingPredicate: [NSPredicate predicateWithFormat: @"length > 0"]].count;

        bodyHtml = [NSString stringWithFormat:
            @"<div style='font-family:-apple-system,BlinkMacSystemFont,sans-serif; padding:10px;'>"
            @"  <h3 style='margin:0 0 14px 0; color:#007aff;'>📊 File Structure & Metrics</h3>"
            @"  <div style='display:grid; grid-template-columns:repeat(3, 1fr); gap:10px; margin-bottom:18px;'>"
            @"    <div style='padding:12px; border-radius:8px; background:%@; text-align:center; border:1px solid rgba(128,128,128,0.2);'><div style='font-size:20px; font-weight:700; color:#007aff;'>%lu</div><div style='font-size:11px; opacity:0.7;'>Total Lines</div></div>"
            @"    <div style='padding:12px; border-radius:8px; background:%@; text-align:center; border:1px solid rgba(128,128,128,0.2);'><div style='font-size:20px; font-weight:700; color:#34c759;'>%lu</div><div style='font-size:11px; opacity:0.7;'>Words</div></div>"
            @"    <div style='padding:12px; border-radius:8px; background:%@; text-align:center; border:1px solid rgba(128,128,128,0.2);'><div style='font-size:20px; font-weight:700; color:#ff9500;'>%lu</div><div style='font-size:11px; opacity:0.7;'>Characters</div></div>"
            @"  </div>"
            @"  <div style='padding:14px; border-radius:8px; background:%@; border:1px solid rgba(128,128,128,0.2); font-size:12px; line-height:1.8;'>"
            @"    <div><b>File Name:</b> %@</div>"
            @"    <div><b>Extension:</b> .%@</div>"
            @"    <div><b>Lexer Engine:</b> <span style='background:rgba(0,122,255,0.15); color:#007aff; padding:2px 6px; border-radius:4px;'>%@</span></div>"
            @"    <div><b>Render Pipeline:</b> Native Cocoa WebKit / GFM Engine</div>"
            @"  </div>"
            @"</div>",
            _isDarkMode ? @"#252528" : @"#f4f6f8", (unsigned long)lineCount,
            _isDarkMode ? @"#252528" : @"#f4f6f8", (unsigned long)wordCount,
            _isDarkMode ? @"#252528" : @"#f4f6f8", (unsigned long)charCount,
            _isDarkMode ? @"#252528" : @"#f4f6f8", fileName, ext, lexer];
    }
    // 0: Rendered format mode per language category
    else {
        // 1. Markdown / Documentation
        if ([ext isEqualToString: @"md"] || [ext isEqualToString: @"markdown"] || [lexer isEqualToString: @"markdown"]) {
            modeTitle = @"[Markdown GFM]";
            bodyHtml = renderMarkdownToHtmlBody(content, _isDarkMode);
        }
        // 2. HTML / Web pages
        else if ([ext isEqualToString: @"html"] || [ext isEqualToString: @"htm"] || [lexer isEqualToString: @"hypertext"]) {
            modeTitle = @"[HTML Live View]";
            bodyHtml = content;
        }
        // 3. SVG Vector Graphic
        else if ([ext isEqualToString: @"svg"]) {
            modeTitle = @"[SVG Vector Canvas]";
            bodyHtml = [NSString stringWithFormat:
                @"<div style='display:flex; flex-direction:column; align-items:center; justify-content:center; min-height:260px; padding:20px;'>"
                @"  <div style='padding:20px; border-radius:12px; background:%@; border:1px dashed rgba(128,128,128,0.3); max-width:100%%; overflow:auto;'>%@</div>"
                @"  <div style='margin-top:12px; font-size:11px; opacity:0.6;'>SVG Vector Rendering Canvas</div>"
                @"</div>", _isDarkMode ? @"#1e1e20" : @"#ffffff", content];
        }
        // 4. JSON / GeoJSON / JSON5 (Interactive Tree / Colorized)
        else if ([ext isEqualToString: @"json"] || [ext isEqualToString: @"geojson"] || [lexer isEqualToString: @"json"]) {
            modeTitle = @"[JSON Structured View]";
            NSString* esc = [[content stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                    stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
            bodyHtml = [NSString stringWithFormat:
                @"<div style='margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;'>"
                @"  <span style='font-weight:600; font-size:12px; color:#007aff;'>📦 JSON Object Presentation</span>"
                @"  <span style='font-size:11px; opacity:0.7;'>%lu characters</span>"
                @"</div>"
                @"<pre style='margin:0; padding:14px; border-radius:8px; font-family:Menlo,Consolas,monospace; font-size:12px; line-height:1.5; background:%@; border:1px solid rgba(128,128,128,0.2); overflow-x:auto;'><code>%@</code></pre>",
                (unsigned long)content.length, _isDarkMode ? @"#222225" : @"#f6f8fa", esc];
        }
        // 5. XML / Plist / XAML
        else if ([ext isEqualToString: @"xml"] || [ext isEqualToString: @"plist"] || [ext isEqualToString: @"xaml"] || [lexer isEqualToString: @"xml"]) {
            modeTitle = @"[XML Tag Hierarchy]";
            NSString* esc = [[content stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                    stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
            bodyHtml = [NSString stringWithFormat:
                @"<div style='margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;'>"
                @"  <span style='font-weight:600; font-size:12px; color:#ff9500;'>📄 XML Element Hierarchy</span>"
                @"  <span style='font-size:11px; opacity:0.7;'>%lu characters</span>"
                @"</div>"
                @"<pre style='margin:0; padding:14px; border-radius:8px; font-family:Menlo,Consolas,monospace; font-size:12px; line-height:1.5; background:%@; border:1px solid rgba(128,128,128,0.2); overflow-x:auto;'><code>%@</code></pre>",
                (unsigned long)content.length, _isDarkMode ? @"#222225" : @"#f6f8fa", esc];
        }
        // 6. YAML / TOML / INI / Props Configuration
        else if ([ext isEqualToString: @"yaml"] || [ext isEqualToString: @"yml"] || [ext isEqualToString: @"toml"] || [ext isEqualToString: @"ini"] || [ext isEqualToString: @"cfg"] || [ext isEqualToString: @"conf"] || [lexer isEqualToString: @"yaml"] || [lexer isEqualToString: @"toml"] || [lexer isEqualToString: @"props"]) {
            modeTitle = @"[Config Structured Inspector]";
            NSString* esc = [[content stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                    stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
            bodyHtml = [NSString stringWithFormat:
                @"<div style='margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;'>"
                @"  <span style='font-weight:600; font-size:12px; color:#34c759;'>⚙️ Configuration Key-Value View</span>"
                @"  <span style='font-size:11px; opacity:0.7;'>Format: %@</span>"
                @"</div>"
                @"<pre style='margin:0; padding:14px; border-radius:8px; font-family:Menlo,Consolas,monospace; font-size:12px; line-height:1.5; background:%@; border:1px solid rgba(128,128,128,0.2); overflow-x:auto;'><code>%@</code></pre>",
                lexer.uppercaseString, _isDarkMode ? @"#222225" : @"#f6f8fa", esc];
        }
        // 7. CSV / TSV Tabular Data
        else if ([ext isEqualToString: @"csv"] || [ext isEqualToString: @"tsv"]) {
            modeTitle = @"[Tabular Grid]";
            NSString* sep = [ext isEqualToString: @"tsv"] ? @"\t" : @",";
            NSArray<NSString *>* rows = [content componentsSeparatedByString: @"\n"];
            NSMutableString* tableHtml = [NSMutableString stringWithString: @"<div style='overflow-x:auto;'><table style='width:100%; border-collapse:collapse; font-size:12px;'>"];
            for (size_t r = 0; r < rows.count && r < 200; ++r) {
                NSString* rowStr = [rows[r] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (rowStr.length == 0) continue;
                NSArray<NSString *>* cols = [rowStr componentsSeparatedByString: sep];
                [tableHtml appendString: @"<tr>"];
                for (NSString* col in cols) {
                    if (r == 0) {
                        [tableHtml appendFormat: @"<th style='background:%@; padding:7px 10px; border:1px solid rgba(128,128,128,0.3); text-align:left;'>%@</th>", _isDarkMode ? @"#2a2a2e" : @"#eef1f5", [col stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"]];
                    } else {
                        [tableHtml appendFormat: @"<td style='padding:6px 10px; border:1px solid rgba(128,128,128,0.2);'>%@</td>", [col stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"]];
                    }
                }
                [tableHtml appendString: @"</tr>"];
            }
            [tableHtml appendString: @"</table></div>"];
            bodyHtml = tableHtml;
        }
        // 8. SQL Query Viewer
        else if ([ext isEqualToString: @"sql"] || [lexer isEqualToString: @"sql"]) {
            modeTitle = @"[SQL Query View]";
            NSString* esc = [[content stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                    stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
            bodyHtml = [NSString stringWithFormat:
                @"<div style='margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;'>"
                @"  <span style='font-weight:600; font-size:12px; color:#af52de;'>🗄️ SQL Query Presentation</span>"
                @"</div>"
                @"<pre style='margin:0; padding:14px; border-radius:8px; font-family:Menlo,Consolas,monospace; font-size:12px; line-height:1.5; background:%@; border:1px solid rgba(128,128,128,0.2); overflow-x:auto;'><code>%@</code></pre>",
                _isDarkMode ? @"#222225" : @"#f6f8fa", esc];
        }
        // 9. All Other Code / Source Files (C++, Python, Rust, Go, JS/TS, Swift, Java, etc.)
        else {
            NSString* langDisplayName = lexer.uppercaseString;
            NSString* langIcon = @"⚡";
            if ([lexer isEqualToString: @"javascript"]) { langDisplayName = @"JavaScript"; langIcon = @"🟨"; }
            else if ([lexer isEqualToString: @"typescript"]) { langDisplayName = @"TypeScript"; langIcon = @"🟦"; }
            else if ([lexer isEqualToString: @"python"]) { langDisplayName = @"Python"; langIcon = @"🐍"; }
            else if ([lexer isEqualToString: @"rust"]) { langDisplayName = @"Rust"; langIcon = @"🦀"; }
            else if ([lexer isEqualToString: @"go"]) { langDisplayName = @"Go"; langIcon = @"🐹"; }
            else if ([lexer isEqualToString: @"java"]) { langDisplayName = @"Java"; langIcon = @"☕"; }
            else if ([lexer isEqualToString: @"csharp"]) { langDisplayName = @"C#"; langIcon = @"🔷"; }
            else if ([lexer isEqualToString: @"kotlin"]) { langDisplayName = @"Kotlin"; langIcon = @"🟣"; }
            else if ([lexer isEqualToString: @"swift"]) { langDisplayName = @"Swift"; langIcon = @"🐦"; }
            else if ([lexer isEqualToString: @"c"]) { langDisplayName = @"C"; langIcon = @"⚙️"; }
            else if ([lexer isEqualToString: @"cpp"]) { langDisplayName = @"C++"; langIcon = @"⚡"; }
            else if ([lexer isEqualToString: @"objc"]) { langDisplayName = @"Objective-C"; langIcon = @"🍎"; }
            else if ([lexer isEqualToString: @"ruby"]) { langDisplayName = @"Ruby"; langIcon = @"💎"; }
            else if ([lexer isEqualToString: @"php"]) { langDisplayName = @"PHP"; langIcon = @"🐘"; }
            else if ([lexer isEqualToString: @"bash"]) { langDisplayName = @"Shell Script"; langIcon = @"🐚"; }
            else if ([lexer isEqualToString: @"lua"]) { langDisplayName = @"Lua"; langIcon = @"🌙"; }

            modeTitle = [NSString stringWithFormat: @"[%@ Code Card]", langDisplayName];
            NSArray<NSString *>* lines = [content componentsSeparatedByString: @"\n"];
            NSMutableString* codeBlock = [NSMutableString string];
            for (size_t l = 0; l < lines.count && l < 500; ++l) {
                NSString* lineEsc = [[lines[l] stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                            stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
                [codeBlock appendFormat: @"<div style='display:flex;'><span style='width:36px; min-width:36px; user-select:none; opacity:0.4; font-size:11px; text-align:right; padding-right:12px;'>%zu</span><span style='white-space:pre;'>%@</span></div>", l + 1, lineEsc];
            }
            bodyHtml = [NSString stringWithFormat:
                @"<div style='margin-bottom:10px; display:flex; justify-content:space-between; align-items:center;'>"
                @"  <span style='font-weight:600; font-size:12px; color:#007aff;'>%@ %@ Source Code (%lu lines)</span>"
                @"  <span style='font-size:11px; opacity:0.7;'>%@</span>"
                @"</div>"
                @"<div style='padding:14px 10px; border-radius:8px; font-family:Menlo,Consolas,monospace; font-size:12px; line-height:1.5; background:%@; border:1px solid rgba(128,128,128,0.2); overflow-x:auto;'>%@</div>",
                langIcon, langDisplayName, (unsigned long)lines.count, fileName, _isDarkMode ? @"#222225" : @"#f6f8fa", codeBlock];
        }
    }

    // Connect language name and rendering mode to Title Label
    if (fileName && fileName.length > 0) {
        _titleLabel.stringValue = [NSString stringWithFormat: @"PREVIEW: %@ %@", fileName, modeTitle];
    } else {
        _titleLabel.stringValue = [NSString stringWithFormat: @"PREVIEW: %@", modeTitle];
    }

    NSString* fontCss = @"font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;";
    NSString* fullPageHtml = [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
        @"<style>"
        @"  body { margin:0; padding:16px; font-size:13px; line-height:1.6; color:%@; background:%@; %@ }"
        @"  a { color:#007aff; text-decoration:none; }"
        @"  a:hover { text-decoration:underline; }"
        @"</style></head><body>%@</body></html>",
        _isDarkMode ? @"#e6e6e6" : @"#1f1f1f",
        _isDarkMode ? @"#1a1a1c" : @"#ffffff",
        fontCss,
        bodyHtml];

    NSURL* baseURL = [NSURL fileURLWithPath: [[NSBundle mainBundle] resourcePath]];
    if (!baseURL || ![[NSFileManager defaultManager] fileExistsAtPath: [baseURL path]]) {
        baseURL = [NSURL fileURLWithPath: @"/Users/mac/Antigravity/notepadpp/PowerEditor/src"];
    }
    [_webView loadHTMLString: fullPageHtml baseURL: baseURL];
}

- (void) onCloseClicked: (id) sender {
    if ([_delegate respondsToSelector: @selector(secondaryPreviewCloseRequested)]) {
        [_delegate secondaryPreviewCloseRequested];
    }
}

- (void) setIsDarkMode: (BOOL) isDark {
    _isDarkMode = isDark;
    if (_titleLabel) {
        _titleLabel.textColor = isDark ? [NSColor whiteColor] : [NSColor blackColor];
    }
    if (_modeSegment) {
        _modeSegment.appearance = isDark ? [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]
                                         : [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    }
    [self renderDocumentContent: _currentRawContent fileName: _currentFileName lexerName: _currentLexer];
    [self setNeedsDisplay: YES];
}

- (void) drawRect: (NSRect) dirtyRect {
    [super drawRect: dirtyRect];
    NSColor* bg = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.14 green: 0.14 blue: 0.15 alpha: 1.0]
                              : [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];
    [bg setFill];
    NSRectFill(self.bounds);

    NSColor* border = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.20 green: 0.20 blue: 0.22 alpha: 1.0]
                                  : [NSColor colorWithCalibratedRed: 0.80 green: 0.80 blue: 0.82 alpha: 1.0];
    [border setFill];
    NSRectFill(NSMakeRect(0, 0, 1, self.bounds.size.height));
}

@end

@protocol NppDragDropDelegate <NSObject>
- (void) filesDropped: (NSArray<NSString *> *) filePaths;
@end

@interface NppMainContentView : NSView <NSSplitViewDelegate>
@property (nonatomic, weak) id<NppDragDropDelegate> dragDelegate;
@property (nonatomic, strong) NppTabBarView* tabBar;
@property (nonatomic, strong) NSSplitView* mainHorizontalSplit;
@property (nonatomic, strong) NSSplitView* centerVerticalSplit;
@property (nonatomic, strong) NppFileExplorerView* primarySidePanel;
@property (nonatomic, strong) ScintillaView* editor;
@property (nonatomic, strong) NppTerminalPanelView* bottomPanel;
@property (nonatomic, strong) NppSecondaryPreviewView* secondarySidePanel;
@property (nonatomic, strong) NppStatusBarView* statusBar;

@property (nonatomic, assign) BOOL isPrimarySidePanelVisible;
@property (nonatomic, assign) BOOL isBottomPanelVisible;
@property (nonatomic, assign) BOOL isSecondarySidePanelVisible;

- (void) updateSplitLayout;
@end

@implementation NppMainContentView

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        [self registerForDraggedTypes: @[NSPasteboardTypeFileURL]];
        _isPrimarySidePanelVisible = NO;
        _isBottomPanelVisible = NO;
        _isSecondarySidePanelVisible = NO;
    }
    return self;
}

- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) sender {
    NSPasteboard* pboard = [sender draggingPasteboard];
    if ([pboard.types containsObject: NSPasteboardTypeFileURL]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender {
    NSPasteboard* pboard = [sender draggingPasteboard];
    if ([pboard.types containsObject: NSPasteboardTypeFileURL]) {
        NSArray* urls = [pboard readObjectsForClasses: @[[NSURL class]] options: nil];
        NSMutableArray<NSString *>* paths = [NSMutableArray array];
        for (NSURL* url in urls) {
            [paths addObject: url.path];
        }
        if (paths.count > 0 && [_dragDelegate respondsToSelector: @selector(filesDropped:)]) {
            [_dragDelegate filesDropped: paths];
            return YES;
        }
    }
    return NO;
}

- (void) layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat w = b.size.width;
    CGFloat h = b.size.height;

    CGFloat tabH = 30.0;
    CGFloat statusH = 24.0;

    if (_tabBar) _tabBar.frame = NSMakeRect(0, 0, w, tabH);
    if (_statusBar) _statusBar.frame = NSMakeRect(0, h - statusH, w, statusH);

    CGFloat middleTop = tabH;
    CGFloat middleH = std::max<CGFloat>(0.0, h - statusH - middleTop);

    if (_mainHorizontalSplit) {
        _mainHorizontalSplit.frame = NSMakeRect(0, middleTop, w, middleH);
        [_mainHorizontalSplit adjustSubviews];
    }
    if (_centerVerticalSplit) {
        [_centerVerticalSplit adjustSubviews];
    }
}

- (BOOL) splitView: (NSSplitView *) splitView shouldHideDividerAtIndex: (NSInteger) dividerIndex {
    if (splitView == _mainHorizontalSplit) {
        if (dividerIndex == 0 && !_isPrimarySidePanelVisible) return YES;
        if (dividerIndex == 1 && !_isSecondarySidePanelVisible) return YES;
    } else if (splitView == _centerVerticalSplit) {
        if (!_isBottomPanelVisible) return YES;
    }
    return NO;
}

- (void) updateSplitLayout {
    if (_primarySidePanel) {
        [_primarySidePanel setHidden: !_isPrimarySidePanelVisible];
    }
    if (_secondarySidePanel) {
        [_secondarySidePanel setHidden: !_isSecondarySidePanelVisible];
    }
    if (_bottomPanel) {
        [_bottomPanel setHidden: !_isBottomPanelVisible];
    }

    [_mainHorizontalSplit adjustSubviews];
    [_centerVerticalSplit adjustSubviews];
    [self setNeedsLayout: YES];
}

- (CGFloat) splitView: (NSSplitView *) splitView constrainMinCoordinate: (CGFloat) proposedMin ofSubviewAt: (NSInteger) dividerIndex {
    if (splitView == _mainHorizontalSplit) {
        if (dividerIndex == 0) return 160.0;
    } else if (splitView == _centerVerticalSplit) {
        return 100.0;
    }
    return proposedMin;
}

- (CGFloat) splitView: (NSSplitView *) splitView constrainMaxCoordinate: (CGFloat) proposedMax ofSubviewAt: (NSInteger) dividerIndex {
    if (splitView == _mainHorizontalSplit) {
        if (dividerIndex == 0) return 500.0;
        else if (dividerIndex == 1) return splitView.bounds.size.width - 200.0;
    } else if (splitView == _centerVerticalSplit) {
        return splitView.bounds.size.height - 80.0;
    }
    return proposedMax;
}

@end

// ============================================================================
// Column Editor Window Controller (Edit -> Column Editor... ⌥⌘C)
// ============================================================================

@interface NppColumnEditorWindowController : NSWindowController
@property (nonatomic, weak) NotepadPlusAppController* appController;
@property (nonatomic, strong) NSButton* radioText;
@property (nonatomic, strong) NSButton* radioNumber;
@property (nonatomic, strong) NSTextField* textToInsertField;
@property (nonatomic, strong) NSTextField* startNumField;
@property (nonatomic, strong) NSTextField* increaseNumField;
@property (nonatomic, strong) NSTextField* repeatNumField;
@property (nonatomic, strong) NSPopUpButton* formatPopUp;
@property (nonatomic, strong) NSPopUpButton* leadingPopUp;
- (void) showColumnEditor;
@end

// ============================================================================
// Full Master-Detail Preferences Window Controller
// ============================================================================

@interface NppPreferenceWindowController : NSWindowController <NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, weak) NotepadPlusAppController* appController;
@property (nonatomic, strong) NSTableView* categoryTable;
@property (nonatomic, strong) NSView* detailContainer;
@property (nonatomic, strong) NSArray<NSString *>* categories;
@property (nonatomic, assign) NSInteger selectedCategory;
@end

// ============================================================================
// Application Controller Interface
// ============================================================================

@interface NotepadPlusAppController : NSObject <NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, ScintillaNotificationProtocol, NppTabBarDelegate, NppFindReplaceDelegate, NppDragDropDelegate, NppFileExplorerDelegate, NppTerminalPanelDelegate, NppSecondaryPreviewDelegate>
@property (nonatomic, strong) NSWindow* window;
@property (nonatomic, strong) NppMainContentView* rootContentView;
@property (nonatomic, strong) ScintillaView* editor;
@property (nonatomic, strong) NppTabBarView* tabBar;
@property (nonatomic, strong) NppStatusBarView* statusBar;
@property (nonatomic, strong) NppFindReplaceWindowController* findReplaceWindowController;
@property (nonatomic, strong) NppFileExplorerView* primarySidePanel;
@property (nonatomic, strong) NppTerminalPanelView* bottomPanel;
@property (nonatomic, strong) NppSecondaryPreviewView* secondarySidePanel;
@property (nonatomic, strong) NppPreferenceWindowController* prefWindowController;
@property (nonatomic, strong) NppColumnEditorWindowController* columnEditorWindowController;

// Settings Properties
@property (nonatomic, assign) BOOL isDarkMode;
@property (nonatomic, strong) NSString* currentThemeName;
@property (nonatomic, strong) NSString* currentFontName;
@property (nonatomic, assign) int currentFontSize;
@property (nonatomic, assign) int currentTabWidth;
@property (nonatomic, assign) BOOL useSpacesForTabs;
@property (nonatomic, assign) BOOL showLineNumbers;
@property (nonatomic, assign) BOOL showBookmarksMargin;
@property (nonatomic, assign) BOOL showFoldingMargin;
@property (nonatomic, assign) int defaultNewEOL;
@property (nonatomic, assign) int defaultNewEncoding;
@property (nonatomic, strong) NSString* defaultNewLanguage;
@property (nonatomic, assign) BOOL showIndentGuides;
@property (nonatomic, assign) BOOL showWhiteSpace;
@property (nonatomic, assign) BOOL showEOL;
@property (nonatomic, assign) BOOL wordWrap;
@property (nonatomic, assign) BOOL matchBraces;
@property (nonatomic, assign) BOOL highlightCurrentLine;
@property (nonatomic, assign) BOOL smartHighlighting;
@property (nonatomic, assign) BOOL autoClosePairs;
@property (nonatomic, assign) BOOL autoWordCompletion;
@property (nonatomic, assign) BOOL showColumnGuide;
@property (nonatomic, assign) int columnGuidePos;
@property (nonatomic, assign) BOOL rememberSession;
@property (nonatomic, assign) BOOL freeTypingMode;
@property (nonatomic, assign) NSRect lastSavedWindowFrame;
@property (nonatomic, assign) BOOL isSavingSession;
@property (nonatomic, assign) BOOL isAppTerminating;
@property (nonatomic, strong) NSString* currentLocalizationFile;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *>* localizedDict;
- (NSString *) localizedString: (NSString *) key defaultText: (NSString *) defaultText;
- (void) applyLocalization: (NSString *) xmlFileName;

- (NSString *) getDirectoryForActiveTab;
- (void) saveDocumentAtIndex: (NSInteger) index promptIfUntitled: (BOOL) promptIfUntitled;
- (void) saveSessionState;
- (void) applyAllSettings;
- (void) togglePrimarySidePanel: (id) sender;
- (void) toggleColumnMode: (id) sender;
- (void) toggleBottomPanel: (id) sender;
- (void) toggleSecondarySidePanel: (id) sender;
- (void) openMacTerminalAtDirectory: (NSString *) dirPath;
- (void) showColumnEditorDialog: (id) sender;
- (void) applyColumnEditIsText: (BOOL) isText
                         text: (NSString *) insertText
                      initNum: (long long) initNum
                  increaseNum: (long long) increaseNum
                       repeat: (long long) repeatCount
                    formatIdx: (NSInteger) formatIdx
                   leadingIdx: (NSInteger) leadingIdx;
@end

// ============================================================================
// Implementation of NppFindReplaceWindowController
// ============================================================================

@implementation NppFindReplaceWindowController

- (instancetype) initWithAppController: (NotepadPlusAppController *) appCtrl {
    NSRect frame = NSMakeRect(300, 350, 500, 160);
    NSPanel* panel = [[NSPanel alloc] initWithContentRect: frame
                                                 styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                                   backing: NSBackingStoreBuffered
                                                     defer: NO];
    panel.title = @"Find / Replace";
    panel.level = NSFloatingWindowLevel;
    panel.hidesOnDeactivate = NO;

    self = [super initWithWindow: panel];
    if (self) {
        _appController = appCtrl;
        panel.delegate = self;
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    auto L = [&](NSString* key, NSString* defText) -> NSString* {
        return [_appController localizedString: key defaultText: defText];
    };

    self.window.title = [NSString stringWithFormat: @"%@", L(@"cmd_43001", @"Find / Replace")];

    NSView* content = self.window.contentView;
    for (NSView* v in [content.subviews copy]) [v removeFromSuperview];

    CGFloat y = 120.0;

    NSTextField* findLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(12, y + 2, 55, 18)];
    findLabel.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_Find_1701", @"Find")];
    findLabel.bezeled = NO; findLabel.drawsBackground = NO; findLabel.editable = NO;
    findLabel.font = [NSFont systemFontOfSize: 12];
    [content addSubview: findLabel];

    _findField = [[NSTextField alloc] initWithFrame: NSMakeRect(72, y, 275, 22)];
    _findField.target = self;
    _findField.action = @selector(onFindNext:);
    _findField.delegate = self;
    [content addSubview: _findField];

    NSButton* btnFindNext = [[NSButton alloc] initWithFrame: NSMakeRect(355, y - 2, 130, 24)];
    btnFindNext.title = L(@"dlg_Find_1701", @"Find Next");
    btnFindNext.bezelStyle = NSBezelStyleRounded;
    btnFindNext.target = self;
    btnFindNext.action = @selector(onFindNext:);
    [content addSubview: btnFindNext];

    y = 85.0;

    NSTextField* repLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(12, y + 2, 55, 18)];
    repLabel.stringValue = [NSString stringWithFormat: @"%@:", L(@"cmd_43003", @"Replace")];
    repLabel.bezeled = NO; repLabel.drawsBackground = NO; repLabel.editable = NO;
    repLabel.font = [NSFont systemFontOfSize: 12];
    [content addSubview: repLabel];

    _replaceField = [[NSTextField alloc] initWithFrame: NSMakeRect(72, y, 275, 22)];
    _replaceField.target = self;
    _replaceField.action = @selector(onReplace:);
    _replaceField.delegate = self;
    [content addSubview: _replaceField];

    NSButton* btnFindPrev = [[NSButton alloc] initWithFrame: NSMakeRect(355, y - 2, 130, 24)];
    btnFindPrev.title = L(@"search-jumpUp", @"Find Prev");
    btnFindPrev.bezelStyle = NSBezelStyleRounded;
    btnFindPrev.target = self;
    btnFindPrev.action = @selector(onFindPrev:);
    [content addSubview: btnFindPrev];

    y = 52.0;

    _matchCaseCheck = [[NSButton alloc] initWithFrame: NSMakeRect(72, y, 95, 20)];
    _matchCaseCheck.buttonType = NSButtonTypeSwitch;
    _matchCaseCheck.title = L(@"dlg_Find_1703", @"Match case");
    [content addSubview: _matchCaseCheck];

    _wholeWordCheck = [[NSButton alloc] initWithFrame: NSMakeRect(172, y, 95, 20)];
    _wholeWordCheck.buttonType = NSButtonTypeSwitch;
    _wholeWordCheck.title = L(@"dlg_Find_1702", @"Whole word");
    [content addSubview: _wholeWordCheck];

    _regexCheck = [[NSButton alloc] initWithFrame: NSMakeRect(272, y, 75, 20)];
    _regexCheck.buttonType = NSButtonTypeSwitch;
    _regexCheck.title = L(@"dlg_Find_1708", @"Regex");
    [content addSubview: _regexCheck];

    NSButton* btnReplace = [[NSButton alloc] initWithFrame: NSMakeRect(355, y - 2, 130, 24)];
    btnReplace.title = L(@"cmd_43003", @"Replace");
    btnReplace.bezelStyle = NSBezelStyleRounded;
    btnReplace.target = self;
    btnReplace.action = @selector(onReplace:);
    [content addSubview: btnReplace];

    y = 15.0;

    NSButton* btnReplaceAll = [[NSButton alloc] initWithFrame: NSMakeRect(215, y - 2, 132, 24)];
    btnReplaceAll.title = L(@"dlg_Find_1709", @"Replace All");
    btnReplaceAll.bezelStyle = NSBezelStyleRounded;
    btnReplaceAll.target = self;
    btnReplaceAll.action = @selector(onReplaceAll:);
    [content addSubview: btnReplaceAll];

    NSButton* btnMarkAll = [[NSButton alloc] initWithFrame: NSMakeRect(355, y - 2, 130, 24)];
    btnMarkAll.title = L(@"search-markAll", @"Mark All");
    btnMarkAll.bezelStyle = NSBezelStyleRounded;
    btnMarkAll.target = self;
    btnMarkAll.action = @selector(onMarkAll:);
    [content addSubview: btnMarkAll];
}

- (void) populateSelectionIfAny {
    ScintillaView* editor = _appController.editor;
    if (editor) {
        sptr_t selStart = [editor message: SCI_GETSELECTIONSTART];
        sptr_t selEnd = [editor message: SCI_GETSELECTIONEND];
        if (selEnd > selStart && selEnd - selStart < 512) {
            std::vector<char> buf(selEnd - selStart + 1, 0);
            [editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
            NSString* selText = [NSString stringWithUTF8String: buf.data()];
            if (selText.length > 0) _findField.stringValue = selText;
        }
    }
}

- (void) showFindWindow {
    [self buildUI];
    [self populateSelectionIfAny];
    [self.window makeKeyAndOrderFront: nil];
    [self.window makeFirstResponder: _findField];
    [_findField selectText: self];
}

- (void) showReplaceWindow {
    [self buildUI];
    [self populateSelectionIfAny];
    [self.window makeKeyAndOrderFront: nil];
    [self.window makeFirstResponder: _replaceField];
    [_replaceField selectText: self];
}

- (void) setSearchPattern: (NSString *) pattern {
    if (pattern && pattern.length > 0) {
        _findField.stringValue = pattern;
    }
    [self.window makeKeyAndOrderFront: nil];
    [self.window makeFirstResponder: _findField];
    [_findField selectText: self];
}

- (void) updateAppearance: (BOOL) isDark {
    if (self.window) {
        self.window.appearance = isDark ? [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]
                                        : [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    }
}

- (void) onFindNext: (id) sender {
    if (_findField.stringValue.length == 0) return;
    [_appController findNext: _findField.stringValue
                   matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
                   wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                     isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onFindPrev: (id) sender {
    if (_findField.stringValue.length == 0) return;
    [_appController findPrev: _findField.stringValue
                   matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
                   wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                     isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onReplace: (id) sender {
    if (_findField.stringValue.length == 0) return;
    [_appController replaceOne: _findField.stringValue
                      withText: _replaceField.stringValue
                     matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
                     wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                       isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onReplaceAll: (id) sender {
    if (_findField.stringValue.length == 0) return;
    [_appController replaceAll: _findField.stringValue
                      withText: _replaceField.stringValue
                     matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
                     wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                       isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onMarkAll: (id) sender {
    if (_findField.stringValue.length == 0) return;
    [_appController markAll: _findField.stringValue
                  matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
                  wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                    isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (BOOL) control: (NSControl *) control textView: (NSTextView *) textView doCommandBySelector: (SEL) commandSelector {
    if (commandSelector == @selector(cancelOperation:)) {
        [self.window performClose: nil];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:)) {
        NSEventModifierFlags flags = [NSApp currentEvent].modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        if (control == _findField) {
            if (flags & NSEventModifierFlagShift) {
                [self onFindPrev: nil];
            } else {
                [self onFindNext: nil];
            }
            return YES;
        } else if (control == _replaceField) {
            [self onReplace: nil];
            return YES;
        }
    }
    return NO;
}

- (void) windowWillClose: (NSNotification *) notification {
    if (_appController && _appController.window && _appController.editor) {
        [_appController.window makeFirstResponder: _appController.editor];
    }
}

@end

// ============================================================================
// Implementation of NppColumnEditorWindowController
// ============================================================================

@implementation NppColumnEditorWindowController

- (instancetype) initWithAppController: (NotepadPlusAppController *) appCtrl {
    NSRect frame = NSMakeRect(200, 200, 440, 310);
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSWindow* win = [[NSWindow alloc] initWithContentRect: frame styleMask: mask backing: NSBackingStoreBuffered defer: NO];
    win.title = @"Column Editor (⌥⌘C)";

    self = [super initWithWindow: win];
    if (self) {
        _appController = appCtrl;
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    auto L = [&](NSString* key, NSString* defText) -> NSString* {
        return [_appController localizedString: key defaultText: defText];
    };
    self.window.title = [NSString stringWithFormat: @"%@ (⌥⌘C)", L(@"dlg_title_ColumnEditor", @"Column Editor")];

    NSView* content = self.window.contentView;
    for (NSView* v in [content.subviews copy]) [v removeFromSuperview];

    // Mode 1: Text to Insert Box
    NSBox* boxText = [[NSBox alloc] initWithFrame: NSMakeRect(16, 180, 408, 85)];
    boxText.title = L(@"dlg_ColumnEditor_2023", L(@"dlg_2023", @"Text to Insert"));
    [content addSubview: boxText];

    _radioText = [[NSButton alloc] initWithFrame: NSMakeRect(12, 40, 160, 20)];
    _radioText.buttonType = NSButtonTypeRadio;
    _radioText.title = [NSString stringWithFormat: @"%@:", L(@"dlg_ColumnEditor_2023", L(@"dlg_2023", @"Text to Insert"))];
    _radioText.state = NSControlStateValueOn;
    _radioText.target = self;
    _radioText.action = @selector(onRadioModeChanged:);
    [boxText.contentView addSubview: _radioText];

    _textToInsertField = [[NSTextField alloc] initWithFrame: NSMakeRect(160, 38, 220, 22)];
    _textToInsertField.placeholderString = @"prefix_ or text";
    [boxText.contentView addSubview: _textToInsertField];

    // Mode 2: Number to Insert Box
    NSBox* boxNum = [[NSBox alloc] initWithFrame: NSMakeRect(16, 50, 408, 125)];
    boxNum.title = L(@"dlg_ColumnEditor_2024", L(@"dlg_2024", @"Number to Insert"));
    [content addSubview: boxNum];

    _radioNumber = [[NSButton alloc] initWithFrame: NSMakeRect(12, 78, 160, 20)];
    _radioNumber.buttonType = NSButtonTypeRadio;
    _radioNumber.title = L(@"dlg_ColumnEditor_2024", L(@"dlg_2024", @"Number to Insert"));
    _radioNumber.state = NSControlStateValueOff;
    _radioNumber.target = self;
    _radioNumber.action = @selector(onRadioModeChanged:);
    [boxNum.contentView addSubview: _radioNumber];

    NSTextField* lblInit = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 50, 90, 18)];
    lblInit.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_ColumnEditor_2024", @"Initial number")];
    lblInit.bezeled = NO; lblInit.drawsBackground = NO; lblInit.editable = NO;
    lblInit.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblInit];

    _startNumField = [[NSTextField alloc] initWithFrame: NSMakeRect(115, 48, 75, 20)];
    _startNumField.stringValue = @"1";
    [boxNum.contentView addSubview: _startNumField];

    NSTextField* lblInc = [[NSTextField alloc] initWithFrame: NSMakeRect(200, 50, 85, 18)];
    lblInc.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_ColumnEditor_2025", @"Increase by")];
    lblInc.bezeled = NO; lblInc.drawsBackground = NO; lblInc.editable = NO;
    lblInc.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblInc];

    _increaseNumField = [[NSTextField alloc] initWithFrame: NSMakeRect(285, 48, 75, 20)];
    _increaseNumField.stringValue = @"1";
    [boxNum.contentView addSubview: _increaseNumField];

    NSTextField* lblRep = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 20, 90, 18)];
    lblRep.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_ColumnEditor_2026", @"Repeat")];
    lblRep.bezeled = NO; lblRep.drawsBackground = NO; lblRep.editable = NO;
    lblRep.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblRep];

    _repeatNumField = [[NSTextField alloc] initWithFrame: NSMakeRect(115, 18, 75, 20)];
    _repeatNumField.stringValue = @"1";
    [boxNum.contentView addSubview: _repeatNumField];

    NSTextField* lblFmt = [[NSTextField alloc] initWithFrame: NSMakeRect(200, 20, 50, 18)];
    lblFmt.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_ColumnEditor_2027", @"Format")];
    lblFmt.bezeled = NO; lblFmt.drawsBackground = NO; lblFmt.editable = NO;
    lblFmt.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblFmt];

    _formatPopUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(255, 16, 65, 22) pullsDown: NO];
    [_formatPopUp addItemsWithTitles: @[L(@"dlg_ColumnEditor_2029", @"Dec"), L(@"dlg_ColumnEditor_2030", @"Hex"), L(@"dlg_ColumnEditor_2031", @"Oct"), L(@"dlg_ColumnEditor_2032", @"Bin")]];
    [boxNum.contentView addSubview: _formatPopUp];

    _leadingPopUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(325, 16, 80, 22) pullsDown: NO];
    [_leadingPopUp addItemsWithTitles: @[L(@"dlg_ColumnEditor_2033", @"None"), L(@"dlg_ColumnEditor_2034", @"Zeros"), L(@"dlg_ColumnEditor_2035", @"Spaces")]];
    [boxNum.contentView addSubview: _leadingPopUp];

    // Buttons
    NSButton* btnOK = [[NSButton alloc] initWithFrame: NSMakeRect(230, 12, 90, 28)];
    btnOK.title = L(@"dlg_1", @"OK");
    btnOK.bezelStyle = NSBezelStyleRounded;
    btnOK.keyEquivalent = @"\r";
    btnOK.target = self;
    btnOK.action = @selector(onOK:);
    [content addSubview: btnOK];

    NSButton* btnCancel = [[NSButton alloc] initWithFrame: NSMakeRect(330, 12, 90, 28)];
    btnCancel.title = L(@"dlg_2", @"Cancel");
    btnCancel.bezelStyle = NSBezelStyleRounded;
    btnCancel.keyEquivalent = @"\e";
    btnCancel.target = self;
    btnCancel.action = @selector(onCancel:);
    [content addSubview: btnCancel];
}

- (void) onRadioModeChanged: (id) sender {
    if (sender == _radioText) {
        _radioText.state = NSControlStateValueOn;
        _radioNumber.state = NSControlStateValueOff;
        [_textToInsertField becomeFirstResponder];
    } else {
        _radioText.state = NSControlStateValueOff;
        _radioNumber.state = NSControlStateValueOn;
        [_startNumField becomeFirstResponder];
    }
}

- (void) showColumnEditor {
    [self buildUI];
    [self.window center];
    [self.window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    [_textToInsertField becomeFirstResponder];
}

- (void) onOK: (id) sender {
    BOOL isText = (_radioText.state == NSControlStateValueOn);
    NSString* textToInsert = _textToInsertField.stringValue ?: @"";
    long long initNum = [_startNumField.stringValue longLongValue];
    long long increaseNum = [_increaseNumField.stringValue longLongValue];
    long long repeatCount = [_repeatNumField.stringValue longLongValue];
    if (repeatCount <= 0) repeatCount = 1;
    NSInteger formatIdx = _formatPopUp.indexOfSelectedItem;
    NSInteger leadingIdx = _leadingPopUp.indexOfSelectedItem;

    [self.window close];

    [_appController applyColumnEditIsText: isText
                                     text: textToInsert
                                  initNum: initNum
                              increaseNum: increaseNum
                                   repeat: repeatCount
                                formatIdx: formatIdx
                               leadingIdx: leadingIdx];
}

- (void) onCancel: (id) sender {
    [self.window close];
}

@end

// ============================================================================
// Implementation of NppPreferenceWindowController
// ============================================================================

@implementation NppPreferenceWindowController

- (instancetype) initWithAppController: (NotepadPlusAppController *) appCtrl {
    NSRect frame = NSMakeRect(150, 150, 800, 520);
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
    NSWindow* win = [[NSWindow alloc] initWithContentRect: frame styleMask: mask backing: NSBackingStoreBuffered defer: NO];
    win.title = @"Notepad++ Preferences";
    win.minSize = NSMakeSize(720, 460);

    self = [super initWithWindow: win];
    if (self) {
        _appController = appCtrl;
        [self refreshCategoryTitles];
        _selectedCategory = 0;
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    NSView* content = self.window.contentView;
    NSRect b = content.bounds;

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(12, 50, 200, b.size.height - 62)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewHeightSizable;

    _categoryTable = [[NSTableView alloc] initWithFrame: scroll.bounds];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier: @"CatCol"];
    col.title = @"Categories";
    col.width = 180;
    [_categoryTable addTableColumn: col];
    _categoryTable.headerView = nil;
    _categoryTable.delegate = self;
    _categoryTable.dataSource = self;
    scroll.documentView = _categoryTable;
    [content addSubview: scroll];

    _detailContainer = [[NSView alloc] initWithFrame: NSMakeRect(224, 50, b.size.width - 236, b.size.height - 62)];
    _detailContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview: _detailContainer];

    NSButton* btnClose = [[NSButton alloc] initWithFrame: NSMakeRect(b.size.width - 100, 12, 85, 28)];
    btnClose.title = @"Close";
    btnClose.bezelStyle = NSBezelStyleRounded;
    btnClose.target = self;
    btnClose.action = @selector(onClose:);
    btnClose.autoresizingMask = NSViewMinXMargin;
    [content addSubview: btnClose];

    [_categoryTable selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
    [self loadCategoryPage: 0];
}

- (void) refreshCategoryTitles {
    auto L = [&](NSString* key, NSString* defText) -> NSString* {
        return [_appController localizedString: key defaultText: defText];
    };
    self.window.title = L(@"dlg_title_Preference", @"Preferences");
    _categories = @[
        [NSString stringWithFormat: @"⚙️ %@", L(@"dlg_title_Global", L(@"dlg_6002", @"General"))],
        [NSString stringWithFormat: @"✏️ %@", L(@"dlg_title_Scintillas", @"Editing")],
        [NSString stringWithFormat: @"📐 %@", L(@"dlg_title_MarginsBorderEdge", @"Margins & Border")],
        [NSString stringWithFormat: @"📄 %@", L(@"dlg_title_NewDoc", @"New Document")],
        [NSString stringWithFormat: @"⇥ %@", L(@"dlg_title_Language", @"Indentation & Tabs")],
        [NSString stringWithFormat: @"🎨 %@", L(@"dlg_title_DarkMode", @"Themes & Dark Mode")],
        [NSString stringWithFormat: @"💡 %@", L(@"dlg_title_Highlighting", @"Highlighting")],
        [NSString stringWithFormat: @"⚡ %@", L(@"dlg_title_AutoCompletion", @"Auto-Completion")],
        [NSString stringWithFormat: @"🔍 %@", L(@"dlg_title_Searching", @"Searching")],
        [NSString stringWithFormat: @"💾 %@", L(@"dlg_title_Backup", @"Backup & Session")],
        [NSString stringWithFormat: @"🚀 %@", L(@"dlg_title_Performance", @"Performance")]
    ];
    if (_categoryTable) [_categoryTable reloadData];
}

- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView { return _categories.count; }

- (NSView *) tableView: (NSTableView *) tableView viewForTableColumn: (NSTableColumn *) tableColumn row: (NSInteger) row {
    NSTextField* cell = [tableView makeViewWithIdentifier: @"CatCell" owner: self];
    if (!cell) {
        cell = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 180, 26)];
        cell.identifier = @"CatCell";
        cell.bezeled = NO; cell.drawsBackground = NO; cell.editable = NO;
        cell.font = [NSFont systemFontOfSize: 13 weight: NSFontWeightMedium];
    }
    cell.stringValue = _categories[row];
    return cell;
}

- (CGFloat) tableView: (NSTableView *) tableView heightOfRow: (NSInteger) row { return 28.0; }

- (void) tableViewSelectionDidChange: (NSNotification *) notification {
    NSInteger row = _categoryTable.selectedRow;
    if (row >= 0 && row < static_cast<NSInteger>(_categories.count)) {
        _selectedCategory = row;
        [self loadCategoryPage: row];
    }
}

- (void) showPreferencesAtCategory: (NSInteger) categoryIndex {
    [self refreshCategoryTitles];
    [self.window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    if (categoryIndex >= 0 && categoryIndex < static_cast<NSInteger>(_categories.count)) {
        [_categoryTable selectRowIndexes: [NSIndexSet indexSetWithIndex: categoryIndex] byExtendingSelection: NO];
        [self loadCategoryPage: categoryIndex];
    }
}

- (void) onClose: (id) sender { [self.window close]; }


- (NSArray<NSArray<NSString *> *> *) allLocalizationLanguages {
    static NSArray<NSArray<NSString *> *>* s_langs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_langs = @[
        @[@"한국어", @"korean.xml"],
        @[@"English", @"english.xml"],
        @[@"日本語 (Japanese)", @"japanese.xml"],
        @[@"简体中文 (Chinese Simplified)", @"chineseSimplified.xml"],
        @[@"繁體中文 (Chinese Traditional)", @"taiwaneseMandarin.xml"],
        @[@"Français (French)", @"french.xml"],
        @[@"Deutsch (German)", @"german.xml"],
        @[@"Español (Spanish)", @"spanish.xml"],
        @[@"Italiano (Italian)", @"italian.xml"],
        @[@"Русский (Russian)", @"russian.xml"],
        @[@"Português (Portuguese)", @"portuguese.xml"],
        @[@"Brazilian Portuguese", @"brazilian_portuguese.xml"],
        @[@"Nederlands (Dutch)", @"dutch.xml"],
        @[@"Polski (Polish)", @"polish.xml"],
        @[@"Türkçe (Turkish)", @"turkish.xml"],
        @[@"Tiếng Việt (Vietnamese)", @"vietnamese.xml"],
        @[@"---", @"---"],
        @[@"Afrikaans", @"afrikaans.xml"],
        @[@"Arabic", @"arabic.xml"],
        @[@"aragonese", @"aragonese.xml"],
        @[@"Aranese", @"aranese.xml"],
        @[@"Azərbaycan", @"azerbaijani.xml"],
        @[@"Bahasa Melayu", @"malay.xml"],
        @[@"Basque", @"basque.xml"],
        @[@"Bosanski", @"bosnian.xml"],
        @[@"Brezhoneg", @"breton.xml"],
        @[@"Castellano - Español", @"spanish_ar.xml"],
        @[@"Català", @"catalan.xml"],
        @[@"Corsu", @"corsican.xml"],
        @[@"Cymraeg", @"welsh.xml"],
        @[@"Dansk", @"danish.xml"],
        @[@"English", @"english_customizable.xml"],
        @[@"Esperanto", @"esperanto.xml"],
        @[@"Estonian", @"estonian.xml"],
        @[@"Estremeñu", @"extremaduran.xml"],
        @[@"Farsi", @"farsi.xml"],
        @[@"Finnish", @"finnish.xml"],
        @[@"Furlan", @"friulian.xml"],
        @[@"Gaeilge", @"irish.xml"],
        @[@"Galego", @"galician.xml"],
        @[@"Greek", @"greek.xml"],
        @[@"Hebrew", @"hebrew.xml"],
        @[@"Hrvatski", @"croatian.xml"],
        @[@"Indonesian", @"indonesian.xml"],
        @[@"Latviešu", @"latvian.xml"],
        @[@"Lithuanian", @"lithuanian.xml"],
        @[@"Lëtzebuergesch", @"luxembourgish.xml"],
        @[@"Macedonian", @"macedonian.xml"],
        @[@"Magyar", @"hungarian.xml"],
        @[@"Mongolian", @"mongolian.xml"],
        @[@"Nepali", @"nepali.xml"],
        @[@"Norsk", @"norwegian.xml"],
        @[@"Norsk-nynorsk", @"nynorsk.xml"],
        @[@"Occitan", @"occitan.xml"],
        @[@"Oʻzbekcha", @"uzbek.xml"],
        @[@"Pig Latin", @"piglatin.xml"],
        @[@"Romanian", @"romanian.xml"],
        @[@"Samogitian", @"samogitian.xml"],
        @[@"Sardu", @"sardinian.xml"],
        @[@"Shqip", @"albanian.xml"],
        @[@"Sinhala", @"sinhala.xml"],
        @[@"Slovenčina", @"slovak.xml"],
        @[@"Slovenščina", @"slovenian.xml"],
        @[@"Srpski", @"serbian.xml"],
        @[@"Svenska", @"swedish.xml"],
        @[@"Tagalog", @"tagalog.xml"],
        @[@"Taqbaylit", @"kabyle.xml"],
        @[@"thai", @"thai.xml"],
        @[@"Urdu", @"urdu.xml"],
        @[@"Uyghurche", @"uyghur.xml"],
        @[@"Vèneto", @"venetian.xml"],
        @[@"Zeneize", @"ligurian.xml"],
        @[@"zulu", @"zulu.xml"],
        @[@"Čeština", @"czech.xml"],
        @[@"Аԥсуа", @"abkhazian.xml"],
        @[@"Беларуская", @"belarusian.xml"],
        @[@"Български", @"bulgarian.xml"],
        @[@"Кыргызча", @"kyrgyz.xml"],
        @[@"Српски", @"serbianCyrillic.xml"],
        @[@"Татарча", @"tatar.xml"],
        @[@"Тоҷикӣ", @"tajikCyrillic.xml"],
        @[@"Українська", @"ukrainian.xml"],
        @[@"Ўзбекча", @"uzbekCyrillic.xml"],
        @[@"Қазақша", @"kazakh.xml"],
        @[@"كوردی", @"kurdish.xml"],
        @[@"मराठी", @"marathi.xml"],
        @[@"हिन्दी", @"hindi.xml"],
        @[@"বাঙালি", @"bengali.xml"],
        @[@"ਪੰਜਾਬੀ ਦੇ", @"punjabi.xml"],
        @[@"ગુજરાતી", @"gujarati.xml"],
        @[@"தமிழ்", @"tamil.xml"],
        @[@"తెలుగు", @"telugu.xml"],
        @[@"ಕನ್ನಡ", @"kannada.xml"],
        @[@"ქართული", @"georgian.xml"],
        @[@"香港廣東話", @"hongKongCantonese.xml"],
    ];

    });
    return s_langs;
}

- (void) populateLocalizationPopUp: (NSPopUpButton *) popUp {
    [popUp removeAllItems];
    NSArray* list = [self allLocalizationLanguages];
    NSString* currentFname = _appController.currentLocalizationFile ?: @"korean.xml";
    NSInteger selIdx = 0;
    NSInteger itemIndex = 0;
    for (NSInteger i = 0; i < (NSInteger)list.count; ++i) {
        NSString* title = list[i][0];
        NSString* fname = list[i][1];
        if ([title isEqualToString: @"---"]) {
            [[popUp menu] addItem: [NSMenuItem separatorItem]];
        } else {
            [popUp addItemWithTitle: title];
            NSMenuItem* it = [popUp itemAtIndex: itemIndex];
            it.representedObject = fname;
            if ([fname isEqualToString: currentFname] || [fname isEqualToString: [currentFname lastPathComponent]]) {
                selIdx = itemIndex;
            }
            itemIndex++;
        }
    }
    if (selIdx >= 0 && selIdx < popUp.numberOfItems) {
        [popUp selectItemAtIndex: selIdx];
    }
}

- (void) onLocalizationSelected: (id) sender {
    NSPopUpButton* pop = (NSPopUpButton *)sender;
    NSMenuItem* item = pop.selectedItem;
    if (item && item.representedObject) {
        NSString* fname = item.representedObject;
        [_appController applyLocalization: fname];
        [self refreshCategoryTitles];
        [self loadCategoryPage: 0];
    }
}

- (void) loadCategoryPage: (NSInteger) category {
    for (NSView* sub in [_detailContainer.subviews copy]) [sub removeFromSuperview];

    NSRect r = _detailContainer.bounds;
    NSView* page = [[NSView alloc] initWithFrame: r];
    page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_detailContainer addSubview: page];

    auto addTitle = [&](NSString* title) {
        NSTextField* lbl = [[NSTextField alloc] initWithFrame: NSMakeRect(10, r.size.height - 32, r.size.width - 20, 24)];
        lbl.stringValue = title;
        lbl.font = [NSFont systemFontOfSize: 15 weight: NSFontWeightBold];
        lbl.bezeled = NO; lbl.drawsBackground = NO; lbl.editable = NO;
        [page addSubview: lbl];

        NSBox* sep = [[NSBox alloc] initWithFrame: NSMakeRect(10, r.size.height - 38, r.size.width - 20, 1)];
        sep.boxType = NSBoxSeparator;
        [page addSubview: sep];
    };

    auto addBox = [&](NSString* title, CGFloat y, CGFloat h) -> NSBox* {
        NSBox* box = [[NSBox alloc] initWithFrame: NSMakeRect(10, y, r.size.width - 20, h)];
        box.title = title;
        box.autoresizingMask = NSViewWidthSizable;
        [page addSubview: box];
        return box;
    };

    auto addCheck = [&](NSBox* box, NSString* title, CGFloat y, BOOL state, SEL action) -> NSButton* {
        NSButton* btn = [[NSButton alloc] initWithFrame: NSMakeRect(15, y, box.contentView.bounds.size.width - 30, 20)];
        btn.buttonType = NSButtonTypeSwitch;
        btn.title = title;
        btn.state = state ? NSControlStateValueOn : NSControlStateValueOff;
        btn.target = self;
        btn.action = action;
        [box.contentView addSubview: btn];
        return btn;
    };

    auto L = [&](NSString* key, NSString* defText) -> NSString* {
        return [_appController localizedString: key defaultText: defText];
    };

    switch (category) {
        case 0: { // General
            addTitle(L(@"dlg_title_Global", L(@"dlg_6002", @"General")));

            // 1. Localization Box (94 Languages Dropdown)
            NSBox* boxLang = addBox(L(@"dlg_6123", @"Localization"), r.size.height - 135, 85);
            NSTextField* lblLang = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 36, 175, 18)];
            lblLang.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_6123", @"Display Language")];
            lblLang.bezeled = NO; lblLang.drawsBackground = NO; lblLang.editable = NO;
            lblLang.font = [NSFont systemFontOfSize: 12 weight: NSFontWeightMedium];
            [boxLang.contentView addSubview: lblLang];

            NSPopUpButton* popLang = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(195, 32, 320, 26) pullsDown: NO];
            [self populateLocalizationPopUp: popLang];
            popLang.target = self;
            popLang.action = @selector(onLocalizationSelected:);
            [boxLang.contentView addSubview: popLang];

            // 2. Tab Bar & Window Box
            NSBox* box1 = addBox(L(@"dlg_title_Tabbar", @"Tab Bar"), r.size.height - 265, 120);
            addCheck(box1, L(@"dlg_6112", @"Show close button on each tab"), 65, YES, nil);
            addCheck(box1, L(@"dlg_6113", @"Double click to close document"), 40, YES, nil);
            addCheck(box1, L(@"dlg_6115", @"Enable pin tab feature"), 15, YES, nil);

            // 3. Status Bar & Toolbar Box
            NSBox* box2 = addBox(L(@"dlg_6133", @"Status Bar"), r.size.height - 395, 120);
            addCheck(box2, L(@"dlg_6133", @"Show Status Bar"), 65, YES, nil);
            addCheck(box2, L(@"view", @"Show 3-Panel Layout Toolbar Icons"), 40, YES, nil);
            addCheck(box2, L(@"Window", @"Enable Unified macOS Window Titlebar"), 15, YES, nil);
            break;
        }
        case 1: { // Editing & Column Mode
            addTitle(L(@"dlg_title_Scintillas", @"Editing"));
            NSBox* box1 = addBox(L(@"dlg_6521", @"Multi-Editing"), r.size.height - 190, 140);
            addCheck(box1, L(@"dlg_6522", @"Enable Multi-Editing (⌘ + Click)"), 85, YES, nil);
            addCheck(box1, L(@"dlg_6523", @"Enable Column Selection to Multi-Editing (⌥ + Drag)"), 60, YES, nil);
            addCheck(box1, L(@"dlg_6245", @"Enable virtual space"), 35, YES, nil);
            addCheck(box1, L(@"edit-pasteSpecial", @"Multi-Paste into each selected column line"), 10, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6252", @"Non-Printing Characters"), r.size.height - 310, 100);
            addCheck(box2, L(@"dlg_6252", @"Show White Space characters"), 45, _appController.showWhiteSpace, @selector(onToggleWhiteSpace:));
            addCheck(box2, L(@"dlg_6247", @"Show End of Line (EOL) marks"), 15, _appController.showEOL, @selector(onToggleEOL:));
            break;
        }
        case 2: { // Margins
            addTitle(L(@"dlg_title_MarginsBorderEdge", @"Margins & Border"));
            NSBox* box1 = addBox(L(@"dlg_6201", @"Margins"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_6206", @"Display Line Numbers Margin"), 75, _appController.showLineNumbers, @selector(onToggleLineNumbers:));
            addCheck(box1, L(@"dlg_6207", @"Display Bookmark & Symbol Margin"), 50, _appController.showBookmarksMargin, nil);
            addCheck(box1, L(@"dlg_6205", @"Display Code Folding Margin"), 25, _appController.showFoldingMargin, nil);

            NSBox* box2 = addBox(L(@"dlg_6211", @"Vertical Column Guide"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6211", @"Show Vertical Column Guide (Edge Line)"), 45, _appController.showColumnGuide, @selector(onToggleColumnGuide:));

            NSTextField* lblEdge = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 15, 120, 20)];
            lblEdge.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_6655", @"Column Position")];
            lblEdge.bezeled = NO; lblEdge.drawsBackground = NO; lblEdge.editable = NO;
            [box2.contentView addSubview: lblEdge];

            NSPopUpButton* popEdge = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(140, 13, 100, 24) pullsDown: NO];
            [popEdge addItemsWithTitles: @[@"80", @"100", @"120"]];
            [popEdge selectItemWithTitle: [NSString stringWithFormat: @"%d", _appController.columnGuidePos]];
            popEdge.target = self; popEdge.action = @selector(onSelectColumnPos:);
            [box2.contentView addSubview: popEdge];
            break;
        }
        case 3: { // New Document
            addTitle(L(@"dlg_title_NewDoc", @"New Document"));
            NSBox* box1 = addBox(L(@"dlg_6401", @"Format (Line ending)"), r.size.height - 160, 110);
            NSPopUpButton* popEOL = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popEOL addItemsWithTitles: @[L(@"dlg_6403", @"Unix (LF)"), L(@"dlg_6402", @"Windows (CRLF)"), L(@"dlg_6404", @"Macintosh (CR)")]];
            [popEOL selectItemAtIndex: _appController.defaultNewEOL == 2 ? 0 : (_appController.defaultNewEOL == 0 ? 1 : 2)];
            popEOL.target = self; popEOL.action = @selector(onSelectNewEOL:);
            [box1.contentView addSubview: popEOL];

            NSBox* box2 = addBox(L(@"dlg_6405", @"Encoding"), r.size.height - 290, 110);
            NSPopUpButton* popEnc = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popEnc addItemsWithTitles: @[L(@"dlg_6407", @"UTF-8"), L(@"dlg_6408", @"UTF-8 with BOM"), L(@"dlg_6410", @"UTF-16 LE"), L(@"dlg_6409", @"UTF-16 BE"), L(@"dlg_6406", @"ANSI"), @"EUC-KR", @"Shift-JIS"]];
            [popEnc selectItemAtIndex: _appController.defaultNewEncoding];
            popEnc.target = self; popEnc.action = @selector(onSelectNewEncoding:);
            [box2.contentView addSubview: popEnc];
            addCheck(box2, L(@"dlg_6420", @"Apply UTF-8 encoding to opened ANSI files"), 15, YES, nil);
            break;
        }
        case 4: { // Indentation
            addTitle(L(@"dlg_title_Language", @"Indentation & Tabs"));
            NSBox* box1 = addBox(L(@"dlg_6301", @"Tab Configuration"), r.size.height - 180, 130);
            NSTextField* lblTab = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 75, 120, 20)];
            lblTab.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_6303", @"Tab Size")];
            lblTab.bezeled = NO; lblTab.drawsBackground = NO; lblTab.editable = NO;
            [box1.contentView addSubview: lblTab];

            NSPopUpButton* popTab = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(140, 73, 100, 24) pullsDown: NO];
            [popTab addItemsWithTitles: @[@"2", @"4", @"8"]];
            [popTab selectItemWithTitle: [NSString stringWithFormat: @"%d", _appController.currentTabWidth]];
            popTab.target = self; popTab.action = @selector(onSelectTabWidth:);
            [box1.contentView addSubview: popTab];

            addCheck(box1, L(@"dlg_6302", @"Replace tabs by spaces"), 45, _appController.useSpacesForTabs, @selector(onToggleUseSpaces:));
            addCheck(box1, L(@"dlg_6512", @"Backspace unindents"), 15, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_7161", @"Indentation Guides"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_7161", @"Show Indentation Guides"), 45, _appController.showIndentGuides, @selector(onToggleIndentGuides:));
            addCheck(box2, L(@"edit-indent", @"Smart Auto-Indentation on Enter"), 15, YES, nil);
            break;
        }
        case 5: { // Themes
            addTitle(L(@"dlg_title_DarkMode", @"Themes & Dark Mode"));
            NSBox* box1 = addBox(L(@"dlg_7135", @"Color Theme"), r.size.height - 160, 110);
            NSPopUpButton* popTheme = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popTheme addItemsWithTitles: @[
                @"🌙 Notepad++ Dark",
                @"☀️ Default Light",
                @"🌌 Monokai Pro",
                @"🧛 Dracula",
                @"🌊 Solarized Dark",
                @"🏖️ Solarized Light",
                @"🌋 Obsidian"
            ]];
            [popTheme selectItemWithTitle: _appController.currentThemeName];
            popTheme.target = self; popTheme.action = @selector(onSelectTheme:);
            [box1.contentView addSubview: popTheme];

            NSBox* box2 = addBox(L(@"dlg_6215", @"Editor Font & Size"), r.size.height - 310, 130);
            NSTextField* lblFont = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 75, 100, 20)];
            lblFont.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_6215", @"Font Family")];
            lblFont.bezeled = NO; lblFont.drawsBackground = NO; lblFont.editable = NO;
            [box2.contentView addSubview: lblFont];

            NSPopUpButton* popFont = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(120, 73, 160, 24) pullsDown: NO];
            [popFont addItemsWithTitles: @[@"SF Mono", @"Menlo", @"Monaco", @"Courier New", @"Consolas"]];
            [popFont selectItemWithTitle: _appController.currentFontName];
            popFont.target = self; popFont.action = @selector(onSelectFont:);
            [box2.contentView addSubview: popFont];

            NSTextField* lblSize = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 35, 100, 20)];
            lblSize.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_6655", @"Font Size")];
            lblSize.bezeled = NO; lblSize.drawsBackground = NO; lblSize.editable = NO;
            [box2.contentView addSubview: lblSize];

            NSPopUpButton* popSize = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(120, 33, 100, 24) pullsDown: NO];
            [popSize addItemsWithTitles: @[@"10", @"11", @"12", @"13", @"14", @"15", @"16", @"18", @"20", @"24"]];
            [popSize selectItemWithTitle: [NSString stringWithFormat: @"%d", _appController.currentFontSize]];
            popSize.target = self; popSize.action = @selector(onSelectFontSize:);
            [box2.contentView addSubview: popSize];
            break;
        }
        case 6: { // Highlighting
            addTitle(L(@"dlg_title_Highlighting", @"Highlighting"));
            NSBox* box1 = addBox(L(@"dlg_6329", @"Brace Matching"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_7147", @"Highlight matching braces () [] {}"), 75, _appController.matchBraces, @selector(onToggleMatchBraces:));
            addCheck(box1, L(@"dlg_6327", @"Highlight matching HTML/XML tags"), 50, YES, nil);
            addCheck(box1, L(@"dlg_6653", @"Highlight current line background"), 25, _appController.highlightCurrentLine, @selector(onToggleHighlightLine:));

            NSBox* box2 = addBox(L(@"dlg_6333", @"Smart Highlighting"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6326", @"Enable Smart Highlighting"), 45, _appController.smartHighlighting, @selector(onToggleSmartHighlight:));
            addCheck(box2, L(@"dlg_6332", @"Match case for Smart Highlighting"), 15, YES, nil);
            break;
        }
        case 7: { // Auto-Completion
            addTitle(L(@"dlg_title_AutoCompletion", @"Auto-Completion"));
            NSBox* box1 = addBox(L(@"dlg_6851", @"Auto-Insert Matching Pairs"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_6860", @"Parentheses () and Brackets []"), 75, _appController.autoClosePairs, @selector(onToggleAutoPairs:));
            addCheck(box1, L(@"dlg_6863", @"Braces {}"), 50, _appController.autoClosePairs, nil);
            addCheck(box1, L(@"dlg_6866", @"Double Quotes \"\" and Single Quotes ''"), 25, _appController.autoClosePairs, nil);

            NSBox* box2 = addBox(L(@"dlg_6807", @"Auto-Completion"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6808", @"Enable auto-completion on each input"), 45, _appController.autoWordCompletion, @selector(onToggleWordCompletion:));
            addCheck(box2, L(@"dlg_6815", @"Function parameters hint on input"), 15, YES, nil);
            break;
        }
        case 8: { // Searching
            addTitle(L(@"dlg_title_Searching", @"Searching"));
            NSBox* box1 = addBox(L(@"dlg_6907", @"Find Dialog"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_6908", @"Fill Find Field with Selected Text"), 75, YES, nil);
            addCheck(box1, L(@"dlg_6909", @"Select Word Under Caret when Nothing Selected"), 50, YES, nil);
            addCheck(box1, L(@"dlg_6907", @"Fill Find in Files Directory Field Based On Active Document"), 25, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6904", @"Search Result Window"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6904", @"Show only one entry per found line if possible"), 45, YES, nil);
            addCheck(box2, L(@"search", @"Find in Files: Prefer on-disk file content"), 15, YES, nil);
            break;
        }
        case 9: { // Backup & Session
            addTitle(L(@"dlg_title_Backup", @"Backup & Session"));
            NSBox* box1 = addBox(L(@"dlg_6817", @"Session Snapshot & Backup"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_6818", @"Enable session snapshot and periodic backup"), 75, _appController.rememberSession, @selector(onToggleRememberSession:));
            addCheck(box1, L(@"dlg_6309", @"Remember current session for next launch"), 50, _appController.rememberSession, nil);
            addCheck(box1, L(@"dlg_6817", @"Remember inaccessible files from past session"), 25, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6801", @"Backup on Save"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6316", @"Simple backup (.bak file creation)"), 45, NO, nil);
            addCheck(box2, L(@"dlg_6317", @"Verbose backup with timestamp"), 15, NO, nil);
            break;
        }
        case 10: { // Performance
            addTitle(L(@"dlg_title_Performance", @"Performance"));
            NSBox* box1 = addBox(L(@"dlg_7141", @"Large File Restriction"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_7143", @"Enable Large File Restriction (Deactivate heavy lexers for >50MB)"), 75, YES, nil);
            addCheck(box1, L(@"dlg_7150", @"Deactivate Word Wrap globally for huge files"), 50, YES, nil);
            addCheck(box1, L(@"dlg_7152", @"Suppress warning when opening large files"), 25, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6363", @"Rendering & Hardware Acceleration"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6363", @"Direct2D / Metal Hardware Accelerated Text Rendering"), 45, YES, nil);
            addCheck(box2, L(@"dlg_6215", @"Subpixel Anti-Aliasing (Retina Font Smoothing)"), 15, YES, nil);
            break;
        }
        default: break;
    }
}

- (void) onToggleLineNumbers: (NSButton *) btn { _appController.showLineNumbers = (btn.state == NSControlStateValueOn); [_appController applyAllSettings]; }
- (void) onToggleColumnGuide: (NSButton *) btn { _appController.showColumnGuide = (btn.state == NSControlStateValueOn); [_appController applyAllSettings]; }
- (void) onSelectColumnPos: (NSPopUpButton *) pop { _appController.columnGuidePos = [[pop titleOfSelectedItem] intValue]; [_appController applyAllSettings]; }
- (void) onToggleWhiteSpace: (NSButton *) btn { _appController.showWhiteSpace = (btn.state == NSControlStateValueOn); [_appController applyAllSettings]; }
- (void) onToggleEOL: (NSButton *) btn { _appController.showEOL = (btn.state == NSControlStateValueOn); [_appController applyAllSettings]; }
- (void) onSelectNewEOL: (NSPopUpButton *) pop { NSInteger idx = [pop indexOfSelectedItem]; _appController.defaultNewEOL = (idx == 0) ? 2 : (idx == 1 ? 0 : 1); }
- (void) onSelectNewEncoding: (NSPopUpButton *) pop { _appController.defaultNewEncoding = static_cast<int>([pop indexOfSelectedItem]); }
- (void) onSelectTabWidth: (NSPopUpButton *) pop { _appController.currentTabWidth = [[pop titleOfSelectedItem] intValue]; [_appController applyAllSettings]; }
- (void) onToggleUseSpaces: (NSButton *) btn { _appController.useSpacesForTabs = (btn.state == NSControlStateValueOn); [_appController applyAllSettings]; }
- (void) onToggleIndentGuides: (NSButton *) btn { _appController.showIndentGuides = (btn.state == NSControlStateValueOn); [_appController applyAllSettings]; }
- (void) onSelectTheme: (NSPopUpButton *) pop {
    _appController.currentThemeName = [pop titleOfSelectedItem];
    _appController.isDarkMode = ![_appController.currentThemeName containsString: @"Light"];
    [_appController applyAllSettings];
}
- (void) onSelectFont: (NSPopUpButton *) pop { _appController.currentFontName = [pop titleOfSelectedItem]; [_appController applyAllSettings]; }
- (void) onSelectFontSize: (NSPopUpButton *) pop { _appController.currentFontSize = [[pop titleOfSelectedItem] intValue]; [_appController applyAllSettings]; }
- (void) onToggleMatchBraces: (NSButton *) btn { _appController.matchBraces = (btn.state == NSControlStateValueOn); }
- (void) onToggleHighlightLine: (NSButton *) btn { _appController.highlightCurrentLine = (btn.state == NSControlStateValueOn); [_appController applyAllSettings]; }
- (void) onToggleSmartHighlight: (NSButton *) btn { _appController.smartHighlighting = (btn.state == NSControlStateValueOn); }
- (void) onToggleAutoPairs: (NSButton *) btn { _appController.autoClosePairs = (btn.state == NSControlStateValueOn); }
- (void) onToggleWordCompletion: (NSButton *) btn { _appController.autoWordCompletion = (btn.state == NSControlStateValueOn); }
- (void) onToggleRememberSession: (NSButton *) btn { _appController.rememberSession = (btn.state == NSControlStateValueOn); }

@end

// ============================================================================
// Application Controller Implementation
// ============================================================================

@implementation NotepadPlusAppController {
    std::vector<NppDocument> mDocuments;
    NSInteger mActiveIndex;
    int mUntitledCounter;
    BOOL mIsRecordingMacro;
    std::vector<MacroStep> mRecordedMacro;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        mActiveIndex = 0;
        mUntitledCounter = 1;
        mIsRecordingMacro = NO;

        _isDarkMode = NO;
        _currentThemeName = @"🌙 Notepad++ Dark (Default Dark)";
        _currentFontName = @"SF Mono";
        _currentFontSize = 13;
        _currentTabWidth = 4;
        _useSpacesForTabs = YES;
        _showLineNumbers = YES;
        _showBookmarksMargin = YES;
        _showFoldingMargin = YES;
        _defaultNewEOL = 2;
        _defaultNewEncoding = 0;
        _defaultNewLanguage = @"text";
        _showIndentGuides = YES;
        _showWhiteSpace = NO;
        _showEOL = NO;
        _wordWrap = NO;
        _matchBraces = YES;
        _highlightCurrentLine = YES;
        _smartHighlighting = YES;
        _autoClosePairs = YES;
        _autoWordCompletion = YES;
        _showColumnGuide = NO;
        _columnGuidePos = 80;
        _rememberSession = YES;
        _freeTypingMode = NO;
    }
    return self;
}

- (void) applicationWillFinishLaunching: (NSNotification *) notification {
    [self loadAndSetAppIcon];
    [self createMainMenu];
}


// ============================================================================
// Session Persistence & Help Documentation
// ============================================================================

- (NSString *) sessionFilePath {
    NSString* appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString* nppDir = [appSupport stringByAppendingPathComponent: @"Notepad++"];
    [[NSFileManager defaultManager] createDirectoryAtPath: nppDir withIntermediateDirectories: YES attributes: nil error: nil];
    return [nppDir stringByAppendingPathComponent: @"session.json"];
}

- (void) saveSessionState {
    if (mDocuments.empty()) return;
    if (_isSavingSession) return;
    _isSavingSession = YES;

    @try {
        // Safely update lastSavedWindowFrame if window is valid
        if (_window && !_isAppTerminating) {
            NSRect curF = _window.frame;
            if (curF.size.width >= 400 && curF.size.height >= 300) {
                _lastSavedWindowFrame = curF;
            }
        }

        // Save current active document cursor position & buffer
        if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size()) && _editor) {
            mDocuments[mActiveIndex].cursorPosition = static_cast<int>([_editor message: SCI_GETCURRENTPOS]);
        }

        sptr_t originalDocPointer = _editor ? [_editor message: SCI_GETDOCPOINTER wParam: 0 lParam: 0] : 0;

        NSMutableArray* fileList = [NSMutableArray array];
        for (size_t i = 0; i < mDocuments.size(); ++i) {
            const auto& doc = mDocuments[i];
            NSString* title = [NSString stringWithUTF8String: wstring_to_utf8(doc.title).c_str()];
            NSString* path = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
            NSString* lex = [NSString stringWithUTF8String: doc.lexerName.c_str()];

            // Retrieve buffer text without disturbing editor's active document pointer or caret
            NSString* content = @"";
            if (static_cast<NSInteger>(i) == mActiveIndex && _editor) {
                content = [_editor string] ?: @"";
                mDocuments[i].cachedContent = [content UTF8String];
            } else {
                content = [NSString stringWithUTF8String: doc.cachedContent.c_str()] ?: @"";
            }

            [fileList addObject: @{
                @"title": title ?: @"new 1",
                @"path": path ?: @"",
                @"isUntitled": @(doc.isUntitled),
                @"isModified": @(doc.isModified),
                @"lexer": lex ?: @"text",
                @"cursorPos": @(doc.cursorPosition),
                @"content": content ?: @""
            }];
        }

        BOOL primaryVisible = _rootContentView ? _rootContentView.isPrimarySidePanelVisible : NO;
        BOOL bottomVisible = _rootContentView ? _rootContentView.isBottomPanelVisible : NO;
        BOOL secondaryVisible = _rootContentView ? _rootContentView.isSecondarySidePanelVisible : NO;

        NSRect frameToSave = _lastSavedWindowFrame;
        if (frameToSave.size.width < 400 || frameToSave.size.height < 300) {
            frameToSave = NSMakeRect(80, 80, 1200, 800);
        }

        NSDictionary* sessionDict = @{
            @"openFiles": fileList,
            @"activeIndex": @(mActiveIndex >= 0 ? mActiveIndex : 0),
            @"untitledCounter": @(mUntitledCounter),
            @"isPrimarySidePanelVisible": @(primaryVisible),
            @"isBottomPanelVisible": @(bottomVisible),
            @"isSecondarySidePanelVisible": @(secondaryVisible),
            @"isDarkMode": @(_isDarkMode),
            @"themeName": _currentThemeName ?: @"",
            @"localizationFile": _currentLocalizationFile ?: @"korean.xml",
            @"freeTypingMode": @(_freeTypingMode),
            @"windowFrame": NSStringFromRect(frameToSave)
        };

        NSData* data = [NSJSONSerialization dataWithJSONObject: sessionDict options: NSJSONWritingPrettyPrinted error: nil];
        if (data) {
            [data writeToFile: [self sessionFilePath] atomically: YES];
        }
    }
    @catch (NSException* exception) {
        // Prevent any unexpected exceptions from bubbling to crash reporter
    }
    @finally {
        _isSavingSession = NO;
    }
}

- (void) restoreSessionState {
    NSString* path = [self sessionFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath: path]) return;

    NSData* data = [NSData dataWithContentsOfFile: path];
    if (!data) return;

    NSDictionary* dict = [NSJSONSerialization JSONObjectWithData: data options: 0 error: nil];
    if (![dict isKindOfClass: [NSDictionary class]]) return;

    // Restore Window Frame with visible screen bounds safety guard
    NSString* frameStr = dict[@"windowFrame"];
    if (frameStr && frameStr.length > 0) {
        NSRect savedFrame = NSRectFromString(frameStr);
        NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
        if (savedFrame.size.width >= 400 && savedFrame.size.height >= 300 &&
            NSIntersectsRect(savedFrame, screenFrame)) {
            savedFrame.origin.x = std::max(screenFrame.origin.x, std::min(savedFrame.origin.x, screenFrame.origin.x + screenFrame.size.width - savedFrame.size.width));
            savedFrame.origin.y = std::max(screenFrame.origin.y, std::min(savedFrame.origin.y, screenFrame.origin.y + screenFrame.size.height - savedFrame.size.height));
            savedFrame.size.width = std::min(savedFrame.size.width, screenFrame.size.width);
            savedFrame.size.height = std::min(savedFrame.size.height, screenFrame.size.height);
            [_window setFrame: savedFrame display: YES animate: NO];
        } else {
            [_window center];
        }
    } else {
        [_window center];
    }

    // Restore Panel Visibility
    if (dict[@"isPrimarySidePanelVisible"]) {
        _rootContentView.isPrimarySidePanelVisible = [dict[@"isPrimarySidePanelVisible"] boolValue];
    }
    if (dict[@"isBottomPanelVisible"]) {
        _rootContentView.isBottomPanelVisible = [dict[@"isBottomPanelVisible"] boolValue];
    }
    if (dict[@"isSecondarySidePanelVisible"]) {
        _rootContentView.isSecondarySidePanelVisible = [dict[@"isSecondarySidePanelVisible"] boolValue];
    }
    [_rootContentView updateSplitLayout];

    if (dict[@"untitledCounter"]) {
        mUntitledCounter = [dict[@"untitledCounter"] intValue];
    }
    if (dict[@"localizationFile"]) {
        _currentLocalizationFile = dict[@"localizationFile"];
    }
    if (dict[@"freeTypingMode"]) {
        _freeTypingMode = [dict[@"freeTypingMode"] boolValue];
    }

    // Restore Open Files & Unsaved Document Buffers
    NSArray* fileList = dict[@"openFiles"];
    if ([fileList isKindOfClass: [NSArray class]] && fileList.count > 0) {
        // Release any initial placeholder documents
        while (!mDocuments.empty()) {
            if (mDocuments[0].pDoc) {
                [_editor message: SCI_RELEASEDOCUMENT wParam: 0 lParam: reinterpret_cast<sptr_t>(mDocuments[0].pDoc)];
            }
            mDocuments.erase(mDocuments.begin());
        }
        mActiveIndex = -1;

        for (NSDictionary* fInfo in fileList) {
            NSString* p = fInfo[@"path"];
            NSString* title = fInfo[@"title"] ?: [p lastPathComponent] ?: @"new 1";
            BOOL isUnt = [fInfo[@"isUntitled"] boolValue];
            BOOL isMod = [fInfo[@"isModified"] boolValue];
            NSString* lex = fInfo[@"lexer"] ?: @"text";
            NSString* content = fInfo[@"content"] ?: @"";
            NSInteger pos = [fInfo[@"cursorPos"] integerValue];

            if (!isUnt && p && [[NSFileManager defaultManager] fileExistsAtPath: p]) {
                [self openFileAtPath: p];
                if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
                    NppDocument& doc = mDocuments[mActiveIndex];
                    if (content && content.length > 0 && isMod) {
                        [_editor setString: content];
                        doc.isModified = YES;
                    }
                    if (pos > 0) {
                        doc.cursorPosition = static_cast<int>(pos);
                        [_editor message: SCI_GOTOPOS wParam: pos lParam: 0];
                        [_editor message: SCI_SCROLLCARET];
                    }
                }
            } else {
                // Restore untitled document with its exact unsaved content
                [self newDocumentWithTitle: title];
                if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
                    NppDocument& doc = mDocuments[mActiveIndex];
                    doc.lexerName = [lex UTF8String];
                    doc.isModified = isMod || (content.length > 0);
                    if (content && content.length > 0) {
                        [_editor setString: content];
                        if (!isMod) {
                            [_editor message: SCI_SETSAVEPOINT];
                            doc.isModified = false;
                        }
                    }
                    if (pos > 0) {
                        doc.cursorPosition = static_cast<int>(pos);
                        [_editor message: SCI_GOTOPOS wParam: pos lParam: 0];
                        [_editor message: SCI_SCROLLCARET];
                    }
                }
            }
        }

        NSInteger targetIdx = [dict[@"activeIndex"] integerValue];
        if (targetIdx >= 0 && targetIdx < static_cast<NSInteger>(mDocuments.size())) {
            [self switchToDocumentAtIndex: targetIdx];
        } else if (!mDocuments.empty()) {
            [self switchToDocumentAtIndex: 0];
        }
    }
}

- (NSString *) generateLocalizedHelpGuideMarkdown {
    NSString* langFile = _currentLocalizationFile ?: @"korean.xml";
    NSString* langLower = [langFile lowercaseString];

    if ([langLower containsString: @"korean"]) {
        NSArray<NSString *>* kPaths = @[
            [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"HELP_GUIDE.md"],
            @"/Users/mac/Antigravity/notepadpp/PowerEditor/src/HELP_GUIDE.md",
            @"PowerEditor/src/HELP_GUIDE.md"
        ];
        for (NSString* p in kPaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath: p]) {
                NSString* s = [NSString stringWithContentsOfFile: p encoding: NSUTF8StringEncoding error: nil];
                if (s && s.length > 50) return s;
            }
        }
    } else if ([langLower containsString: @"english"]) {
        NSArray<NSString *>* ePaths = @[
            [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"HELP_GUIDE_en.md"],
            @"/Users/mac/Antigravity/notepadpp/PowerEditor/src/HELP_GUIDE_en.md",
            @"PowerEditor/src/HELP_GUIDE_en.md"
        ];
        for (NSString* p in ePaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath: p]) {
                NSString* s = [NSString stringWithContentsOfFile: p encoding: NSUTF8StringEncoding error: nil];
                if (s && s.length > 50) return s;
            }
        }
    }

    // Dynamic multi-lingual markdown generator for all 94 native languages!
    NSString* titleApp = @"Notepad++ for macOS";
    NSString* langDisplayName = [_localizedDict[@"lang_display_name"] ?: [langFile stringByDeletingPathExtension] capitalizedString];

    auto L = [&](NSString* key, NSString* def) -> NSString* {
        return [self localizedString: key defaultText: def];
    };

    NSString* mFile = L(@"file", @"File");
    NSString* mEdit = L(@"edit", @"Edit");
    NSString* mSearch = L(@"search", @"Search");
    NSString* mView = L(@"view", @"View");
    NSString* mEncoding = L(@"encoding", @"Encoding");
    NSString* mLanguage = L(@"language", @"Language");
    NSString* mSettings = L(@"settings", @"Settings");
    NSString* mTools = L(@"tools", @"Tools");
    NSString* mHelp = L(@"help", @"Help");

    NSString* cNew = L(@"cmd_41001", @"New");
    NSString* cOpen = L(@"cmd_41002", @"Open...");
    NSString* cSave = L(@"cmd_41006", @"Save");
    NSString* cSaveAll = L(@"cmd_41008", @"Save All");
    NSString* cClose = L(@"cmd_41003", @"Close");
    NSString* cCloseAll = L(@"cmd_41004", @"Close All");
    NSString* cUndo = L(@"cmd_42001", @"Undo");
    NSString* cRedo = L(@"cmd_42002", @"Redo");
    NSString* cCut = L(@"cmd_42003", @"Cut");
    NSString* cCopy = L(@"cmd_42004", @"Copy");
    NSString* cPaste = L(@"cmd_42005", @"Paste");
    NSString* cSelectAll = L(@"cmd_42006", @"Select All");
    NSString* cColEdit = L(@"cmd_42024", @"Column Editor...");
    NSString* cDupLine = L(@"cmd_42028", @"Duplicate Current Line");
    NSString* cComment = L(@"cmd_42022", @"Toggle Line Comment");
    NSString* cFind = L(@"cmd_43001", @"Find...");
    NSString* cFindNext = L(@"cmd_43003", @"Find Next");
    NSString* cFindPrev = L(@"cmd_43004", @"Find Previous");
    NSString* cReplace = L(@"cmd_43005", @"Replace...");
    NSString* cBookmark = L(@"cmd_43022", @"Toggle Bookmark");
    NSString* cNextBmk = L(@"cmd_43023", @"Next Bookmark");
    NSString* cPrevBmk = L(@"cmd_43024", @"Previous Bookmark");
    NSString* cClearBmk = L(@"cmd_43025", @"Clear All Bookmarks");
    NSString* cWordWrap = L(@"cmd_44022", @"Word wrap");
    NSString* cPref = L(@"cmd_48005", @"Preferences...");
    NSString* cStyle = L(@"cmd_48006", @"Style Configurator...");

    NSMutableString* md = [NSMutableString string];
    [md appendFormat: @"# 📘 %@ (%@)\n\n", titleApp, langDisplayName];
    [md appendString: @"[![Notepad++ macOS](https://img.shields.io/badge/Notepad%2B%2B-macOS%20Native-brightgreen.svg)](https://github.com/notepad-plus-plus/notepad-plus-plus)\n"];
    [md appendFormat: @"[![Language](https://img.shields.io/badge/Language-%@-orange.svg)](#)\n\n", [langDisplayName stringByReplacingOccurrencesOfString: @" " withString: @"%20"]];

    [md appendFormat: @"---\n\n## 🚀 %@ (Shortcuts Cheatsheet)\n\n", L(@"dlg_title_Shortcuts", @"Shortcuts Cheatsheet")];
    [md appendString: @"| Category | Feature | macOS Shortcut | Description |\n"];
    [md appendString: @"| :--- | :--- | :--- | :--- |\n"];
    [md appendFormat: @"| **%@** | %@ / %@ | `⌘N` / `⌘O` | %@ |\n", mFile, cNew, cOpen, cNew];
    [md appendFormat: @"| | %@ / %@ | `⌘S` / `⌥⌘S` | %@ |\n", cSave, cSaveAll, cSaveAll];
    [md appendFormat: @"| | %@ / %@ | `⌘W` / `⇧⌘W` | %@ |\n", cClose, cCloseAll, cCloseAll];
    [md appendFormat: @"| **%@** | %@ | `⌥` + Drag | Column selection mode |\n", mEdit, cColEdit];
    [md appendFormat: @"| | %@ | `⌥⌘C` | Multi-line sequence insertion |\n", cColEdit];
    [md appendFormat: @"| | %@ | `⌘D` | Duplicate line |\n", cDupLine];
    [md appendFormat: @"| | %@ | `⌘/` | Toggle line comment |\n", cComment];
    [md appendFormat: @"| **%@** | %@ / %@ | `⌘F` / `⌥⌘F` | Interactive find & replace |\n", mSearch, cFind, cReplace];
    [md appendFormat: @"| | %@ / %@ | `⌘G` / `⇧⌘G` | Navigate matching occurrences |\n", cFindNext, cFindPrev];
    [md appendFormat: @"| | %@ | `⌘F2` | Set / remove line bookmark |\n", cBookmark];
    [md appendFormat: @"| | %@ / %@ | `F2` / `⇧F2` | Jump between bookmarks |\n", cNextBmk, cPrevBmk];
    [md appendFormat: @"| | %@ | `⇧⌘F2` | Remove all bookmarks |\n", cClearBmk];
    [md appendFormat: @"| **%@** | Explorer / Terminal / Preview | `⌥⌘1` / `⌥⌘2` / `⌥⌘3` | 3 IDE split panels |\n", mView];
    [md appendFormat: @"| | %@ | `⌥⌘W` | Toggle visual word wrapping |\n", cWordWrap];
    [md appendFormat: @"| **%@** | %@ / %@ | `⌘,` | Master preferences & themes |\n\n", mSettings, cPref, cStyle];

    [md appendFormat: @"---\n\n## 📌 %@ (Menu Guide & Features)\n\n", L(@"dlg_title_MenuBar", @"Menu Guide")];
    [md appendFormat: @"### 1. 📁 %@ (%@)\n", mFile, L(@"file", @"File")];
    [md appendFormat: @"- **%@ (`⌘N`)**: %@\n", cNew, L(@"cmd_41001", @"Create a new document")];
    [md appendFormat: @"- **%@ (`⌘O`)**: %@\n", cOpen, L(@"cmd_41002", @"Open an existing document")];
    [md appendFormat: @"- **%@ (`⌘S`) / %@ (`⌥⌘S`)**: %@\n", cSave, cSaveAll, L(@"cmd_41006", @"Save modifications to disk")];
    [md appendFormat: @"- **%@ (`⌘W`)**: %@\n\n", cClose, L(@"cmd_41003", @"Close current active document")];

    [md appendFormat: @"### 2. ✏️ %@ (%@)\n", mEdit, L(@"edit", @"Edit")];
    [md appendFormat: @"- **%@ (`⌘Z`) / %@ (`⇧⌘Z`)**: %@\n", cUndo, cRedo, L(@"cmd_42001", @"Undo and redo text edits")];
    [md appendFormat: @"- **%@ (`⌥⌘C`)**: %@\n", cColEdit, L(@"cmd_42024", @"Batch insert numbers or strings across rectangular columns")];
    [md appendFormat: @"- **%@ (`⌘D`)**: %@\n", cDupLine, L(@"cmd_42028", @"Duplicate active line")];
    [md appendFormat: @"- **%@ (`⌘/`)**: %@\n\n", cComment, L(@"cmd_42022", @"Toggle line comment")];

    [md appendFormat: @"### 3. 🔍 %@ (%@)\n", mSearch, L(@"search", @"Search")];
    [md appendFormat: @"- **%@ (`⌘F`) / %@ (`⌥⌘F`)**: %@\n", cFind, cReplace, L(@"cmd_43001", @"Interactive search with regex, whole word, match case")];
    [md appendFormat: @"- **%@ (`⌘F2`) / %@ (`F2`)**: %@\n\n", cBookmark, cNextBmk, L(@"cmd_43022", @"Manage line bookmarks and rapid navigation")];

    [md appendFormat: @"### 4. 👁️ %@ (%@)\n", mView, L(@"view", @"View")];
    [md appendFormat: @"- **%@ (`⌥⌘W`)**: %@\n", cWordWrap, L(@"cmd_44022", @"Wrap long lines automatically")];
    [md appendString: @"- **Side & Bottom Panels**: Left Explorer (`⌥⌘1`), Bottom Terminal (`⌥⌘2`), Right WebKit Preview (`⌥⌘3`)\n\n"];

    [md appendFormat: @"### 5. 🌐 %@ & %@\n", mEncoding, mLanguage];
    [md appendString: @"- **Encoding**: UTF-8, UTF-8 BOM, UTF-16, ANSI, EUC-KR, Shift-JIS, Big5, GB2312, LF / CRLF / CR\n"];
    [md appendString: @"- **Language**: C/C++, Python, JavaScript, TypeScript, HTML, XML, JSON, Markdown, SQL, Rust, Go, Swift, Java\n\n"];

    [md appendFormat: @"### 6. ⚙️ %@ (%@)\n", mSettings, L(@"settings", @"Settings")];
    [md appendFormat: @"- **%@ (`⌘,`)**: %@\n", cPref, L(@"cmd_48005", @"Configure 94-language UI localization, tabs, font, themes, backups")];
    [md appendFormat: @"- **%@**: %@\n", cStyle, L(@"cmd_48006", @"Choose from 7 authentic dark & light syntax themes")];

    return md;
}

- (void) showHelpGuide: (id) sender {
    NSString* helpContent = [self generateLocalizedHelpGuideMarkdown];

    // Open Secondary Preview Side Bar
    _rootContentView.isSecondarySidePanelVisible = YES;
    [_rootContentView updateSplitLayout];

    // Render localized guide in the right panel
    NSString* helpDocName = [NSString stringWithFormat: @"HELP_GUIDE_%@.md", _currentLocalizationFile ?: @"korean.xml"];
    [_secondarySidePanel renderDocumentContent: helpContent fileName: helpDocName lexerName: @"markdown"];
}

- (void) applicationDidFinishLaunching: (NSNotification *) notification {
    // Ultra-Fast Balloon Tooltips across entire macOS UI (10ms delay)
    [[NSUserDefaults standardUserDefaults] registerDefaults: @{
        @"NSInitialToolTipDelay": @10,
        @"NSAutoToolTipDelay": @10
    }];
    [[NSUserDefaults standardUserDefaults] setInteger: 10 forKey: @"NSInitialToolTipDelay"];
    [[NSUserDefaults standardUserDefaults] setInteger: 10 forKey: @"NSAutoToolTipDelay"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self createMainWindow];
    [self setupToolbar];

    NSString* appearanceName = [[NSApp effectiveAppearance] name];
    _isDarkMode = [appearanceName containsString: @"Dark"];
    _currentThemeName = _isDarkMode ? @"🌙 Notepad++ Dark (Default Dark)" : @"☀️ Default Light (Classic)";
    if (!_currentLocalizationFile) _currentLocalizationFile = @"korean.xml";
    [self applyLocalization: _currentLocalizationFile];

    [self applyAllSettings];

    // Temporary self-test (NPP_COLUMN_SELFTEST=1): reproduce macOS IME call sequences
    // on a multi-caret column selection without requiring accessibility permissions.
    if ([[NSProcessInfo processInfo] environment][@"NPP_COLUMN_SELFTEST"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [_editor setString: @"aaa\nbbb\nccc\n"];
            // Three column carets after "a"/"b"/"c" of each line
            [_editor message: SCI_CLEARSELECTIONS wParam: 0 lParam: 0];
            [_editor message: SCI_SETSELECTION wParam: 1 lParam: 1];
            [_editor message: SCI_ADDSELECTION wParam: 5 lParam: 5];
            [_editor message: SCI_ADDSELECTION wParam: 9 lParam: 9];
            SCIContentView* content = [_editor content];
            FILE* out = fopen("/tmp/npp_column_selftest.log", "w");
            auto dump = [&](const char* stage) {
                sptr_t len = [_editor message: SCI_GETLENGTH wParam: 0 lParam: 0];
                std::vector<char> buf(static_cast<size_t>(len) + 1, '\0');
                [_editor message: SCI_GETTEXT wParam: len + 1 lParam: reinterpret_cast<sptr_t>(buf.data())];
                sptr_t n = [_editor message: SCI_GETSELECTIONS wParam: 0 lParam: 0];
                fprintf(out, "== %s == sels=%lld text=[%s]\n", stage,
                        (long long)n, buf.data());
                for (sptr_t r = 0; r < n; ++r) {
                    fprintf(out, "   sel%lld anchor=%lld caret=%lld\n", (long long)r,
                            (long long)[_editor message: SCI_GETSELECTIONNANCHOR wParam: r lParam: 0],
                            (long long)[_editor message: SCI_GETSELECTIONNCARET wParam: r lParam: 0]);
                }
                fflush(out);
            };
            // Korean composition sequence exactly as macOS delivers it
            [content setMarkedText: @"ㅆ" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
            dump("after jamo1 tentative");
            [content setMarkedText: @"쌰" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
            dump("after syllable compose");
            [content insertText: @"쌰 " replacementRange: NSMakeRange(NSNotFound, 0)];
            dump("after commit via insertText");
            // Next syllable: new composition after commit
            [content setMarkedText: @"ㄴ" selectedRange: NSMakeRange(0, 0) replacementRange: NSMakeRange(NSNotFound, 0)];
            dump("after next-jamo tentative");
            [content unmarkText];
            dump("after unmarkText");

            // --- Column Mode menu toggle verification ---
            [_editor message: SCI_CLEARSELECTIONS wParam: 0 lParam: 0];
            [_editor setString: @"aaa\nbbb\nccc\n"];
            [_editor message: SCI_SETSELECTION wParam: 10 lParam: 1]; // stream selection over 3 lines
            [self toggleColumnMode: nil];
            dump("menu toggle -> ON");
            fprintf(out, "   statusBar=[%s]\n", _statusBar.statusText.UTF8String ?: "");
            [self toggleColumnMode: nil];
            dump("menu toggle -> OFF");
            fclose(out);
        });
    }

    NSArray* args = [[NSProcessInfo processInfo] arguments];
    BOOL openedFromArgs = NO;
    for (NSUInteger i = 1; i < args.count; ++i) {
        NSString* arg = args[i];
        if (![arg hasPrefix: @"-"] && [[NSFileManager defaultManager] fileExistsAtPath: arg]) {
            [self openFileAtPath: arg];
            openedFromArgs = YES;
        }
    }

    if (!openedFromArgs) {
        [self restoreSessionState];
    }

    if (mDocuments.empty()) {
        [self newDocumentWithTitle: @"new 1"];
    }

    [_window makeKeyAndOrderFront: nil];
    [_window orderFrontRegardless];
    [_window setIsVisible: YES];
    [_window makeFirstResponder: _editor];
    [NSApp activateIgnoringOtherApps: YES];
}

- (BOOL) applicationShouldHandleReopen: (NSApplication *) sender hasVisibleWindows: (BOOL) flag {
    if (!flag || !_window.isVisible) {
        [_window makeKeyAndOrderFront: nil];
        [_window orderFrontRegardless];
        [_window setIsVisible: YES];
        [NSApp activateIgnoringOtherApps: YES];
    }
    return YES;
}

- (BOOL) applicationShouldOpenUntitledFile: (NSApplication *) sender {
    return YES;
}

- (void) windowWillClose: (NSNotification *) notification {
    [self saveSessionState];
}

- (void) windowDidResize: (NSNotification *) notification {
    if (_window && !_isAppTerminating) {
        _lastSavedWindowFrame = _window.frame;
    }
    [self saveSessionState];
}

- (void) windowDidMove: (NSNotification *) notification {
    if (_window && !_isAppTerminating) {
        _lastSavedWindowFrame = _window.frame;
    }
    [self saveSessionState];
}

- (void) applicationWillTerminate: (NSNotification *) notification {
    _isAppTerminating = YES;
    [self saveSessionState];
}

- (void) applicationDidResignActive: (NSNotification *) notification {
    [self saveSessionState];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *) sender { return YES; }

- (BOOL) application: (NSApplication *) sender openFile: (NSString *) filename {
    [self openFileAtPath: filename];
    return YES;
}

- (void) filesDropped: (NSArray<NSString *> *) filePaths {
    for (NSString* p in filePaths) [self openFileAtPath: p];
}

- (void) loadAndSetAppIcon {
    NSArray<NSString *>* iconCandidates = @[
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"AppIcon.icns"],
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"Configure.icns"],
        @"/Users/mac/Antigravity/notepadpp/PowerEditor/src/AppIcon.icns",
        @"/Users/mac/Downloads/Configure.icns"
    ];

    for (NSString* path in iconCandidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath: path]) {
            NSImage* icon = [[NSImage alloc] initWithContentsOfFile: path];
            if (icon) {
                [NSApp setApplicationIconImage: icon];
                break;
            }
        }
    }
}

// ============================================================================
// Main Window & Resizable Split View Setup
// ============================================================================

- (void) createMainWindow {
    NSRect frame = NSMakeRect(80, 80, 1200, 800);
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

    _window = [[NSWindow alloc] initWithContentRect: frame styleMask: mask backing: NSBackingStoreBuffered defer: NO];
    _window.title = @"Notepad++";
    _lastSavedWindowFrame = frame;
    _window.minSize = NSMakeSize(680, 440);
    _window.delegate = self;
    [_window center];

    if (@available(macOS 11.0, *)) {
        _window.toolbarStyle = NSWindowToolbarStyleUnified;
    }

    _rootContentView = [[NppMainContentView alloc] initWithFrame: [_window.contentView bounds]];
    _rootContentView.dragDelegate = self;
    _rootContentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _window.contentView = _rootContentView;

    // 1. Tab Bar
    _tabBar = [[NppTabBarView alloc] initWithFrame: NSMakeRect(0, 0, frame.size.width, 30)];
    _tabBar.delegate = self;
    [_rootContentView addSubview: _tabBar];
    _rootContentView.tabBar = _tabBar;

    // 2. Resizable Main Horizontal Split View
    NSSplitView* mainSplit = [[NSSplitView alloc] initWithFrame: NSMakeRect(0, 30, frame.size.width, frame.size.height - 54)];
    mainSplit.vertical = YES;
    mainSplit.dividerStyle = NSSplitViewDividerStyleThin;
    mainSplit.delegate = _rootContentView;
    mainSplit.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_rootContentView addSubview: mainSplit];
    _rootContentView.mainHorizontalSplit = mainSplit;

    // Subview 0: Left Finder Tree Panel (Default 240px)
    _primarySidePanel = [[NppFileExplorerView alloc] initWithFrame: NSMakeRect(0, 0, 240, mainSplit.bounds.size.height)];
    _primarySidePanel.delegate = self;
    _primarySidePanel.hidden = YES;
    [mainSplit addSubview: _primarySidePanel];
    _rootContentView.primarySidePanel = _primarySidePanel;

    // Subview 1: Center Vertical Split View (Editor Top + Terminal Bottom)
    NSSplitView* centerSplit = [[NSSplitView alloc] initWithFrame: NSMakeRect(0, 0, frame.size.width - 240, mainSplit.bounds.size.height)];
    centerSplit.vertical = NO;
    centerSplit.dividerStyle = NSSplitViewDividerStyleThin;
    centerSplit.delegate = _rootContentView;
    centerSplit.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [mainSplit addSubview: centerSplit];
    _rootContentView.centerVerticalSplit = centerSplit;

    // Editor View
    _editor = [[ScintillaView alloc] initWithFrame: NSMakeRect(0, 0, centerSplit.bounds.size.width, centerSplit.bounds.size.height - 180)];
    _editor.delegate = self;
    [centerSplit addSubview: _editor];
    _rootContentView.editor = _editor;

    // Embedded Terminal Bottom Panel
    _bottomPanel = [[NppTerminalPanelView alloc] initWithFrame: NSMakeRect(0, 0, centerSplit.bounds.size.width, 180)];
    _bottomPanel.delegate = self;
    _bottomPanel.hidden = YES;
    [centerSplit addSubview: _bottomPanel];
    _rootContentView.bottomPanel = _bottomPanel;

    // Subview 2: Right Secondary Preview Panel (Default 340px)
    _secondarySidePanel = [[NppSecondaryPreviewView alloc] initWithFrame: NSMakeRect(0, 0, 340, mainSplit.bounds.size.height)];
    _secondarySidePanel.delegate = self;
    _secondarySidePanel.hidden = YES;
    [mainSplit addSubview: _secondarySidePanel];
    _rootContentView.secondarySidePanel = _secondarySidePanel;

    // 3. Find & Replace Window
    _findReplaceWindowController = [[NppFindReplaceWindowController alloc] initWithAppController: self];

    // 4. Status Bar
    _statusBar = [[NppStatusBarView alloc] initWithFrame: NSMakeRect(0, frame.size.height - 24, frame.size.width, 24)];
    [_rootContentView addSubview: _statusBar];
    _rootContentView.statusBar = _statusBar;

    // Preference & Column Editor Windows
    _prefWindowController = [[NppPreferenceWindowController alloc] initWithAppController: self];
    _columnEditorWindowController = [[NppColumnEditorWindowController alloc] initWithAppController: self];

    [self setupScintillaDefaults];
    [_rootContentView updateSplitLayout];
}

// ============================================================================
// Top Toolbar with VS Code Layout Buttons
// ============================================================================

static NSString* const kToolbarNew              = @"kToolbarNew";
static NSString* const kToolbarOpen             = @"kToolbarOpen";
static NSString* const kToolbarSave             = @"kToolbarSave";
static NSString* const kToolbarSaveAll          = @"kToolbarSaveAll";
static NSString* const kToolbarClose            = @"kToolbarClose";
static NSString* const kToolbarCut              = @"kToolbarCut";
static NSString* const kToolbarCopy             = @"kToolbarCopy";
static NSString* const kToolbarPaste            = @"kToolbarPaste";
static NSString* const kToolbarUndo             = @"kToolbarUndo";
static NSString* const kToolbarRedo             = @"kToolbarRedo";
static NSString* const kToolbarFind             = @"kToolbarFind";
static NSString* const kToolbarReplace          = @"kToolbarReplace";
static NSString* const kToolbarColumnEditor     = @"kToolbarColumnEditor";
static NSString* const kToolbarWordWrap         = @"kToolbarWordWrap";
static NSString* const kToolbarAllChars         = @"kToolbarAllChars";
static NSString* const kToolbarMacroRec         = @"kToolbarMacroRec";
static NSString* const kToolbarMacroStop        = @"kToolbarMacroStop";
static NSString* const kToolbarMacroPlay        = @"kToolbarMacroPlay";
static NSString* const kToolbarSummary          = @"kToolbarSummary";
static NSString* const kToolbarTogglePrimary    = @"kToolbarTogglePrimary";   // Left Finder Panel
static NSString* const kToolbarToggleBottom     = @"kToolbarToggleBottom";    // Bottom Embedded Terminal Panel
static NSString* const kToolbarToggleSecondary  = @"kToolbarToggleSecondary"; // Right Language-aware Preview
static NSString* const kToolbarDarkMode         = @"kToolbarDarkMode";
static NSString* const kToolbarSettings         = @"kToolbarSettings";
static NSString* const kToolbarFreeTyping       = @"kToolbarFreeTyping";

+ (NSImage *) wordWrapToolbarImage {
    NSImage* img = [NSImage imageWithSize: NSMakeSize(18, 18) flipped: NO drawingHandler: ^BOOL(NSRect dstRect) {
        [[NSColor blackColor] setStroke];

        // Top line
        NSBezierPath* line1 = [NSBezierPath bezierPath];
        [line1 moveToPoint: NSMakePoint(2.5, 14.5)];
        [line1 lineToPoint: NSMakePoint(15.5, 14.5)];
        line1.lineWidth = 1.5;
        line1.lineCapStyle = NSLineCapStyleRound;
        [line1 stroke];

        // Middle line wrapping around
        NSBezierPath* line2 = [NSBezierPath bezierPath];
        [line2 moveToPoint: NSMakePoint(2.5, 9.5)];
        [line2 lineToPoint: NSMakePoint(12.0, 9.5)];
        [line2 appendBezierPathWithArcWithCenter: NSMakePoint(12.0, 6.5) radius: 3.0 startAngle: 90 endAngle: -90 clockwise: YES];
        [line2 lineToPoint: NSMakePoint(6.5, 3.5)];
        line2.lineWidth = 1.5;
        line2.lineCapStyle = NSLineCapStyleRound;
        line2.lineJoinStyle = NSLineJoinStyleRound;
        [line2 stroke];

        // Arrow head pointing left
        NSBezierPath* arrow = [NSBezierPath bezierPath];
        [arrow moveToPoint: NSMakePoint(8.8, 5.8)];
        [arrow lineToPoint: NSMakePoint(6.0, 3.5)];
        [arrow lineToPoint: NSMakePoint(8.8, 1.2)];
        arrow.lineWidth = 1.5;
        arrow.lineCapStyle = NSLineCapStyleRound;
        arrow.lineJoinStyle = NSLineJoinStyleRound;
        [arrow stroke];

        return YES;
    }];
    [img setTemplate: YES];
    return img;
}

- (void) setupToolbar {
    NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier: @"NotepadPlusMainToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = YES;
    toolbar.autosavesConfiguration = YES;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    _window.toolbar = toolbar;
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {
    return @[
        kToolbarNew, kToolbarOpen, kToolbarSave, kToolbarSaveAll, kToolbarClose,
        NSToolbarSeparatorItemIdentifier,
        kToolbarCut, kToolbarCopy, kToolbarPaste, kToolbarUndo, kToolbarRedo,
        NSToolbarSeparatorItemIdentifier,
        kToolbarFind, kToolbarReplace, kToolbarColumnEditor,
        NSToolbarSeparatorItemIdentifier,
        kToolbarWordWrap, kToolbarAllChars,
        kToolbarMacroRec, kToolbarMacroStop, kToolbarMacroPlay, kToolbarSummary,
        NSToolbarFlexibleSpaceItemIdentifier,
        kToolbarTogglePrimary, kToolbarToggleBottom, kToolbarToggleSecondary,
        NSToolbarSeparatorItemIdentifier,
        kToolbarDarkMode, kToolbarSettings, kToolbarFreeTyping
    ];
}

- (NSArray<NSToolbarItemIdentifier> *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {
    return @[
        kToolbarNew, kToolbarOpen, kToolbarSave, kToolbarSaveAll, kToolbarClose,
        NSToolbarSeparatorItemIdentifier,
        kToolbarCut, kToolbarCopy, kToolbarPaste, kToolbarUndo, kToolbarRedo,
        NSToolbarSeparatorItemIdentifier,
        kToolbarFind, kToolbarReplace, kToolbarColumnEditor,
        NSToolbarSeparatorItemIdentifier,
        kToolbarWordWrap, kToolbarAllChars,
        kToolbarMacroRec, kToolbarMacroStop, kToolbarMacroPlay,
        NSToolbarFlexibleSpaceItemIdentifier,
        kToolbarTogglePrimary, kToolbarToggleBottom, kToolbarToggleSecondary,
        NSToolbarSeparatorItemIdentifier,
        kToolbarDarkMode, kToolbarSettings, kToolbarFreeTyping
    ];
}

- (NSToolbarItem *) toolbar: (NSToolbar *) toolbar itemForItemIdentifier: (NSToolbarItemIdentifier) itemIdentifier willBeInsertedIntoToolbar: (BOOL) flag {
    NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier: itemIdentifier];

    auto makeItem = [&](NSString* label, NSString* tip, NSString* sfName, SEL action) {
        item.label = label;
        item.paletteLabel = label;
        item.toolTip = tip;
        item.target = self;
        item.action = action;
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName: sfName accessibilityDescription: label];
        }
    };

    if ([itemIdentifier isEqualToString: kToolbarNew]) makeItem(@"New", @"Create a new document (⌘N)", @"doc.badge.plus", @selector(newFile:));
    else if ([itemIdentifier isEqualToString: kToolbarOpen]) makeItem(@"Open", @"Open existing file (⌘O)", @"folder", @selector(openFile:));
    else if ([itemIdentifier isEqualToString: kToolbarSave]) makeItem(@"Save", @"Save active document (⌘S)", @"square.and.arrow.down", @selector(saveFile:));
    else if ([itemIdentifier isEqualToString: kToolbarSaveAll]) makeItem(@"Save All", @"Save all open documents (⌥⌘S)", @"square.and.arrow.down.on.square", @selector(saveAllFiles:));
    else if ([itemIdentifier isEqualToString: kToolbarClose]) makeItem(@"Close", @"Close active document (⌘W)", @"xmark.square", @selector(closeTab:));
    else if ([itemIdentifier isEqualToString: kToolbarCut]) makeItem(@"Cut", @"Cut selection (⌘X)", @"scissors", @selector(cut:));
    else if ([itemIdentifier isEqualToString: kToolbarCopy]) makeItem(@"Copy", @"Copy selection (⌘C)", @"doc.on.doc", @selector(copy:));
    else if ([itemIdentifier isEqualToString: kToolbarPaste]) makeItem(@"Paste", @"Paste from clipboard (⌘V)", @"doc.on.clipboard", @selector(paste:));
    else if ([itemIdentifier isEqualToString: kToolbarUndo]) makeItem(@"Undo", @"Undo last action (⌘Z)", @"arrow.uturn.backward", @selector(undo:));
    else if ([itemIdentifier isEqualToString: kToolbarRedo]) makeItem(@"Redo", @"Redo last action (⇧⌘Z)", @"arrow.uturn.forward", @selector(redo:));
    else if ([itemIdentifier isEqualToString: kToolbarFind]) makeItem(@"Find", @"Find in document (⌘F)", @"magnifyingglass", @selector(showFind:));
    else if ([itemIdentifier isEqualToString: kToolbarReplace]) makeItem(@"Replace", @"Replace in document (⌥⌘F)", @"arrow.triangle.2.circlepath", @selector(showReplace:));
    else if ([itemIdentifier isEqualToString: kToolbarColumnEditor]) makeItem(@"Column Editor", [NSString stringWithFormat: @"%@ (⌥⌘C)", [self localizedString: @"dlg_title_ColumnEditor" defaultText: @"Column Editor"]], @"tablecells", @selector(showColumnEditorDialog:));
    else if ([itemIdentifier isEqualToString: kToolbarWordWrap]) {
        item.label = @"Wrap";
        item.paletteLabel = @"Wrap";
        item.toolTip = @"Toggle word wrap (⌥⌘W)";
        item.target = self;
        item.action = @selector(toggleWordWrap:);
        item.image = [NotepadPlusAppController wordWrapToolbarImage];
    }
    else if ([itemIdentifier isEqualToString: kToolbarAllChars]) makeItem(@"All Chars", @"Show White Space & EOL", @"paragraphsign", @selector(toggleShowAllCharacters:));
    else if ([itemIdentifier isEqualToString: kToolbarMacroRec]) makeItem(@"Record", @"Start Macro Recording (⌃⌘R)", @"record.circle", @selector(startMacroRecording:));
    else if ([itemIdentifier isEqualToString: kToolbarMacroStop]) makeItem(@"Stop", @"Stop Macro Recording (⇧⌃⌘R)", @"stop.circle", @selector(stopMacroRecording:));
    else if ([itemIdentifier isEqualToString: kToolbarMacroPlay]) makeItem(@"Playback", @"Play Macro (⌃⌘P)", @"play.circle", @selector(playbackMacro:));
    else if ([itemIdentifier isEqualToString: kToolbarSummary]) makeItem(@"Summary", @"Document Summary", @"chart.bar.doc.horizontal", @selector(showSummaryDialog:));

    // VS Code Layout Toggle Icons
    else if ([itemIdentifier isEqualToString: kToolbarTogglePrimary]) makeItem(@"Primary Side Bar", @"Toggle Primary Side Panel (Finder Tree) (⌘B)", @"sidebar.left", @selector(togglePrimarySidePanel:));
    else if ([itemIdentifier isEqualToString: kToolbarToggleBottom]) makeItem(@"Bottom Panel", @"Toggle Embedded Terminal Panel (⌃`)", @"dock.rectangle", @selector(toggleBottomPanel:));
    else if ([itemIdentifier isEqualToString: kToolbarToggleSecondary]) makeItem(@"Secondary Side Bar", @"Toggle Secondary Side Panel (Language Preview) (⇧⌘P)", @"sidebar.right", @selector(toggleSecondarySidePanel:));

    else if ([itemIdentifier isEqualToString: kToolbarDarkMode]) makeItem(@"Theme", @"Toggle Dark/Light Mode (⇧⌘D)", @"circle.righthalf.filled", @selector(toggleDarkMode:));
    else if ([itemIdentifier isEqualToString: kToolbarSettings]) makeItem(@"Preferences", @"Preferences (⌘,)", @"gearshape", @selector(showPreferences:));
    else if ([itemIdentifier isEqualToString: kToolbarFreeTyping]) {
        item.label = @"Free Typing";
        item.paletteLabel = @"Free Typing Mode";
        item.toolTip = @"Free Typing Mode: click anywhere in the text area and start writing from that position";
        item.target = self;
        item.action = @selector(toggleFreeTypingMode:);
        if (@available(macOS 11.0, *)) {
            item.image = [NSImage imageWithSystemSymbolName: _freeTypingMode ? @"cursorarrow.rays" : @"cursorarrow"
                                     accessibilityDescription: @"Free Typing Mode"];
            item.bordered = YES;
        }
    }

    return item;
}

// ============================================================================
// Directory Context & Panel Toggle Actions
// ============================================================================

- (NSString *) getDirectoryForActiveTab {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        if (!doc.isUntitled && doc.filePath.length() > 0) {
            NSString* path = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
            NSString* dir = [path stringByDeletingLastPathComponent];
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath: dir isDirectory: &isDir] && isDir) {
                return dir;
            }
        }
    }
    // New/untitled tabs: base on the Left Explorer panel's current folder when visible
    if (_rootContentView.isPrimarySidePanelVisible && _primarySidePanel.rootDirectory.length > 0) {
        NSString* panelDir = _primarySidePanel.rootDirectory;
        BOOL isPanelDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath: panelDir isDirectory: &isPanelDir] && isPanelDir) {
            return panelDir;
        }
    }
    return NSHomeDirectory(); // Default to ~/ for new/untitled tabs
}

- (void) applyFreeTypingMode {
    // Free Typing Mode ON  -> caret may live in virtual space (click anywhere, type from there)
    // Free Typing Mode OFF -> caret constrained to real text (classic behavior)
    const sptr_t vsOptions = _freeTypingMode ? (SCVS_RECTANGULARSELECTION | SCVS_USERACCESSIBLE)
                                             : SCVS_RECTANGULARSELECTION;
    [_editor message: SCI_SETVIRTUALSPACEOPTIONS wParam: vsOptions lParam: 0];
}

- (void) toggleFreeTypingMode: (id) sender {
    _freeTypingMode = !_freeTypingMode;
    [self applyFreeTypingMode];

    _statusBar.statusText = _freeTypingMode ? @"Free Typing Mode: ON — click any position and start writing"
                                            : @"Free Typing Mode: OFF";
    [_statusBar setNeedsDisplay: YES];

    // Refresh the toolbar icon to reflect the new state
    if (_window.toolbar) {
        [self setupToolbar];
    }

    [self saveSessionState];
}

- (void) togglePrimarySidePanel: (id) sender {
    _rootContentView.isPrimarySidePanelVisible = !_rootContentView.isPrimarySidePanelVisible;
    if (_rootContentView.isPrimarySidePanelVisible) {
        [_primarySidePanel setDirectoryPath: [self getDirectoryForActiveTab]];
    }
    [_rootContentView updateSplitLayout];
}

- (void) toggleBottomPanel: (id) sender {
    _rootContentView.isBottomPanelVisible = !_rootContentView.isBottomPanelVisible;
    if (_rootContentView.isBottomPanelVisible) {
        [_bottomPanel setWorkingDirectoryPath: [self getDirectoryForActiveTab]];
        [_window makeFirstResponder: _bottomPanel.outputTextView];
    }
    [_rootContentView updateSplitLayout];
}

- (void) toggleSecondarySidePanel: (id) sender {
    _rootContentView.isSecondarySidePanelVisible = !_rootContentView.isSecondarySidePanelVisible;
    if (_rootContentView.isSecondarySidePanelVisible) {
        [self updateLivePreviewForActiveDocument];
    }
    [_rootContentView updateSplitLayout];
}

- (void) openMacTerminalAtDirectory: (NSString *) dirPath {
    if (!dirPath || dirPath.length == 0) dirPath = NSHomeDirectory();
    NSTask* task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/open";
    task.arguments = @[@"-a", @"Terminal", dirPath];
    [task launch];

    _statusBar.statusText = [NSString stringWithFormat: @"Opened Terminal at: %@", [dirPath lastPathComponent]];
    [_statusBar setNeedsDisplay: YES];
}

- (void) updateLivePreviewForActiveDocument {
    if (!_rootContentView.isSecondarySidePanelVisible) return;
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        NSString* text = [_editor string];
        NSString* fName = [NSString stringWithUTF8String: wstring_to_utf8(doc.title).c_str()];
        NSString* lexer = [NSString stringWithUTF8String: doc.lexerName.c_str()];
        [_secondarySidePanel renderDocumentContent: text fileName: fName lexerName: lexer];
    }
}

- (void) fileExplorerOpenFile: (NSString *) filePath { [self openFileAtPath: filePath]; }

- (void) terminalPanelCloseRequested {
    _rootContentView.isBottomPanelVisible = NO;
    [_rootContentView updateSplitLayout];
}

- (void) terminalPanelOpenExternalRequested: (NSString *) dirPath {
    [self openMacTerminalAtDirectory: dirPath];
}

- (void) secondaryPreviewCloseRequested {
    _rootContentView.isSecondarySidePanelVisible = NO;
    [_rootContentView updateSplitLayout];
}

- (void) secondaryPreviewLanguageSelected: (NSString *) lexerName {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        mDocuments[mActiveIndex].lexerName = [lexerName UTF8String];
        [self configureLexerForActiveDocument];
        [self updateStatusBar];
        [self updateLivePreviewForActiveDocument];
    }
}

// ============================================================================
// Column Mode & Column Editor Implementation (⌥⌘C)
// ============================================================================

- (void) toggleColumnMode: (id) sender {
    if (!_editor) return;
    auto L = [&](NSString* key, NSString* defText) -> NSString* {
        return [self localizedString: key defaultText: defText];
    };

    const sptr_t sels = [_editor message: SCI_GETSELECTIONS wParam: 0 lParam: 0];
    const sptr_t selMode = [_editor message: SCI_GETSELECTIONMODE wParam: 0 lParam: 0];
    const BOOL columnActive = (sels > 1) || (selMode == SC_SEL_RECTANGLE) || (selMode == SC_SEL_THIN);

    if (columnActive) {
        // Column Mode ON -> OFF: collapse to a single caret at the main position
        const sptr_t caret = [_editor message: SCI_GETCURRENTPOS wParam: 0 lParam: 0];
        [_editor message: SCI_CLEARSELECTIONS wParam: 0 lParam: 0];
        [_editor message: SCI_SETSELECTION wParam: caret lParam: caret];
        _statusBar.statusText = @"Column Mode: OFF";
    } else {
        // OFF -> ON: turn the current selection into a rectangular column selection
        const sptr_t anchor = [_editor message: SCI_GETANCHOR wParam: 0 lParam: 0];
        const sptr_t caret = [_editor message: SCI_GETCURRENTPOS wParam: 0 lParam: 0];
        if (anchor == caret) {
            _statusBar.statusText = L(@"dlg_6523", @"Select text first, then enable Column Mode");
            [_statusBar setNeedsDisplay: YES];
            return;
        }
        [_editor message: SCI_SETRECTANGULARSELECTIONCARET wParam: caret lParam: 0];
        [_editor message: SCI_SETRECTANGULARSELECTIONANCHOR wParam: anchor lParam: 0];
        const sptr_t lines = [_editor message: SCI_GETSELECTIONS wParam: 0 lParam: 0];
        _statusBar.statusText = [NSString stringWithFormat:@"Column Mode: ON (%ld lines)", (long)lines];
    }
    [_statusBar setNeedsDisplay: YES];
}

- (void) showColumnModeTip: (id) sender {
    auto L = [&](NSString* key, NSString* defText) -> NSString* {
        return [self localizedString: key defaultText: defText];
    };
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat: @"🔲 %@", L(@"dlg_6523", @"Column Mode Editing")];
    
    NSString* colTitle = L(@"dlg_title_ColumnEditor", @"Column Editor");
    alert.informativeText = [NSString stringWithFormat:
        @"1. %@: ⌥ (Option) + Drag\n"
        @"2. %@: ⌥ + ⇧ + Arrows\n"
        @"3. %@: Multi-Caret typing on selected column\n"
        @"4. %@ (⌥⌘C): Batch insert numbers or text",
        L(@"dlg_6523", @"Rectangular Selection (Mouse)"),
        L(@"dlg_6523", @"Rectangular Selection (Keyboard)"),
        L(@"dlg_6522", @"Multi-Editing"),
        colTitle
    ];
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle: colTitle];
    [alert addButtonWithTitle: L(@"dlg_1", @"OK")];

    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertFirstButtonReturn) {
        [self showColumnEditorDialog: sender];
    }
}

- (void) showColumnEditorDialog: (id) sender {
    [_columnEditorWindowController showColumnEditor];
}

- (void) applyColumnEditIsText: (BOOL) isText
                          text: (NSString *) insertText
                       initNum: (long long) initNum
                   increaseNum: (long long) increaseNum
                        repeat: (long long) repeatCount
                     formatIdx: (NSInteger) formatIdx
                    leadingIdx: (NSInteger) leadingIdx {
    [_editor message: SCI_BEGINUNDOACTION];

    BOOL isRect = ([_editor message: SCI_SELECTIONISRECTANGLE] != 0);
    sptr_t numSelections = [_editor message: SCI_GETSELECTIONS];

    auto formatNumber = [&](long long val, int minWidth) -> std::string {
        std::string numStr;
        if (formatIdx == 1) { // Hex
            std::stringstream ss;
            ss << std::hex << std::uppercase << val;
            numStr = ss.str();
        } else if (formatIdx == 2) { // Oct
            std::stringstream ss;
            ss << std::oct << val;
            numStr = ss.str();
        } else if (formatIdx == 3) { // Bin
            std::string b;
            unsigned long long uval = (unsigned long long)val;
            if (uval == 0) b = "0";
            while (uval > 0) {
                b = ((uval & 1) ? "1" : "0") + b;
                uval >>= 1;
            }
            numStr = b;
        } else { // Dec
            numStr = std::to_string(val);
        }

        if (leadingIdx == 1 && (int)numStr.length() < minWidth) { // Zeros
            numStr = std::string(minWidth - numStr.length(), '0') + numStr;
        } else if (leadingIdx == 2 && (int)numStr.length() < minWidth) { // Spaces
            numStr = std::string(minWidth - numStr.length(), ' ') + numStr;
        }
        return numStr;
    };

    if (isRect || numSelections > 1) {
        long long curNum = initNum;
        long long rep = 0;
        for (sptr_t i = 0; i < numSelections; ++i) {
            sptr_t selStart = [_editor message: SCI_GETSELECTIONNSTART wParam: i lParam: 0];
            sptr_t selEnd = [_editor message: SCI_GETSELECTIONNEND wParam: i lParam: 0];

            std::string str;
            if (isText) {
                str = [insertText UTF8String];
            } else {
                str = formatNumber(curNum, 1);
                rep++;
                if (rep >= repeatCount) {
                    curNum += increaseNum;
                    rep = 0;
                }
            }
            [_editor message: SCI_SETTARGETSTART wParam: selStart lParam: 0];
            [_editor message: SCI_SETTARGETEND wParam: selEnd lParam: 0];
            [_editor message: SCI_REPLACETARGET wParam: str.length() lParam: reinterpret_cast<sptr_t>(str.c_str())];
        }
    } else {
        sptr_t curPos = [_editor message: SCI_GETCURRENTPOS];
        sptr_t curCol = [_editor message: SCI_GETCOLUMN wParam: curPos lParam: 0];
        sptr_t curLine = [_editor message: SCI_LINEFROMPOSITION wParam: curPos lParam: 0];
        sptr_t endLine = [_editor message: SCI_GETLINECOUNT] - 1;

        sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
        sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
        if (selEnd > selStart) {
            curLine = [_editor message: SCI_LINEFROMPOSITION wParam: selStart lParam: 0];
            endLine = [_editor message: SCI_LINEFROMPOSITION wParam: selEnd lParam: 0];
        }

        int maxLen = 1;
        if (!isText && leadingIdx != 0) {
            long long maxVal = initNum + (endLine - curLine) * increaseNum;
            maxLen = (int)formatNumber(maxVal, 0).length();
        }

        long long curNum = initNum;
        long long rep = 0;
        for (sptr_t l = curLine; l <= endLine; ++l) {
            sptr_t lineStart = [_editor message: SCI_POSITIONFROMLINE wParam: l lParam: 0];
            sptr_t lineEnd = [_editor message: SCI_GETLINEENDPOSITION wParam: l lParam: 0];
            sptr_t colPos = [_editor message: SCI_FINDCOLUMN wParam: l lParam: curCol];
            if (colPos == -1 || colPos > lineEnd) colPos = lineEnd;

            std::string str;
            if (isText) {
                str = [insertText UTF8String];
            } else {
                str = formatNumber(curNum, maxLen);
                rep++;
                if (rep >= repeatCount) {
                    curNum += increaseNum;
                    rep = 0;
                }
            }

            [_editor message: SCI_INSERTTEXT wParam: colPos lParam: reinterpret_cast<sptr_t>(str.c_str())];
        }
    }

    [_editor message: SCI_ENDUNDOACTION];
    [self updateLivePreviewForActiveDocument];
}

// ============================================================================
// Scintilla Defaults & Theme Engine (Gray Line Selection)
// ============================================================================

- (void) setupScintillaDefaults {
    [_editor suspendDrawing: YES];
    [_editor message: SCI_SETCODEPAGE wParam: SC_CP_UTF8 lParam: 0];
    [_editor message: SCI_SETREADONLY wParam: 0 lParam: 0];

    NSString* fontToUse = _currentFontName;
    if (!fontToUse || [fontToUse isEqualToString: @"SF Mono"]) {
        if (@available(macOS 10.15, *)) {
            fontToUse = [NSFont monospacedSystemFontOfSize: _currentFontSize weight: NSFontWeightRegular].fontName;
        } else {
            fontToUse = @"Menlo";
        }
    }
    [_editor setStringProperty: SCI_STYLESETFONT parameter: STYLE_DEFAULT value: fontToUse];
    [_editor setGeneralProperty: SCI_STYLESETSIZE parameter: STYLE_DEFAULT value: _currentFontSize];
    [_editor message: SCI_STYLECLEARALL];

    // CallTip / 풍선 도움말 2x 크기 (24pt) 및 테마 연동 색상
    [_editor setGeneralProperty: SCI_STYLESETSIZE parameter: STYLE_CALLTIP value: 24];
    [_editor setColorProperty: SCI_CALLTIPSETFORE parameter: 0 value: _isDarkMode ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite: 0.10 alpha: 1.0]];
    [_editor setColorProperty: SCI_CALLTIPSETBACK parameter: 0 value: _isDarkMode ? [NSColor colorWithCalibratedRed: 0.16 green: 0.16 blue: 0.20 alpha: 1.0] : [NSColor colorWithCalibratedRed: 1.0 green: 0.98 blue: 0.88 alpha: 1.0]];

    [_editor message: SCI_SETEOLMODE wParam: _defaultNewEOL == 2 ? SC_EOL_LF : (_defaultNewEOL == 0 ? SC_EOL_CRLF : SC_EOL_CR) lParam: 0];

    // Margins
    [_editor message: SCI_SETMARGINTYPEN wParam: 0 lParam: SC_MARGIN_NUMBER];
    [_editor message: SCI_SETMARGINWIDTHN wParam: 0 lParam: _showLineNumbers ? 46 : 0];

    [_editor message: SCI_SETMARGINTYPEN wParam: 1 lParam: SC_MARGIN_SYMBOL];
    [_editor message: SCI_SETMARGINWIDTHN wParam: 1 lParam: _showBookmarksMargin ? 16 : 0];
    [_editor message: SCI_SETMARGINSENSITIVEN wParam: 1 lParam: 1];

    [_editor message: SCI_SETMARGINTYPEN wParam: 2 lParam: SC_MARGIN_SYMBOL];
    [_editor message: SCI_SETMARGINMASKN wParam: 2 lParam: SC_MASK_FOLDERS];
    [_editor message: SCI_SETMARGINWIDTHN wParam: 2 lParam: _showFoldingMargin ? 14 : 0];
    [_editor message: SCI_SETMARGINSENSITIVEN wParam: 2 lParam: 1];
    [_editor message: SCI_SETAUTOMATICFOLD wParam: SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE lParam: 0];

    // Fold markers (Classic Notepad++ [-] [+] Square Box Folding Tree)
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDEROPEN lParam: SC_MARK_BOXMINUS];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDER lParam: SC_MARK_BOXPLUS];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDERSUB lParam: SC_MARK_VLINE];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDERTAIL lParam: SC_MARK_LCORNER];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDEREND lParam: SC_MARK_BOXPLUSCONNECTED];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDEROPENMID lParam: SC_MARK_BOXMINUSCONNECTED];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDERMIDTAIL lParam: SC_MARK_TCORNER];

    NSColor* foldFore = [NSColor colorWithCalibratedWhite: 0.50 alpha: 1.0];
    NSColor* foldBack = _isDarkMode ? [NSColor colorWithCalibratedWhite: 0.20 alpha: 1.0] : [NSColor whiteColor];

    // Fold buttons ([-] and [+]) use foldBack for fill, foldFore for border
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDEROPEN value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDEROPEN value: foldBack];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDER value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDER value: foldBack];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDEROPENMID value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDEROPENMID value: foldBack];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDEREND value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDEREND value: foldBack];

    // Connecting lines (| vertical line and corners L, T) MUST use foldFore for BACK because LineMarker fills body with back color!
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDERSUB value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDERSUB value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDERTAIL value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDERTAIL value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDERMIDTAIL value: foldFore];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDERMIDTAIL value: foldFore];

    // Bookmark marker
    [_editor message: SCI_MARKERDEFINE wParam: 1 lParam: SC_MARK_SHORTARROW];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: 1 value: [NSColor colorWithCalibratedRed: 0.2 green: 0.6 blue: 1.0 alpha: 1.0]];

    // Search Style Indicators (SCE_UNIVERSAL_FOUND_STYLE_EXT1..5 = 25..21, FIND_STYLE =31)
    // Light-theme base per spec: 1=Light Blue, 2=Orange, 3=Yellow, 4=Dark Blue, 5=Dark Green
    // Dark theme uses lighter/brighter variants to avoid “deleted” look on dark bg
    NSArray<NSColor *>* styleColors;
    if (_isDarkMode) {
        styleColors = @[
            [NSColor colorWithCalibratedRed: 0.35 green: 0.65 blue: 0.98 alpha: 1.0], // 25 Light Blue (brighter for dark bg)
            [NSColor colorWithCalibratedRed: 1.00 green: 0.72 blue: 0.35 alpha: 1.0], // 24 Orange (lighter)
            [NSColor colorWithCalibratedRed: 1.00 green: 0.95 blue: 0.45 alpha: 1.0], // 23 Yellow (pale, visible on dark)
            [NSColor colorWithCalibratedRed: 0.45 green: 0.60 blue: 0.95 alpha: 1.0], // 22 Dark Blue → light periwinkle on dark
            [NSColor colorWithCalibratedRed: 0.25 green: 0.78 blue: 0.45 alpha: 1.0]  // 21 Dark Green → mint on dark
        ];
    } else {
        styleColors = @[
            [NSColor colorWithCalibratedRed: 0.68 green: 0.85 blue: 1.00 alpha: 1.0], // 25 Light Blue 연한 하늘색
            [NSColor colorWithCalibratedRed: 1.00 green: 0.65 blue: 0.15 alpha: 1.0], // 24 Orange 주황
            [NSColor colorWithCalibratedRed: 1.00 green: 0.93 blue: 0.20 alpha: 1.0], // 23 Yellow 노랑
            [NSColor colorWithCalibratedRed: 0.14 green: 0.30 blue: 0.65 alpha: 1.0], // 22 Dark Blue 어두운 파랑
            [NSColor colorWithCalibratedRed: 0.00 green: 0.45 blue: 0.18 alpha: 1.0]  // 21 Dark Green 진한 초록
        ];
    }
    for (int i = 0; i < 5; ++i) {
        int indic = 21 + (4 - i); // 21..25 mapped to colors 4..0 to keep order 1=gold
        // style 25=1st, 24=2nd ... 21=5th (match Notepad++ SCE_UNIVERSAL_FOUND_STYLE_EXT1..5)
        int styleIndic = 25 - i;
        [_editor message: SCI_INDICSETSTYLE wParam: styleIndic lParam: INDIC_ROUNDBOX];
        [_editor setColorProperty: SCI_INDICSETFORE parameter: styleIndic value: styleColors[i]];
        [_editor message: SCI_INDICSETALPHA wParam: styleIndic lParam: 100];
        [_editor message: SCI_INDICSETUNDER wParam: styleIndic lParam: 1];
    }
    // Smart highlight / generic found style (31) — used for "Mark All" default and incremental
    [_editor message: SCI_INDICSETSTYLE wParam: SCE_UNIVERSAL_FOUND_STYLE lParam: INDIC_ROUNDBOX];
    [_editor setColorProperty: SCI_INDICSETFORE parameter: SCE_UNIVERSAL_FOUND_STYLE value: [NSColor colorWithCalibratedRed: 0.92 green: 0.42 blue: 0.42 alpha: 1.0]];
    [_editor message: SCI_INDICSETALPHA wParam: SCE_UNIVERSAL_FOUND_STYLE lParam: 100];
    [_editor message: SCI_INDICSETUNDER wParam: SCE_UNIVERSAL_FOUND_STYLE lParam: 1];

    // CallTip / 풍선 도움말 (Ultra-Fast 50ms Dwell Time & 2x Font Size: 24pt)
    [_editor message: SCI_SETMOUSEDWELLTIME wParam: 50 lParam: 0];
    [_editor setGeneralProperty: SCI_STYLESETSIZE parameter: STYLE_CALLTIP value: 24];
    [_editor setStringProperty: SCI_STYLESETFONT parameter: STYLE_CALLTIP value: @"Helvetica Neue"];
    [_editor message: SCI_CALLTIPUSESTYLE wParam: 32 lParam: 0];



    // Column Mode & Rectangular Selection Configuration (Option+Drag & ⌥⇧+Arrows)
    [_editor message: SCI_SETMULTIPLESELECTION wParam: 1 lParam: 0];
    [_editor message: SCI_SETADDITIONALSELECTIONTYPING wParam: 1 lParam: 0];
    [_editor message: SCI_SETADDITIONALCARETSVISIBLE wParam: 1 lParam: 0];
    [_editor message: SCI_SETADDITIONALCARETSBLINK wParam: 1 lParam: 0];
    [_editor message: SCI_SETMULTIPASTE wParam: SC_MULTIPASTE_EACH lParam: 0];
    [_editor message: SCI_SETRECTANGULARSELECTIONMODIFIER wParam: SCMOD_ALT lParam: 0];
    [_editor message: SCI_SETMOUSESELECTIONRECTANGULARSWITCH wParam: 1 lParam: 0];
    [self applyFreeTypingMode];

    // Tabs & Indentation
    [_editor message: SCI_SETTABWIDTH wParam: _currentTabWidth lParam: 0];
    [_editor message: SCI_SETUSETABS wParam: _useSpacesForTabs ? 0 : 1 lParam: 0];
    [_editor message: SCI_SETTABINDENTS wParam: 1 lParam: 0];
    [_editor message: SCI_SETBACKSPACEUNINDENTS wParam: 1 lParam: 0];
    [_editor message: SCI_SETINDENTATIONGUIDES wParam: _showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE lParam: 0];

    // Caret & Line (High-visibility 4px Retina Caret, 2x thicker than default)
    [_editor message: SCI_SETCARETSTYLE wParam: CARETSTYLE_LINE lParam: 0];
    [_editor message: SCI_SETCARETWIDTH wParam: 4 lParam: 0];
    [_editor message: SCI_SETCARETPERIOD wParam: 500 lParam: 0];
    [_editor message: SCI_SETCARETLINEVISIBLE wParam: _highlightCurrentLine ? 1 : 0 lParam: 0];
    [_editor message: SCI_SETWRAPMODE wParam: _wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE lParam: 0];
    [_editor message: SCI_SETVIEWWS wParam: _showWhiteSpace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE lParam: 0];
    [_editor message: SCI_SETVIEWEOL wParam: _showEOL ? 1 : 0 lParam: 0];

    if (_showColumnGuide) {
        [_editor message: SCI_SETEDGEMODE wParam: EDGE_LINE lParam: 0];
        [_editor message: SCI_SETEDGECOLUMN wParam: _columnGuidePos lParam: 0];
        [_editor setColorProperty: SCI_SETEDGECOLOUR parameter: 0 value: [NSColor colorWithCalibratedWhite: 0.5 alpha: 0.5]];
    } else {
        [_editor message: SCI_SETEDGEMODE wParam: EDGE_NONE lParam: 0];
    }

    [_editor suspendDrawing: NO];
}

- (void) applyAllSettings {
    [self setupScintillaDefaults];
    [self applyThemeColors];
}

- (void) applyThemeColors {
    [_editor suspendDrawing: YES];

    _window.appearance = _isDarkMode ? [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]
                                     : [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    _window.backgroundColor = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.13 green: 0.13 blue: 0.14 alpha: 1.0]
                                          : [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];

    _tabBar.isDarkMode = _isDarkMode;
    [_tabBar setNeedsDisplay: YES];

    _primarySidePanel.isDarkMode = _isDarkMode;
    _bottomPanel.isDarkMode = _isDarkMode;
    _secondarySidePanel.isDarkMode = _isDarkMode;

    _statusBar.isDarkMode = _isDarkMode;
    [_statusBar setNeedsDisplay: YES];

    [_findReplaceWindowController updateAppearance: _isDarkMode];

    if (_prefWindowController && _prefWindowController.window) {
        _prefWindowController.window.appearance = _isDarkMode ? [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]
                                                              : [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    }
    if (_columnEditorWindowController && _columnEditorWindowController.window) {
        _columnEditorWindowController.window.appearance = _isDarkMode ? [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]
                                                                      : [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    }

    NSColor* bgCol = [NSColor whiteColor];
    NSColor* foreCol = [NSColor blackColor];
    // Translucent contrasting caret line (Light theme: soft sky blue highlight)
    NSColor* caretLineCol = [NSColor colorWithCalibratedRed: 0.10 green: 0.50 blue: 1.00 alpha: 1.0];
    NSColor* selCol = [NSColor colorWithCalibratedRed: 0.78 green: 0.80 blue: 0.84 alpha: 1.0];
    NSColor* marginBg = [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];
    NSColor* marginFore = [NSColor colorWithCalibratedRed: 0.45 green: 0.45 blue: 0.45 alpha: 1.0];

    if ([_currentThemeName containsString: @"Monokai"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.16 green: 0.15 blue: 0.17 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.97 green: 0.97 blue: 0.94 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.95 green: 0.90 blue: 0.55 alpha: 1.0]; // Contrasting warm amber tint
        selCol = [NSColor colorWithCalibratedRed: 0.38 green: 0.37 blue: 0.42 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.17 blue: 0.19 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.55 green: 0.55 blue: 0.55 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Dracula"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.16 green: 0.17 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.95 green: 0.95 blue: 0.96 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.75 green: 0.55 blue: 0.98 alpha: 1.0]; // Contrasting soft violet tint
        selCol = [NSColor colorWithCalibratedRed: 0.36 green: 0.38 blue: 0.48 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.19 blue: 0.23 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.50 green: 0.52 blue: 0.60 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Solarized Dark"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.00 green: 0.17 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.51 green: 0.58 blue: 0.59 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.15 green: 0.85 blue: 0.80 alpha: 1.0]; // Contrasting cyan-teal tint
        selCol = [NSColor colorWithCalibratedRed: 0.14 green: 0.34 blue: 0.40 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.04 green: 0.19 blue: 0.23 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.40 green: 0.48 blue: 0.50 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Solarized Light"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.99 green: 0.96 blue: 0.89 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.40 green: 0.48 blue: 0.51 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.15 green: 0.45 blue: 0.65 alpha: 1.0]; // Contrasting ocean tint
        selCol = [NSColor colorWithCalibratedRed: 0.84 green: 0.82 blue: 0.74 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.94 green: 0.91 blue: 0.84 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.58 green: 0.63 blue: 0.63 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Obsidian"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.18 green: 0.20 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.88 green: 0.88 blue: 0.88 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.45 green: 0.85 blue: 0.95 alpha: 1.0]; // Contrasting glacier cyan tint
        selCol = [NSColor colorWithCalibratedRed: 0.36 green: 0.42 blue: 0.48 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.20 blue: 0.21 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.50 green: 0.52 blue: 0.54 alpha: 1.0];
    } else if (_isDarkMode) {
        bgCol = [NSColor colorWithCalibratedRed: 0.13 green: 0.13 blue: 0.14 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.90 green: 0.90 blue: 0.90 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.22 green: 0.48 blue: 0.88 alpha: 1.0]; // 투명 파란색 반전 (inverted transparent blue)
        selCol = [NSColor colorWithCalibratedRed: 0.35 green: 0.37 blue: 0.42 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.18 blue: 0.20 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.60 green: 0.60 blue: 0.60 alpha: 1.0];
    } else {
        // Pure Crisp White Light Theme
        bgCol = [NSColor whiteColor];
        foreCol = [NSColor blackColor];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.10 green: 0.50 blue: 1.00 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.78 green: 0.80 blue: 0.84 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.45 green: 0.45 blue: 0.45 alpha: 1.0];
    }

    [_editor setColorProperty: SCI_STYLESETFORE parameter: STYLE_DEFAULT value: foreCol];
    [_editor setColorProperty: SCI_STYLESETBACK parameter: STYLE_DEFAULT value: bgCol];
    [_editor message: SCI_STYLECLEARALL];

    [_editor setColorProperty: SCI_STYLESETBACK parameter: STYLE_LINENUMBER value: marginBg];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: STYLE_LINENUMBER value: marginFore];

    [_editor message: SCI_SETCARETSTYLE wParam: CARETSTYLE_LINE lParam: 0];
    [_editor message: SCI_SETCARETWIDTH wParam: 4 lParam: 0]; // 2x thicker caret
    [_editor message: SCI_SETCARETPERIOD wParam: 500 lParam: 0];
    // Caret color follows the actual editor background luminance:
    // white caret on dark backgrounds, near-black caret on light backgrounds
    NSColor* resolvedBg = [bgCol colorUsingColorSpace: [NSColorSpace sRGBColorSpace]] ?: bgCol;
    double bgLuminance = 0.2126 * resolvedBg.redComponent + 0.7152 * resolvedBg.greenComponent + 0.0722 * resolvedBg.blueComponent;
    if (bgLuminance < 0.5) {
        [_editor setColorProperty: SCI_SETCARETFORE parameter: 0 value: [NSColor whiteColor]];
    } else {
        [_editor setColorProperty: SCI_SETCARETFORE parameter: 0 value: [NSColor colorWithCalibratedWhite: 0.05 alpha: 1.0]];
    }
    [_editor setColorProperty: SCI_SETCARETLINEBACK parameter: 0 value: caretLineCol];
    // 다크모드에서는 더 투명하게 (반전 효과)
    int caretAlpha = _isDarkMode ? 36 : 50;
    [_editor message: SCI_SETCARETLINEBACKALPHA wParam: caretAlpha lParam: 0];
    [_editor message: SCI_SETCARETLINEVISIBLE wParam: _highlightCurrentLine ? 1 : 0 lParam: 0];
    [_editor message: SCI_SETCARETLINEVISIBLEALWAYS wParam: 1 lParam: 0];

    [_editor message: SCI_SETSELFORE wParam: 0 lParam: 0];
    [_editor setColorProperty: SCI_SETSELBACK parameter: 1 value: selCol];

    [_editor setColorProperty: SCI_SETFOLDMARGINCOLOUR parameter: 1 value: marginBg];
    [_editor setColorProperty: SCI_SETFOLDMARGINHICOLOUR parameter: 1 value: marginBg];

    NSColor* foldForeTheme = [NSColor colorWithCalibratedWhite: 0.50 alpha: 1.0];
    NSColor* foldBackTheme = _isDarkMode ? [NSColor colorWithCalibratedWhite: 0.20 alpha: 1.0] : [NSColor whiteColor];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDEROPEN value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDEROPEN value: foldBackTheme];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDER value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDER value: foldBackTheme];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDEROPENMID value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDEROPENMID value: foldBackTheme];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDEREND value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDEREND value: foldBackTheme];

    // Connecting lines (| vertical line and corners L, T) use foldForeTheme for BACK
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDERSUB value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDERSUB value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDERTAIL value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDERTAIL value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETFORE parameter: SC_MARKNUM_FOLDERMIDTAIL value: foldForeTheme];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: SC_MARKNUM_FOLDERMIDTAIL value: foldForeTheme];

    [self configureLexerForActiveDocument];
    [self updateLivePreviewForActiveDocument];
    [_editor suspendDrawing: NO];
}

// ============================================================================
// Document Management
// ============================================================================

- (int) computeNextUntitledNumber {
    int maxNum = 0;
    for (const auto& doc : mDocuments) {
        if (doc.isUntitled) {
            std::string t = wstring_to_utf8(doc.title);
            int n = 0;
            if (sscanf(t.c_str(), "new %d", &n) == 1) {
                if (n > maxNum) maxNum = n;
            }
        }
    }
    return maxNum + 1;
}

- (void) newDocumentWithTitle: (NSString *) title {
    NppDocument doc;
    doc.title = utf8_to_wstring([title UTF8String]);
    doc.filePath = L"";
    doc.isUntitled = true;
    doc.isModified = false;
    doc.isReadOnly = false;
    doc.encoding = _defaultNewEncoding;
    doc.eolMode = _defaultNewEOL;
    doc.lexerName = _defaultNewLanguage ? [_defaultNewLanguage UTF8String] : "text";

    void* pDoc = reinterpret_cast<void*>([_editor message: SCI_CREATEDOCUMENT wParam: 0 lParam: 0]);
    doc.pDoc = pDoc;

    mDocuments.push_back(doc);
    [self switchToDocumentAtIndex: mDocuments.size() - 1];
    mUntitledCounter++;
}

- (void) switchToDocumentAtIndex: (NSInteger) index {
    if (index < 0 || index >= static_cast<NSInteger>(mDocuments.size())) return;

    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size()) && _editor) {
        mDocuments[mActiveIndex].cursorPosition = static_cast<int>([_editor message: SCI_GETCURRENTPOS]);
        mDocuments[mActiveIndex].scrollPosition = static_cast<int>([_editor message: SCI_GETFIRSTVISIBLELINE]);
        mDocuments[mActiveIndex].cachedContent = [[_editor string] UTF8String];
    }

    mActiveIndex = index;
    NppDocument& doc = mDocuments[mActiveIndex];

    [_editor message: SCI_SETDOCPOINTER wParam: 0 lParam: reinterpret_cast<sptr_t>(doc.pDoc)];
    [self configureLexerForActiveDocument];
    [_editor message: SCI_SETCURRENTPOS wParam: doc.cursorPosition lParam: 0];

    [self updateWindowTitle];
    [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
    [self updateStatusBar];

    NSString* activeDir = [self getDirectoryForActiveTab];
    if (_rootContentView.isPrimarySidePanelVisible) {
        [_primarySidePanel setDirectoryPath: activeDir];
    }
    if (_rootContentView.isBottomPanelVisible) {
        [_bottomPanel setWorkingDirectoryPath: activeDir];
    }
    if (_rootContentView.isSecondarySidePanelVisible) {
        [self updateLivePreviewForActiveDocument];
    }
    [self saveSessionState];
}

- (void) updateWindowTitle {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    const NppDocument& doc = mDocuments[mActiveIndex];
    std::string title = wstring_to_utf8(doc.title);
    if (doc.isModified) title = "*" + title;
    _window.title = [NSString stringWithFormat: @"%s - Notepad++", title.c_str()];

    if (!doc.isUntitled) {
        NSString* fPath = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
        _window.representedURL = [NSURL fileURLWithPath: fPath];
    } else {
        _window.representedURL = nil;
    }
    _window.documentEdited = doc.isModified;
}

- (void) updateStatusBar {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    const NppDocument& doc = mDocuments[mActiveIndex];

    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: pos] + 1;
    sptr_t col = [_editor message: SCI_GETCOLUMN wParam: pos] + 1;
    sptr_t totalLines = [_editor message: SCI_GETLINECOUNT];
    sptr_t length = [_editor message: SCI_GETLENGTH];
    sptr_t selLength = [_editor message: SCI_GETSELECTIONEND] - [_editor message: SCI_GETSELECTIONSTART];

    _statusBar.posText = [NSString stringWithFormat: @"Ln: %ld  Col: %ld  Pos: %ld", (long)line, (long)col, (long)pos + 1];
    if (selLength > 0) {
        _statusBar.lengthText = [NSString stringWithFormat: @"Len: %ld  Lines: %ld  Sel: %ld", (long)length, (long)totalLines, (long)selLength];
    } else {
        _statusBar.lengthText = [NSString stringWithFormat: @"Length: %ld  Lines: %ld", (long)length, (long)totalLines];
    }

    switch (doc.eolMode) {
        case 0: _statusBar.eolText = @"Windows (CR LF)"; break;
        case 1: _statusBar.eolText = @"Macintosh (CR)"; break;
        case 2: _statusBar.eolText = @"Unix (LF)"; break;
        default: _statusBar.eolText = @"Unix (LF)"; break;
    }

    switch (doc.encoding) {
        case 0: _statusBar.encodingText = @"UTF-8"; break;
        case 1: _statusBar.encodingText = @"UTF-8 BOM"; break;
        case 2: _statusBar.encodingText = @"UTF-16 LE"; break;
        case 3: _statusBar.encodingText = @"UTF-16 BE"; break;
        case 4: _statusBar.encodingText = @"ANSI"; break;
        case 5: _statusBar.encodingText = @"EUC-KR"; break;
        case 6: _statusBar.encodingText = @"Shift-JIS"; break;
        case 7: _statusBar.encodingText = @"Big5"; break;
        case 8: _statusBar.encodingText = @"GB2312"; break;
        default: _statusBar.encodingText = @"UTF-8"; break;
    }

    _statusBar.langText = [NSString stringWithUTF8String: doc.lexerName.c_str()];
    _statusBar.statusText = doc.isReadOnly ? @"Read-Only" : (doc.isModified ? @"Modified" : @"Ready");
    _statusBar.insText = ([_editor message: SCI_GETOVERTYPE] != 0) ? @"OVR" : @"INS";
    _statusBar.macroText = mIsRecordingMacro ? @"REC ●" : @"";

    [_statusBar setNeedsDisplay: YES];
}

// ============================================================================
// Language & Syntax Highlighting
// ============================================================================

- (std::string) detectLexerForPath: (const std::wstring&) path {
    std::string pathUtf8 = wstring_to_utf8(path);
    std::string fileName = pathUtf8;
    size_t slash = fileName.find_last_of("/\\");
    if (slash != std::string::npos) fileName = fileName.substr(slash + 1);
    std::string lowerFileName = fileName;
    std::transform(lowerFileName.begin(), lowerFileName.end(), lowerFileName.begin(), ::tolower);

    // Exact filename matches
    if (lowerFileName == "makefile" || lowerFileName == "gnumakefile") return "makefile";
    if (lowerFileName == "dockerfile" || lowerFileName == "containerfile") return "bash";
    if (lowerFileName == "cmakelists.txt") return "cmake";
    if (lowerFileName == "gemfile" || lowerFileName == "rakefile") return "ruby";

    size_t dot = pathUtf8.find_last_of('.');
    if (dot == std::string::npos) return "text";
    std::string ext = pathUtf8.substr(dot + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

    static const std::unordered_map<std::string, std::string> s_extMap = {
        {"ada", "ada"},
        {"adb", "ada"},
        {"ads", "ada"},
        {"ans", "escseq"},
        {"as", "cpp"},
        {"asm", "asm"},
        {"asp", "hypertext"},
        {"aspx", "hypertext"},
        {"astro", "hypertext"},
        {"au3", "au3"},
        {"avs", "avs"},
        {"avsi", "avs"},
        {"bas", "freebasic"},
        {"bash", "bash"},
        {"bash_profile", "bash"},
        {"bashrc", "bash"},
        {"bat", "batch"},
        {"bb", "blitzbasic"},
        {"bc", "baan"},
        {"bi", "freebasic"},
        {"bsh", "bash"},
        {"c", "c"},
        {"cbd", "cobol"},
        {"cbl", "cobol"},
        {"cc", "cpp"},
        {"cdb", "cobol"},
        {"cdc", "cobol"},
        {"cf", "props"},
        {"cfg", "props"},
        {"cjs", "javascript"},
        {"cl", "visualprolog"},
        {"cln", "baan"},
        {"cmake", "cmake"},
        {"cmd", "batch"},
        {"cob", "cobol"},
        {"coffee", "coffeescript"},
        {"conf", "props"},
        {"containerfile", "bash"},
        {"copy", "cobol"},
        {"cpp", "cpp"},
        {"cpy", "cobol"},
        {"cs", "csharp"},
        {"csd", "csound"},
        {"csh", "bash"},
        {"csproj", "xml"},
        {"css", "css"},
        {"csxproj", "xml"},
        {"cxx", "cpp"},
        {"d", "d"},
        {"dart", "dart"},
        {"dbproj", "xml"},
        {"diff", "diff"},
        {"dockerfile", "bash"},
        {"dpr", "pascal"},
        {"dproj", "xml"},
        {"editorconfig", "props"},
        {"em", "escript"},
        {"env", "bash"},
        {"erl", "erlang"},
        {"err", "errorlist"},
        {"f", "fortran"},
        {"f23", "fortran"},
        {"f2k", "fortran"},
        {"f77", "f77"},
        {"f90", "fortran"},
        {"f95", "fortran"},
        {"fish", "bash"},
        {"for", "fortran"},
        {"forth", "forth"},
        {"gd", "gdscript"},
        {"geojson", "json"},
        {"gitattributes", "props"},
        {"gitconfig", "props"},
        {"gitmodules", "props"},
        {"gml", "xml"},
        {"go", "go"},
        {"gpx", "xml"},
        {"gql", "json"},
        {"graphql", "json"},
        {"gui", "gui4cli"},
        {"h", "c"},
        {"hex", "ihex"},
        {"hh", "cpp"},
        {"hpp", "cpp"},
        {"hrl", "erlang"},
        {"hs", "haskell"},
        {"hta", "hypertext"},
        {"htm", "hypertext"},
        {"html", "hypertext"},
        {"hws", "hollywood"},
        {"hxx", "cpp"},
        {"i", "visualprolog"},
        {"ilproj", "xml"},
        {"inc", "pascal"},
        {"inf", "props"},
        {"ini", "props"},
        {"ino", "cpp"},
        {"ipynb", "json"},
        {"iss", "inno"},
        {"itcl", "tcl"},
        {"java", "java"},
        {"jl", "julia"},
        {"js", "javascript"},
        {"jsm", "cpp"},
        {"json", "json"},
        {"json5", "json"},
        {"jsonc", "json"},
        {"jsp", "hypertext"},
        {"jsx", "javascript"},
        {"kix", "kix"},
        {"kml", "xml"},
        {"kt", "kotlin"},
        {"kts", "kotlin"},
        {"las", "haskell"},
        {"less", "css"},
        {"lex", "cpp"},
        {"lhs", "haskell"},
        {"lisp", "lisp"},
        {"litcoffee", "coffeescript"},
        {"lock", "toml"},
        {"lpr", "pascal"},
        {"lsp", "lisp"},
        {"lst", "cobol"},
        {"lua", "lua"},
        {"m", "matlab"},
        {"mak", "makefile"},
        {"makefile", "makefile"},
        {"markdown", "markdown"},
        {"md", "markdown"},
        {"mdown", "markdown"},
        {"mib", "asn1"},
        {"mjs", "javascript"},
        {"mk", "makefile"},
        {"ml", "caml"},
        {"mli", "caml"},
        {"mm", "objc"},
        {"mms", "mmixal"},
        {"mot", "srec"},
        {"mx", "cpp"},
        {"mxml", "xml"},
        {"mysql", "sql"},
        {"nfo", "nfo"},
        {"nim", "nim"},
        {"nsh", "nsis"},
        {"nsi", "nsis"},
        {"nt", "batch"},
        {"orc", "csound"},
        {"osx", "oscript"},
        {"out", "spice"},
        {"p", "pascal"},
        {"p6", "raku"},
        {"pack", "visualprolog"},
        {"pas", "pascal"},
        {"patch", "diff"},
        {"pb", "purebasic"},
        {"pgsql", "sql"},
        {"ph", "visualprolog"},
        {"php", "phpscript"},
        {"php3", "phpscript"},
        {"php4", "phpscript"},
        {"php5", "phpscript"},
        {"phps", "phpscript"},
        {"phpt", "phpscript"},
        {"phtml", "phpscript"},
        {"pl", "perl"},
        {"plist", "xml"},
        {"plx", "perl"},
        {"pm", "perl"},
        {"pm6", "raku"},
        {"pod6", "raku"},
        {"pp", "pascal"},
        {"pro", "visualprolog"},
        {"profile", "bash"},
        {"properties", "props"},
        {"proto", "cpp"},
        {"ps", "ps"},
        {"ps1", "powershell"},
        {"psd1", "powershell"},
        {"psm1", "powershell"},
        {"pxd", "python"},
        {"pxi", "python"},
        {"py", "python"},
        {"pyi", "python"},
        {"pyw", "python"},
        {"pyx", "python"},
        {"r", "r"},
        {"r2", "rebol"},
        {"r3", "rebol"},
        {"raku", "raku"},
        {"rakudoc", "raku"},
        {"rakumod", "raku"},
        {"rakutest", "raku"},
        {"rb", "ruby"},
        {"rbw", "ruby"},
        {"rc", "cpp"},
        {"reb", "rebol"},
        {"reg", "registry"},
        {"resx", "xml"},
        {"rlib", "rust"},
        {"rs", "rust"},
        {"s", "r"},
        {"sas", "sas"},
        {"sass", "css"},
        {"scm", "lisp"},
        {"sco", "csound"},
        {"scp", "spice"},
        {"scss", "css"},
        {"sh", "bash"},
        {"shtm", "hypertext"},
        {"shtml", "hypertext"},
        {"sitemap", "xml"},
        {"slnx", "xml"},
        {"smd", "lisp"},
        {"sml", "caml"},
        {"spf", "nncrontab"},
        {"splus", "r"},
        {"sql", "sql"},
        {"sqlite", "sql"},
        {"src", "escript"},
        {"srec", "srec"},
        {"ss", "lisp"},
        {"st", "smalltalk"},
        {"sty", "latex"},
        {"sv", "verilog"},
        {"svelte", "hypertext"},
        {"svg", "xml"},
        {"svh", "verilog"},
        {"swift", "swift"},
        {"sxbl", "xml"},
        {"t", "perl"},
        {"t2t", "txt2tags"},
        {"t6", "raku"},
        {"tab", "nncrontab"},
        {"targets", "xml"},
        {"tcl", "tcl"},
        {"tek", "tehex"},
        {"tex", "tex"},
        {"thy", "caml"},
        {"toml", "toml"},
        {"topojson", "json"},
        {"ts", "typescript"},
        {"tsql", "sql"},
        {"tsx", "typescript"},
        {"txt", "normal"},
        {"url", "props"},
        {"v", "verilog"},
        {"vb", "vb"},
        {"vba", "vb"},
        {"vbproj", "xml"},
        {"vbs", "vb"},
        {"vcproj", "xml"},
        {"vcxproj", "xml"},
        {"vh", "verilog"},
        {"vhd", "vhdl"},
        {"vhdl", "vhdl"},
        {"vue", "hypertext"},
        {"wer", "props"},
        {"wixproj", "xml"},
        {"wsdl", "xml"},
        {"wxs", "xml"},
        {"xaml", "xml"},
        {"xbl", "xml"},
        {"xht", "hypertext"},
        {"xhtml", "hypertext"},
        {"xlf", "xml"},
        {"xliff", "xml"},
        {"xml", "xml"},
        {"xsd", "xml"},
        {"xsl", "xml"},
        {"xslt", "xml"},
        {"xsml", "xml"},
        {"xul", "xml"},
        {"yaml", "yaml"},
        {"yml", "yaml"},
        {"zig", "zig"},
        {"zon", "zig"},
        {"zsh", "bash"},
    };

    auto it = s_extMap.find(ext);
    if (it != s_extMap.end()) return it->second;
    return "text";
}

- (void) configureLexerForActiveDocument {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[mActiveIndex];

    const char* lexerToCreate = doc.lexerName.c_str();
    if (doc.lexerName == "javascript" || doc.lexerName == "typescript" ||
        doc.lexerName == "java" || doc.lexerName == "csharp" ||
        doc.lexerName == "kotlin" || doc.lexerName == "swift" ||
        doc.lexerName == "actionscript" || doc.lexerName == "c" ||
        doc.lexerName == "objc" || doc.lexerName == "scala") {
        lexerToCreate = "cpp";
    } else if (doc.lexerName == "html" || doc.lexerName == "php" || doc.lexerName == "asp" || doc.lexerName == "jsp") {
        lexerToCreate = "hypertext";
    }

    Scintilla::ILexer5* pLexer = CreateLexer(lexerToCreate);
    if (pLexer) {
        [_editor setReferenceProperty: SCI_SETILEXER parameter: 0 value: pLexer];

        // Language-Specific Keywords
        if (doc.lexerName == "javascript") {
            const char* jsKeywords = "abstract arguments async await boolean break byte case catch char class const continue debugger default delete do double else enum eval export extends false final finally float for function get goto if implements import in instanceof int interface let long native new null of package private protected public return set short static super switch synchronized this throw throws transient true try typeof undefined var void volatile while with yield from as";
            pLexer->WordListSet(0, jsKeywords);
        } else if (doc.lexerName == "typescript") {
            const char* tsKeywords = "abstract any arguments as async await boolean break byte case catch char class const constructor continue debugger declare default delete do double else enum eval export extends false final finally float for from function get goto if implements import in infer instanceof int interface is keyof let long module namespace native never new null number object of override package private protected public readonly require return set short static string super switch symbol synchronized this throw throws transient true try type typeof undefined unique unknown var void volatile while with yield";
            pLexer->WordListSet(0, tsKeywords);
        } else if (doc.lexerName == "java") {
            const char* javaKeywords = "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null";
            pLexer->WordListSet(0, javaKeywords);
        } else if (doc.lexerName == "csharp") {
            const char* csKeywords = "abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly record ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while yield async await var";
            pLexer->WordListSet(0, csKeywords);
        } else if (doc.lexerName == "kotlin") {
            const char* ktKeywords = "as as? break class continue do else false for fun if in !in interface is !is null object package return super this throw true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam value where actual abstract annotation companion const crossinline data enum expect external final inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg";
            pLexer->WordListSet(0, ktKeywords);
        } else if (doc.lexerName == "swift") {
            const char* swiftKeywords = "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case continue default defer do else fallthrough for guard if in repeat return switch where while as Any catch false is nil rethrows self Self super throw throws true try actor async await isolated nonisolated some";
            pLexer->WordListSet(0, swiftKeywords);
        } else if (doc.lexerName == "c") {
            const char* cKeywords = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while _Alignas _Alignof _Atomic _Bool _Complex _Generic _Imaginary _Noreturn _Static_assert _Thread_local";
            pLexer->WordListSet(0, cKeywords);
        } else if (doc.lexerName == "cpp") {
            const char* cppKeywords = "alignas alignof and and_eq asm atomic_cancel atomic_commit atomic_noexcept auto bitand bitor bool break case catch char char8_t char16_t char32_t class compl concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit export extern false float for friend goto if inline int long mutable namespace new noexcept not not_eq nullptr operator or or_eq private protected public reflexpr register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid typename union unsigned using virtual void volatile wchar_t while xor xor_eq";
            pLexer->WordListSet(0, cppKeywords);
        } else if (doc.lexerName == "python") {
            const char* pyKeywords = "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case";
            pLexer->WordListSet(0, pyKeywords);
        } else if (doc.lexerName == "rust") {
            const char* rustKeywords = "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while";
            pLexer->WordListSet(0, rustKeywords);
        } else if (doc.lexerName == "go") {
            const char* goKeywords = "break default func interface select case defer go map struct chan else goto package switch const fallthrough if range type continue for import return var";
            pLexer->WordListSet(0, goKeywords);
        }
    } else {
        [_editor setReferenceProperty: SCI_SETILEXER parameter: 0 value: nullptr];
    }

    // Enable Code Folding properties for all Lexilla lexers (C++, XML, HTML, Python, JSON, SQL, etc.)
    [_editor setLexerProperty: @"fold" value: @"1"];
    [_editor setLexerProperty: @"fold.compact" value: @"1"];
    [_editor setLexerProperty: @"fold.comment" value: @"1"];
    [_editor setLexerProperty: @"fold.preprocessor" value: @"1"];
    [_editor setLexerProperty: @"fold.html" value: @"1"];
    [_editor setLexerProperty: @"fold.hypertext.comment" value: @"1"];
    [_editor setLexerProperty: @"fold.xml" value: @"1"];
    [_editor setLexerProperty: @"fold.sql" value: @"1"];
    [_editor setLexerProperty: @"fold.quotes.python" value: @"1"];
    [_editor setLexerProperty: @"fold.json" value: @"1"];

    // Adjust fold margin width: show 14px if lexer active, 0 if plain text
    BOOL isPlainText = (doc.lexerName == "text" || doc.lexerName.empty());
    [_editor message: SCI_SETMARGINWIDTHN wParam: 2 lParam: isPlainText ? 0 : 14];

    [self configureStylesForLexer: doc.lexerName];

    // Trigger full document colourise to immediately calculate fold levels and display [-] / [+] fold boxes
    [_editor message: SCI_COLOURISE wParam: 0 lParam: -1];
}

- (void) configureStylesForLexer: (const std::string&) lexer {
    [_editor suspendDrawing: YES];

    NSColor* commentCol = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.42 green: 0.72 blue: 0.42 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.00 green: 0.52 blue: 0.00 alpha: 1.0];
    NSColor* keywordCol = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.35 green: 0.72 blue: 0.98 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.00 green: 0.10 blue: 0.85 alpha: 1.0];
    NSColor* keyword2Col = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.80 green: 0.55 blue: 0.95 alpha: 1.0]
                                       : [NSColor colorWithCalibratedRed: 0.50 green: 0.15 blue: 0.75 alpha: 1.0];
    NSColor* stringCol  = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.92 green: 0.60 blue: 0.48 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.70 green: 0.15 blue: 0.15 alpha: 1.0];
    NSColor* numberCol  = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.98 green: 0.78 blue: 0.38 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.82 green: 0.42 blue: 0.00 alpha: 1.0];
    NSColor* opCol      = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.88 green: 0.88 blue: 0.88 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.10 green: 0.10 blue: 0.10 alpha: 1.0];
    NSColor* prepCol    = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.70 green: 0.50 blue: 0.90 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.55 green: 0.30 blue: 0.75 alpha: 1.0];
    NSColor* tagCol     = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.35 green: 0.75 blue: 0.98 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.00 green: 0.20 blue: 0.85 alpha: 1.0];
    NSColor* attrCol    = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.75 green: 0.55 blue: 0.95 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.60 green: 0.35 blue: 0.80 alpha: 1.0];
    NSColor* varCol     = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.85 green: 0.70 blue: 0.95 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.30 green: 0.20 blue: 0.60 alpha: 1.0];

    // Style numbers for C/C++/C#/Java/JS/TS/Rust/Go/Dart/Swift/PHP/Obj-C
    for (int style = 1; style <= 3; ++style) [_editor setColorProperty: SCI_STYLESETFORE parameter: style value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_WORD2 value: keyword2Col];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_CHARACTER value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_PREPROCESSOR value: prepCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_OPERATOR value: opCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_IDENTIFIER value: _isDarkMode ? [NSColor whiteColor] : [NSColor blackColor]];

    // Python / Ruby
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_COMMENTLINE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_COMMENTBLOCK value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_WORD2 value: keyword2Col];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_CHARACTER value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_OPERATOR value: opCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_IDENTIFIER value: _isDarkMode ? [NSColor whiteColor] : [NSColor blackColor]];

    // HTML / XML / ASP / JSP
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_TAG value: tagCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_TAGUNKNOWN value: tagCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_ATTRIBUTE value: attrCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_ATTRIBUTEUNKNOWN value: attrCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_DOUBLESTRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_SINGLESTRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_XMLSTART value: prepCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_XMLEND value: prepCol];

    // JSON
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_KEYWORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_PROPERTYNAME value: tagCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_LINECOMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_BLOCKCOMMENT value: commentCol];

    // CSS
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_CSS_TAG value: tagCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_CSS_CLASS value: keyword2Col];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_CSS_ID value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_CSS_ATTRIBUTE value: attrCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_CSS_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_CSS_VALUE value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_CSS_DIRECTIVE value: prepCol];

    // SQL
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_COMMENTLINE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_COMMENTDOC value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_CHARACTER value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_OPERATOR value: opCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_USER1 value: keyword2Col];

    // Bash / Shell / Batch / PowerShell / Props / YAML / TOML
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_COMMENTLINE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_CHARACTER value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_OPERATOR value: opCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_IDENTIFIER value: varCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SH_SCALAR value: varCol];

    // Batch
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_BAT_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_BAT_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_BAT_LABEL value: prepCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_BAT_HIDE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_BAT_COMMAND value: keyword2Col];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_BAT_IDENTIFIER value: varCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_BAT_OPERATOR value: opCol];

    // Props / INI
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_PROPS_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_PROPS_SECTION value: prepCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_PROPS_KEY value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_PROPS_ASSIGNMENT value: opCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_PROPS_DEFVAL value: stringCol];

    // YAML
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_YAML_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_YAML_IDENTIFIER value: tagCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_YAML_KEYWORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_YAML_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_YAML_TEXT value: stringCol];

    // TOML
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_TOML_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_TOML_KEY value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_TOML_STRING_SQ value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_TOML_STRING_DQ value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_TOML_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_TOML_TABLE value: prepCol];

    // Markdown
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MARKDOWN_HEADER1 value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MARKDOWN_HEADER2 value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MARKDOWN_HEADER3 value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MARKDOWN_CODE value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MARKDOWN_CODEBK value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MARKDOWN_LINK value: tagCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MARKDOWN_BLOCKQUOTE value: commentCol];

    // Lua
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_LUA_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_LUA_COMMENTLINE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_LUA_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_LUA_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_LUA_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_LUA_CHARACTER value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_LUA_OPERATOR value: opCol];

    // Diff
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_DIFF_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_DIFF_COMMAND value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_DIFF_HEADER value: prepCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_DIFF_POSITION value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_DIFF_DELETED value: [NSColor colorWithCalibratedRed: 0.85 green: 0.20 blue: 0.20 alpha: 1.0]];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_DIFF_ADDED value: [NSColor colorWithCalibratedRed: 0.15 green: 0.70 blue: 0.25 alpha: 1.0]];

    // Makefile
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MAKE_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MAKE_PREPROCESSOR value: prepCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MAKE_IDENTIFIER value: varCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MAKE_OPERATOR value: opCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_MAKE_TARGET value: keywordCol];
}

- (void) openFileAtPath: (NSString *) path {
    std::wstring wPath = utf8_to_wstring([path UTF8String]);

    for (size_t i = 0; i < mDocuments.size(); ++i) {
        if (mDocuments[i].filePath == wPath) {
            [self switchToDocumentAtIndex: i];
            return;
        }
    }

    std::ifstream file([path UTF8String], std::ios::binary);
    if (!file.is_open()) return;

    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    file.close();

    uchardet_t ud = uchardet_new();
    uchardet_handle_data(ud, content.data(), content.size());
    uchardet_data_end(ud);
    const char* charset = uchardet_get_charset(ud);
    uchardet_delete(ud);

    int enc = 0;
    if (content.size() >= 3 && (unsigned char)content[0] == 0xEF && (unsigned char)content[1] == 0xBB && (unsigned char)content[2] == 0xBF) {
        enc = 1;
    } else if (charset && strcmp(charset, "UTF-16LE") == 0) {
        enc = 2;
    } else if (charset && strcmp(charset, "UTF-16BE") == 0) {
        enc = 3;
    }

    int eol = 2;
    if (content.find("\r\n") != std::string::npos) eol = 0;
    else if (content.find('\r') != std::string::npos) eol = 1;

    NppDocument doc;
    doc.filePath = wPath;
    doc.title = utf8_to_wstring([[path lastPathComponent] UTF8String]);
    doc.isUntitled = false;
    doc.isModified = false;
    doc.isReadOnly = false;
    doc.encoding = enc;
    doc.eolMode = eol;
    doc.lexerName = [self detectLexerForPath: doc.filePath];

    void* pDoc = reinterpret_cast<void*>([_editor message: SCI_CREATEDOCUMENT wParam: 0 lParam: 0]);
    doc.pDoc = pDoc;

    if (mDocuments.size() == 1 && mDocuments[0].isUntitled && !mDocuments[0].isModified && [_editor message: SCI_GETLENGTH] == 0) {
        [_editor message: SCI_RELEASEDOCUMENT wParam: 0 lParam: reinterpret_cast<sptr_t>(mDocuments[0].pDoc)];
        mDocuments.clear();
    }

    mDocuments.push_back(doc);
    [self switchToDocumentAtIndex: mDocuments.size() - 1];

    [_editor setString: [NSString stringWithUTF8String: content.c_str()]];
    [_editor message: SCI_SETSAVEPOINT];
    doc.isModified = false;

    [self updateWindowTitle];
    [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
    [self updateStatusBar];
    [self saveSessionState];
}

- (void) saveDocumentAtIndex: (NSInteger) index promptIfUntitled: (BOOL) promptIfUntitled {
    if (index < 0 || index >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[index];

    // Untitled documents: route Save to the "Save As" dialog so the user picks the
    // location (defaults to the Left Explorer panel's folder when visible)
    if (promptIfUntitled && (doc.isUntitled || doc.filePath.empty())) {
        [self saveDocumentAsAtIndex: index];
        return;
    }

    // If doc has no filePath yet, auto-assign default path in active directory / Documents
    // (covers Save All on untitled tabs: promptIfUntitled==NO)
    if (doc.isUntitled || doc.filePath.empty()) {
        NSString* defaultDir = [self getDirectoryForActiveTab];
        if (!defaultDir || [defaultDir isEqualToString: NSHomeDirectory()]) {
            NSString* docsDir = [NSHomeDirectory() stringByAppendingPathComponent: @"Documents"];
            if ([[NSFileManager defaultManager] fileExistsAtPath: docsDir]) {
                defaultDir = docsDir;
            } else {
                defaultDir = NSHomeDirectory();
            }
        }
        NSString* titleStr = [NSString stringWithUTF8String: wstring_to_utf8(doc.title).c_str()];
        if (![titleStr containsString: @"."]) {
            titleStr = [titleStr stringByAppendingString: @".txt"];
        }
        NSString* autoPath = [defaultDir stringByAppendingPathComponent: titleStr];
        doc.filePath = utf8_to_wstring([autoPath UTF8String]);
        doc.isUntitled = false;
    }

    if (index == mActiveIndex && _editor) {
        NSString* text = [_editor string];
        std::string content = [text UTF8String];
        std::ofstream out(wstring_to_utf8(doc.filePath), std::ios::binary);
        if (out.is_open()) {
            if (doc.encoding == 1) {
                unsigned char bom[] = {0xEF, 0xBB, 0xBF};
                out.write(reinterpret_cast<char*>(bom), 3);
            }
            out.write(content.data(), content.size());
            out.close();
            doc.isModified = false;
            doc.cachedContent = content;
            [_editor message: SCI_SETSAVEPOINT];
        }
    } else {
        // Inactive document: retrieve content from pDoc or cachedContent
        if (doc.pDoc && _editor) {
            sptr_t curPos = [_editor message: SCI_GETCURRENTPOS];
            sptr_t firstLine = [_editor message: SCI_GETFIRSTVISIBLELINE];
            sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
            sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
            void* activePDoc = (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) ? mDocuments[mActiveIndex].pDoc : nullptr;

            [_editor message: SCI_SETDOCPOINTER wParam: 0 lParam: reinterpret_cast<sptr_t>(doc.pDoc)];
            sptr_t len = [_editor message: SCI_GETLENGTH];
            std::string content(static_cast<size_t>(len), '\x00');
            if (len > 0) {
                [_editor message: SCI_GETTEXT wParam: len + 1 lParam: reinterpret_cast<sptr_t>(content.data())];
            }

            std::ofstream out(wstring_to_utf8(doc.filePath), std::ios::binary);
            if (out.is_open()) {
                if (doc.encoding == 1) {
                    unsigned char bom[] = {0xEF, 0xBB, 0xBF};
                    out.write(reinterpret_cast<char*>(bom), 3);
                }
                if (len > 0) {
                    out.write(content.data(), content.size());
                }
                out.close();
                doc.isModified = false;
                doc.cachedContent = content;
                [_editor message: SCI_SETSAVEPOINT];
            }

            if (activePDoc) {
                [_editor message: SCI_SETDOCPOINTER wParam: 0 lParam: reinterpret_cast<sptr_t>(activePDoc)];
                [_editor message: SCI_SETCURRENTPOS wParam: curPos lParam: 0];
                [_editor message: SCI_SETSELECTIONSTART wParam: selStart lParam: 0];
                [_editor message: SCI_SETSELECTIONEND wParam: selEnd lParam: 0];
                [_editor message: SCI_SETFIRSTVISIBLELINE wParam: firstLine lParam: 0];
            }
        } else if (!doc.cachedContent.empty()) {
            std::ofstream out(wstring_to_utf8(doc.filePath), std::ios::binary);
            if (out.is_open()) {
                if (doc.encoding == 1) {
                    unsigned char bom[] = {0xEF, 0xBB, 0xBF};
                    out.write(reinterpret_cast<char*>(bom), 3);
                }
                out.write(doc.cachedContent.data(), doc.cachedContent.size());
                out.close();
                doc.isModified = false;
            }
        }
    }

    [self updateWindowTitle];
    [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
    [self updateStatusBar];
    [self saveSessionState];
}

- (void) saveDocumentAsAtIndex: (NSInteger) index {
    if (index < 0 || index >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[index];

    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.title = @"Save As";
    panel.nameFieldStringValue = [NSString stringWithUTF8String: wstring_to_utf8(doc.title).c_str()];
    // Open the dialog in the contextual base directory (Left Explorer folder when visible)
    NSString* baseDir = [self getDirectoryForActiveTab];
    if (baseDir && baseDir.length > 0) {
        panel.directoryURL = [NSURL fileURLWithPath: baseDir];
    }

    if ([panel runModal] == NSModalResponseOK) {
        NSURL* url = panel.URL;
        doc.filePath = utf8_to_wstring([url.path UTF8String]);
        doc.title = utf8_to_wstring([[url lastPathComponent] UTF8String]);
        doc.isUntitled = false;
        doc.lexerName = [self detectLexerForPath: doc.filePath];

        [self saveDocumentAtIndex: index promptIfUntitled: NO];
        [self configureLexerForActiveDocument];

        NSString* activeDir = [self getDirectoryForActiveTab];
        if (_rootContentView.isPrimarySidePanelVisible) [_primarySidePanel setDirectoryPath: activeDir];
        if (_rootContentView.isBottomPanelVisible) [_bottomPanel setWorkingDirectoryPath: activeDir];
    }
}

- (void) closeDocumentAtIndex: (NSInteger) index {
    if (index < 0 || index >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[index];

    if (doc.isModified) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat: @"Save changes to \"%s\"?", wstring_to_utf8(doc.title).c_str()];
        alert.informativeText = @"Your changes will be lost if you don't save them.";
        [alert addButtonWithTitle: @"Save"];
        [alert addButtonWithTitle: @"Don't Save"];
        [alert addButtonWithTitle: @"Cancel"];

        NSModalResponse res = [alert runModal];
        if (res == NSAlertFirstButtonReturn) {
            [self saveDocumentAtIndex: index promptIfUntitled: YES];
        } else if (res == NSAlertThirdButtonReturn) {
            return;
        }
    }

    if (doc.pDoc) {
        [_editor message: SCI_RELEASEDOCUMENT wParam: 0 lParam: reinterpret_cast<sptr_t>(doc.pDoc)];
    }

    mDocuments.erase(mDocuments.begin() + index);

    if (mDocuments.empty()) {
        [self newDocumentWithTitle: @"new 1"];
    } else {
        NSInteger newIndex = std::min(index, static_cast<NSInteger>(mDocuments.size() - 1));
        [self switchToDocumentAtIndex: newIndex];
    }
    [self saveSessionState];
}

// ============================================================================
// Delegates
// ============================================================================

- (void) tabSelectedAtIndex: (NSInteger) index { [self switchToDocumentAtIndex: index]; }

- (void) prevTab: (id) sender {
    if (mDocuments.empty()) return;
    NSInteger n = mDocuments.size();
    NSInteger next = (mActiveIndex - 1 + n) % n;
    [self switchToDocumentAtIndex: next];
}

- (void) nextTab: (id) sender {
    if (mDocuments.empty()) return;
    NSInteger n = mDocuments.size();
    NSInteger next = (mActiveIndex + 1) % n;
    [self switchToDocumentAtIndex: next];
}
- (void) tabClosedAtIndex: (NSInteger) index { [self closeDocumentAtIndex: index]; }
- (void) newTabRequested { [self newDocumentWithTitle: [NSString stringWithFormat: @"new %d", [self computeNextUntitledNumber]]]; }

- (void) tabContextMenuRequestedAtIndex: (NSInteger) index event: (NSEvent *) event {
    if (index < 0 || index >= static_cast<NSInteger>(mDocuments.size())) return;
    [self switchToDocumentAtIndex: index];

    NSMenu* menu = [[NSMenu alloc] initWithTitle: @"Tab Context"];
    auto addContextItem = [&](NSString* title, SEL action) {
        NSMenuItem* item = [menu addItemWithTitle: title action: action keyEquivalent: @""];
        item.target = self;
    };

    addContextItem(@"Close", @selector(closeTab:));
    addContextItem(@"Close All", @selector(closeAllDocuments:));
    addContextItem(@"Close All BUT This", @selector(closeAllButActive:));
    addContextItem(@"Close All to the Left", @selector(closeAllLeft:));
    addContextItem(@"Close All to the Right", @selector(closeAllRight:));
    [menu addItem: [NSMenuItem separatorItem]];
    addContextItem(@"Save", @selector(saveFile:));
    addContextItem(@"Save As...", @selector(saveFileAs:));
    addContextItem([self localizedString: @"file-rename" defaultText: @"Rename..."], @selector(renameCurrentFile:));
    [menu addItem: [NSMenuItem separatorItem]];
    addContextItem(@"Toggle Pin Tab", @selector(togglePinTab:));
    addContextItem(@"Reveal in Finder", @selector(revealInFinder:));
    addContextItem(@"Open in Terminal", @selector(openInTerminal:));
    addContextItem(@"Copy Full Path", @selector(copyFullPath:));

    [NSMenu popUpContextMenu: menu withEvent: event forView: _tabBar];
}

- (void) notification: (SCNotification *) notification {
    if (notification->nmhdr.code == SCN_DWELLSTART) {
        sptr_t pos = notification->position;
        if (pos >= 0) {
            sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: pos lParam: 0];
            sptr_t foldLevel = [_editor message: SCI_GETFOLDLEVEL wParam: line lParam: 0];
            BOOL isFoldHeader = (foldLevel & SC_FOLDLEVELHEADERFLAG) != 0;
            BOOL isExpanded = ([_editor message: SCI_GETFOLDEXPANDED wParam: line lParam: 0] != 0);

            if (isFoldHeader && !isExpanded) {
                // Show folded block preview in 2x large CallTip balloon!
                sptr_t endLine = [_editor message: SCI_GETLASTCHILD wParam: line lParam: -1];
                std::string previewText = "📖 Folded Block Preview:\n";
                for (sptr_t l = line + 1; l <= endLine && l <= line + 6; ++l) {
                    sptr_t lineLen = [_editor message: SCI_LINELENGTH wParam: l lParam: 0];
                    if (lineLen > 0) {
                        std::vector<char> buf(lineLen + 1, 0);
                        [_editor message: SCI_GETLINE wParam: l lParam: reinterpret_cast<sptr_t>(buf.data())];
                        previewText += "  " + std::string(buf.data());
                    }
                }
                if (endLine > line + 6) previewText += "  ...\n";
                [_editor message: SCI_CALLTIPSHOW wParam: pos lParam: reinterpret_cast<sptr_t>(previewText.c_str())];
            }
        }
    } else if (notification->nmhdr.code == SCN_DWELLEND) {
        [_editor message: SCI_CALLTIPCANCEL];
    } else if (notification->nmhdr.code == SCN_MODIFIED) {
        if (notification->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) {
            BOOL modified = ([_editor message: SCI_GETMODIFY] != 0);
            if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
                if (mDocuments[mActiveIndex].isModified != modified) {
                    mDocuments[mActiveIndex].isModified = modified;
                    [self updateWindowTitle];
                    [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
                    [self updateStatusBar];
                }
            }
            // State Guard (React Native PR #56082 principle):
            // Do NOT churn session disk serialization or preview rendering during tentative IME composition
            if (![_editor hasMarkedText]) {
                [self updateLivePreviewForActiveDocument];
                [self saveSessionState];
            }
        }
    } else if (notification->nmhdr.code == SCN_UPDATEUI) {
        [self updateStatusBar];

        // State Guard: Only calculate brace highlight when not in the middle of active IME composition
        if (_matchBraces && ![_editor hasMarkedText]) {
            sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
            sptr_t bracePos = [_editor message: SCI_BRACEMATCH wParam: pos - 1 lParam: 0];
            if (bracePos != -1) {
                [_editor message: SCI_BRACEHIGHLIGHT wParam: pos - 1 lParam: bracePos];
            } else {
                bracePos = [_editor message: SCI_BRACEMATCH wParam: pos lParam: 0];
                if (bracePos != -1) {
                    [_editor message: SCI_BRACEHIGHLIGHT wParam: pos lParam: bracePos];
                } else {
                    [_editor message: SCI_BRACEBADLIGHT wParam: -1 lParam: 0];
                }
            }
        }
    } else if (notification->nmhdr.code == SCN_MACRORECORD) {
        if (mIsRecordingMacro) {
            MacroStep step;
            step.msg = notification->message;
            step.wParam = notification->wParam;
            step.lParam = notification->lParam;
            step.textParam = "";
            // Messages that carry string in lParam
            if (notification->message == SCI_ADDTEXT || notification->message == SCI_INSERTTEXT ||
                notification->message == SCI_REPLACESEL || notification->message == SCI_APPENDTEXT ||
                notification->message == SCI_SETSEL || notification->message == SCI_SETTEXT) {
                if (notification->lParam != 0) {
                    const char* txt = reinterpret_cast<const char*>(notification->lParam);
                    if (txt) step.textParam = txt;
                }
            }
            mRecordedMacro.push_back(step);
            _statusBar.statusText = [NSString stringWithFormat: @"REC ● %lu steps", (unsigned long)mRecordedMacro.size()];
            [_statusBar setNeedsDisplay: YES];
        }
    } else if (notification->nmhdr.code == SCN_MARGINCLICK) {
        if (notification->margin == 2) {
            sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: notification->position];
            [_editor message: SCI_TOGGLEFOLD wParam: line lParam: 0];
        } else if (notification->margin == 1) {
            sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: notification->position];
            sptr_t markers = [_editor message: SCI_MARKERGET wParam: line lParam: 0];
            if (markers & (1 << 1)) {
                [_editor message: SCI_MARKERDELETE wParam: line lParam: 1];
            } else {
                [_editor message: SCI_MARKERADD wParam: line lParam: 1];
            }
        }
    }
}

// ============================================================================
// Find, Replace & Mark Delegate Implementation
// ============================================================================

- (void) findNext: (NSString *) query matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    if (!query || query.length == 0) return;

    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;
    if (ww) flags |= SCFIND_WHOLEWORD;
    if (regex) flags |= (SCFIND_REGEXP | SCFIND_CXX11REGEX);

    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];

    sptr_t curPos = [_editor message: SCI_GETSELECTIONEND];
    sptr_t docLength = [_editor message: SCI_GETLENGTH];

    [_editor message: SCI_SETTARGETSTART wParam: curPos lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];

    const char* q = [query UTF8String];
    sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];

    if (pos == -1) {
        sptr_t wrapEnd = [_editor message: SCI_GETSELECTIONSTART];
        [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: wrapEnd lParam: 0];
        pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];
    }

    if (pos != -1) {
        sptr_t tStart = [_editor message: SCI_GETTARGETSTART];
        sptr_t tEnd = [_editor message: SCI_GETTARGETEND];
        sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: tStart lParam: 0];
        [_editor message: SCI_ENSUREVISIBLE wParam: line lParam: 0];
        [_editor message: SCI_SETSEL wParam: tStart lParam: tEnd];
        [_editor message: SCI_SCROLLCARET];
        _statusBar.statusText = [NSString stringWithFormat: @"Found match at line %ld, pos %ld", (long)(line + 1), (long)tStart];
        [_statusBar setNeedsDisplay: YES];
    } else {
        NSBeep();
        _statusBar.statusText = [NSString stringWithFormat: @"Cannot find \"%@\"", query];
        [_statusBar setNeedsDisplay: YES];
    }
}

- (void) findPrev: (NSString *) query matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    if (!query || query.length == 0) return;

    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;
    if (ww) flags |= SCFIND_WHOLEWORD;
    if (regex) flags |= (SCFIND_REGEXP | SCFIND_CXX11REGEX);

    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];

    sptr_t curPos = [_editor message: SCI_GETSELECTIONSTART];

    [_editor message: SCI_SETTARGETSTART wParam: curPos lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: 0 lParam: 0];

    const char* q = [query UTF8String];
    sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];

    if (pos == -1) {
        sptr_t docLength = [_editor message: SCI_GETLENGTH];
        sptr_t wrapStart = [_editor message: SCI_GETSELECTIONEND];
        [_editor message: SCI_SETTARGETSTART wParam: docLength lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: wrapStart lParam: 0];
        pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];
    }

    if (pos != -1) {
        sptr_t tStart = [_editor message: SCI_GETTARGETSTART];
        sptr_t tEnd = [_editor message: SCI_GETTARGETEND];
        sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: tStart lParam: 0];
        [_editor message: SCI_ENSUREVISIBLE wParam: line lParam: 0];
        [_editor message: SCI_SETSEL wParam: tStart lParam: tEnd];
        [_editor message: SCI_SCROLLCARET];
        _statusBar.statusText = [NSString stringWithFormat: @"Found match at line %ld, pos %ld", (long)(line + 1), (long)tStart];
        [_statusBar setNeedsDisplay: YES];
    } else {
        NSBeep();
        _statusBar.statusText = [NSString stringWithFormat: @"Cannot find \"%@\"", query];
        [_statusBar setNeedsDisplay: YES];
    }
}

- (void) replaceOne: (NSString *) query withText: (NSString *) rep matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    if (!query || query.length == 0) return;

    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];

    if (selEnd > selStart) {
        int flags = 0;
        if (mc) flags |= SCFIND_MATCHCASE;
        if (ww) flags |= SCFIND_WHOLEWORD;
        if (regex) flags |= (SCFIND_REGEXP | SCFIND_CXX11REGEX);

        [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];
        [_editor message: SCI_SETTARGETSTART wParam: selStart lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: selEnd lParam: 0];

        const char* q = [query UTF8String];
        sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];
        if (pos == selStart && [_editor message: SCI_GETTARGETEND] == selEnd) {
            const char* r = [rep UTF8String];
            [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>(r)];
        }
    }
    [self findNext: query matchCase: mc wholeWord: ww isRegex: regex];
}

- (void) replaceAll: (NSString *) query withText: (NSString *) rep matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    if (!query || query.length == 0) return;

    [_editor message: SCI_BEGINUNDOACTION];

    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;
    if (ww) flags |= SCFIND_WHOLEWORD;
    if (regex) flags |= (SCFIND_REGEXP | SCFIND_CXX11REGEX);

    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];

    sptr_t docLength = [_editor message: SCI_GETLENGTH];
    [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];

    const char* q = [query UTF8String];
    const char* r = [rep UTF8String];
    size_t qLen = strlen(q);
    size_t rLen = strlen(r);

    int count = 0;
    while ([_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)] != -1) {
        sptr_t tStart = [_editor message: SCI_GETTARGETSTART];
        sptr_t tEnd = [_editor message: SCI_GETTARGETEND];
        if (tEnd <= tStart) {
            [_editor message: SCI_SETTARGETSTART wParam: tEnd + 1 lParam: 0];
            [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];
            if (tEnd + 1 >= docLength) break;
            continue;
        }
        [_editor message: SCI_REPLACETARGET wParam: rLen lParam: reinterpret_cast<sptr_t>(r)];
        sptr_t targetEnd = [_editor message: SCI_GETTARGETEND];
        docLength = [_editor message: SCI_GETLENGTH];
        [_editor message: SCI_SETTARGETSTART wParam: targetEnd lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];
        count++;
    }

    [_editor message: SCI_ENDUNDOACTION];

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Replace All";
    alert.informativeText = [NSString stringWithFormat: @"Replaced %d occurrence(s).", count];
    [alert runModal];
}

- (void) markAll: (NSString *) query matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    if (!query || query.length == 0) return;

    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;
    if (ww) flags |= SCFIND_WHOLEWORD;
    if (regex) flags |= (SCFIND_REGEXP | SCFIND_CXX11REGEX);

    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];

    sptr_t docLength = [_editor message: SCI_GETLENGTH];
    [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];

    const char* q = [query UTF8String];
    size_t qLen = strlen(q);

    int count = 0;
    while ([_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)] != -1) {
        sptr_t tStart = [_editor message: SCI_GETTARGETSTART];
        sptr_t tEnd = [_editor message: SCI_GETTARGETEND];
        if (tEnd <= tStart) {
            [_editor message: SCI_SETTARGETSTART wParam: tEnd + 1 lParam: 0];
            [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];
            if (tEnd + 1 >= docLength) break;
            continue;
        }
        sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: tStart lParam: 0];
        [_editor message: SCI_MARKERADD wParam: line lParam: 1];

        [_editor message: SCI_SETTARGETSTART wParam: tEnd lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];
        count++;
    }

    _statusBar.statusText = [NSString stringWithFormat: @"Marked %d match(es)", count];
    [_statusBar setNeedsDisplay: YES];
}

- (void) closeFindBar {
    if (_findReplaceWindowController && _findReplaceWindowController.window) {
        [_findReplaceWindowController.window performClose: nil];
    }
}

// ============================================================================
// Actions & Menu Handlers
// ============================================================================

- (void) newFile: (id) sender { [self newTabRequested]; }

- (void) openFile: (id) sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;

    if ([panel runModal] == NSModalResponseOK) {
        for (NSURL* url in panel.URLs) {
            [self openFileAtPath: url.path];
        }
    }
}

- (void) reloadFromDisk: (id) sender {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        if (!doc.isUntitled) {
            NSString* path = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
            std::ifstream file([path UTF8String], std::ios::binary);
            if (file.is_open()) {
                std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
                file.close();
                [_editor setString: [NSString stringWithUTF8String: content.c_str()]];
                [_editor message: SCI_SETSAVEPOINT];
                mDocuments[mActiveIndex].isModified = false;
                [self updateWindowTitle];
                [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
            }
        }
    }
}

- (void) saveFile: (id) sender { [self saveDocumentAtIndex: mActiveIndex promptIfUntitled: YES]; }
- (void) saveFileAs: (id) sender { [self saveDocumentAsAtIndex: mActiveIndex]; }
- (void) saveAllFiles: (id) sender {
    if (mDocuments.empty()) return;

    for (size_t i = 0; i < mDocuments.size(); ++i) {
        [self saveDocumentAtIndex: i promptIfUntitled: NO];
    }

    [self updateWindowTitle];
    [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
    [self updateStatusBar];
    [self saveSessionState];
}
- (void) closeTab: (id) sender { [self closeDocumentAtIndex: mActiveIndex]; }
- (void) closeAllDocuments: (id) sender {
    while (!mDocuments.empty() && !(mDocuments.size() == 1 && mDocuments[0].isUntitled)) {
        [self closeDocumentAtIndex: 0];
    }
}
- (void) closeAllButActive: (id) sender {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    void* targetDocPtr = mDocuments[mActiveIndex].pDoc;
    while (mDocuments.size() > 1) {
        NSInteger closeIdx = -1;
        for (NSInteger i = 0; i < static_cast<NSInteger>(mDocuments.size()); ++i) {
            if (mDocuments[i].pDoc != targetDocPtr) {
                closeIdx = i;
                break;
            }
        }
        if (closeIdx == -1) break;
        size_t prevCount = mDocuments.size();
        [self closeDocumentAtIndex: closeIdx];
        if (mDocuments.size() == prevCount) break; // User canceled save prompt
    }
}
- (void) closeAllLeft: (id) sender {
    if (mActiveIndex <= 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    void* targetDocPtr = mDocuments[mActiveIndex].pDoc;
    while (!mDocuments.empty()) {
        NSInteger targetIdx = -1;
        for (NSInteger i = 0; i < static_cast<NSInteger>(mDocuments.size()); ++i) {
            if (mDocuments[i].pDoc == targetDocPtr) {
                targetIdx = i;
                break;
            }
        }
        if (targetIdx <= 0) break; // No tabs to the left
        size_t prevCount = mDocuments.size();
        [self closeDocumentAtIndex: 0];
        if (mDocuments.size() == prevCount) break; // User canceled save prompt
    }
}
- (void) closeAllRight: (id) sender {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    void* targetDocPtr = mDocuments[mActiveIndex].pDoc;
    while (!mDocuments.empty()) {
        NSInteger targetIdx = -1;
        for (NSInteger i = 0; i < static_cast<NSInteger>(mDocuments.size()); ++i) {
            if (mDocuments[i].pDoc == targetDocPtr) {
                targetIdx = i;
                break;
            }
        }
        if (targetIdx == -1 || targetIdx >= static_cast<NSInteger>(mDocuments.size()) - 1) break; // No tabs to the right
        size_t prevCount = mDocuments.size();
        [self closeDocumentAtIndex: targetIdx + 1];
        if (mDocuments.size() == prevCount) break; // User canceled save prompt
    }
}
- (void) tabMovedFromIndex: (NSInteger) fromIndex toIndex: (NSInteger) toIndex {
    if (fromIndex == toIndex || fromIndex < 0 || toIndex < 0 ||
        fromIndex >= static_cast<NSInteger>(mDocuments.size()) ||
        toIndex >= static_cast<NSInteger>(mDocuments.size())) {
        return;
    }

    NppDocument doc = mDocuments[fromIndex];
    mDocuments.erase(mDocuments.begin() + fromIndex);
    mDocuments.insert(mDocuments.begin() + toIndex, doc);

    if (mActiveIndex == fromIndex) {
        mActiveIndex = toIndex;
    } else if (fromIndex < mActiveIndex && toIndex >= mActiveIndex) {
        mActiveIndex--;
    } else if (fromIndex > mActiveIndex && toIndex <= mActiveIndex) {
        mActiveIndex++;
    }

    [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
    [self updateWindowTitle];
    [self saveSessionState];
}

- (void) togglePinTab: (id) sender {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        mDocuments[mActiveIndex].isPinned = !mDocuments[mActiveIndex].isPinned;

        // Smart Pin grouping: Keep pinned tabs grouped at the front
        NppDocument activeDoc = mDocuments[mActiveIndex];
        std::vector<NppDocument> pinnedDocs;
        std::vector<NppDocument> unpinnedDocs;
        NSInteger newActiveIndex = 0;

        for (size_t i = 0; i < mDocuments.size(); ++i) {
            if (mDocuments[i].isPinned) {
                if (static_cast<NSInteger>(i) == mActiveIndex) {
                    newActiveIndex = static_cast<NSInteger>(pinnedDocs.size());
                }
                pinnedDocs.push_back(mDocuments[i]);
            } else {
                if (static_cast<NSInteger>(i) == mActiveIndex) {
                    newActiveIndex = static_cast<NSInteger>(pinnedDocs.size() + unpinnedDocs.size());
                }
                unpinnedDocs.push_back(mDocuments[i]);
            }
        }

        mDocuments.clear();
        mDocuments.insert(mDocuments.end(), pinnedDocs.begin(), pinnedDocs.end());
        mDocuments.insert(mDocuments.end(), unpinnedDocs.begin(), unpinnedDocs.end());
        if (newActiveIndex >= 0 && newActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
            mActiveIndex = newActiveIndex;
        }

        [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
        [self saveSessionState];
    }
}

- (void) renameCurrentFile: (id) sender {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument &doc = mDocuments[mActiveIndex];
    // If the document is untitled, fall back to Save As dialog
    if (doc.isUntitled) {
        [self saveDocumentAsAtIndex: mActiveIndex];
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [self localizedString: @"rename-file-title" defaultText: @"Rename File"];
    alert.informativeText = [self localizedString: @"rename-file-prompt" defaultText: @"Enter new filename:"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.stringValue = [NSString stringWithUTF8String:wstring_to_utf8(doc.title).c_str()];
    alert.accessoryView = input;
    [alert addButtonWithTitle: @"Rename"];
    [alert addButtonWithTitle: @"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString* newTitle = input.stringValue;
        if (newTitle.length > 0) {
            doc.title = utf8_to_wstring([newTitle UTF8String]);
            [self updateWindowTitle];
            [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
        }
    }
}

- (void) revealInFinder: (id) sender {
    NSString* targetPath = nil;
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        if (!doc.isUntitled && !doc.filePath.empty()) {
            targetPath = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
        }
    }
    if (targetPath && [[NSFileManager defaultManager] fileExistsAtPath: targetPath]) {
        [[NSWorkspace sharedWorkspace] selectFile: targetPath inFileViewerRootedAtPath: @""];
    } else {
        NSString* dir = [self getDirectoryForActiveTab];
        [[NSWorkspace sharedWorkspace] openURL: [NSURL fileURLWithPath: dir]];
    }
}

- (void) openInTerminal: (id) sender {
    [self toggleBottomPanel: sender];
}

- (void) copyFullPath: (id) sender {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        NSString* path = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
        NSPasteboard* pboard = [NSPasteboard generalPasteboard];
        [pboard clearContents];
        [pboard setString: path forType: NSPasteboardTypeString];
    }
}

- (void) copyFilename: (id) sender {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        NSString* name = [NSString stringWithUTF8String: wstring_to_utf8(doc.title).c_str()];
        NSPasteboard* pboard = [NSPasteboard generalPasteboard];
        [pboard clearContents];
        [pboard setString: name forType: NSPasteboardTypeString];
    }
}

- (void) copyDirectoryPath: (id) sender {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        NSString* path = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
        NSString* dir = [path stringByDeletingLastPathComponent];
        NSPasteboard* pboard = [NSPasteboard generalPasteboard];
        [pboard clearContents];
        [pboard setString: dir forType: NSPasteboardTypeString];
    }
}

- (void) sortLinesAscending: (id) sender {
    sptr_t currentPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t currentLine = [_editor message: SCI_LINEFROMPOSITION wParam: currentPos];
    sptr_t firstVisible = [_editor message: SCI_GETFIRSTVISIBLELINE];

    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *>* sorted = [lines mutableCopy];
    [sorted sortUsingSelector: @selector(localizedCaseInsensitiveCompare:)];

    NSString* resultText = [sorted componentsJoinedByString: @"\n"];
    [_editor message: SCI_BEGINUNDOACTION];
    [_editor message: SCI_TARGETWHOLEDOCUMENT];
    const char* utf8Str = [resultText UTF8String];
    [_editor message: SCI_REPLACETARGET wParam: strlen(utf8Str) lParam: reinterpret_cast<sptr_t>(utf8Str)];
    [_editor message: SCI_ENDUNDOACTION];

    sptr_t maxLines = [_editor message: SCI_GETLINECOUNT];
    sptr_t targetLine = MIN(currentLine, MAX(0, maxLines - 1));
    sptr_t targetPos = [_editor message: SCI_POSITIONFROMLINE wParam: targetLine];
    [_editor message: SCI_SETCURRENTPOS wParam: targetPos lParam: 0];
    [_editor message: SCI_SETSELECTION wParam: targetPos lParam: targetPos];
    [_editor message: SCI_SETFIRSTVISIBLELINE wParam: firstVisible];
    [_editor message: SCI_SCROLLCARET];
}

- (void) sortLinesDescending: (id) sender {
    sptr_t currentPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t currentLine = [_editor message: SCI_LINEFROMPOSITION wParam: currentPos];
    sptr_t firstVisible = [_editor message: SCI_GETFIRSTVISIBLELINE];

    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *>* sorted = [lines mutableCopy];
    [sorted sortUsingComparator: ^NSComparisonResult(id obj1, id obj2) {
        return [obj2 localizedCaseInsensitiveCompare: obj1];
    }];

    NSString* resultText = [sorted componentsJoinedByString: @"\n"];
    [_editor message: SCI_BEGINUNDOACTION];
    [_editor message: SCI_TARGETWHOLEDOCUMENT];
    const char* utf8Str = [resultText UTF8String];
    [_editor message: SCI_REPLACETARGET wParam: strlen(utf8Str) lParam: reinterpret_cast<sptr_t>(utf8Str)];
    [_editor message: SCI_ENDUNDOACTION];

    sptr_t maxLines = [_editor message: SCI_GETLINECOUNT];
    sptr_t targetLine = MIN(currentLine, MAX(0, maxLines - 1));
    sptr_t targetPos = [_editor message: SCI_POSITIONFROMLINE wParam: targetLine];
    [_editor message: SCI_SETCURRENTPOS wParam: targetPos lParam: 0];
    [_editor message: SCI_SETSELECTION wParam: targetPos lParam: targetPos];
    [_editor message: SCI_SETFIRSTVISIBLELINE wParam: firstVisible];
    [_editor message: SCI_SCROLLCARET];
}

- (void) removeDuplicateLines: (id) sender {
    sptr_t currentPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t currentLine = [_editor message: SCI_LINEFROMPOSITION wParam: currentPos];
    sptr_t firstVisible = [_editor message: SCI_GETFIRSTVISIBLELINE];

    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *>* unique = [NSMutableArray array];
    NSMutableSet<NSString *>* seen = [NSMutableSet set];
    for (NSString* line in lines) {
        if (![seen containsObject: line]) {
            [seen addObject: line];
            [unique addObject: line];
        }
    }

    NSString* resultText = [unique componentsJoinedByString: @"\n"];
    [_editor message: SCI_BEGINUNDOACTION];
    [_editor message: SCI_TARGETWHOLEDOCUMENT];
    const char* utf8Str = [resultText UTF8String];
    [_editor message: SCI_REPLACETARGET wParam: strlen(utf8Str) lParam: reinterpret_cast<sptr_t>(utf8Str)];
    [_editor message: SCI_ENDUNDOACTION];

    sptr_t maxLines = [_editor message: SCI_GETLINECOUNT];
    sptr_t targetLine = MIN(currentLine, MAX(0, maxLines - 1));
    sptr_t targetPos = [_editor message: SCI_POSITIONFROMLINE wParam: targetLine];
    [_editor message: SCI_SETCURRENTPOS wParam: targetPos lParam: 0];
    [_editor message: SCI_SETSELECTION wParam: targetPos lParam: targetPos];
    [_editor message: SCI_SETFIRSTVISIBLELINE wParam: firstVisible];
    [_editor message: SCI_SCROLLCARET];
}

- (void) removeEmptyLines: (id) sender {
    sptr_t currentPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t currentLine = [_editor message: SCI_LINEFROMPOSITION wParam: currentPos];
    sptr_t firstVisible = [_editor message: SCI_GETFIRSTVISIBLELINE];

    [_editor message: SCI_BEGINUNDOACTION];
    sptr_t lineCount = [_editor message: SCI_GETLINECOUNT];
    sptr_t removedBeforeCurrent = 0;

    for (sptr_t i = lineCount - 1; i >= 0; --i) {
        sptr_t lineStart = [_editor message: SCI_POSITIONFROMLINE wParam: i];
        sptr_t lineEnd = [_editor message: SCI_GETLINEENDPOSITION wParam: i];
        if (lineStart == lineEnd) {
            sptr_t nextLineStart = (i + 1 < lineCount) ? [_editor message: SCI_POSITIONFROMLINE wParam: i + 1] : [_editor message: SCI_GETLENGTH];
            sptr_t deleteLen = nextLineStart - lineStart;
            if (deleteLen > 0) {
                [_editor message: SCI_DELETERANGE wParam: lineStart lParam: deleteLen];
                if (i < currentLine) removedBeforeCurrent++;
            }
        }
    }
    [_editor message: SCI_ENDUNDOACTION];

    sptr_t targetLine = MAX(0, currentLine - removedBeforeCurrent);
    sptr_t targetPos = [_editor message: SCI_POSITIONFROMLINE wParam: targetLine];
    [_editor message: SCI_SETCURRENTPOS wParam: targetPos lParam: 0];
    [_editor message: SCI_SETSELECTION wParam: targetPos lParam: targetPos];
    [_editor message: SCI_SETFIRSTVISIBLELINE wParam: MAX(0, firstVisible - removedBeforeCurrent)];
    [_editor message: SCI_SCROLLCARET];
}

- (void) removeEmptyLinesWithBlank: (id) sender {
    sptr_t currentPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t currentLine = [_editor message: SCI_LINEFROMPOSITION wParam: currentPos];
    sptr_t firstVisible = [_editor message: SCI_GETFIRSTVISIBLELINE];

    [_editor message: SCI_BEGINUNDOACTION];
    sptr_t lineCount = [_editor message: SCI_GETLINECOUNT];
    sptr_t removedBeforeCurrent = 0;

    for (sptr_t i = lineCount - 1; i >= 0; --i) {
        sptr_t lineStart = [_editor message: SCI_POSITIONFROMLINE wParam: i];
        sptr_t lineEnd = [_editor message: SCI_GETLINEENDPOSITION wParam: i];
        sptr_t lineLen = lineEnd - lineStart;
        BOOL isBlank = YES;
        if (lineLen > 0) {
            std::vector<char> buf(lineLen + 1, 0);
            [_editor message: SCI_GETLINE wParam: i lParam: reinterpret_cast<sptr_t>(buf.data())];
            for (sptr_t b = 0; b < lineLen; ++b) {
                char c = buf[b];
                if (c != ' ' && c != '\t' && c != '\r' && c != '\n') {
                    isBlank = NO;
                    break;
                }
            }
        }
        if (isBlank) {
            sptr_t nextLineStart = (i + 1 < lineCount) ? [_editor message: SCI_POSITIONFROMLINE wParam: i + 1] : [_editor message: SCI_GETLENGTH];
            sptr_t deleteLen = nextLineStart - lineStart;
            if (deleteLen > 0) {
                [_editor message: SCI_DELETERANGE wParam: lineStart lParam: deleteLen];
                if (i < currentLine) removedBeforeCurrent++;
            }
        }
    }
    [_editor message: SCI_ENDUNDOACTION];

    sptr_t targetLine = MAX(0, currentLine - removedBeforeCurrent);
    sptr_t targetPos = [_editor message: SCI_POSITIONFROMLINE wParam: targetLine];
    [_editor message: SCI_SETCURRENTPOS wParam: targetPos lParam: 0];
    [_editor message: SCI_SETSELECTION wParam: targetPos lParam: targetPos];
    [_editor message: SCI_SETFIRSTVISIBLELINE wParam: MAX(0, firstVisible - removedBeforeCurrent)];
    [_editor message: SCI_SCROLLCARET];
}

- (void) joinLines: (id) sender {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selStart == selEnd) {
        sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: selStart];
        sptr_t maxLine = [_editor message: SCI_GETLINECOUNT];
        if (line + 1 < maxLine) {
            sptr_t startPos = [_editor message: SCI_POSITIONFROMLINE wParam: line];
            sptr_t endPos = [_editor message: SCI_GETLINEENDPOSITION wParam: line + 1];
            [_editor message: SCI_SETSEL wParam: startPos lParam: endPos];
        }
    }
    [_editor message: SCI_LINESJOIN];
}

- (void) splitLines: (id) sender {
    sptr_t width = [_editor message: SCI_GETEDGECOLUMN];
    if (width <= 0) width = 80;
    [_editor message: SCI_LINESSPLIT wParam: width lParam: 0];
}

- (void) toggleFoldCurrentLevel: (id) sender {
    sptr_t curPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: curPos];
    [_editor message: SCI_TOGGLEFOLD wParam: line lParam: 0];
}

- (void) moveLineUp: (id) sender { [_editor message: SCI_MOVESELECTEDLINESUP]; }
- (void) moveLineDown: (id) sender { [_editor message: SCI_MOVESELECTEDLINESDOWN]; }

- (void) trimTrailingSpace: (id) sender {
    sptr_t currentPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t currentLine = [_editor message: SCI_LINEFROMPOSITION wParam: currentPos];
    sptr_t firstVisible = [_editor message: SCI_GETFIRSTVISIBLELINE];

    [_editor message: SCI_BEGINUNDOACTION];
    sptr_t lineCount = [_editor message: SCI_GETLINECOUNT];

    for (sptr_t i = lineCount - 1; i >= 0; --i) {
        sptr_t lineStart = [_editor message: SCI_POSITIONFROMLINE wParam: i];
        sptr_t lineEnd = [_editor message: SCI_GETLINEENDPOSITION wParam: i];
        sptr_t len = lineEnd - lineStart;
        if (len > 0) {
            std::vector<char> buf(len + 1, 0);
            [_editor message: SCI_GETLINE wParam: i lParam: reinterpret_cast<sptr_t>(buf.data())];

            sptr_t trimLen = 0;
            for (sptr_t b = len - 1; b >= 0; --b) {
                char c = buf[b];
                if (c == ' ' || c == '\t') {
                    trimLen++;
                } else {
                    break;
                }
            }
            if (trimLen > 0) {
                [_editor message: SCI_DELETERANGE wParam: lineEnd - trimLen lParam: trimLen];
            }
        }
    }
    [_editor message: SCI_ENDUNDOACTION];

    sptr_t targetPos = [_editor message: SCI_POSITIONFROMLINE wParam: currentLine];
    [_editor message: SCI_SETCURRENTPOS wParam: targetPos lParam: 0];
    [_editor message: SCI_SETSELECTION wParam: targetPos lParam: targetPos];
    [_editor message: SCI_SETFIRSTVISIBLELINE wParam: firstVisible];
    [_editor message: SCI_SCROLLCARET];
}

- (void) trimLeadingSpace: (id) sender {
    sptr_t currentPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t currentLine = [_editor message: SCI_LINEFROMPOSITION wParam: currentPos];
    sptr_t firstVisible = [_editor message: SCI_GETFIRSTVISIBLELINE];

    [_editor message: SCI_BEGINUNDOACTION];
    sptr_t lineCount = [_editor message: SCI_GETLINECOUNT];

    for (sptr_t i = lineCount - 1; i >= 0; --i) {
        sptr_t lineStart = [_editor message: SCI_POSITIONFROMLINE wParam: i];
        sptr_t lineEnd = [_editor message: SCI_GETLINEENDPOSITION wParam: i];
        sptr_t len = lineEnd - lineStart;
        if (len > 0) {
            std::vector<char> buf(len + 1, 0);
            [_editor message: SCI_GETLINE wParam: i lParam: reinterpret_cast<sptr_t>(buf.data())];

            sptr_t trimLen = 0;
            for (sptr_t b = 0; b < len; ++b) {
                char c = buf[b];
                if (c == ' ' || c == '\t') {
                    trimLen++;
                } else {
                    break;
                }
            }
            if (trimLen > 0) {
                [_editor message: SCI_DELETERANGE wParam: lineStart lParam: trimLen];
            }
        }
    }
    [_editor message: SCI_ENDUNDOACTION];

    sptr_t targetPos = [_editor message: SCI_POSITIONFROMLINE wParam: currentLine];
    [_editor message: SCI_SETCURRENTPOS wParam: targetPos lParam: 0];
    [_editor message: SCI_SETSELECTION wParam: targetPos lParam: targetPos];
    [_editor message: SCI_SETFIRSTVISIBLELINE wParam: firstVisible];
    [_editor message: SCI_SCROLLCARET];
}

- (void) insertDateTimeShort: (id) sender {
    NSDateFormatter* fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat: @"yyyy-MM-dd HH:mm"];
    NSString* str = [fmt stringFromDate: [NSDate date]];
    [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>([str UTF8String])];
}

- (void) insertDateTimeLong: (id) sender {
    NSDateFormatter* fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat: @"EEEE, MMMM d, yyyy h:mm:ss a"];
    NSString* str = [fmt stringFromDate: [NSDate date]];
    [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>([str UTF8String])];
}

- (std::string) getSelectionOrFullText {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd > selStart) {
        std::vector<char> buf(selEnd - selStart + 1, 0);
        [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
        return std::string(buf.data());
    }
    return std::string([[_editor string] UTF8String]);
}

- (void) generateMD5: (id) sender {
    std::string text = [self getSelectionOrFullText];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(text.data(), (CC_LONG)text.size(), digest);
    char hex[CC_MD5_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; ++i) snprintf(hex + i * 2, 3, "%02x", digest[i]);

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"MD5 Hash Result";
    alert.informativeText = [NSString stringWithFormat: @"MD5: %s\n\n(Copied to clipboard)", hex];
    [alert addButtonWithTitle: @"OK"];

    NSPasteboard* pboard = [NSPasteboard generalPasteboard];
    [pboard clearContents];
    [pboard setString: [NSString stringWithUTF8String: hex] forType: NSPasteboardTypeString];
    [alert runModal];
}

- (void) generateSHA256: (id) sender {
    std::string text = [self getSelectionOrFullText];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(text.data(), (CC_LONG)text.size(), digest);
    char hex[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) snprintf(hex + i * 2, 3, "%02x", digest[i]);

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"SHA-256 Hash Result";
    alert.informativeText = [NSString stringWithFormat: @"SHA-256: %s\n\n(Copied to clipboard)", hex];
    [alert addButtonWithTitle: @"OK"];

    NSPasteboard* pboard = [NSPasteboard generalPasteboard];
    [pboard clearContents];
    [pboard setString: [NSString stringWithUTF8String: hex] forType: NSPasteboardTypeString];
    [alert runModal];
}

- (void) base64EncodeSelection: (id) sender {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd <= selStart) return;

    std::vector<char> buf(selEnd - selStart + 1, 0);
    [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
    NSData* data = [NSData dataWithBytes: buf.data() length: strlen(buf.data())];
    NSString* b64 = [data base64EncodedStringWithOptions: 0];
    [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>([b64 UTF8String])];
}

- (void) base64DecodeSelection: (id) sender {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd <= selStart) return;

    std::vector<char> buf(selEnd - selStart + 1, 0);
    [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
    NSString* nsStr = [NSString stringWithUTF8String: buf.data()];
    NSData* data = [[NSData alloc] initWithBase64EncodedString: nsStr options: NSDataBase64DecodingIgnoreUnknownCharacters];
    if (data) {
        NSString* decoded = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
        if (decoded) [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>([decoded UTF8String])];
    }
}

- (void) urlEncodeSelection: (id) sender {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd <= selStart) return;

    std::vector<char> buf(selEnd - selStart + 1, 0);
    [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
    NSString* str = [NSString stringWithUTF8String: buf.data()];
    NSString* enc = [str stringByAddingPercentEncodingWithAllowedCharacters: [NSCharacterSet URLQueryAllowedCharacterSet]];
    if (enc) [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>([enc UTF8String])];
}

- (void) urlDecodeSelection: (id) sender {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd <= selStart) return;

    std::vector<char> buf(selEnd - selStart + 1, 0);
    [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
    NSString* str = [NSString stringWithUTF8String: buf.data()];
    NSString* dec = [str stringByRemovingPercentEncoding];
    if (dec) [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>([dec UTF8String])];
}

- (void) toggleMacroRecording: (id) sender {
    mIsRecordingMacro = !mIsRecordingMacro;
    if (mIsRecordingMacro) {
        mRecordedMacro.clear();
        [_editor message: SCI_STARTRECORD];
        _statusBar.statusText = @"Macro Recording: ON";
    } else {
        [_editor message: SCI_STOPRECORD];
        _statusBar.statusText = [NSString stringWithFormat: @"Macro Recording: OFF (%lu steps)", (unsigned long)mRecordedMacro.size()];
    }
    [self updateStatusBar];
}

- (void) startMacroRecording: (id) sender {
    if (!mIsRecordingMacro) [self toggleMacroRecording: sender];
}
- (void) stopMacroRecording: (id) sender {
    if (mIsRecordingMacro) [self toggleMacroRecording: sender];
}

- (void) playbackMacro: (id) sender {
    if (mRecordedMacro.empty()) { NSBeep(); _statusBar.statusText = @"No macro recorded"; [_statusBar setNeedsDisplay: YES]; return; }
    [_editor message: SCI_BEGINUNDOACTION];
    for (const auto& step : mRecordedMacro) {
        if (!step.textParam.empty()) {
            [_editor message: step.msg wParam: step.wParam lParam: reinterpret_cast<sptr_t>(step.textParam.c_str())];
        } else {
            [_editor message: step.msg wParam: step.wParam lParam: step.lParam];
        }
    }
    [_editor message: SCI_ENDUNDOACTION];
    _statusBar.statusText = [NSString stringWithFormat: @"Played %lu macro step(s)", (unsigned long)mRecordedMacro.size()];
    [_statusBar setNeedsDisplay: YES];
}

- (void) saveRecordedMacro: (id) sender {
    if (mRecordedMacro.empty()) { NSBeep(); [self showAlert: @"No macro to save" info: @"Record a macro first (Macro → Start Recording)"]; return; }
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Save Macro";
    alert.informativeText = [NSString stringWithFormat: @"%lu steps. Enter macro name:", (unsigned long)mRecordedMacro.size()];
    [alert addButtonWithTitle: @"Save"];
    [alert addButtonWithTitle: @"Cancel"];
    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 280, 24)];
    input.placeholderString = @"MyMacro";
    alert.accessoryView = input;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString* name = [input.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) name = [NSString stringWithFormat: @"macro_%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSString* safeName = [[name componentsSeparatedByCharactersInSet: [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString: @"_"];
    NSString* dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent: @"Notepad++/macros"];
    [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: nil];
    NSString* path = [dir stringByAppendingPathComponent: [safeName stringByAppendingPathExtension: @"json"]];
    NSMutableArray* arr = [NSMutableArray array];
    for (auto &s : mRecordedMacro) {
        [arr addObject: @{ @"msg": @(s.msg), @"wParam": @(s.wParam), @"lParam": @(s.lParam), @"text": [NSString stringWithUTF8String: s.textParam.c_str()] }];
    }
    NSData* data = [NSJSONSerialization dataWithJSONObject: arr options: NSJSONWritingPrettyPrinted error: nil];
    [data writeToFile: path atomically: YES];
    _statusBar.statusText = [NSString stringWithFormat: @"Macro \"%@\" saved (%lu steps) → %@", name, (unsigned long)mRecordedMacro.size(), path.lastPathComponent];
    [_statusBar setNeedsDisplay: YES];
    NSAlert* done = [[NSAlert alloc] init];
    done.messageText = @"Macro Saved";
    done.informativeText = [NSString stringWithFormat: @"Saved to %@\n%lu steps", path, (unsigned long)mRecordedMacro.size()];
    [done runModal];
}

- (void) runMacroMultipleTimes: (id) sender {
    if (mRecordedMacro.empty()) { NSBeep(); [self showAlert: @"No macro" info: @"Record a macro first"]; return; }
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Run Macro Multiple Times";
    alert.informativeText = @"Repeat count:";
    [alert addButtonWithTitle: @"Run"];
    [alert addButtonWithTitle: @"Cancel"];
    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 200, 24)];
    input.stringValue = @"3";
    alert.accessoryView = input;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSInteger n = [input.stringValue integerValue];
    if (n < 1) n = 1; if (n > 999) n = 999;
    [_editor message: SCI_BEGINUNDOACTION];
    for (NSInteger i = 0; i < n; ++i) {
        for (const auto& step : mRecordedMacro) {
            if (!step.textParam.empty()) {
                [_editor message: step.msg wParam: step.wParam lParam: reinterpret_cast<sptr_t>(step.textParam.c_str())];
            } else {
                [_editor message: step.msg wParam: step.wParam lParam: step.lParam];
            }
        }
    }
    [_editor message: SCI_ENDUNDOACTION];
    _statusBar.statusText = [NSString stringWithFormat: @"Ran macro %ld× (%lu steps each)", (long)n, (unsigned long)mRecordedMacro.size()];
    [_statusBar setNeedsDisplay: YES];
}

- (void) showAlert: (NSString *) title info: (NSString *) info {
    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = title; a.informativeText = info ?: @"";
    [a addButtonWithTitle: @"OK"];
    [a runModal];
}

- (NSString *) expandRunVariables: (NSString *) cmd {
    NSString* out = cmd ?: @"";
    // Document vars
    NSString* fullPath = @"";
    NSString* curDir = NSHomeDirectory();
    NSString* fileName = @"";
    NSString* namePart = @"";
    NSString* extPart = @"";
    if (mActiveIndex >= 0 && mActiveIndex < (NSInteger)mDocuments.size()) {
        const NppDocument& d = mDocuments[mActiveIndex];
        if (!d.isUntitled && d.filePath.length() > 0) {
            fullPath = [NSString stringWithUTF8String: wstring_to_utf8(d.filePath).c_str()];
            curDir = [fullPath stringByDeletingLastPathComponent];
            fileName = [fullPath lastPathComponent];
            namePart = [fileName stringByDeletingPathExtension];
            extPart = [fileName pathExtension];
        } else {
            NSString* title = [NSString stringWithUTF8String: wstring_to_utf8(d.title).c_str()];
            fileName = title; namePart = [title stringByDeletingPathExtension]; extPart = [title pathExtension];
            curDir = [self getDirectoryForActiveTab];
        }
    }
    NSString* nppDir = [[NSBundle mainBundle] bundlePath] ?: @"/Applications/Notepad++.app";
    // Editor vars
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: pos] + 1;
    sptr_t col = [_editor message: SCI_GETCOLUMN wParam: pos] + 1;
    // CURRENT_WORD
    sptr_t ws = [_editor message: SCI_WORDSTARTPOSITION wParam: pos lParam: 1];
    sptr_t we = [_editor message: SCI_WORDENDPOSITION wParam: pos lParam: 1];
    NSString* curWord = @"";
    if (we > ws && we - ws < 512) {
        std::vector<char> buf(we - ws + 1, 0);
        Sci_TextRangeFull tr; tr.chrg.cpMin = ws; tr.chrg.cpMax = we; tr.lpstrText = buf.data();
        [_editor message: SCI_GETTEXTRANGEFULL wParam: 0 lParam: reinterpret_cast<sptr_t>(&tr)];
        curWord = [NSString stringWithUTF8String: buf.data()] ?: @"";
    }
    NSDictionary* vars = @{
        @"$(FULL_CURRENT_PATH)": fullPath,
        @"$(CURRENT_DIRECTORY)": curDir,
        @"$(FILE_NAME)": fileName,
        @"$(NAME_PART)": namePart,
        @"$(EXT_PART)": extPart,
        @"$(NPP_DIRECTORY)": nppDir,
        @"$(CURRENT_WORD)": curWord,
        @"$(CURRENT_LINE)": [NSString stringWithFormat: @"%ld", (long)line],
        @"$(CURRENT_COLUMN)": [NSString stringWithFormat: @"%ld", (long)col],
    };
    for (NSString* k in vars) out = [out stringByReplacingOccurrencesOfString: k withString: vars[k]];
    return out;
}

- (void) runCommand: (id) sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Run...";
    alert.informativeText = @"Command (variables: $(FULL_CURRENT_PATH) $(CURRENT_DIRECTORY) $(FILE_NAME) $(NAME_PART) $(EXT_PART) $(NPP_DIRECTORY) $(CURRENT_WORD) $(CURRENT_LINE) $(CURRENT_COLUMN)):";
    [alert addButtonWithTitle: @"Run"];
    [alert addButtonWithTitle: @"Cancel"];
    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 420, 24)];
    input.placeholderString = @"e.g. python3 \"$(FULL_CURRENT_PATH)\"  or  open \"$(CURRENT_DIRECTORY)\"";
    alert.accessoryView = input;
    // Use a larger alert by embedding input in a view — fallback to simple
    NSModalResponse resp = [alert runModal];
    if (resp != NSAlertFirstButtonReturn) return;
    NSString* raw = [input.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) { NSBeep(); return; }
    NSString* expanded = [self expandRunVariables: raw];
    _statusBar.statusText = [NSString stringWithFormat: @"Run: %@", expanded];
    [_statusBar setNeedsDisplay: YES];
    // Execute via zsh -c
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask* task = [[NSTask alloc] init];
        task.launchPath = @"/bin/zsh";
        task.arguments = @[@"-c", expanded];
        task.currentDirectoryPath = [self getDirectoryForActiveTab];
        NSPipe* pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = pipe;
        @try {
            [task launch]; [task waitUntilExit];
            NSData* d = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString* out = [[NSString alloc] initWithData: d encoding: NSUTF8StringEncoding];
            if (out.length > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSAlert* a = [[NSAlert alloc] init];
                    a.messageText = @"Run Output";
                    a.informativeText = [out substringToIndex: MIN(out.length, 2000)];
                    [a addButtonWithTitle: @"OK"];
                    if (out.length > 2000) {
                        NSPasteboard* pb = [NSPasteboard generalPasteboard]; [pb clearContents]; [pb setString: out forType: NSPasteboardTypeString];
                        a.informativeText = [a.informativeText stringByAppendingString: @"\n\n(Full output copied to clipboard)"];
                    }
                    [a runModal];
                });
            }
        } @catch (NSException* e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showAlert: @"Run failed" info: e.reason];
            });
        }
    });
}

- (void) validateShortcuts: (id) sender {
    NSString* path = [[NSBundle mainBundle] pathForResource: @"shortcuts" ofType: @"xml"];
    if (!path) path = [NSString stringWithFormat: @"%@/PowerEditor/src/shortcuts.xml", [[NSBundle mainBundle] bundlePath]];
    // Fallback: check known locations
    NSArray* candidates = @[
        [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Application Support/Notepad++/shortcuts.xml"],
        @"PowerEditor/src/shortcuts.xml"
    ];
    for (NSString* c in candidates) if ([[NSFileManager defaultManager] fileExistsAtPath: c]) { path = c; break; }
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath: path]) {
        [self showAlert: @"Validate shortcuts.xml" info: @"shortcuts.xml not found — no custom shortcuts to validate (using defaults)."]; return;
    }
    pugi::xml_document doc;
    pugi::xml_parse_result r = doc.load_file([path UTF8String]);
    if (r) {
        [self showAlert: @"Validate shortcuts.xml" info: [NSString stringWithFormat: @"OK: %@ parsed successfully", path.lastPathComponent]];
    } else {
        [self showAlert: @"Validate shortcuts.xml" info: [NSString stringWithFormat: @"Parse error at offset %ld: %s", (long)r.offset, r.description()]];
    }
}

- (void) showSummaryDialog: (id) sender {
    NSString* text = [_editor string];
    NSUInteger totalChars = text.length;
    NSUInteger totalBytes = [text lengthOfBytesUsingEncoding: NSUTF8StringEncoding];
    sptr_t totalLines = [_editor message: SCI_GETLINECOUNT];

    NSArray* words = [text componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUInteger wordCount = 0;
    NSUInteger nonSpaceChars = 0;
    for (NSString* w in words) if (w.length > 0) wordCount++;
    for (NSUInteger i = 0; i < totalChars; ++i) {
        if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: [text characterAtIndex: i]]) {
            nonSpaceChars++;
        }
    }

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Document Summary";
    alert.informativeText = [NSString stringWithFormat:
        @"Characters (total):  %lu\n"
        @"Characters (no spaces): %lu\n"
        @"Words:  %lu\n"
        @"Lines:  %ld\n"
        @"Document size:  %lu bytes",
        (unsigned long)totalChars, (unsigned long)nonSpaceChars, (unsigned long)wordCount, (long)totalLines, (unsigned long)totalBytes];
    [alert addButtonWithTitle: @"OK"];
    [alert runModal];
}

- (void) toggleShowAllCharacters: (id) sender {
    _showWhiteSpace = !_showWhiteSpace;
    _showEOL = _showWhiteSpace;
    [self applyAllSettings];
}

- (void) toggleIndentGuides: (id) sender {
    _showIndentGuides = !_showIndentGuides;
    [self applyAllSettings];
}

- (void) foldAll: (id) sender { [_editor message: SCI_FOLDALL wParam: SC_FOLDACTION_CONTRACT lParam: 0]; }
- (void) unfoldAll: (id) sender { [_editor message: SCI_FOLDALL wParam: SC_FOLDACTION_EXPAND lParam: 0]; }

- (void) showFind: (id) sender {
    [_findReplaceWindowController showFindWindow];
}

- (void) showReplace: (id) sender {
    [_findReplaceWindowController showReplaceWindow];
}

- (void) openFindBar: (id) s { [self showFind: s]; }
- (void) openReplaceBar: (id) s { [self showReplace: s]; }

- (void) onFindNext: (id) sender {
    [_findReplaceWindowController onFindNext: sender];
}

- (void) onFindPrev: (id) sender {
    [_findReplaceWindowController onFindPrev: sender];
}

- (void) useSelectionForFind: (id) sender {
    NSString* pat = nil;
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd > selStart && selEnd - selStart < 512) {
        std::vector<char> buf(selEnd - selStart + 1, 0);
        [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
        pat = [NSString stringWithUTF8String: buf.data()];
    } else {
        sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
        sptr_t ws = [_editor message: SCI_WORDSTARTPOSITION wParam: pos lParam: 1];
        sptr_t we = [_editor message: SCI_WORDENDPOSITION wParam: pos lParam: 1];
        if (we > ws && we - ws < 512) {
            std::vector<char> buf(we - ws + 1, 0);
            Sci_TextRangeFull tr; tr.chrg.cpMin = ws; tr.chrg.cpMax = we; tr.lpstrText = buf.data();
            [_editor message: SCI_GETTEXTRANGEFULL wParam: 0 lParam: reinterpret_cast<sptr_t>(&tr)];
            pat = [NSString stringWithUTF8String: buf.data()];
        }
    }
    if (!pat || pat.length == 0) { NSBeep(); _statusBar.statusText = @"Use Selection for Find: no word/selection"; [_statusBar setNeedsDisplay: YES]; return; }
    [_findReplaceWindowController setSearchPattern: pat];
    _statusBar.statusText = [NSString stringWithFormat: @"Find pattern set: \"%@\"", pat];
    [_statusBar setNeedsDisplay: YES];
}

- (void) goToLine: (id) sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Go to Line";
    sptr_t maxLine = [_editor message: SCI_GETLINECOUNT];
    alert.informativeText = [NSString stringWithFormat: @"Enter line number (1 - %ld):", (long)maxLine];

    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 200, 24)];
    sptr_t curLine = [_editor message: SCI_LINEFROMPOSITION wParam: [_editor message: SCI_GETCURRENTPOS]] + 1;
    input.stringValue = [NSString stringWithFormat: @"%ld", (long)curLine];
    alert.accessoryView = input;

    [alert addButtonWithTitle: @"Go"];
    [alert addButtonWithTitle: @"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger targetLine = [input.stringValue integerValue];
        if (targetLine >= 1 && targetLine <= maxLine) {
            [_editor message: SCI_GOTOLINE wParam: targetLine - 1 lParam: 0];
            [_editor message: SCI_SCROLLCARET];
        }
    }
}

- (void) goToMatchingBrace: (id) sender {
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t bracePos = [_editor message: SCI_BRACEMATCH wParam: pos - 1 lParam: 0];
    if (bracePos == -1) bracePos = [_editor message: SCI_BRACEMATCH wParam: pos lParam: 0];
    if (bracePos != -1) {
        [_editor message: SCI_GOTOPOS wParam: bracePos lParam: 0];
        [_editor message: SCI_SCROLLCARET];
    }
}

- (void) toggleBookmark: (id) sender {
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: pos];
    sptr_t markers = [_editor message: SCI_MARKERGET wParam: line lParam: 0];
    if (markers & (1 << 1)) [_editor message: SCI_MARKERDELETE wParam: line lParam: 1];
    else [_editor message: SCI_MARKERADD wParam: line lParam: 1];
}

- (void) nextBookmark: (id) sender {
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: pos];
    sptr_t next = [_editor message: SCI_MARKERNEXT wParam: line + 1 lParam: 1 << 1];
    if (next == -1) next = [_editor message: SCI_MARKERNEXT wParam: 0 lParam: 1 << 1];
    if (next != -1) {
        [_editor message: SCI_GOTOLINE wParam: next lParam: 0];
        [_editor message: SCI_SCROLLCARET];
    }
}

- (void) prevBookmark: (id) sender {
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: pos];
    sptr_t prev = [_editor message: SCI_MARKERPREVIOUS wParam: line - 1 lParam: 1 << 1];
    if (prev == -1) {
        sptr_t maxLine = [_editor message: SCI_GETLINECOUNT];
        prev = [_editor message: SCI_MARKERPREVIOUS wParam: maxLine lParam: 1 << 1];
    }
    if (prev != -1) {
        [_editor message: SCI_GOTOLINE wParam: prev lParam: 0];
        [_editor message: SCI_SCROLLCARET];
    }
}

- (void) clearAllBookmarks: (id) sender { [_editor message: SCI_MARKERDELETEALL wParam: 1 lParam: 0]; }

// ---------------------------------------------------------------
// Search Style Indicators (SCE_UNIVERSAL_FOUND_STYLE_* 21..25,31)
// 5-color Mark — replicates Notepad++ Search → Mark All / Style One Token
// ---------------------------------------------------------------
- (NSString *) currentStyleSearchPattern {
    // 1) Find window query takes precedence
    if (_findReplaceWindowController && _findReplaceWindowController.findField.stringValue.length > 0) {
        NSString* q = [_findReplaceWindowController.findField.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (q.length > 0) return q;
    }
    // 2) Current selection
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd > selStart && selEnd - selStart < 512) {
        sptr_t len = selEnd - selStart;
        std::vector<char> buf(len + 1, 0);
        [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
        NSString* sel = [NSString stringWithUTF8String: buf.data()];
        if (sel.length > 0) return sel;
    }
    // 3) Word at caret
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t ws = [_editor message: SCI_WORDSTARTPOSITION wParam: pos lParam: 1];
    sptr_t we = [_editor message: SCI_WORDENDPOSITION wParam: pos lParam: 1];
    if (we > ws) {
        sptr_t len = we - ws;
        std::vector<char> buf(len + 1, 0);
        [_editor message: SCI_GETTEXT wParam: len + 1 lParam: reinterpret_cast<sptr_t>(buf.data())];
        Sci_TextRangeFull tr; tr.chrg.cpMin = ws; tr.chrg.cpMax = we; tr.lpstrText = buf.data();
        [_editor message: SCI_GETTEXTRANGEFULL wParam: 0 lParam: reinterpret_cast<sptr_t>(&tr)];
        NSString* w = [NSString stringWithUTF8String: buf.data()];
        if (w.length > 0) return w;
    }
    return @"";
}

- (void) applyIndicatorToAll: (int) indic pattern: (NSString *) pat flags: (int) flags {
    if (!pat || pat.length == 0) { NSBeep(); _statusBar.statusText = @"Style: empty search pattern"; [_statusBar setNeedsDisplay: YES]; return; }
    const char* q = [pat UTF8String]; size_t qLen = strlen(q);
    if (qLen == 0) { NSBeep(); return; }
    sptr_t docLen = [_editor message: SCI_GETLENGTH];
    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];
    [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
    int count = 0;
    [_editor message: SCI_SETINDICATORCURRENT wParam: indic lParam: 0];
    while ([_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)] != -1) {
        sptr_t s = [_editor message: SCI_GETTARGETSTART];
        sptr_t e = [_editor message: SCI_GETTARGETEND];
        if (e <= s) {
            [_editor message: SCI_SETTARGETSTART wParam: e + 1 lParam: 0];
            [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
            if (e + 1 >= docLen) break;
            continue;
        }
        [_editor message: SCI_INDICATORFILLRANGE wParam: s lParam: e - s];
        [_editor message: SCI_SETTARGETSTART wParam: e lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
        count++;
        if (count > 5000) break;
    }
    _statusBar.statusText = [NSString stringWithFormat: @"Style %d: %d match(es) for \"%@\"", indic - 20, count, pat];
    [_statusBar setNeedsDisplay: YES];
}

- (void) styleAllUsingIndicator: (int) indic {
    NSString* pat = [self currentStyleSearchPattern];
    int flags = 0;
    if (_findReplaceWindowController) {
        if (_findReplaceWindowController.matchCaseCheck.state == NSControlStateValueOn) flags |= SCFIND_MATCHCASE;
        if (_findReplaceWindowController.wholeWordCheck.state == NSControlStateValueOn) flags |= SCFIND_WHOLEWORD;
        if (_findReplaceWindowController.regexCheck.state == NSControlStateValueOn) flags |= SCFIND_REGEXP;
    }
    [self applyIndicatorToAll: indic pattern: pat flags: flags];
}

- (void) styleOneUsingIndicator: (int) indic {
    NSString* pat = [self currentStyleSearchPattern];
    if (!pat || pat.length == 0) { NSBeep(); return; }
    const char* q = [pat UTF8String]; size_t qLen = strlen(q);
    sptr_t cur = [_editor message: SCI_GETCURRENTPOS];
    sptr_t docLen = [_editor message: SCI_GETLENGTH];
    int flags = 0;
    if (_findReplaceWindowController) {
        if (_findReplaceWindowController.matchCaseCheck.state == NSControlStateValueOn) flags |= SCFIND_MATCHCASE;
        if (_findReplaceWindowController.wholeWordCheck.state == NSControlStateValueOn) flags |= SCFIND_WHOLEWORD;
        if (_findReplaceWindowController.regexCheck.state == NSControlStateValueOn) flags |= SCFIND_REGEXP;
    }
    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];
    [_editor message: SCI_SETTARGETSTART wParam: cur lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
    sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)];
    if (pos == -1) { // wrap
        [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: cur lParam: 0];
        pos = [_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)];
    }
    if (pos != -1) {
        sptr_t s = [_editor message: SCI_GETTARGETSTART];
        sptr_t e = [_editor message: SCI_GETTARGETEND];
        [_editor message: SCI_SETINDICATORCURRENT wParam: indic lParam: 0];
        [_editor message: SCI_INDICATORFILLRANGE wParam: s lParam: e - s];
        [_editor message: SCI_SETSEL wParam: s lParam: e];
        [_editor message: SCI_SCROLLCARET];
        _statusBar.statusText = [NSString stringWithFormat: @"Style %d: marked one \"%@\"", indic - 20, pat];
        [_statusBar setNeedsDisplay: YES];
    } else {
        NSBeep(); _statusBar.statusText = [NSString stringWithFormat: @"Not found: \"%@\"", pat]; [_statusBar setNeedsDisplay: YES];
    }
}

- (void) clearIndicator: (int) indic {
    sptr_t len = [_editor message: SCI_GETLENGTH];
    [_editor message: SCI_SETINDICATORCURRENT wParam: indic lParam: 0];
    [_editor message: SCI_INDICATORCLEARRANGE wParam: 0 lParam: len];
    _statusBar.statusText = [NSString stringWithFormat: @"Style %d cleared", indic - 20];
    [_statusBar setNeedsDisplay: YES];
}

- (void) clearAllIndicators: (id) sender {
    sptr_t len = [_editor message: SCI_GETLENGTH];
    for (int indic = 21; indic <= 25; ++indic) {
        [_editor message: SCI_SETINDICATORCURRENT wParam: indic lParam: 0];
        [_editor message: SCI_INDICATORCLEARRANGE wParam: 0 lParam: len];
    }
    [_editor message: SCI_SETINDICATORCURRENT wParam: SCE_UNIVERSAL_FOUND_STYLE lParam: 0];
    [_editor message: SCI_INDICATORCLEARRANGE wParam: 0 lParam: len];
    _statusBar.statusText = @"All styles cleared";
    [_statusBar setNeedsDisplay: YES];
}

// Menu wrappers (tag = indicator id or style number)
- (void) markAllExt1: (id) s { [self styleAllUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT1]; }
- (void) markAllExt2: (id) s { [self styleAllUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT2]; }
- (void) markAllExt3: (id) s { [self styleAllUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT3]; }
- (void) markAllExt4: (id) s { [self styleAllUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT4]; }
- (void) markAllExt5: (id) s { [self styleAllUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT5]; }
- (void) markOneExt1: (id) s { [self styleOneUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT1]; }
- (void) markOneExt2: (id) s { [self styleOneUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT2]; }
- (void) markOneExt3: (id) s { [self styleOneUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT3]; }
- (void) markOneExt4: (id) s { [self styleOneUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT4]; }
- (void) markOneExt5: (id) s { [self styleOneUsingIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT5]; }
- (void) unmarkExt1: (id) s { [self clearIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT1]; }
- (void) unmarkExt2: (id) s { [self clearIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT2]; }
- (void) unmarkExt3: (id) s { [self clearIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT3]; }
- (void) unmarkExt4: (id) s { [self clearIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT4]; }
- (void) unmarkExt5: (id) s { [self clearIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT5]; }

- (void) goNextMarkExt1: (id) s { [self goNextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT1]; }
- (void) goNextMarkExt2: (id) s { [self goNextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT2]; }
- (void) goNextMarkExt3: (id) s { [self goNextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT3]; }
- (void) goNextMarkExt4: (id) s { [self goNextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT4]; }
- (void) goNextMarkExt5: (id) s { [self goNextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT5]; }
- (void) goPrevMarkExt1: (id) s { [self goPrevForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT1]; }
- (void) goPrevMarkExt2: (id) s { [self goPrevForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT2]; }
- (void) goPrevMarkExt3: (id) s { [self goPrevForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT3]; }
- (void) goPrevMarkExt4: (id) s { [self goPrevForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT4]; }
- (void) goPrevMarkExt5: (id) s { [self goPrevForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT5]; }

- (void) goNextForIndicator: (int) indic {
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t len = [_editor message: SCI_GETLENGTH];
    sptr_t cur = pos + 1;
    if (cur >= len) cur = 0;
    // skip current if already inside indicator
    if ([_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: cur] != 0) {
        cur = [_editor message: SCI_INDICATOREND wParam: indic lParam: cur];
    }
    // linear scan for next filled range (cap to avoid O(n^2))
    for (sptr_t p = cur; p < len; ) {
        if ([_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: p] != 0) {
            sptr_t s = [_editor message: SCI_INDICATORSTART wParam: indic lParam: p];
            sptr_t e = [_editor message: SCI_INDICATOREND wParam: indic lParam: p];
            [_editor message: SCI_GOTOPOS wParam: s lParam: 0];
            [_editor message: SCI_SETSEL wParam: s lParam: e];
            [_editor message: SCI_SCROLLCARET];
            return;
        }
        // advance: if gap, jump to next possible indicator start via incremental search
        // Fallback naive +1
        p++;
        if (p - cur > 200000) break;
    }
    // wrap to start
    for (sptr_t p = 0; p < cur && p < len; ++p) {
        if ([_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: p] != 0) {
            sptr_t s = [_editor message: SCI_INDICATORSTART wParam: indic lParam: p];
            sptr_t e = [_editor message: SCI_INDICATOREND wParam: indic lParam: p];
            [_editor message: SCI_GOTOPOS wParam: s lParam: 0];
            [_editor message: SCI_SETSEL wParam: s lParam: e];
            [_editor message: SCI_SCROLLCARET];
            return;
        }
    }
    NSBeep(); _statusBar.statusText = [NSString stringWithFormat: @"No Style %d marks", indic - 20];
    [_statusBar setNeedsDisplay: YES];
}

- (void) goPrevForIndicator: (int) indic {
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t len = [_editor message: SCI_GETLENGTH];
    sptr_t cur = pos - 1;
    if (cur < 0) cur = len - 1;
    if (cur >= 0 && [_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: cur] != 0) {
        cur = [_editor message: SCI_INDICATORSTART wParam: indic lParam: cur] - 1;
        if (cur < 0) cur = len - 1;
    }
    for (sptr_t p = cur; p >= 0; --p) {
        if ([_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: p] != 0) {
            sptr_t s = [_editor message: SCI_INDICATORSTART wParam: indic lParam: p];
            sptr_t e = [_editor message: SCI_INDICATOREND wParam: indic lParam: p];
            [_editor message: SCI_GOTOPOS wParam: s lParam: 0];
            [_editor message: SCI_SETSEL wParam: s lParam: e];
            [_editor message: SCI_SCROLLCARET];
            return;
        }
        if (cur - p > 200000) break;
    }
    // wrap to end
    for (sptr_t p = len - 1; p > cur; --p) {
        if ([_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: p] != 0) {
            sptr_t s = [_editor message: SCI_INDICATORSTART wParam: indic lParam: p];
            sptr_t e = [_editor message: SCI_INDICATOREND wParam: indic lParam: p];
            [_editor message: SCI_GOTOPOS wParam: s lParam: 0];
            [_editor message: SCI_SETSEL wParam: s lParam: e];
            [_editor message: SCI_SCROLLCARET];
            return;
        }
    }
    NSBeep(); _statusBar.statusText = [NSString stringWithFormat: @"No Style %d marks", indic - 20];
    [_statusBar setNeedsDisplay: YES];
}

- (void) copyStyledTextForIndicator: (int) indic {
    NSMutableString* out = [NSMutableString string];
    sptr_t len = [_editor message: SCI_GETLENGTH];
    sptr_t p = 0; int count = 0;
    while (p < len) {
        if ([_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: p] != 0) {
            sptr_t s = [_editor message: SCI_INDICATORSTART wParam: indic lParam: p];
            sptr_t e = [_editor message: SCI_INDICATOREND wParam: indic lParam: p];
            sptr_t rlen = e - s;
            std::vector<char> buf(rlen + 1, 0);
            Sci_TextRangeFull tr; tr.chrg.cpMin = s; tr.chrg.cpMax = e; tr.lpstrText = buf.data();
            [_editor message: SCI_GETTEXTRANGEFULL wParam: 0 lParam: reinterpret_cast<sptr_t>(&tr)];
            NSString* seg = [NSString stringWithUTF8String: buf.data()];
            if (seg) [out appendFormat: @"%@\n", seg];
            count++; p = e + 1;
        } else {
            p++;
        }
        if (count > 5000 || out.length > 1000000) break;
    }
    if (count == 0) { NSBeep(); _statusBar.statusText = [NSString stringWithFormat: @"Style %d: no styled text", indic - 20]; [_statusBar setNeedsDisplay: YES]; return; }
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents]; [pb setString: out forType: NSPasteboardTypeString];
    _statusBar.statusText = [NSString stringWithFormat: @"Copied %d Style %d fragment(s) to clipboard", count, indic - 20];
    [_statusBar setNeedsDisplay: YES];
}

- (void) copyStyled1: (id) s { [self copyStyledTextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT1]; }
- (void) copyStyled2: (id) s { [self copyStyledTextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT2]; }
- (void) copyStyled3: (id) s { [self copyStyledTextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT3]; }
- (void) copyStyled4: (id) s { [self copyStyledTextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT4]; }
- (void) copyStyled5: (id) s { [self copyStyledTextForIndicator: SCE_UNIVERSAL_FOUND_STYLE_EXT5]; }
- (void) copyStyledAll: (id) s {
    NSMutableString* out = [NSMutableString string]; int total = 0;
    for (int indic = 21; indic <= 25; ++indic) {
        sptr_t len = [_editor message: SCI_GETLENGTH];
        sptr_t p = 0;
        while (p < len) {
            if ([_editor message: SCI_INDICATORVALUEAT wParam: indic lParam: p] != 0) {
                sptr_t sPos = [_editor message: SCI_INDICATORSTART wParam: indic lParam: p];
                sptr_t ePos = [_editor message: SCI_INDICATOREND wParam: indic lParam: p];
                std::vector<char> buf(ePos - sPos + 1, 0);
                Sci_TextRangeFull tr; tr.chrg.cpMin = sPos; tr.chrg.cpMax = ePos; tr.lpstrText = buf.data();
                [_editor message: SCI_GETTEXTRANGEFULL wParam: 0 lParam: reinterpret_cast<sptr_t>(&tr)];
                NSString* seg = [NSString stringWithUTF8String: buf.data()];
                if (seg) [out appendFormat: @"%@\n", seg];
                total++; p = ePos + 1;
            } else { p++; }
            if (total > 5000) break;
        }
    }
    if (total == 0) { NSBeep(); _statusBar.statusText = @"No styled text to copy"; [_statusBar setNeedsDisplay: YES]; return; }
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents]; [pb setString: out forType: NSPasteboardTypeString];
    _statusBar.statusText = [NSString stringWithFormat: @"Copied %d styled fragment(s) (all styles)", total];
    [_statusBar setNeedsDisplay: YES];
}

// ---------------------------------------------------------------
// Multi-Select (Edit → Multi-select All / Next)
// ---------------------------------------------------------------
- (NSString *) currentMultiSelectPatternForFlags: (int) flags {
    // Prefer selection, then find bar, then word at caret
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd > selStart && selEnd - selStart < 512) {
        std::vector<char> buf(selEnd - selStart + 1, 0);
        [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
        NSString* s = [NSString stringWithUTF8String: buf.data()];
        if (s.length > 0) return s;
    }
    if (_findReplaceWindowController && _findReplaceWindowController.findField.stringValue.length > 0) {
        NSString* q = [_findReplaceWindowController.findField.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (q.length > 0) return q;
    }
    sptr_t pos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t ws = [_editor message: SCI_WORDSTARTPOSITION wParam: pos lParam: 1];
    sptr_t we = [_editor message: SCI_WORDENDPOSITION wParam: pos lParam: 1];
    if (we > ws && we - ws < 512) {
        std::vector<char> buf(we - ws + 1, 0);
        Sci_TextRangeFull tr; tr.chrg.cpMin = ws; tr.chrg.cpMax = we; tr.lpstrText = buf.data();
        [_editor message: SCI_GETTEXTRANGEFULL wParam: 0 lParam: reinterpret_cast<sptr_t>(&tr)];
        NSString* w = [NSString stringWithUTF8String: buf.data()];
        if (w.length > 0) return w;
    }
    return @"";
}

- (void) multiSelectAllWithFlags: (int) flags {
    NSString* pat = [self currentMultiSelectPatternForFlags: flags];
    if (!pat || pat.length == 0) { NSBeep(); _statusBar.statusText = @"Multi-select: no pattern"; [_statusBar setNeedsDisplay: YES]; return; }
    const char* q = [pat UTF8String]; size_t qLen = strlen(q);
    sptr_t docLen = [_editor message: SCI_GETLENGTH];
    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];
    [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
    // Collect all ranges first
    std::vector<std::pair<sptr_t,sptr_t>> ranges;
    while ([_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)] != -1) {
        sptr_t s = [_editor message: SCI_GETTARGETSTART];
        sptr_t e = [_editor message: SCI_GETTARGETEND];
        if (e <= s) { // zero-length guard
            [_editor message: SCI_SETTARGETSTART wParam: e + 1 lParam: 0];
            [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
            if (e + 1 >= docLen) break;
            continue;
        }
        ranges.emplace_back(s, e);
        [_editor message: SCI_SETTARGETSTART wParam: e lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
        if (ranges.size() > 5000) break;
    }
    if (ranges.empty()) { NSBeep(); _statusBar.statusText = [NSString stringWithFormat: @"Not found: \"%@\"", pat]; [_statusBar setNeedsDisplay: YES]; return; }
    [_editor message: SCI_CLEARSELECTIONS];
    for (size_t i = 0; i < ranges.size(); ++i) {
        if (i == 0) [_editor message: SCI_SETSELECTION wParam: ranges[i].first lParam: ranges[i].second];
        else [_editor message: SCI_ADDSELECTION wParam: ranges[i].first lParam: ranges[i].second];
    }
    // Set main caret to last
    [_editor message: SCI_SCROLLCARET];
    _statusBar.statusText = [NSString stringWithFormat: @"Multi-select All: %lu occurrence(s) of \"%@\"", (unsigned long)ranges.size(), pat];
    [_statusBar setNeedsDisplay: YES];
}

- (void) multiSelectNextWithFlags: (int) flags {
    NSString* pat = [self currentMultiSelectPatternForFlags: flags];
    if (!pat || pat.length == 0) { NSBeep(); return; }
    const char* q = [pat UTF8String]; size_t qLen = strlen(q);
    sptr_t docLen = [_editor message: SCI_GETLENGTH];
    // Determine search start: main selection end (last added)
    sptr_t nSel = [_editor message: SCI_GETSELECTIONS];
    sptr_t startPos = 0;
    if (nSel > 0) {
        sptr_t lastEnd = [_editor message: SCI_GETSELECTIONNEND wParam: nSel - 1 lParam: 0];
        startPos = lastEnd;
        // If current selection already covers a match, start after it
    } else {
        startPos = [_editor message: SCI_GETCURRENTPOS];
    }
    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];
    [_editor message: SCI_SETTARGETSTART wParam: startPos lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
    sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)];
    if (pos == -1) { // wrap
        [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: startPos lParam: 0];
        pos = [_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)];
    }
    if (pos != -1) {
        sptr_t s = [_editor message: SCI_GETTARGETSTART];
        sptr_t e = [_editor message: SCI_GETTARGETEND];
        if (nSel == 0) {
            [_editor message: SCI_SETSELECTION wParam: s lParam: e];
        } else {
            // If no multi-selection yet, convert current selection to first, then add
            if (nSel == 1) {
                // keep existing, just add
            }
            [_editor message: SCI_ADDSELECTION wParam: s lParam: e];
            [_editor message: SCI_SETMAINSELECTION wParam: nSel lParam: 0]; // keep main at new?
            // Ensure Scintilla knows main is newest
            sptr_t newCount = [_editor message: SCI_GETSELECTIONS];
            [_editor message: SCI_SETMAINSELECTION wParam: newCount - 1 lParam: 0];
        }
        [_editor message: SCI_SCROLLCARET];
        sptr_t total = [_editor message: SCI_GETSELECTIONS];
        _statusBar.statusText = [NSString stringWithFormat: @"Multi-select Next: %ld selection(s)", (long)total];
        [_statusBar setNeedsDisplay: YES];
    } else {
        NSBeep(); _statusBar.statusText = [NSString stringWithFormat: @"Not found: \"%@\"", pat]; [_statusBar setNeedsDisplay: YES];
    }
}

- (void) multiSelectUndo: (id) sender {
    sptr_t n = [_editor message: SCI_GETSELECTIONS];
    if (n <= 1) { NSBeep(); return; }
    // Collect all but last
    std::vector<std::pair<sptr_t,sptr_t>> ranges;
    for (sptr_t i = 0; i < n - 1; ++i) {
        sptr_t s = [_editor message: SCI_GETSELECTIONNSTART wParam: i lParam: 0];
        sptr_t e = [_editor message: SCI_GETSELECTIONNEND wParam: i lParam: 0];
        ranges.emplace_back(s, e);
    }
    [_editor message: SCI_CLEARSELECTIONS];
    for (size_t i = 0; i < ranges.size(); ++i) {
        if (i == 0) [_editor message: SCI_SETSELECTION wParam: ranges[i].first lParam: ranges[i].second];
        else [_editor message: SCI_ADDSELECTION wParam: ranges[i].first lParam: ranges[i].second];
    }
    [_editor message: SCI_SCROLLCARET];
    _statusBar.statusText = [NSString stringWithFormat: @"Multi-select Undo: %lu selection(s) remain", (unsigned long)ranges.size()];
    [_statusBar setNeedsDisplay: YES];
}

- (void) multiSelectSkip: (id) sender {
    // Undo last then add next occurrence after it
    sptr_t n = [_editor message: SCI_GETSELECTIONS];
    if (n == 0) { // no selection, just next
        [self multiSelectNextWithFlags: 0];
        return;
    }
    // Remove last selection
    std::vector<std::pair<sptr_t,sptr_t>> ranges;
    for (sptr_t i = 0; i < n - 1; ++i) {
        sptr_t s = [_editor message: SCI_GETSELECTIONNSTART wParam: i lParam: 0];
        sptr_t e = [_editor message: SCI_GETSELECTIONNEND wParam: i lParam: 0];
        ranges.emplace_back(s, e);
    }
    // Determine flags from last multi-select? Use 0 (ignore case?) We'll infer from last pattern's case: just use 0|SCFIND_MATCHCASE? Use plain
    // Keep previous selection count minus one, then search for next after the removed range's start?
    sptr_t lastStart = [_editor message: SCI_GETSELECTIONNSTART wParam: n - 1 lParam: 0];
    sptr_t lastEnd = [_editor message: SCI_GETSELECTIONNEND wParam: n - 1 lParam: 0];
    // Apply removal
    [_editor message: SCI_CLEARSELECTIONS];
    for (size_t i = 0; i < ranges.size(); ++i) {
        if (i == 0) [_editor message: SCI_SETSELECTION wParam: ranges[i].first lParam: ranges[i].second];
        else [_editor message: SCI_ADDSELECTION wParam: ranges[i].first lParam: ranges[i].second];
    }
    if (ranges.empty() && n > 0) {
        // No remaining selections, set caret to lastEnd
        [_editor message: SCI_SETCURRENTPOS wParam: lastEnd lParam: 0];
    }
    // Now find next after lastEnd with default flags (use pattern from current)
    NSString* pat = [self currentMultiSelectPatternForFlags: 0];
    if (!pat || pat.length == 0) { NSBeep(); return; }
    const char* q = [pat UTF8String]; size_t qLen = strlen(q);
    sptr_t docLen = [_editor message: SCI_GETLENGTH];
    sptr_t searchFrom = lastEnd;
    [_editor message: SCI_SETSEARCHFLAGS wParam: 0 lParam: 0];
    [_editor message: SCI_SETTARGETSTART wParam: searchFrom lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLen lParam: 0];
    sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)];
    if (pos == -1) {
        [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: searchFrom lParam: 0];
        pos = [_editor message: SCI_SEARCHINTARGET wParam: qLen lParam: reinterpret_cast<sptr_t>(q)];
    }
    if (pos != -1) {
        sptr_t s = [_editor message: SCI_GETTARGETSTART];
        sptr_t e = [_editor message: SCI_GETTARGETEND];
        if (ranges.empty()) {
            [_editor message: SCI_SETSELECTION wParam: s lParam: e];
        } else {
            [_editor message: SCI_ADDSELECTION wParam: s lParam: e];
            sptr_t newCount = [_editor message: SCI_GETSELECTIONS];
            [_editor message: SCI_SETMAINSELECTION wParam: newCount - 1 lParam: 0];
        }
        [_editor message: SCI_SCROLLCARET];
    } else {
        NSBeep();
    }
}

// Wrappers matching menu selectors
- (void) multiSelectAllIgnoreCaseWholeWord: (id) s { [self multiSelectAllWithFlags: 0]; }
- (void) multiSelectAllCase: (id) s { [self multiSelectAllWithFlags: SCFIND_MATCHCASE]; }
- (void) multiSelectAllWord: (id) s { [self multiSelectAllWithFlags: SCFIND_WHOLEWORD]; }
- (void) multiSelectAllCaseWord: (id) s { [self multiSelectAllWithFlags: SCFIND_MATCHCASE | SCFIND_WHOLEWORD]; }
- (void) multiSelectNextIgnoreCaseWholeWord: (id) s { [self multiSelectNextWithFlags: 0]; }
- (void) multiSelectNextCase: (id) s { [self multiSelectNextWithFlags: SCFIND_MATCHCASE]; }
- (void) multiSelectNextWord: (id) s { [self multiSelectNextWithFlags: SCFIND_WHOLEWORD]; }
- (void) multiSelectNextCaseWord: (id) s { [self multiSelectNextWithFlags: SCFIND_MATCHCASE | SCFIND_WHOLEWORD]; }

- (void) duplicateLine: (id) sender { [_editor message: SCI_LINEDUPLICATE]; }

- (void) toggleLineComment: (id) sender {
    sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: [_editor message: SCI_GETCURRENTPOS]];
    sptr_t lineStart = [_editor message: SCI_POSITIONFROMLINE wParam: line];
    sptr_t lineLen = [_editor message: SCI_LINELENGTH wParam: line];
    if (lineLen <= 0) return;

    std::vector<char> buf(lineLen + 1, 0);
    [_editor message: SCI_GETLINE wParam: line lParam: reinterpret_cast<sptr_t>(buf.data())];
    std::string text(buf.data());

    if (text.rfind("// ", 0) == 0) {
        [_editor message: SCI_SETSEL wParam: lineStart lParam: lineStart + 3];
        [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>("")];
    } else if (text.rfind("//", 0) == 0) {
        [_editor message: SCI_SETSEL wParam: lineStart lParam: lineStart + 2];
        [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>("")];
    } else {
        [_editor message: SCI_INSERTTEXT wParam: lineStart lParam: reinterpret_cast<sptr_t>("// ")];
    }
}

- (void) upperCase: (id) sender { [_editor message: SCI_UPPERCASE]; }
- (void) lowerCase: (id) sender { [_editor message: SCI_LOWERCASE]; }
// ---------------------------------------------------------------
// Clipboard & Editing — route through First Responder (Terminal, Search, Dialogs) or Scintilla
// ---------------------------------------------------------------
- (BOOL) isTerminalFirstResponder: (NSResponder *) resp {
    if (!resp || !_bottomPanel) return NO;
    if ([resp isKindOfClass: [NSView class]] && [(NSView *) resp isDescendantOf: _bottomPanel]) return YES;
    if ([resp isKindOfClass: [NSTextView class]]) {
        NSTextView* tv = (NSTextView *) resp;
        NSView* del = (NSView *) tv.delegate;
        if (del && [del isDescendantOf: _bottomPanel]) return YES;
        if (_bottomPanel.outputTextView == resp) return YES;
    }
    return NO;
}

- (void) cut: (id) sender {
    NSResponder* firstResp = [_window firstResponder];
    if ([self isTerminalFirstResponder: firstResp]) {
        [_bottomPanel cut: sender];
        return;
    }
    if (firstResp && firstResp != _editor && firstResp != (id)self && ![firstResp isKindOfClass: NSClassFromString(@"SCIContentView")]) {
        if ([firstResp respondsToSelector: @selector(cut:)]) {
            [firstResp performSelector: @selector(cut:) withObject: sender];
            return;
        }
    }
    // Otherwise route to Scintilla
    if ([_editor hasMarkedText]) {
        [[NSTextInputContext currentInputContext] discardMarkedText];
    }
    [_editor message: SCI_CUT];
}

- (void) copy: (id) sender {
    NSResponder* firstResp = [_window firstResponder];
    if ([self isTerminalFirstResponder: firstResp]) {
        [_bottomPanel copy: sender];
        return;
    }
    if (firstResp && firstResp != _editor && firstResp != (id)self && ![firstResp isKindOfClass: NSClassFromString(@"SCIContentView")]) {
        if ([firstResp respondsToSelector: @selector(copy:)]) {
            [firstResp performSelector: @selector(copy:) withObject: sender];
            return;
        }
    }
    [_editor message: SCI_COPY];
}

- (void) paste: (id) sender {
    NSResponder* firstResp = [_window firstResponder];
    if ([self isTerminalFirstResponder: firstResp]) {
        [_bottomPanel paste: sender];
        return;
    }
    if (firstResp && firstResp != _editor && firstResp != (id)self && ![firstResp isKindOfClass: NSClassFromString(@"SCIContentView")]) {
        if ([firstResp respondsToSelector: @selector(paste:)]) {
            [firstResp performSelector: @selector(paste:) withObject: sender];
            return;
        }
    }
    if ([_editor hasMarkedText]) {
        [[NSTextInputContext currentInputContext] discardMarkedText];
    }
    [_editor message: SCI_PASTE];
}

- (void) selectAll: (id) sender {
    NSResponder* firstResp = [_window firstResponder];
    if ([self isTerminalFirstResponder: firstResp]) {
        [_bottomPanel selectAll: sender];
        return;
    }
    if (firstResp && firstResp != _editor && firstResp != (id)self && ![firstResp isKindOfClass: NSClassFromString(@"SCIContentView")]) {
        if ([firstResp respondsToSelector: @selector(selectAll:)]) {
            [firstResp performSelector: @selector(selectAll:) withObject: sender];
            return;
        }
    }
    [_editor message: SCI_SELECTALL];
}

- (void) undo: (id) sender {
    NSResponder* firstResp = [_window firstResponder];
    if ([self isTerminalFirstResponder: firstResp]) {
        [_bottomPanel sendSigTstp];
        return;
    }
    if (firstResp && firstResp != _editor && firstResp != (id)self && ![firstResp isKindOfClass: NSClassFromString(@"SCIContentView")]) {
        NSUndoManager* um = [firstResp undoManager];
        if (um && [um canUndo]) {
            [um undo];
            return;
        }
        if ([firstResp respondsToSelector: @selector(undo:)]) {
            [firstResp performSelector: @selector(undo:) withObject: sender];
            return;
        }
    }
    if ([_editor hasMarkedText]) {
        [[NSTextInputContext currentInputContext] discardMarkedText];
    }
    [_editor message: SCI_UNDO];
}

- (void) redo: (id) sender {
    NSResponder* firstResp = [_window firstResponder];
    if ([self isTerminalFirstResponder: firstResp]) {
        return;
    }
    if (firstResp && firstResp != _editor && firstResp != (id)self && ![firstResp isKindOfClass: NSClassFromString(@"SCIContentView")]) {
        NSUndoManager* um = [firstResp undoManager];
        if (um && [um canRedo]) {
            [um redo];
            return;
        }
        if ([firstResp respondsToSelector: @selector(redo:)]) {
            [firstResp performSelector: @selector(redo:) withObject: sender];
            return;
        }
    }
    [_editor message: SCI_REDO];
}

- (BOOL) validateMenuItem: (NSMenuItem *) menuItem {
    SEL action = menuItem.action;
    NSResponder* firstResp = [_window firstResponder];
    BOOL isBottomPanel = [self isTerminalFirstResponder: firstResp];
    BOOL isOtherResponder = isBottomPanel || (firstResp && firstResp != _editor && firstResp != (id)self && ![firstResp isKindOfClass: NSClassFromString(@"SCIContentView")]);

    if (action == @selector(undo:)) {
        if (isBottomPanel) return YES;
        if (isOtherResponder) {
            NSUndoManager* um = [firstResp undoManager];
            return um ? [um canUndo] : YES;
        }
        return [_editor message: SCI_CANUNDO] != 0;
    }
    if (action == @selector(redo:)) {
        if (isBottomPanel) return NO;
        if (isOtherResponder) {
            NSUndoManager* um = [firstResp undoManager];
            return um ? [um canRedo] : YES;
        }
        return [_editor message: SCI_CANREDO] != 0;
    }
    if (action == @selector(cut:) || action == @selector(copy:)) {
        if (isBottomPanel) return YES;
        if (isOtherResponder) {
            if ([firstResp isKindOfClass: [NSTextView class]]) {
                return [(NSTextView*)firstResp selectedRange].length > 0;
            }
            if ([firstResp isKindOfClass: [NSText class]]) {
                return [(NSText*)firstResp selectedRange].length > 0;
            }
            return YES;
        }
        return [_editor message: SCI_GETSELECTIONEMPTY] == 0;
    }
    if (action == @selector(paste:)) {
        if (isBottomPanel) {
            NSPasteboard* pb = [NSPasteboard generalPasteboard];
            return [pb stringForType: NSPasteboardTypeString] != nil || [pb stringForType: NSStringPboardType] != nil;
        }
        if (isOtherResponder) {
            return [[NSPasteboard generalPasteboard] stringForType: NSPasteboardTypeString] != nil;
        }
        return [_editor message: SCI_CANPASTE] != 0;
    }
    if (action == @selector(selectAll:)) {
        return YES;
    }
    if (action == @selector(toggleColumnMode:)) {
        const sptr_t sels = _editor ? [_editor message: SCI_GETSELECTIONS wParam: 0 lParam: 0] : 0;
        const sptr_t selMode = _editor ? [_editor message: SCI_GETSELECTIONMODE wParam: 0 lParam: 0] : 0;
        menuItem.state = ((sels > 1) || selMode == SC_SEL_RECTANGLE || selMode == SC_SEL_THIN)
                             ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    return YES;
}
- (void) toggleWordWrap: (id) sender {
    _wordWrap = !_wordWrap;
    [_editor message: SCI_SETWRAPMODE wParam: _wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE lParam: 0];
}

- (void) toggleLineNumbers: (id) sender {
    _showLineNumbers = !_showLineNumbers;
    [_editor message: SCI_SETMARGINWIDTHN wParam: 0 lParam: _showLineNumbers ? 46 : 0];
}

- (void) toggleDarkMode: (id) sender {
    _isDarkMode = !_isDarkMode;
    _currentThemeName = _isDarkMode ? @"🌙 Notepad++ Dark (Default Dark)" : @"☀️ Default Light (Classic)";
    [self applyAllSettings];
}

- (void) convertToLF: (id) sender {
    [_editor message: SCI_CONVERTEOLS wParam: SC_EOL_LF lParam: 0];
    [_editor message: SCI_SETEOLMODE wParam: SC_EOL_LF lParam: 0];
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        mDocuments[mActiveIndex].eolMode = 2;
        [self updateStatusBar];
    }
}

- (void) convertToCRLF: (id) sender {
    [_editor message: SCI_CONVERTEOLS wParam: SC_EOL_CRLF lParam: 0];
    [_editor message: SCI_SETEOLMODE wParam: SC_EOL_CRLF lParam: 0];
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        mDocuments[mActiveIndex].eolMode = 0;
        [self updateStatusBar];
    }
}

- (void) convertToCR: (id) sender {
    [_editor message: SCI_CONVERTEOLS wParam: SC_EOL_CR lParam: 0];
    [_editor message: SCI_SETEOLMODE wParam: SC_EOL_CR lParam: 0];
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        mDocuments[mActiveIndex].eolMode = 1;
        [self updateStatusBar];
    }
}

- (void) selectEncoding: (id) sender {
    if ([sender isKindOfClass: [NSMenuItem class]]) {
        NSMenuItem* item = (NSMenuItem*)sender;
        int enc = static_cast<int>(item.tag);
        if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
            mDocuments[mActiveIndex].encoding = enc;
            [self updateStatusBar];
        }
    }
}

- (void) selectLanguage: (id) sender {
    if ([sender isKindOfClass: [NSMenuItem class]]) {
        NSMenuItem* item = (NSMenuItem*)sender;
        if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
            NSString* lexer = item.representedObject ?: @"text";
            mDocuments[mActiveIndex].lexerName = [lexer UTF8String];
            [self configureLexerForActiveDocument];
            [self updateStatusBar];

            // If user selected markdown/html/json/xml, ensure preview panel is open to see live rendering
            if ([lexer isEqualToString: @"markdown"] || [lexer isEqualToString: @"hypertext"] || [lexer isEqualToString: @"json"] || [lexer isEqualToString: @"xml"]) {
                if (!_rootContentView.isSecondarySidePanelVisible) {
                    _rootContentView.isSecondarySidePanelVisible = YES;
                    [_rootContentView updateSplitLayout];
                }
            }
            [self updateLivePreviewForActiveDocument];
        }
    }
}

- (void) showPreferences: (id) sender { [_prefWindowController showPreferencesAtCategory: 0]; }
- (void) showStyleConfigurator: (id) sender { [_prefWindowController showPreferencesAtCategory: 5]; }

- (void) showAbout: (id) sender {
    NSDictionary* options = @{
        NSAboutPanelOptionApplicationName: @"Notepad++",
        NSAboutPanelOptionApplicationVersion: @"8.7.6",
        NSAboutPanelOptionVersion: @"macOS Native Cocoa (Apple Clang C++20)",
        @"Copyright": @"Copyright © Don HO and Notepad++ Contributors.\nmacOS Native Port."
    };
    [NSApp orderFrontStandardAboutPanelWithOptions: options];
}

// ============================================================================
// Main Menu Bar Creation
// ============================================================================


- (NSString *) localizedString: (NSString *) key defaultText: (NSString *) defaultText {
    if (_localizedDict && _localizedDict[key]) {
        return _localizedDict[key];
    }
    return defaultText ?: @"";
}

- (void) applyLocalization: (NSString *) xmlFileName {
    if (!xmlFileName || xmlFileName.length == 0) xmlFileName = @"korean.xml";
    _currentLocalizationFile = xmlFileName;

    // Find XML file in bundle or project
    NSArray<NSString *>* paths = @[
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: [NSString stringWithFormat: @"localization/%@", xmlFileName]],
        [NSString stringWithFormat: @"/Users/mac/Antigravity/notepadpp/PowerEditor/installer/nativeLang/%@", xmlFileName],
        [NSString stringWithFormat: @"PowerEditor/installer/nativeLang/%@", xmlFileName]
    ];

    NSString* xmlPath = nil;
    for (NSString* p in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath: p]) {
            xmlPath = p;
            break;
        }
    }

    if (!xmlPath) return;

    pugi::xml_document doc;
    pugi::xml_parse_result result = doc.load_file([xmlPath UTF8String], pugi::parse_default | pugi::parse_escapes);
    if (!result) return;

    if (!_localizedDict) _localizedDict = [NSMutableDictionary dictionary];
    else [_localizedDict removeAllObjects];

    auto cleanName = [](const char* raw) -> NSString* {
        if (!raw) return @"";
        NSString* s = [NSString stringWithUTF8String: raw];
        // Strip accelerator keys like (&F), (&N), (&O)
        NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern: @"\\(&[A-Za-z0-9]\\)" options: 0 error: nil];
        s = [regex stringByReplacingMatchesInString: s options: 0 range: NSMakeRange(0, s.length) withTemplate: @""];
        s = [s stringByReplacingOccurrencesOfString: @"&amp;" withString: @""];
        s = [s stringByReplacingOccurrencesOfString: @"&" withString: @""];
        return [s stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    };

    pugi::xml_node nativeLang = doc.child("NotepadPlus").child("Native-Langue");
    if (!nativeLang) nativeLang = doc.child("Native-Langue");
    pugi::xml_node menuMain = nativeLang.child("Menu").child("Main");

    // 1. Menu Entries (file, edit, search, view, encoding, language, settings, tools, macro, run, Window, etc.)
    for (pugi::xml_node item : menuMain.child("Entries").children("Item")) {
        const char* menuId = item.attribute("menuId").as_string();
        const char* name = item.attribute("name").as_string();
        if (menuId && name && strlen(menuId) > 0) {
            _localizedDict[[NSString stringWithUTF8String: menuId]] = cleanName(name);
        }
    }

    // 2. Sub Menu Entries
    for (pugi::xml_node item : menuMain.child("SubEntries").children("Item")) {
        const char* subMenuId = item.attribute("subMenuId").as_string();
        const char* name = item.attribute("name").as_string();
        if (subMenuId && name && strlen(subMenuId) > 0) {
            _localizedDict[[NSString stringWithUTF8String: subMenuId]] = cleanName(name);
        }
    }

    // 3. Command Items (41001: New, 41002: Open, etc.)
    for (pugi::xml_node item : menuMain.child("Commands").children("Item")) {
        const char* idStr = item.attribute("id").as_string();
        const char* name = item.attribute("name").as_string();
        if (idStr && name && strlen(idStr) > 0) {
            _localizedDict[[NSString stringWithFormat: @"cmd_%s", idStr]] = cleanName(name);
        }
    }

    // 4. Dialogs & Preferences (Recursive Indexing)
    std::function<void(pugi::xml_node)> indexDialogNode = [&](pugi::xml_node node) {
        for (pugi::xml_node child : node.children()) {
            if (strcmp(child.name(), "Item") == 0) {
                const char* idStr = child.attribute("id").as_string();
                const char* name = child.attribute("name").as_string();
                if (idStr && name && strlen(idStr) > 0) {
                    _localizedDict[[NSString stringWithFormat: @"dlg_%s", idStr]] = cleanName(name);
                }
            } else {
                const char* title = child.attribute("title").as_string();
                if (title && strlen(title) > 0) {
                    _localizedDict[[NSString stringWithFormat: @"dlg_title_%s", child.name()]] = cleanName(title);
                }
            }
            indexDialogNode(child);
        }
    };

    for (pugi::xml_node dlg : nativeLang.child("Dialog").children()) {
        const char* dlgTitle = dlg.attribute("title").as_string();
        if (dlgTitle && strlen(dlgTitle) > 0) {
            _localizedDict[[NSString stringWithFormat: @"dlg_title_%s", dlg.name()]] = cleanName(dlgTitle);
        }
        indexDialogNode(dlg);
    }

    // Rebuild macOS Menu Bar immediately in the chosen language!
    [self createMainMenu];
    [self updateStatusBar];
    [self updateWindowTitle];
    [self saveSessionState];
}

- (void) createMainMenu {
    NSMenu* menubar = [[NSMenu alloc] init];

    auto L = [&](NSString* key, NSString* defText) -> NSString* {
        return [self localizedString: key defaultText: defText];
    };

    auto addItem = [&](NSMenu* menu, NSString* title, SEL action, NSString* key, NSEventModifierFlags mods) -> NSMenuItem* {
        NSMenuItem* item = [menu addItemWithTitle: title action: action keyEquivalent: key];
        item.target = self;
        // Always explicitly set the modifier mask so there is no ambiguity.
        // Default macOS value for keyEquivalentModifierMask is NSEventModifierFlagCommand,
        // but we set it explicitly for clarity and correctness.
        item.keyEquivalentModifierMask = (mods != 0) ? mods : NSEventModifierFlagCommand;
        return item;
    };

    // 1. App Menu
    NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle: @"Notepad++"];
    [appMenu addItemWithTitle: [NSString stringWithFormat: @"%@ Notepad++", L(@"help", @"About")] action: @selector(showAbout:) keyEquivalent: @""].target = self;
    [appMenu addItem: [NSMenuItem separatorItem]];
    {
        // App menu: Preferences without shortcut to avoid conflict with Settings menu ⌘,
        NSMenuItem* prefApp = [appMenu addItemWithTitle: [NSString stringWithFormat: @"%@...", L(@"cmd_48011", L(@"dlg_title_Preference", @"Preferences"))] action: @selector(showPreferences:) keyEquivalent: @""];
        prefApp.target = self;
    }
    [appMenu addItem: [NSMenuItem separatorItem]];
    [appMenu addItemWithTitle: @"Hide Notepad++" action: @selector(hide:) keyEquivalent: @"h"];
    [appMenu addItemWithTitle: @"Hide Others" action: @selector(hideOtherApplications:) keyEquivalent: @"h"].keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle: @"Show All" action: @selector(unhideAllApplications:) keyEquivalent: @""];
    [appMenu addItem: [NSMenuItem separatorItem]];
    [appMenu addItemWithTitle: @"Quit Notepad++" action: @selector(terminate:) keyEquivalent: @"q"];
    appMenuItem.submenu = appMenu;
    [menubar addItem: appMenuItem];

    // 2. File Menu
    NSMenuItem* fileMenuItem = [[NSMenuItem alloc] init];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle: L(@"file", @"File")];
    addItem(fileMenu, L(@"cmd_41001", @"New"), @selector(newFile:), @"n", 0);
    addItem(fileMenu, L(@"cmd_41002", @"Open..."), @selector(openFile:), @"o", 0);
    addItem(fileMenu, L(@"file-reload", @"Reload from Disk"), @selector(reloadFromDisk:), @"r", 0);
    [fileMenu addItem: [NSMenuItem separatorItem]];
    addItem(fileMenu, L(@"cmd_41006", @"Save"), @selector(saveFile:), @"s", 0);
    addItem(fileMenu, L(@"cmd_41008", @"Save As..."), @selector(saveFileAs:), @"S", 0);
    addItem(fileMenu, L(@"cmd_41007", @"Save All"), @selector(saveAllFiles:), @"s", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    [fileMenu addItem: [NSMenuItem separatorItem]];
    addItem(fileMenu, L(@"file-rename", @"Rename..."), @selector(renameCurrentFile:), @"", 0);
    addItem(fileMenu, L(@"file-openFolder", @"Reveal in Finder"), @selector(revealInFinder:), @"R", 0);
    addItem(fileMenu, L(@"cmd_41020", @"Open in Terminal"), @selector(openInTerminal:), @"T", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(fileMenu, L(@"edit-copyToClipboard", @"Copy Full Path"), @selector(copyFullPath:), @"C", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(fileMenu, L(@"dlg_6425", @"Copy Filename"), @selector(copyFilename:), @"", 0);
    addItem(fileMenu, L(@"dlg_6426", @"Copy Directory Path"), @selector(copyDirectoryPath:), @"", 0);
    [fileMenu addItem: [NSMenuItem separatorItem]];
    addItem(fileMenu, L(@"cmd_41003", @"Close Tab"), @selector(closeTab:), @"w", 0);
    addItem(fileMenu, L(@"cmd_41004", @"Close All"), @selector(closeAllDocuments:), @"W", 0);
    addItem(fileMenu, L(@"cmd_41005", @"Close All BUT Active"), @selector(closeAllButActive:), @"", 0);
    [fileMenu addItem: [NSMenuItem separatorItem]];
    {
        NSString* leftArr  = [NSString stringWithFormat: @"%C", (unichar)NSLeftArrowFunctionKey];
        NSString* rightArr = [NSString stringWithFormat: @"%C", (unichar)NSRightArrowFunctionKey];
        addItem(fileMenu, L(@"cmd_41018", @"Previous Tab"), @selector(prevTab:), leftArr,  NSEventModifierFlagCommand | NSEventModifierFlagOption);
        addItem(fileMenu, L(@"cmd_41019", @"Next Tab"),     @selector(nextTab:), rightArr, NSEventModifierFlagCommand | NSEventModifierFlagOption);
    }
    fileMenuItem.submenu = fileMenu;
    [menubar addItem: fileMenuItem];

    // 3. Edit Menu
    NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle: L(@"edit", @"Edit")];
    addItem(editMenu, L(@"cmd_42003", @"Undo"), @selector(undo:), @"z", 0);
    addItem(editMenu, L(@"cmd_42004", @"Redo"), @selector(redo:), @"Z", 0);
    [editMenu addItem: [NSMenuItem separatorItem]];
    addItem(editMenu, L(@"cmd_42001", @"Cut"), @selector(cut:), @"x", 0);
    addItem(editMenu, L(@"cmd_42002", @"Copy"), @selector(copy:), @"c", 0);
    addItem(editMenu, L(@"cmd_42005", @"Paste"), @selector(paste:), @"v", 0);
    addItem(editMenu, L(@"cmd_42007", @"Select All"), @selector(selectAll:), @"a", 0);
    [editMenu addItem: [NSMenuItem separatorItem]];

    // Column Mode & Column Editor
    addItem(editMenu, [NSString stringWithFormat: @"%@...", L(@"dlg_6523", @"Enable Column Selection to Multi-Editing")], @selector(showColumnModeTip:), @"", 0);
    addItem(editMenu, [NSString stringWithFormat: @"%@...", L(@"dlg_title_ColumnEditor", @"Column Editor")], @selector(showColumnEditorDialog:), @"c", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    [editMenu addItem: [NSMenuItem separatorItem]];

    // Line Operations
    NSMenuItem* lineOpsItem = [editMenu addItemWithTitle: L(@"edit-lineOperations", @"Line Operations") action: nil keyEquivalent: @""];
    NSMenu* lineOpsMenu = [[NSMenu alloc] initWithTitle: L(@"edit-lineOperations", @"Line Operations")];
    addItem(lineOpsMenu, [NSString stringWithFormat: @"%@ (⌥Drag / ⌥⇧Arrows)", L(@"edit-columnMode", @"열 모드...")], @selector(toggleColumnMode:), @"", 0);
    [lineOpsMenu addItem: [NSMenuItem separatorItem]];
    addItem(lineOpsMenu, L(@"cmd_42029", @"Duplicate Current Line"), @selector(duplicateLine:), @"d", 0);
    addItem(lineOpsMenu, L(@"cmd_42030", @"Split Lines"), @selector(splitLines:), @"", 0);
    addItem(lineOpsMenu, L(@"cmd_42031", @"Join Lines"), @selector(joinLines:), @"j", NSEventModifierFlagControl);
    {
        NSString* upArr   = [NSString stringWithFormat: @"%C", (unichar)NSUpArrowFunctionKey];
        NSString* downArr = [NSString stringWithFormat: @"%C", (unichar)NSDownArrowFunctionKey];
        addItem(lineOpsMenu, L(@"cmd_42032", @"Move Selected Lines Up"),   @selector(moveLineUp:),   upArr,   NSEventModifierFlagOption | NSEventModifierFlagCommand);
        addItem(lineOpsMenu, L(@"cmd_42033", @"Move Selected Lines Down"), @selector(moveLineDown:), downArr, NSEventModifierFlagOption | NSEventModifierFlagCommand);
    }
    [lineOpsMenu addItem: [NSMenuItem separatorItem]];
    addItem(lineOpsMenu, L(@"cmd_42034", @"Sort Lines Ascending"), @selector(sortLinesAscending:), @"", 0);
    addItem(lineOpsMenu, L(@"cmd_42035", @"Sort Lines Descending"), @selector(sortLinesDescending:), @"", 0);
    addItem(lineOpsMenu, L(@"cmd_42036", @"Remove Duplicate Lines"), @selector(removeDuplicateLines:), @"", 0);
    addItem(lineOpsMenu, L(@"cmd_42037", @"Remove Empty Lines"), @selector(removeEmptyLines:), @"", 0);
    lineOpsItem.submenu = lineOpsMenu;

    // Blank Operations
    NSMenuItem* blankOpsItem = [editMenu addItemWithTitle: L(@"edit-blankOperations", @"Blank Operations") action: nil keyEquivalent: @""];
    NSMenu* blankOpsMenu = [[NSMenu alloc] initWithTitle: L(@"edit-blankOperations", @"Blank Operations")];
    addItem(blankOpsMenu, L(@"cmd_42024", @"Trim Trailing Space"), @selector(trimTrailingSpace:), @"", 0);
    addItem(blankOpsMenu, L(@"cmd_42025", @"Trim Leading Space"), @selector(trimLeadingSpace:), @"", 0);
    addItem(blankOpsMenu, L(@"cmd_42026", @"Trim Trailing and Leading"), @selector(trimBoth:), @"", 0);
    [blankOpsMenu addItem: [NSMenuItem separatorItem]];
    addItem(blankOpsMenu, L(@"cmd_42027", @"TAB to Space"), @selector(tabToSpace:), @"", 0);
    addItem(blankOpsMenu, L(@"cmd_42028", @"Space to TAB"), @selector(spaceToTab:), @"", 0);
    blankOpsItem.submenu = blankOpsMenu;

    // Convert Case
    NSMenuItem* caseItem = [editMenu addItemWithTitle: L(@"edit-convertCaseTo", @"Convert Case to") action: nil keyEquivalent: @""];
    NSMenu* caseMenu = [[NSMenu alloc] initWithTitle: L(@"edit-convertCaseTo", @"Convert Case to")];
    addItem(caseMenu, L(@"cmd_42018", @"UPPERCASE"), @selector(upperCase:), @"u", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    addItem(caseMenu, L(@"cmd_42019", @"lowercase"), @selector(lowerCase:), @"u", 0);
    caseItem.submenu = caseMenu;

    // Comments
    NSMenuItem* commentItem = [editMenu addItemWithTitle: L(@"edit-comment", @"Comment/Uncomment") action: nil keyEquivalent: @""];
    NSMenu* commentMenu = [[NSMenu alloc] initWithTitle: L(@"edit-comment", @"Comment/Uncomment")];
    addItem(commentMenu, L(@"cmd_42022", @"Toggle Single Line Comment"), @selector(toggleLineComment:), @"/", 0);
    commentItem.submenu = commentMenu;

    [editMenu addItem: [NSMenuItem separatorItem]];

    // Multi-Select (Edit → Multi-select All / Next) — mirrors Notepad++ Edit menu
    NSMenuItem* msAllItem = [editMenu addItemWithTitle: L(@"edit-multiSelectALL", @"Multi-select All") action: nil keyEquivalent: @""];
    NSMenu* msAllMenu = [[NSMenu alloc] initWithTitle: L(@"edit-multiSelectALL", @"Multi-select All")];
    addItem(msAllMenu, L(@"cmd_42090", @"Ignore Case && Whole Word"), @selector(multiSelectAllIgnoreCaseWholeWord:), @"", 0);
    addItem(msAllMenu, L(@"cmd_42091", @"Match Case Only"), @selector(multiSelectAllCase:), @"", 0);
    addItem(msAllMenu, L(@"cmd_42092", @"Match Whole Word Only"), @selector(multiSelectAllWord:), @"", 0);
    addItem(msAllMenu, L(@"cmd_42093", @"Match Case && Whole Word"), @selector(multiSelectAllCaseWord:), @"", 0);
    msAllItem.submenu = msAllMenu;

    NSMenuItem* msNextItem = [editMenu addItemWithTitle: L(@"edit-multiSelectNext", @"Multi-select Next") action: nil keyEquivalent: @""];
    NSMenu* msNextMenu = [[NSMenu alloc] initWithTitle: L(@"edit-multiSelectNext", @"Multi-select Next")];
    addItem(msNextMenu, L(@"cmd_42094", @"Ignore Case && Whole Word"), @selector(multiSelectNextIgnoreCaseWholeWord:), @"", 0);
    addItem(msNextMenu, L(@"cmd_42095", @"Match Case Only"), @selector(multiSelectNextCase:), @"", 0);
    addItem(msNextMenu, L(@"cmd_42096", @"Match Whole Word Only"), @selector(multiSelectNextWord:), @"", 0);
    addItem(msNextMenu, L(@"cmd_42097", @"Match Case && Whole Word"), @selector(multiSelectNextCaseWord:), @"", 0);
    msNextItem.submenu = msNextMenu;

    addItem(editMenu, L(@"cmd_42098", @"Undo the Latest Added Multi-Select"), @selector(multiSelectUndo:), @"", 0);
    addItem(editMenu, L(@"cmd_42099", @"Skip Current && Go to Next Multi-select"), @selector(multiSelectSkip:), @"", 0);

    editMenuItem.submenu = editMenu;
    [menubar addItem: editMenuItem];

    // 4. Search Menu
    NSMenuItem* searchMenuItem = [[NSMenuItem alloc] init];
    NSMenu* searchMenu = [[NSMenu alloc] initWithTitle: L(@"search", @"Search")];
    addItem(searchMenu, L(@"cmd_43001", @"Find..."), @selector(showFind:), @"f", 0);
    addItem(searchMenu, L(@"cmd_43003", @"Replace..."), @selector(showReplace:), @"f", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(searchMenu, L(@"dlg_Find_1701", L(@"dlg_1", @"Find Next")), @selector(onFindNext:), @"g", 0);
    addItem(searchMenu, L(@"search-jumpUp", @"Find Previous"), @selector(onFindPrev:), @"G", 0);
    addItem(searchMenu, L(@"dlg_6908", @"Use Selection for Find"), @selector(useSelectionForFind:), @"e", 0);
    [searchMenu addItem: [NSMenuItem separatorItem]];
    addItem(searchMenu, L(@"dlg_GoToLine_2007", @"Go to Line..."), @selector(goToLine:), @"l", 0);
    addItem(searchMenu, L(@"cmd_43011", @"Matching Brace"), @selector(goToMatchingBrace:), @"b", 0);
    [searchMenu addItem: [NSMenuItem separatorItem]];

    NSMenuItem* bmItem = [searchMenu addItemWithTitle: L(@"search-bookmark", @"Bookmark") action: nil keyEquivalent: @""];
    NSMenu* bmMenu = [[NSMenu alloc] initWithTitle: L(@"search-bookmark", @"Bookmark")];
    NSString* f2Str = [NSString stringWithFormat: @"%C", (unichar)NSF2FunctionKey];
    NSMenuItem* itBmToggle = [bmMenu addItemWithTitle: L(@"search-bookmark", @"Toggle Bookmark") action: @selector(toggleBookmark:) keyEquivalent: f2Str];
    itBmToggle.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    itBmToggle.target = self;

    NSMenuItem* itBmNext = [bmMenu addItemWithTitle: L(@"cmd_43023", @"Next Bookmark") action: @selector(nextBookmark:) keyEquivalent: f2Str];
    itBmNext.keyEquivalentModifierMask = 0;
    itBmNext.target = self;

    NSMenuItem* itBmPrev = [bmMenu addItemWithTitle: L(@"cmd_43024", @"Previous Bookmark") action: @selector(prevBookmark:) keyEquivalent: f2Str];
    itBmPrev.keyEquivalentModifierMask = NSEventModifierFlagShift;
    itBmPrev.target = self;

    NSMenuItem* itBmClear = [bmMenu addItemWithTitle: L(@"cmd_43025", @"Clear All Bookmarks") action: @selector(clearAllBookmarks:) keyEquivalent: f2Str];
    itBmClear.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    itBmClear.target = self;
    bmItem.submenu = bmMenu;

    [searchMenu addItem: [NSMenuItem separatorItem]];

    // Search Style (5-color) — replicates Notepad++ Search → Style All / Style One / Clear / Jump / Copy
    NSMenuItem* styleAllItem = [searchMenu addItemWithTitle: L(@"search-markAll", @"Style All Occurrences of Token") action: nil keyEquivalent: @""];
    NSMenu* styleAllMenu = [[NSMenu alloc] initWithTitle: L(@"search-markAll", @"Style All Occurrences of Token")];
    // Spec: Ctrl+Alt+Shift+1..5 = apply style 1..5 (light blue/orange/yellow/dark blue/dark green)
    NSEventModifierFlags styleMods = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
    addItem(styleAllMenu, L(@"cmd_43022", @"Using 1st Style — Light Blue"), @selector(markAllExt1:), @"1", styleMods);
    addItem(styleAllMenu, L(@"cmd_43024", @"Using 2nd Style — Orange"), @selector(markAllExt2:), @"2", styleMods);
    addItem(styleAllMenu, L(@"cmd_43026", @"Using 3rd Style — Yellow"), @selector(markAllExt3:), @"3", styleMods);
    addItem(styleAllMenu, L(@"cmd_43028", @"Using 4th Style — Dark Blue"), @selector(markAllExt4:), @"4", styleMods);
    addItem(styleAllMenu, L(@"cmd_43030", @"Using 5th Style — Dark Green"), @selector(markAllExt5:), @"5", styleMods);
    styleAllItem.submenu = styleAllMenu;

    NSMenuItem* styleOneItem = [searchMenu addItemWithTitle: L(@"search-markOne", @"Style One Token") action: nil keyEquivalent: @""];
    NSMenu* styleOneMenu = [[NSMenu alloc] initWithTitle: L(@"search-markOne", @"Style One Token")];
    addItem(styleOneMenu, L(@"cmd_43062", @"Using 1st Style"), @selector(markOneExt1:), @"", 0);
    addItem(styleOneMenu, L(@"cmd_43063", @"Using 2nd Style"), @selector(markOneExt2:), @"", 0);
    addItem(styleOneMenu, L(@"cmd_43064", @"Using 3rd Style"), @selector(markOneExt3:), @"", 0);
    addItem(styleOneMenu, L(@"cmd_43065", @"Using 4th Style"), @selector(markOneExt4:), @"", 0);
    addItem(styleOneMenu, L(@"cmd_43066", @"Using 5th Style"), @selector(markOneExt5:), @"", 0);
    styleOneItem.submenu = styleOneMenu;

    NSMenuItem* clearStyleItem = [searchMenu addItemWithTitle: L(@"search-unmarkAll", @"Clear Style") action: nil keyEquivalent: @""];
    NSMenu* clearStyleMenu = [[NSMenu alloc] initWithTitle: L(@"search-unmarkAll", @"Clear Style")];
    addItem(clearStyleMenu, L(@"cmd_43023", @"Clear 1st Style"), @selector(unmarkExt1:), @"", 0);
    addItem(clearStyleMenu, L(@"cmd_43025", @"Clear 2nd Style"), @selector(unmarkExt2:), @"", 0);
    addItem(clearStyleMenu, L(@"cmd_43027", @"Clear 3rd Style"), @selector(unmarkExt3:), @"", 0);
    addItem(clearStyleMenu, L(@"cmd_43029", @"Clear 4th Style"), @selector(unmarkExt4:), @"", 0);
    addItem(clearStyleMenu, L(@"cmd_43031", @"Clear 5th Style"), @selector(unmarkExt5:), @"", 0);
    [clearStyleMenu addItem: [NSMenuItem separatorItem]];
    addItem(clearStyleMenu, L(@"cmd_43032", @"Clear All Styles"), @selector(clearAllIndicators:), @"", 0);
    clearStyleItem.submenu = clearStyleMenu;

    NSMenuItem* jumpUpItem = [searchMenu addItemWithTitle: L(@"search-jumpUp", @"Jump Up") action: nil keyEquivalent: @""];
    NSMenu* jumpUpMenu = [[NSMenu alloc] initWithTitle: L(@"search-jumpUp", @"Jump Up")];
    // Spec gap: Jump Up has no hotkey in spec; propose Ctrl+Shift+1..5 as Up (mirror of Ctrl+1..5 Down) to avoid conflict
    NSEventModifierFlags upMods = NSEventModifierFlagControl | NSEventModifierFlagShift;
    addItem(jumpUpMenu, @"1st Style — Light Blue", @selector(goPrevMarkExt1:), @"1", upMods);
    addItem(jumpUpMenu, @"2nd Style — Orange", @selector(goPrevMarkExt2:), @"2", upMods);
    addItem(jumpUpMenu, @"3rd Style — Yellow", @selector(goPrevMarkExt3:), @"3", upMods);
    addItem(jumpUpMenu, @"4th Style — Dark Blue", @selector(goPrevMarkExt4:), @"4", upMods);
    addItem(jumpUpMenu, @"5th Style — Dark Green", @selector(goPrevMarkExt5:), @"5", upMods);
    jumpUpItem.submenu = jumpUpMenu;

    NSMenuItem* jumpDownItem = [searchMenu addItemWithTitle: L(@"search-jumpDown", @"Jump Down") action: nil keyEquivalent: @""];
    NSMenu* jumpDownMenu = [[NSMenu alloc] initWithTitle: L(@"search-jumpDown", @"Jump Down")];
    // Spec: Ctrl+1..5 = jump within same style (next occurrence)
    addItem(jumpDownMenu, @"1st Style — Light Blue", @selector(goNextMarkExt1:), @"1", NSEventModifierFlagControl);
    addItem(jumpDownMenu, @"2nd Style — Orange", @selector(goNextMarkExt2:), @"2", NSEventModifierFlagControl);
    addItem(jumpDownMenu, @"3rd Style — Yellow", @selector(goNextMarkExt3:), @"3", NSEventModifierFlagControl);
    addItem(jumpDownMenu, @"4th Style — Dark Blue", @selector(goNextMarkExt4:), @"4", NSEventModifierFlagControl);
    addItem(jumpDownMenu, @"5th Style — Dark Green", @selector(goNextMarkExt5:), @"5", NSEventModifierFlagControl);
    jumpDownItem.submenu = jumpDownMenu;

    NSMenuItem* copyStyledItem = [searchMenu addItemWithTitle: L(@"search-copyStyledText", @"Copy Styled Text") action: nil keyEquivalent: @""];
    NSMenu* copyStyledMenu = [[NSMenu alloc] initWithTitle: L(@"search-copyStyledText", @"Copy Styled Text")];
    addItem(copyStyledMenu, @"1st Style", @selector(copyStyled1:), @"", 0);
    addItem(copyStyledMenu, @"2nd Style", @selector(copyStyled2:), @"", 0);
    addItem(copyStyledMenu, @"3rd Style", @selector(copyStyled3:), @"", 0);
    addItem(copyStyledMenu, @"4th Style", @selector(copyStyled4:), @"", 0);
    addItem(copyStyledMenu, @"5th Style", @selector(copyStyled5:), @"", 0);
    [copyStyledMenu addItem: [NSMenuItem separatorItem]];
    addItem(copyStyledMenu, @"All Styles", @selector(copyStyledAll:), @"", 0);
    copyStyledItem.submenu = copyStyledMenu;

    searchMenuItem.submenu = searchMenu;
    [menubar addItem: searchMenuItem];

    // 5. View Menu (Including 3 Panels)
    NSMenuItem* viewMenuItem = [[NSMenuItem alloc] init];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle: L(@"view", @"View")];
    addItem(viewMenu, [NSString stringWithFormat: @"%@ (⌥⌘1)", L(@"file", @"File Explorer Panel")], @selector(togglePrimarySidePanel:), @"1", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(viewMenu, [NSString stringWithFormat: @"%@ (⌥⌘2)", L(@"cmd_41020", @"Embedded Terminal Panel")], @selector(toggleBottomPanel:), @"2", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(viewMenu, [NSString stringWithFormat: @"%@ (⌥⌘3)", L(@"view-project", @"Secondary Preview Panel")], @selector(toggleSecondarySidePanel:), @"3", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    [viewMenu addItem: [NSMenuItem separatorItem]];
    addItem(viewMenu, L(@"cmd_44023", @"Word wrap"), @selector(toggleWordWrap:), @"w", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(viewMenu, L(@"dlg_6206", @"Show Line Numbers"), @selector(toggleLineNumbers:), @"", 0);
    addItem(viewMenu, L(@"dlg_6252", @"Show All Characters"), @selector(toggleShowAllCharacters:), @"", 0);
    addItem(viewMenu, L(@"dlg_7161", @"Show Indent Guide"), @selector(toggleIndentGuides:), @"", 0);
    [viewMenu addItem: [NSMenuItem separatorItem]];
    addItem(viewMenu, L(@"cmd_44033", @"Zoom In"), @selector(zoomIn:), @"+", 0);
    addItem(viewMenu, L(@"cmd_44034", @"Zoom Out"), @selector(zoomOut:), @"-", 0);
    addItem(viewMenu, L(@"cmd_44035", @"Restore Default Zoom"), @selector(zoomReset:), @"0", 0);
    [viewMenu addItem: [NSMenuItem separatorItem]];
    addItem(viewMenu, L(@"dlg_7132", @"Toggle Dark Mode"), @selector(toggleDarkMode:), @"D", 0);
    viewMenuItem.submenu = viewMenu;
    [menubar addItem: viewMenuItem];

    // 6. Encoding Menu
    NSMenuItem* encMenuItem = [[NSMenuItem alloc] init];
    NSMenu* encMenu = [[NSMenu alloc] initWithTitle: L(@"encoding", @"Encoding")];
    auto addEnc = [&](NSString* title, int enc) {
        NSMenuItem* it = [encMenu addItemWithTitle: title action: @selector(selectEncoding:) keyEquivalent: @""];
        it.target = self; it.tag = enc;
    };
    addEnc(@"UTF-8 (Standard)", 0);
    addEnc(@"UTF-8 with BOM", 1);
    addEnc(@"UTF-16 Little Endian", 2);
    addEnc(@"UTF-16 Big Endian", 3);
    addEnc(@"ANSI (Windows-1252)", 4);
    addEnc(@"Korean (EUC-KR)", 5);
    addEnc(@"Japanese (Shift-JIS)", 6);
    addEnc(@"Traditional Chinese (Big5)", 7);
    addEnc(@"Simplified Chinese (GB2312)", 8);
    [encMenu addItem: [NSMenuItem separatorItem]];
    addItem(encMenu, L(@"dlg_6403", @"Convert to Unix (LF)"), @selector(convertToLF:), @"", 0);
    addItem(encMenu, L(@"dlg_6402", @"Convert to Windows (CRLF)"), @selector(convertToCRLF:), @"", 0);
    addItem(encMenu, L(@"dlg_6404", @"Convert to Macintosh (CR)"), @selector(convertToCR:), @"", 0);
    encMenuItem.submenu = encMenu;
    [menubar addItem: encMenuItem];

    // 7. Language Menu
    NSMenuItem* langMenuItem = [[NSMenuItem alloc] init];
    NSMenu* langMenu = [[NSMenu alloc] initWithTitle: L(@"language", @"Language")];
    auto addLang = [&](NSString* title, NSString* lexer) {
        NSMenuItem* it = [langMenu addItemWithTitle: title action: @selector(selectLanguage:) keyEquivalent: @""];
        it.target = self; it.representedObject = lexer;
    };
    addLang(@"Plain Text", @"text");
    [langMenu addItem: [NSMenuItem separatorItem]];
    addLang(@"C", @"cpp"); addLang(@"C++", @"cpp"); addLang(@"C#", @"cpp"); addLang(@"Java", @"java");
    addLang(@"JavaScript", @"javascript"); addLang(@"TypeScript", @"typescript"); addLang(@"Python", @"python");
    addLang(@"HTML", @"hypertext"); addLang(@"XML", @"xml"); addLang(@"JSON", @"json");
    addLang(@"CSS", @"css"); addLang(@"Markdown", @"markdown"); addLang(@"Rust", @"rust");
    addLang(@"Go", @"go"); addLang(@"Swift", @"cpp"); addLang(@"Kotlin", @"cpp");
    addLang(@"PHP", @"phpscript"); addLang(@"SQL", @"sql"); addLang(@"YAML", @"yaml");
    addLang(@"Shell / Bash", @"bash"); addLang(@"Lua", @"lua"); addLang(@"Makefile", @"makefile");
    langMenuItem.submenu = langMenu;
    [menubar addItem: langMenuItem];

    // 8. Settings Menu (Settings -> Preferences... / Style Configurator...)
    NSMenuItem* settingsMenuItem = [[NSMenuItem alloc] init];
    NSMenu* settingsMenu = [[NSMenu alloc] initWithTitle: L(@"settings", @"Settings")];
    addItem(settingsMenu, [NSString stringWithFormat: @"%@...", L(@"cmd_48011", L(@"dlg_title_Preference", @"Preferences"))], @selector(showPreferences:), @",", 0);
    addItem(settingsMenu, [NSString stringWithFormat: @"%@...", L(@"cmd_48002", @"Style Configurator")], @selector(showStyleConfigurator:), @"", 0);
    settingsMenuItem.submenu = settingsMenu;
    [menubar addItem: settingsMenuItem];

    // 9. Tools Menu
    NSMenuItem* toolsMenuItem = [[NSMenuItem alloc] init];
    NSMenu* toolsMenu = [[NSMenu alloc] initWithTitle: L(@"tools", @"Tools")];
    addItem(toolsMenu, @"Generate MD5 Hash", @selector(generateMD5:), @"", 0);
    addItem(toolsMenu, @"Generate SHA-256 Hash", @selector(generateSHA256:), @"", 0);
    toolsMenuItem.submenu = toolsMenu;
    [menubar addItem: toolsMenuItem];

    // 10. Macro Menu
    NSMenuItem* macroMenuItem = [[NSMenuItem alloc] init];
    NSMenu* macroMenu = [[NSMenu alloc] initWithTitle: L(@"macro", @"Macro")];
    addItem(macroMenu, L(@"cmd_42018", @"Start Recording"), @selector(startMacroRecording:), @"r", NSEventModifierFlagCommand | NSEventModifierFlagControl);
    addItem(macroMenu, L(@"cmd_42019", @"Stop Recording"), @selector(stopMacroRecording:), @"r", NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagShift);
    addItem(macroMenu, L(@"cmd_42021", @"Playback"), @selector(playbackMacro:), @"p", NSEventModifierFlagCommand | NSEventModifierFlagControl);
    [macroMenu addItem: [NSMenuItem separatorItem]];
    addItem(macroMenu, L(@"cmd_42025", @"Save Currently Recorded Macro..."), @selector(saveRecordedMacro:), @"", 0);
    addItem(macroMenu, L(@"cmd_42032", @"Run a Macro Multiple Times..."), @selector(runMacroMultipleTimes:), @"", 0);
    macroMenuItem.submenu = macroMenu;
    [menubar addItem: macroMenuItem];

    // 11. Run Menu
    NSMenuItem* runMenuItem = [[NSMenuItem alloc] init];
    NSMenu* runMenu = [[NSMenu alloc] initWithTitle: L(@"run", @"Run")];
    addItem(runMenu, L(@"cmd_49000", @"Run..."), @selector(runCommand:), @"r", NSEventModifierFlagOption | NSEventModifierFlagCommand);
    addItem(runMenu, L(@"cmd_49001", @"Validate shortcuts.xml"), @selector(validateShortcuts:), @"", 0);
    runMenuItem.submenu = runMenu;
    [menubar addItem: runMenuItem];

    // 12. Window Menu
    NSMenuItem* windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu* windowMenu = [[NSMenu alloc] initWithTitle: L(@"Window", @"Window")];
    [windowMenu addItemWithTitle: @"Minimize" action: @selector(performMiniaturize:) keyEquivalent: @"m"];
    [windowMenu addItemWithTitle: @"Zoom" action: @selector(performZoom:) keyEquivalent: @""];
    [windowMenu addItem: [NSMenuItem separatorItem]];
    addItem(windowMenu, L(@"cmd_41004", @"Close All Documents"), @selector(closeAllDocuments:), @"", 0);
    windowMenuItem.submenu = windowMenu;
    [menubar addItem: windowMenuItem];
    [NSApp setWindowsMenu: windowMenu];

    // 11. Help Menu
    NSMenuItem* helpMenuItem = [[NSMenuItem alloc] init];
    NSMenu* helpMenu = [[NSMenu alloc] initWithTitle: L(@"help", @"Help")];
    NSString* f1Str = [NSString stringWithFormat: @"%C", (unichar)NSF1FunctionKey];
    NSMenuItem* itHelp = [helpMenu addItemWithTitle: [NSString stringWithFormat: @"%@ (Help Guide)", L(@"help", @"Notepad++ Help Guide")] action: @selector(showHelpGuide:) keyEquivalent: f1Str];
    itHelp.keyEquivalentModifierMask = 0;
    itHelp.target = self;
    // Parallel shortcut ⇧⌘/ for macOS keyboards without fn-lock (F1 is system brightness)
    NSMenuItem* itHelpAlt = [helpMenu addItemWithTitle: [NSString stringWithFormat: @"%@ (⇧⌘/)", L(@"help", @"Notepad++ Help Guide")] action: @selector(showHelpGuide:) keyEquivalent: @"/"];
    itHelpAlt.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    itHelpAlt.target = self;
    [helpMenu addItem: [NSMenuItem separatorItem]];
    [helpMenu addItemWithTitle: [NSString stringWithFormat: @"%@ Notepad++", L(@"help", @"About")] action: @selector(showAbout:) keyEquivalent: @""].target = self;
    helpMenuItem.submenu = helpMenu;
    [menubar addItem: helpMenuItem];

    [NSApp setMainMenu: menubar];
}
@end

// ============================================================================
// Main Entrypoint
// ============================================================================

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        NotepadPlusAppController* controller = [[NotepadPlusAppController alloc] init];
        [app setDelegate: controller];

        [app run];
    }
    return 0;
}
