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
}

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _selectedIndex = 0;
        _isDarkMode = NO;
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
                if ([_delegate respondsToSelector: @selector(tabSelectedAtIndex:)]) {
                    [_delegate tabSelectedAtIndex: i];
                }
            }
            break;
        }
    }
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

@interface NppFindBarView : NSView
@property (nonatomic, weak) id<NppFindReplaceDelegate> delegate;
@property (nonatomic, strong) NSTextField* findField;
@property (nonatomic, strong) NSTextField* replaceField;
@property (nonatomic, strong) NSButton* matchCaseCheck;
@property (nonatomic, strong) NSButton* wholeWordCheck;
@property (nonatomic, strong) NSButton* regexCheck;
@property (nonatomic, assign) BOOL isDarkMode;
@end

@implementation NppFindBarView

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _isDarkMode = NO;
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    CGFloat y = 6.0;

    NSTextField* findLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(10, y + 2, 45, 18)];
    findLabel.stringValue = @"Find:";
    findLabel.bezeled = NO;
    findLabel.drawsBackground = NO;
    findLabel.editable = NO;
    findLabel.font = [NSFont systemFontOfSize: 12];
    [self addSubview: findLabel];

    _findField = [[NSTextField alloc] initWithFrame: NSMakeRect(60, y, 220, 22)];
    _findField.target = self;
    _findField.action = @selector(onFindNext:);
    [self addSubview: _findField];

    NSTextField* repLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(10, y + 28, 50, 18)];
    repLabel.stringValue = @"Replace:";
    repLabel.bezeled = NO;
    repLabel.drawsBackground = NO;
    repLabel.editable = NO;
    repLabel.font = [NSFont systemFontOfSize: 12];
    [self addSubview: repLabel];

    _replaceField = [[NSTextField alloc] initWithFrame: NSMakeRect(60, y + 26, 220, 22)];
    _replaceField.target = self;
    _replaceField.action = @selector(onReplace:);
    [self addSubview: _replaceField];

    NSButton* btnFindNext = [[NSButton alloc] initWithFrame: NSMakeRect(290, y - 2, 85, 24)];
    btnFindNext.title = @"Find Next";
    btnFindNext.bezelStyle = NSBezelStyleRounded;
    btnFindNext.target = self;
    btnFindNext.action = @selector(onFindNext:);
    [self addSubview: btnFindNext];

    NSButton* btnFindPrev = [[NSButton alloc] initWithFrame: NSMakeRect(380, y - 2, 85, 24)];
    btnFindPrev.title = @"Find Prev";
    btnFindPrev.bezelStyle = NSBezelStyleRounded;
    btnFindPrev.target = self;
    btnFindPrev.action = @selector(onFindPrev:);
    [self addSubview: btnFindPrev];

    NSButton* btnMarkAll = [[NSButton alloc] initWithFrame: NSMakeRect(470, y - 2, 80, 24)];
    btnMarkAll.title = @"Mark All";
    btnMarkAll.bezelStyle = NSBezelStyleRounded;
    btnMarkAll.target = self;
    btnMarkAll.action = @selector(onMarkAll:);
    [self addSubview: btnMarkAll];

    NSButton* btnReplace = [[NSButton alloc] initWithFrame: NSMakeRect(290, y + 24, 85, 24)];
    btnReplace.title = @"Replace";
    btnReplace.bezelStyle = NSBezelStyleRounded;
    btnReplace.target = self;
    btnReplace.action = @selector(onReplace:);
    [self addSubview: btnReplace];

    NSButton* btnReplaceAll = [[NSButton alloc] initWithFrame: NSMakeRect(380, y + 24, 85, 24)];
    btnReplaceAll.title = @"Replace All";
    btnReplaceAll.bezelStyle = NSBezelStyleRounded;
    btnReplaceAll.target = self;
    btnReplaceAll.action = @selector(onReplaceAll:);
    [self addSubview: btnReplaceAll];

    _matchCaseCheck = [[NSButton alloc] initWithFrame: NSMakeRect(560, y, 95, 20)];
    _matchCaseCheck.buttonType = NSButtonTypeSwitch;
    _matchCaseCheck.title = @"Match case";
    [self addSubview: _matchCaseCheck];

    _wholeWordCheck = [[NSButton alloc] initWithFrame: NSMakeRect(560, y + 26, 95, 20)];
    _wholeWordCheck.buttonType = NSButtonTypeSwitch;
    _wholeWordCheck.title = @"Whole word";
    [self addSubview: _wholeWordCheck];

    _regexCheck = [[NSButton alloc] initWithFrame: NSMakeRect(665, y, 75, 20)];
    _regexCheck.buttonType = NSButtonTypeSwitch;
    _regexCheck.title = @"Regex";
    [self addSubview: _regexCheck];

    NSButton* btnClose = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 30, y + 14, 20, 20)];
    btnClose.title = @"×";
    btnClose.bezelStyle = NSBezelStyleCircular;
    btnClose.target = self;
    btnClose.action = @selector(onClose:);
    btnClose.autoresizingMask = NSViewMinXMargin;
    [self addSubview: btnClose];
}

- (void) drawRect: (NSRect) dirtyRect {
    [super drawRect: dirtyRect];
    NSColor* bg = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.18 green: 0.18 blue: 0.18 alpha: 1.0]
                              : [NSColor colorWithCalibratedRed: 0.92 green: 0.92 blue: 0.92 alpha: 1.0];
    [bg setFill];
    NSRectFill(self.bounds);

    NSColor* border = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.10 green: 0.10 blue: 0.10 alpha: 1.0]
                                  : [NSColor colorWithCalibratedRed: 0.75 green: 0.75 blue: 0.75 alpha: 1.0];
    [border setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 1));
}

- (void) onFindNext: (id) sender {
    [_delegate findNext: _findField.stringValue
              matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
              wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onFindPrev: (id) sender {
    [_delegate findPrev: _findField.stringValue
              matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
              wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onReplace: (id) sender {
    [_delegate replaceOne: _findField.stringValue
                 withText: _replaceField.stringValue
                matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
                wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                  isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onReplaceAll: (id) sender {
    [_delegate replaceAll: _findField.stringValue
                 withText: _replaceField.stringValue
                matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
                wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
                  isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onMarkAll: (id) sender {
    [_delegate markAll: _findField.stringValue
             matchCase: (_matchCaseCheck.state == NSControlStateValueOn)
             wholeWord: (_wholeWordCheck.state == NSControlStateValueOn)
               isRegex: (_regexCheck.state == NSControlStateValueOn)];
}

- (void) onClose: (id) sender {
    [_delegate closeFindBar];
}

- (void) cancelOperation: (id) sender {
    [_delegate closeFindBar];
}

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
    btnBack.toolTip = @"Go to Parent Directory / 뒤로가기";
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

@interface NppCommandTextField : NSTextField
@property (nonatomic, weak) NppTerminalPanelView* terminalPanel;
@end

@interface NppTerminalPanelView : NSView <NSTextFieldDelegate>
@property (nonatomic, weak) id<NppTerminalPanelDelegate> delegate;
@property (nonatomic, strong) NSString* workingDirectory;
@property (nonatomic, strong) NSTextView* outputTextView;
@property (nonatomic, strong) NppCommandTextField* inputField;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, strong) NSView* statusIndicator;
@property (nonatomic, assign) BOOL isDarkMode;
@property (nonatomic, assign) BOOL isExecuting;
- (void) setWorkingDirectoryPath: (NSString *) dirPath;
- (void) appendOutput: (NSString *) text;
- (void) executeCommand: (NSString *) cmd;
- (void) handleHistoryUp;
- (void) handleHistoryDown;
@end

@implementation NppCommandTextField
- (void) keyDown: (NSEvent *) event {
    unsigned short keyCode = event.keyCode;
    if (keyCode == 126) { // Up Arrow
        [_terminalPanel handleHistoryUp];
        return;
    } else if (keyCode == 125) { // Down Arrow
        [_terminalPanel handleHistoryDown];
        return;
    }
    [super keyDown: event];
}
@end

@implementation NppTerminalPanelView {
    NSMutableArray<NSString *>* mCommandHistory;
    NSInteger mHistoryIndex;
}

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _isDarkMode = NO;
        _isExecuting = NO;
        _workingDirectory = NSHomeDirectory();
        mCommandHistory = [NSMutableArray array];
        mHistoryIndex = -1;
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    // 1. Terminal Title Bar
    NSView* header = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, self.bounds.size.width, 28)];
    header.autoresizingMask = NSViewWidthSizable;
    [self addSubview: header];

    // Status Indicator Dot (Green for ready, Yellow for running)
    _statusIndicator = [[NSView alloc] initWithFrame: NSMakeRect(8, 9, 10, 10)];
    _statusIndicator.wantsLayer = YES;
    _statusIndicator.layer.cornerRadius = 5;
    _statusIndicator.layer.backgroundColor = [NSColor colorWithCalibratedRed: 0.20 green: 0.85 blue: 0.30 alpha: 1.0].CGColor;
    [header addSubview: _statusIndicator];

    _titleLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(24, 5, self.bounds.size.width - 255, 18)];
    _titleLabel.stringValue = [NSString stringWithFormat: @"TERMINAL (zsh) — 📁 ~"];
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
    btnClear.toolTip = @"Clear screen";
    btnClear.target = self;
    btnClear.action = @selector(onClearClicked:);
    btnClear.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClear];

    NSButton* btnClose = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 25, 4, 20, 20)];
    btnClose.bezelStyle = NSBezelStyleInline;
    btnClose.title = @"×";
    btnClose.toolTip = @"Close Terminal Panel";
    btnClose.target = self;
    btnClose.action = @selector(onCloseClicked:);
    btnClose.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClose];

    // 2. Terminal Console Output Screen
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 28, self.bounds.size.width, self.bounds.size.height - 56)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview: scroll];

    _outputTextView = [[NSTextView alloc] initWithFrame: scroll.bounds];
    _outputTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _outputTextView.editable = NO;
    _outputTextView.backgroundColor = [NSColor colorWithCalibratedRed: 0.11 green: 0.11 blue: 0.12 alpha: 1.0];
    _outputTextView.textColor = [NSColor colorWithCalibratedRed: 0.92 green: 0.92 blue: 0.92 alpha: 1.0];
    _outputTextView.font = [NSFont monospacedSystemFontOfSize: 12 weight: NSFontWeightRegular];
    scroll.documentView = _outputTextView;

    [self appendOutput: [NSString stringWithFormat: @"Notepad++ macOS Interactive Console (/bin/zsh)\nWorking Directory: %@\nType commands (e.g. ls -la, git status, make) and press Enter.\n\n", _workingDirectory]];

    // 3. Input Prompt Bar
    NSTextField* promptLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(6, self.bounds.size.height - 24, 18, 20)];
    promptLabel.stringValue = @"$";
    promptLabel.bezeled = NO; promptLabel.drawsBackground = NO; promptLabel.editable = NO;
    promptLabel.font = [NSFont boldSystemFontOfSize: 13];
    promptLabel.textColor = [NSColor colorWithCalibratedRed: 0.22 green: 0.70 blue: 0.98 alpha: 1.0];
    promptLabel.autoresizingMask = NSViewMinYMargin;
    [self addSubview: promptLabel];

    _inputField = [[NppCommandTextField alloc] initWithFrame: NSMakeRect(24, self.bounds.size.height - 24, self.bounds.size.width - 30, 22)];
    _inputField.terminalPanel = self;
    _inputField.placeholderString = @"Type command (↑/↓ for history, e.g. ls -la, git status)...";
    _inputField.font = [NSFont monospacedSystemFontOfSize: 12 weight: NSFontWeightRegular];
    _inputField.delegate = self;
    _inputField.target = self;
    _inputField.action = @selector(onInputSubmitted:);
    _inputField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self addSubview: _inputField];
}

- (void) setWorkingDirectoryPath: (NSString *) dirPath {
    if (!dirPath || dirPath.length == 0) dirPath = NSHomeDirectory();
    _workingDirectory = dirPath;

    NSString* display = [dirPath isEqualToString: NSHomeDirectory()] ? @"~" : [dirPath lastPathComponent];
    _titleLabel.stringValue = [NSString stringWithFormat: @"TERMINAL (zsh) — 📁 %@", display];
}

- (void) handleHistoryUp {
    if (mCommandHistory.count > 0) {
        if (mHistoryIndex > 0) mHistoryIndex--;
        else mHistoryIndex = 0;
        _inputField.stringValue = mCommandHistory[mHistoryIndex];
    }
}

- (void) handleHistoryDown {
    if (mCommandHistory.count > 0) {
        if (mHistoryIndex < (NSInteger)mCommandHistory.count - 1) {
            mHistoryIndex++;
            _inputField.stringValue = mCommandHistory[mHistoryIndex];
        } else {
            mHistoryIndex = mCommandHistory.count;
            _inputField.stringValue = @"";
        }
    }
}

- (NSAttributedString *) parseAnsiText: (NSString *) rawText isDarkMode: (BOOL) isDark {
    NSMutableAttributedString* result = [[NSMutableAttributedString alloc] init];
    NSColor* defaultFg = isDark ? [NSColor colorWithCalibratedWhite: 0.92 alpha: 1.0]
                                : [NSColor colorWithCalibratedWhite: 0.15 alpha: 1.0];
    NSFont* defaultFont = [NSFont monospacedSystemFontOfSize: 12 weight: NSFontWeightRegular];

    NSArray<NSColor *>* standardColors = @[
        [NSColor colorWithCalibratedWhite: 0.20 alpha: 1.0],                       // Black
        [NSColor colorWithCalibratedRed: 0.95 green: 0.30 blue: 0.30 alpha: 1.0], // Red
        [NSColor colorWithCalibratedRed: 0.30 green: 0.85 blue: 0.40 alpha: 1.0], // Green
        [NSColor colorWithCalibratedRed: 0.95 green: 0.80 blue: 0.25 alpha: 1.0], // Yellow
        [NSColor colorWithCalibratedRed: 0.35 green: 0.70 blue: 0.98 alpha: 1.0], // Blue
        [NSColor colorWithCalibratedRed: 0.90 green: 0.45 blue: 0.95 alpha: 1.0], // Magenta
        [NSColor colorWithCalibratedRed: 0.30 green: 0.85 blue: 0.95 alpha: 1.0], // Cyan
        [NSColor colorWithCalibratedWhite: 0.95 alpha: 1.0]                       // White
    ];

    NSColor* currentFg = defaultFg;
    BOOL isBold = NO;

    NSScanner* scanner = [NSScanner scannerWithString: rawText];
    scanner.charactersToBeSkipped = nil;

    while (!scanner.isAtEnd) {
        NSString* textChunk = nil;
        if ([scanner scanUpToString: @"\033[" intoString: &textChunk]) {
            if (textChunk.length > 0) {
                NSFont* font = isBold ? [NSFont monospacedSystemFontOfSize: 12 weight: NSFontWeightBold] : defaultFont;
                NSDictionary* attrs = @{
                    NSFontAttributeName: font,
                    NSForegroundColorAttributeName: currentFg
                };
                [result appendAttributedString: [[NSAttributedString alloc] initWithString: textChunk attributes: attrs]];
            }
        }

        if ([scanner scanString: @"\033[" intoString: nil]) {
            NSString* codeStr = nil;
            if ([scanner scanUpToString: @"m" intoString: &codeStr]) {
                [scanner scanString: @"m" intoString: nil];
                NSArray<NSString *>* codes = [codeStr componentsSeparatedByString: @";"];
                for (NSString* c in codes) {
                    int code = [c intValue];
                    if (code == 0) {
                        currentFg = defaultFg;
                        isBold = NO;
                    } else if (code == 1) {
                        isBold = YES;
                    } else if (code >= 30 && code <= 37) {
                        currentFg = standardColors[code - 30];
                    } else if (code >= 90 && code <= 97) {
                        currentFg = standardColors[code - 90];
                    } else if (code == 39) {
                        currentFg = defaultFg;
                    }
                }
            }
        }
    }

    if (result.length == 0 && rawText.length > 0) {
        NSDictionary* attrs = @{ NSFontAttributeName: defaultFont, NSForegroundColorAttributeName: defaultFg };
        return [[NSAttributedString alloc] initWithString: rawText attributes: attrs];
    }
    return result;
}

- (void) appendOutput: (NSString *) text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTextStorage* storage = self->_outputTextView.textStorage;
        NSAttributedString* attrStr = [self parseAnsiText: text isDarkMode: YES];
        [storage appendAttributedString: attrStr];
        [self->_outputTextView scrollRangeToVisible: NSMakeRange(storage.length, 0)];
    });
}

- (void) onInputSubmitted: (id) sender {
    NSString* cmd = [_inputField.stringValue stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (cmd.length == 0) return;

    _inputField.stringValue = @"";
    [mCommandHistory addObject: cmd];
    mHistoryIndex = mCommandHistory.count;

    [self appendOutput: [NSString stringWithFormat: @"$ %@\n", cmd]];
    [self executeCommand: cmd];
}

- (void) executeCommand: (NSString *) cmd {
    if ([cmd isEqualToString: @"clear"]) {
        _outputTextView.string = @"";
        return;
    }

    if ([cmd hasPrefix: @"cd "]) {
        NSString* target = [[cmd substringFromIndex: 3] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([target isEqualToString: @"~"]) target = NSHomeDirectory();
        else if (![target hasPrefix: @"/"]) target = [_workingDirectory stringByAppendingPathComponent: target];

        target = [target stringByStandardizingPath];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath: target isDirectory: &isDir] && isDir) {
            [self setWorkingDirectoryPath: target];
            [self appendOutput: [NSString stringWithFormat: @"Directory changed to: %@\n\n", _workingDirectory]];
        } else {
            [self appendOutput: [NSString stringWithFormat: @"cd: no such directory: %@\n\n", target]];
        }
        return;
    }

    _isExecuting = YES;
    _statusIndicator.layer.backgroundColor = [NSColor colorWithCalibratedRed: 0.95 green: 0.70 blue: 0.20 alpha: 1.0].CGColor;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask* task = [[NSTask alloc] init];
        task.launchPath = @"/bin/zsh";
        task.arguments = @[@"-c", [NSString stringWithFormat: @"export CLICOLOR=1 CLICOLOR_FORCE=1 FORCE_COLOR=1 TERM=xterm-256color LSCOLORS=Gxfxcxdxbxegedabagacad; alias ls='ls -G'; %@", cmd]];
        task.currentDirectoryPath = self->_workingDirectory;

        NSMutableDictionary* env = [[[NSProcessInfo processInfo] environment] mutableCopy];
        env[@"TERM"] = @"xterm-256color";
        env[@"CLICOLOR"] = @"1";
        env[@"CLICOLOR_FORCE"] = @"1";
        env[@"FORCE_COLOR"] = @"1";
        env[@"LSCOLORS"] = @"Gxfxcxdxbxegedabagacad";
        task.environment = env;

        NSPipe* outPipe = [NSPipe pipe];
        NSPipe* errPipe = [NSPipe pipe];
        task.standardOutput = outPipe;
        task.standardError = errPipe;

        NSFileHandle* outHandle = [outPipe fileHandleForReading];
        NSFileHandle* errHandle = [errPipe fileHandleForReading];

        @try {
            [task launch];
            NSData* outData = [outHandle readDataToEndOfFile];
            NSData* errData = [errHandle readDataToEndOfFile];
            [task waitUntilExit];

            NSString* outStr = [[NSString alloc] initWithData: outData encoding: NSUTF8StringEncoding];
            NSString* errStr = [[NSString alloc] initWithData: errData encoding: NSUTF8StringEncoding];

            if (outStr.length > 0) [self appendOutput: outStr];
            if (errStr.length > 0) [self appendOutput: errStr];
            [self appendOutput: @"\n"];
        } @catch (NSException* e) {
            [self appendOutput: [NSString stringWithFormat: @"Execution failed: %@\n\n", e.reason]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_isExecuting = NO;
            self->_statusIndicator.layer.backgroundColor = [NSColor colorWithCalibratedRed: 0.20 green: 0.85 blue: 0.30 alpha: 1.0].CGColor;
        });
    });
}

- (void) onClearClicked: (id) sender { _outputTextView.string = @""; }

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
@property (nonatomic, strong) NppFindBarView* findBar;
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
    CGFloat findH = (_findBar && !_findBar.hidden) ? 60.0 : 0.0;

    if (_tabBar) _tabBar.frame = NSMakeRect(0, 0, w, tabH);
    if (_statusBar) _statusBar.frame = NSMakeRect(0, h - statusH, w, statusH);
    if (_findBar && !_findBar.hidden) _findBar.frame = NSMakeRect(0, h - statusH - findH, w, findH);

    CGFloat middleTop = tabH;
    CGFloat middleH = std::max<CGFloat>(0.0, h - statusH - findH - middleTop);

    if (_mainHorizontalSplit) {
        _mainHorizontalSplit.frame = NSMakeRect(0, middleTop, w, middleH);
    }
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
@property (nonatomic, strong) NppFindBarView* findBar;
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
@property (nonatomic, assign) NSRect lastSavedWindowFrame;
@property (nonatomic, assign) BOOL isSavingSession;
@property (nonatomic, assign) BOOL isAppTerminating;
@property (nonatomic, strong) NSString* currentLocalizationFile;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *>* localizedDict;
- (NSString *) localizedString: (NSString *) key defaultText: (NSString *) defaultText;
- (void) applyLocalization: (NSString *) xmlFileName;

- (NSString *) getDirectoryForActiveTab;
- (void) saveSessionState;
- (void) applyAllSettings;
- (void) togglePrimarySidePanel: (id) sender;
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
// Implementation of NppColumnEditorWindowController
// ============================================================================

@implementation NppColumnEditorWindowController

- (instancetype) initWithAppController: (NotepadPlusAppController *) appCtrl {
    NSRect frame = NSMakeRect(200, 200, 440, 310);
    NSWindowStyleMask mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSWindow* win = [[NSWindow alloc] initWithContentRect: frame styleMask: mask backing: NSBackingStoreBuffered defer: NO];
    win.title = @"Column Editor / 열 편집기 (⌥⌘C)";

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
    self.window.title = [NSString stringWithFormat: @"%@ (⌥⌘C)", L(@"dlg_title_ColumnEditor", @"Column Editor / 열 편집기")];

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
    self.window.title = L(@"dlg_title_Preference", @"Notepad++ Preferences");
    _categories = @[
        [NSString stringWithFormat: @"⚙️ %@", L(@"dlg_6002", @"General")],
        [NSString stringWithFormat: @"✏️ %@", L(@"dlg_6003", @"Editing & Column Mode")],
        [NSString stringWithFormat: @"📐 %@", L(@"dlg_6004", @"Margins & Border")],
        [NSString stringWithFormat: @"📄 %@", L(@"dlg_6005", @"New Document")],
        [NSString stringWithFormat: @"⇥ %@", L(@"dlg_6301", @"Indentation & Tabs")],
        [NSString stringWithFormat: @"🎨 %@", L(@"dlg_7131", @"Themes & Dark Mode")],
        [NSString stringWithFormat: @"💡 %@", L(@"dlg_6333", @"Highlighting")],
        [NSString stringWithFormat: @"⚡ %@", L(@"dlg_6807", @"Auto-Completion")],
        [NSString stringWithFormat: @"🔍 %@", L(@"dlg_6907", @"Searching")],
        [NSString stringWithFormat: @"💾 %@", L(@"dlg_6817", @"Backup & Session")],
        [NSString stringWithFormat: @"🚀 %@", L(@"dlg_7141", @"Performance")]
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
        @[@"한국어 (Korean)", @"korean.xml"],
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
            addTitle(L(@"dlg_6002", @"General Settings / 일반 설정"));

            // 1. Localization / 표시 언어 Box (94 Languages Dropdown)
            NSBox* boxLang = addBox(L(@"dlg_6508", @"Localization / 표시 언어"), r.size.height - 145, 95);
            NSTextField* lblLang = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 42, 175, 18)];
            lblLang.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_6411", @"Display Language / 표시언어")];
            lblLang.bezeled = NO; lblLang.drawsBackground = NO; lblLang.editable = NO;
            lblLang.font = [NSFont systemFontOfSize: 12 weight: NSFontWeightMedium];
            [boxLang.contentView addSubview: lblLang];

            NSPopUpButton* popLang = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(195, 38, 320, 26) pullsDown: NO];
            [self populateLocalizationPopUp: popLang];
            popLang.target = self;
            popLang.action = @selector(onLocalizationSelected:);
            [boxLang.contentView addSubview: popLang];

            NSTextField* lblHint = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 12, boxLang.contentView.bounds.size.width - 30, 18)];
            lblHint.stringValue = @"🌐 Notepad++ 94개국 공식 로컬라이제이션 언어 팩 지원 (메뉴바 및 UI 전체 연동)";
            lblHint.bezeled = NO; lblHint.drawsBackground = NO; lblHint.editable = NO;
            lblHint.font = [NSFont systemFontOfSize: 11];
            lblHint.textColor = [NSColor secondaryLabelColor];
            [boxLang.contentView addSubview: lblHint];

            // 2. Tab Bar & Window Box
            NSBox* box1 = addBox(L(@"dlg_6345", @"Tab Bar & Window / 탭 및 창 관리"), r.size.height - 275, 120);
            addCheck(box1, L(@"dlg_6345_close", @"Show close button on each tab (각 탭에 닫기 버튼 표시)"), 65, YES, nil);
            addCheck(box1, L(@"dlg_6345_dbl", @"Double click to close tab (더블 클릭으로 탭 닫기)"), 40, YES, nil);
            addCheck(box1, L(@"dlg_6345_pin", @"Pin Tab support (고정 탭 기능 지원)"), 15, YES, nil);

            // 3. Status Bar, Panels & Toolbar Box
            NSBox* box2 = addBox(L(@"dlg_6181", @"Status Bar, Panels & Toolbar / 상태 표시줄 및 패널"), r.size.height - 405, 120);
            addCheck(box2, L(@"dlg_6181_status", @"Show Segmented Status Bar (상태 표시줄 표시)"), 65, YES, nil);
            addCheck(box2, L(@"dlg_6181_panels", @"Show Resizable 3-Panel Layout Toolbar Icons (3대 패널 도구 아이콘)"), 40, YES, nil);
            addCheck(box2, L(@"dlg_6181_title", @"Enable Unified macOS Window Titlebar (macOS 통합 타이틀바)"), 15, YES, nil);
            break;
        }
        case 1: { // Editing & Column Mode
            addTitle(L(@"dlg_6003", @"Editor, Multi-Selection & Column Mode"));
            NSBox* box1 = addBox(L(@"dlg_6521", @"Column Mode & Multi-Selection"), r.size.height - 190, 140);
            addCheck(box1, L(@"dlg_6522", @"Enable Multi-Selection & Multi-Caret (⌘ + Click)"), 85, YES, nil);
            addCheck(box1, L(@"dlg_6523", @"Enable Column Mode / Rectangular Selection (⌥ + Drag or ⌥⇧ + Arrows)"), 60, YES, nil);
            addCheck(box1, L(@"dlg_6256", @"Enable Virtual Space on Rectangular Selection"), 35, YES, nil);
            addCheck(box1, L(@"dlg_6521_paste", @"Multi-Paste into each selected column line"), 10, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6252", @"Non-Printing Characters"), r.size.height - 310, 100);
            addCheck(box2, L(@"dlg_6302", @"Show White Space characters"), 45, _appController.showWhiteSpace, @selector(onToggleWhiteSpace:));
            addCheck(box2, L(@"dlg_6247", @"Show End of Line (EOL) marks"), 15, _appController.showEOL, @selector(onToggleEOL:));
            break;
        }
        case 2: { // Margins
            addTitle(L(@"dlg_6004", @"Margins, Border & Column Edge"));
            NSBox* box1 = addBox(L(@"dlg_6201", @"Margins Display"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_6206", @"Display Line Numbers Margin"), 75, _appController.showLineNumbers, @selector(onToggleLineNumbers:));
            addCheck(box1, L(@"dlg_6207", @"Display Bookmark & Symbol Margin"), 50, _appController.showBookmarksMargin, nil);
            addCheck(box1, L(@"dlg_6205", @"Display Code Folding Margin"), 25, _appController.showFoldingMargin, nil);

            NSBox* box2 = addBox(L(@"dlg_6211", @"Vertical Column Guide Line"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6211_enable", @"Show Vertical Column Guide (Edge Line)"), 45, _appController.showColumnGuide, @selector(onToggleColumnGuide:));

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
            addTitle(L(@"dlg_6005", @"New Document Defaults"));
            NSBox* box1 = addBox(L(@"dlg_6401", @"Default Format / Line Endings (EOL)"), r.size.height - 160, 110);
            NSPopUpButton* popEOL = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popEOL addItemsWithTitles: @[L(@"dlg_6403", @"Unix (LF) - macOS Standard"), L(@"dlg_6402", @"Windows (CR LF)"), L(@"dlg_6404", @"Macintosh (CR)")]];
            [popEOL selectItemAtIndex: _appController.defaultNewEOL == 2 ? 0 : (_appController.defaultNewEOL == 0 ? 1 : 2)];
            popEOL.target = self; popEOL.action = @selector(onSelectNewEOL:);
            [box1.contentView addSubview: popEOL];

            NSBox* box2 = addBox(L(@"dlg_6405", @"Default Encoding"), r.size.height - 290, 110);
            NSPopUpButton* popEnc = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popEnc addItemsWithTitles: @[L(@"dlg_6407", @"UTF-8 (macOS Default)"), L(@"dlg_6408", @"UTF-8 with BOM"), L(@"dlg_6410", @"UTF-16 LE"), L(@"dlg_6409", @"UTF-16 BE"), L(@"dlg_6406", @"ANSI"), @"Korean (EUC-KR)", @"Japanese (Shift-JIS)"]];
            [popEnc selectItemAtIndex: _appController.defaultNewEncoding];
            popEnc.target = self; popEnc.action = @selector(onSelectNewEncoding:);
            [box2.contentView addSubview: popEnc];
            addCheck(box2, L(@"dlg_6420", @"Apply UTF-8 encoding to opened ANSI files"), 15, YES, nil);
            break;
        }
        case 4: { // Indentation
            addTitle(L(@"dlg_6301", @"Indentation & Tab Settings"));
            NSBox* box1 = addBox(L(@"dlg_6301_tab", @"Tab Configuration"), r.size.height - 180, 130);
            NSTextField* lblTab = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 75, 120, 20)];
            lblTab.stringValue = [NSString stringWithFormat: @"%@:", L(@"dlg_6303", @"Tab Size (spaces)")];
            lblTab.bezeled = NO; lblTab.drawsBackground = NO; lblTab.editable = NO;
            [box1.contentView addSubview: lblTab];

            NSPopUpButton* popTab = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(140, 73, 100, 24) pullsDown: NO];
            [popTab addItemsWithTitles: @[@"2", @"4", @"8"]];
            [popTab selectItemWithTitle: [NSString stringWithFormat: @"%d", _appController.currentTabWidth]];
            popTab.target = self; popTab.action = @selector(onSelectTabWidth:);
            [box1.contentView addSubview: popTab];

            addCheck(box1, L(@"dlg_6302", @"Replace tabs by spaces (Soft Tabs)"), 45, _appController.useSpacesForTabs, @selector(onToggleUseSpaces:));
            addCheck(box1, L(@"dlg_6512", @"Backspace unindents"), 15, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_7161", @"Indentation Guides & Smart Indent"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_7161_guide", @"Show Indentation Guides"), 45, _appController.showIndentGuides, @selector(onToggleIndentGuides:));
            addCheck(box2, L(@"dlg_7163", @"Smart Auto-Indentation on Enter"), 15, YES, nil);
            break;
        }
        case 5: { // Themes
            addTitle(L(@"dlg_7131", @"Color Themes & Typography"));
            NSBox* box1 = addBox(L(@"dlg_7135", @"Color Theme"), r.size.height - 160, 110);
            NSPopUpButton* popTheme = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popTheme addItemsWithTitles: @[
                @"🌙 Notepad++ Dark (Default Dark)",
                @"☀️ Default Light (Classic)",
                @"🌌 Monokai Pro (Dark)",
                @"🧛 Dracula (Vibrant Dark)",
                @"🌊 Solarized Dark",
                @"🏖️ Solarized Light",
                @"🌋 Obsidian (Dark)"
            ]];
            [popTheme selectItemWithTitle: _appController.currentThemeName];
            popTheme.target = self; popTheme.action = @selector(onSelectTheme:);
            [box1.contentView addSubview: popTheme];

            NSBox* box2 = addBox(L(@"dlg_7135_font", @"Editor Font & Size"), r.size.height - 310, 130);
            NSTextField* lblFont = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 75, 100, 20)];
            lblFont.stringValue = @"Font Family:";
            lblFont.bezeled = NO; lblFont.drawsBackground = NO; lblFont.editable = NO;
            [box2.contentView addSubview: lblFont];

            NSPopUpButton* popFont = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(120, 73, 160, 24) pullsDown: NO];
            [popFont addItemsWithTitles: @[@"SF Mono", @"Menlo", @"Monaco", @"Courier New", @"Consolas"]];
            [popFont selectItemWithTitle: _appController.currentFontName];
            popFont.target = self; popFont.action = @selector(onSelectFont:);
            [box2.contentView addSubview: popFont];

            NSTextField* lblSize = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 35, 100, 20)];
            lblSize.stringValue = @"Font Size:";
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
            addTitle(L(@"dlg_6333", @"Highlighting & Matching"));
            NSBox* box1 = addBox(L(@"dlg_6329", @"Brace & Tag Matching"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_7147", @"Highlight matching braces () [] {}"), 75, _appController.matchBraces, @selector(onToggleMatchBraces:));
            addCheck(box1, L(@"dlg_6327", @"Highlight matching HTML/XML tags"), 50, YES, nil);
            addCheck(box1, L(@"dlg_6330", @"Highlight current line background (Neutral Gray)"), 25, _appController.highlightCurrentLine, @selector(onToggleHighlightLine:));

            NSBox* box2 = addBox(L(@"dlg_6333", @"Smart Highlighting"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6326", @"Smart Highlighting (Highlight matching word occurrences)"), 45, _appController.smartHighlighting, @selector(onToggleSmartHighlight:));
            addCheck(box2, L(@"dlg_6332", @"Match case for Smart Highlighting"), 15, YES, nil);
            break;
        }
        case 7: { // Auto-Completion
            addTitle(L(@"dlg_6807", @"Auto-Completion & Pair Insertion"));
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
            addTitle(L(@"dlg_6907", @"Searching & Find In Files"));
            NSBox* box1 = addBox(L(@"dlg_6907", @"When Find Dialog is Invoked"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_6908", @"Fill Find Field with Selected Text"), 75, YES, nil);
            addCheck(box1, L(@"dlg_6909", @"Select Word Under Caret when Nothing Selected"), 50, YES, nil);
            addCheck(box1, L(@"dlg_6913", @"Fill Find in Files Directory Field Based On Active Document"), 25, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6904", @"Search Result window"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6906", @"Show only one entry per found line if possible"), 45, YES, nil);
            addCheck(box2, L(@"dlg_6917", @"Find in Files: Prefer on-disk file content over open buffers"), 15, YES, nil);
            break;
        }
        case 9: { // Backup & Session
            addTitle(L(@"dlg_6817", @"Backup & Session Snapshot"));
            NSBox* box1 = addBox(L(@"dlg_6817", @"Session Snapshot & Periodic Backup"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_6818", @"Enable session snapshot and periodic backup"), 75, _appController.rememberSession, @selector(onToggleRememberSession:));
            addCheck(box1, L(@"dlg_6309", @"Remember current session for next launch"), 50, _appController.rememberSession, nil);
            addCheck(box1, L(@"dlg_6825", @"Remember inaccessible files from past session"), 25, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6801", @"Backup on Save"), r.size.height - 300, 100);
            addCheck(box2, L(@"dlg_6316", @"Simple backup (.bak file creation)"), 45, NO, nil);
            addCheck(box2, L(@"dlg_6317", @"Verbose backup with timestamp"), 15, NO, nil);
            break;
        }
        case 10: { // Performance
            addTitle(L(@"dlg_7141", @"Performance & Hardware Acceleration"));
            NSBox* box1 = addBox(L(@"dlg_7141", @"Large File Restriction"), r.size.height - 180, 130);
            addCheck(box1, L(@"dlg_7143", @"Enable Large File Restriction (Deactivate heavy lexers for >50MB)"), 75, YES, nil);
            addCheck(box1, L(@"dlg_7150", @"Deactivate Word Wrap globally for huge files"), 50, YES, nil);
            addCheck(box1, L(@"dlg_7152", @"Suppress warning when opening large files"), 25, YES, nil);

            NSBox* box2 = addBox(L(@"dlg_6363", @"Rendering & Hardware Acceleration"), r.size.height - 300, 100);
            addCheck(box2, @"Direct2D / Metal Hardware Accelerated Text Rendering", 45, YES, nil);
            addCheck(box2, @"Subpixel Anti-Aliasing (Retina Font Smoothing)", 15, YES, nil);
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

            // Retrieve full buffer text for both saved and unsaved/untitled documents
            NSString* content = @"";
            if (_editor && doc.pDoc) {
                if (static_cast<NSInteger>(i) == mActiveIndex) {
                    content = [_editor string] ?: @"";
                } else if (!_isAppTerminating) {
                    [_editor message: SCI_SETDOCPOINTER wParam: 0 lParam: reinterpret_cast<sptr_t>(doc.pDoc)];
                    content = [_editor string] ?: @"";
                }
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

        // Restore original active doc pointer
        if (_editor && originalDocPointer && !_isAppTerminating) {
            [_editor message: SCI_SETDOCPOINTER wParam: 0 lParam: originalDocPointer];
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

- (void) showHelpGuide: (id) sender {
    // 1. Find HELP_GUIDE.md
    NSArray<NSString *>* searchPaths = @[
        [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"HELP_GUIDE.md"],
        @"/Users/mac/Antigravity/notepadpp/PowerEditor/src/HELP_GUIDE.md",
        @"PowerEditor/src/HELP_GUIDE.md"
    ];

    NSString* helpContent = nil;
    for (NSString* p in searchPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath: p]) {
            helpContent = [NSString stringWithContentsOfFile: p encoding: NSUTF8StringEncoding error: nil];
            if (helpContent) break;
        }
    }

    if (!helpContent) {
        helpContent = @"# 📘 Notepad++ for macOS Help\n\n도움말 문서를 불러올 수 없습니다.";
    }

    // 2. Open Secondary Preview Side Bar
    _rootContentView.isSecondarySidePanelVisible = YES;
    [_rootContentView updateSplitLayout];

    // 3. Render HELP_GUIDE.md in the right panel
    [_secondarySidePanel renderDocumentContent: helpContent fileName: @"HELP_GUIDE.md" lexerName: @"markdown"];
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

    // 3. Find Bar
    _findBar = [[NppFindBarView alloc] initWithFrame: NSMakeRect(0, frame.size.height - 84, frame.size.width, 60)];
    _findBar.delegate = self;
    _findBar.hidden = YES;
    [_rootContentView addSubview: _findBar];
    _rootContentView.findBar = _findBar;

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
static NSString* const kToolbarMacroPlay        = @"kToolbarMacroPlay";
static NSString* const kToolbarSummary          = @"kToolbarSummary";
static NSString* const kToolbarTogglePrimary    = @"kToolbarTogglePrimary";   // Left Finder Panel
static NSString* const kToolbarToggleBottom     = @"kToolbarToggleBottom";    // Bottom Embedded Terminal Panel
static NSString* const kToolbarToggleSecondary  = @"kToolbarToggleSecondary"; // Right Language-aware Preview
static NSString* const kToolbarDarkMode         = @"kToolbarDarkMode";
static NSString* const kToolbarSettings         = @"kToolbarSettings";

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
        kToolbarMacroRec, kToolbarMacroPlay, kToolbarSummary,
        NSToolbarFlexibleSpaceItemIdentifier,
        kToolbarTogglePrimary, kToolbarToggleBottom, kToolbarToggleSecondary,
        NSToolbarSeparatorItemIdentifier,
        kToolbarDarkMode, kToolbarSettings
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
        kToolbarMacroRec, kToolbarMacroPlay,
        NSToolbarFlexibleSpaceItemIdentifier,
        kToolbarTogglePrimary, kToolbarToggleBottom, kToolbarToggleSecondary,
        NSToolbarSeparatorItemIdentifier,
        kToolbarDarkMode, kToolbarSettings
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
    else if ([itemIdentifier isEqualToString: kToolbarColumnEditor]) makeItem(@"Column Editor", @"Column Editor / 열 편집기 (⌥⌘C)", @"tablecells", @selector(showColumnEditorDialog:));
    else if ([itemIdentifier isEqualToString: kToolbarWordWrap]) makeItem(@"Wrap", @"Toggle word wrap (⌥⌘W)", @"text.wrap", @selector(toggleWordWrap:));
    else if ([itemIdentifier isEqualToString: kToolbarAllChars]) makeItem(@"All Chars", @"Show White Space & EOL", @"paragraphsign", @selector(toggleShowAllCharacters:));
    else if ([itemIdentifier isEqualToString: kToolbarMacroRec]) makeItem(@"Record", @"Start/Stop Macro Recording (⌃⌘R)", @"record.circle", @selector(toggleMacroRecording:));
    else if ([itemIdentifier isEqualToString: kToolbarMacroPlay]) makeItem(@"Playback", @"Play Macro (⌃⌘P)", @"play.circle", @selector(playbackMacro:));
    else if ([itemIdentifier isEqualToString: kToolbarSummary]) makeItem(@"Summary", @"Document Summary", @"chart.bar.doc.horizontal", @selector(showSummaryDialog:));

    // VS Code Layout Toggle Icons
    else if ([itemIdentifier isEqualToString: kToolbarTogglePrimary]) makeItem(@"Primary Side Bar", @"Toggle Primary Side Panel (Finder Tree) (⌘B)", @"sidebar.left", @selector(togglePrimarySidePanel:));
    else if ([itemIdentifier isEqualToString: kToolbarToggleBottom]) makeItem(@"Bottom Panel", @"Toggle Embedded Terminal Panel (⌃`)", @"dock.rectangle", @selector(toggleBottomPanel:));
    else if ([itemIdentifier isEqualToString: kToolbarToggleSecondary]) makeItem(@"Secondary Side Bar", @"Toggle Secondary Side Panel (Language Preview) (⇧⌘P)", @"sidebar.right", @selector(toggleSecondarySidePanel:));

    else if ([itemIdentifier isEqualToString: kToolbarDarkMode]) makeItem(@"Theme", @"Toggle Dark/Light Mode (⇧⌘D)", @"circle.righthalf.filled", @selector(toggleDarkMode:));
    else if ([itemIdentifier isEqualToString: kToolbarSettings]) makeItem(@"Preferences", @"Preferences (⌘,)", @"gearshape", @selector(showPreferences:));

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
    return NSHomeDirectory(); // Default to ~/ for new/untitled tabs
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
        [_window makeFirstResponder: _bottomPanel.inputField];
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

- (void) showColumnModeTip: (id) sender {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"🔲 열 모드 편집 팁 (Column Mode Editing)";
    alert.informativeText =
        @"1. 마우스로 사각형 블록 선택:\n"
        @"   ⌥ (Option) 키를 누른 채 마우스를 드래그하세요.\n\n"
        @"2. 키보드로 사각형 블록 선택:\n"
        @"   ⌥ + ⇧ + 방향키 (Option + Shift + ↑/↓/←/→)를 누르세요.\n\n"
        @"3. 다중 커서 동시 입력:\n"
        @"   선택된 사각형 블록 상태에서 글자를 입력하면 모든 행에 동시에 입력됩니다.\n\n"
        @"4. 연속 번호 / 공통 텍스트 일괄 삽입:\n"
        @"   '열 편집기 (⌥⌘C)'를 이용해 1, 2, 3... 번호나 텍스트를 일괄 삽입할 수 있습니다.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle: @"열 편집기 열기 (Column Editor)"];
    [alert addButtonWithTitle: @"확인"];

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
    [_editor message: SCI_SETVIRTUALSPACEOPTIONS wParam: (SCVS_RECTANGULARSELECTION | SCVS_USERACCESSIBLE) lParam: 0];

    // Tabs & Indentation
    [_editor message: SCI_SETTABWIDTH wParam: _currentTabWidth lParam: 0];
    [_editor message: SCI_SETUSETABS wParam: _useSpacesForTabs ? 0 : 1 lParam: 0];
    [_editor message: SCI_SETTABINDENTS wParam: 1 lParam: 0];
    [_editor message: SCI_SETBACKSPACEUNINDENTS wParam: 1 lParam: 0];
    [_editor message: SCI_SETINDENTATIONGUIDES wParam: _showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE lParam: 0];

    // Caret & Line (High-visibility 2px Retina Caret)
    [_editor message: SCI_SETCARETSTYLE wParam: CARETSTYLE_LINE lParam: 0];
    [_editor message: SCI_SETCARETWIDTH wParam: 2 lParam: 0];
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

    _tabBar.isDarkMode = _isDarkMode;
    [_tabBar setNeedsDisplay: YES];

    _primarySidePanel.isDarkMode = _isDarkMode;
    [_primarySidePanel setNeedsDisplay: YES];

    _bottomPanel.isDarkMode = _isDarkMode;
    [_bottomPanel setNeedsDisplay: YES];

    _secondarySidePanel.isDarkMode = _isDarkMode;
    [_secondarySidePanel setNeedsDisplay: YES];

    _statusBar.isDarkMode = _isDarkMode;
    [_statusBar setNeedsDisplay: YES];

    _findBar.isDarkMode = _isDarkMode;
    [_findBar setNeedsDisplay: YES];

    NSColor* bgCol = [NSColor whiteColor];
    NSColor* foreCol = [NSColor blackColor];
    // Translucent contrasting caret line (Light theme: soft sky blue highlight)
    NSColor* caretLineCol = [NSColor colorWithCalibratedRed: 0.10 green: 0.50 blue: 1.00 alpha: 1.0];
    NSColor* caretColor = [NSColor colorWithCalibratedRed: 0.00 green: 0.45 blue: 0.90 alpha: 1.0];
    NSColor* selCol = [NSColor colorWithCalibratedRed: 0.78 green: 0.80 blue: 0.84 alpha: 1.0];
    NSColor* marginBg = [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];
    NSColor* marginFore = [NSColor colorWithCalibratedRed: 0.45 green: 0.45 blue: 0.45 alpha: 1.0];

    if ([_currentThemeName containsString: @"Monokai"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.16 green: 0.15 blue: 0.17 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.97 green: 0.97 blue: 0.94 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.95 green: 0.90 blue: 0.55 alpha: 1.0]; // Contrasting warm amber tint
        caretColor = [NSColor colorWithCalibratedRed: 0.95 green: 0.90 blue: 0.55 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.38 green: 0.37 blue: 0.42 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.17 blue: 0.19 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.55 green: 0.55 blue: 0.55 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Dracula"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.16 green: 0.17 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.95 green: 0.95 blue: 0.96 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.75 green: 0.55 blue: 0.98 alpha: 1.0]; // Contrasting soft violet tint
        caretColor = [NSColor colorWithCalibratedRed: 0.75 green: 0.55 blue: 0.98 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.36 green: 0.38 blue: 0.48 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.19 blue: 0.23 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.50 green: 0.52 blue: 0.60 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Solarized Dark"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.00 green: 0.17 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.51 green: 0.58 blue: 0.59 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.15 green: 0.85 blue: 0.80 alpha: 1.0]; // Contrasting cyan-teal tint
        caretColor = [NSColor colorWithCalibratedRed: 0.15 green: 0.85 blue: 0.80 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.14 green: 0.34 blue: 0.40 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.04 green: 0.19 blue: 0.23 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.40 green: 0.48 blue: 0.50 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Solarized Light"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.99 green: 0.96 blue: 0.89 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.40 green: 0.48 blue: 0.51 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.15 green: 0.45 blue: 0.65 alpha: 1.0]; // Contrasting ocean tint
        caretColor = [NSColor colorWithCalibratedRed: 0.15 green: 0.45 blue: 0.65 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.84 green: 0.82 blue: 0.74 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.94 green: 0.91 blue: 0.84 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.58 green: 0.63 blue: 0.63 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Obsidian"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.18 green: 0.20 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.88 green: 0.88 blue: 0.88 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.45 green: 0.85 blue: 0.95 alpha: 1.0]; // Contrasting glacier cyan tint
        caretColor = [NSColor colorWithCalibratedRed: 0.45 green: 0.85 blue: 0.95 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.36 green: 0.42 blue: 0.48 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.20 blue: 0.21 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.50 green: 0.52 blue: 0.54 alpha: 1.0];
    } else if (_isDarkMode) {
        bgCol = [NSColor colorWithCalibratedRed: 0.13 green: 0.13 blue: 0.14 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.90 green: 0.90 blue: 0.90 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.35 green: 0.70 blue: 1.00 alpha: 1.0]; // Contrasting soft azure tint
        caretColor = [NSColor colorWithCalibratedRed: 0.25 green: 0.75 blue: 1.00 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.35 green: 0.37 blue: 0.42 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.18 blue: 0.20 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.60 green: 0.60 blue: 0.60 alpha: 1.0];
    }

    [_editor setColorProperty: SCI_STYLESETFORE parameter: STYLE_DEFAULT value: foreCol];
    [_editor setColorProperty: SCI_STYLESETBACK parameter: STYLE_DEFAULT value: bgCol];
    [_editor message: SCI_STYLECLEARALL];

    [_editor setColorProperty: SCI_STYLESETBACK parameter: STYLE_LINENUMBER value: marginBg];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: STYLE_LINENUMBER value: marginFore];

    [_editor message: SCI_SETCARETSTYLE wParam: CARETSTYLE_LINE lParam: 0];
    [_editor message: SCI_SETCARETWIDTH wParam: 2 lParam: 0];
    [_editor message: SCI_SETCARETPERIOD wParam: 500 lParam: 0];
    [_editor setColorProperty: SCI_SETCARETFORE parameter: 0 value: caretColor];
    [_editor setColorProperty: SCI_SETCARETLINEBACK parameter: 0 value: caretLineCol];
    [_editor message: SCI_SETCARETLINEBACKALPHA wParam: 50 lParam: 0];
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

- (void) newDocumentWithTitle: (NSString *) title {
    NppDocument doc;
    doc.title = utf8_to_wstring([title UTF8String]);
    doc.filePath = doc.title;
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

    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        mDocuments[mActiveIndex].cursorPosition = static_cast<int>([_editor message: SCI_GETCURRENTPOS]);
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

- (void) saveDocumentAtIndex: (NSInteger) index {
    if (index < 0 || index >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[index];

    if (doc.isUntitled) {
        [self saveDocumentAsAtIndex: index];
        return;
    }

    if (index == mActiveIndex) {
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
            [_editor message: SCI_SETSAVEPOINT];
        }
    }

    [self updateWindowTitle];
    [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
    [self updateStatusBar];
}

- (void) saveDocumentAsAtIndex: (NSInteger) index {
    if (index < 0 || index >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[index];

    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.title = @"Save As";
    panel.nameFieldStringValue = [NSString stringWithUTF8String: wstring_to_utf8(doc.title).c_str()];

    if ([panel runModal] == NSModalResponseOK) {
        NSURL* url = panel.URL;
        doc.filePath = utf8_to_wstring([url.path UTF8String]);
        doc.title = utf8_to_wstring([[url lastPathComponent] UTF8String]);
        doc.isUntitled = false;
        doc.lexerName = [self detectLexerForPath: doc.filePath];

        [self saveDocumentAtIndex: index];
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
            [self saveDocumentAtIndex: index];
        } else if (res == NSAlertThirdButtonReturn) {
            return;
        }
    }

    if (doc.pDoc) {
        [_editor message: SCI_RELEASEDOCUMENT wParam: 0 lParam: reinterpret_cast<sptr_t>(doc.pDoc)];
    }

    mDocuments.erase(mDocuments.begin() + index);

    if (mDocuments.empty()) {
        [self newDocumentWithTitle: [NSString stringWithFormat: @"new %d", mUntitledCounter]];
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
- (void) tabClosedAtIndex: (NSInteger) index { [self closeDocumentAtIndex: index]; }
- (void) newTabRequested { [self newDocumentWithTitle: [NSString stringWithFormat: @"new %d", mUntitledCounter]]; }

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
    addContextItem(@"Rename...", @selector(renameCurrentFile:));
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
            [self updateLivePreviewForActiveDocument];
            [self saveSessionState];
        }
    } else if (notification->nmhdr.code == SCN_UPDATEUI) {
        [self updateStatusBar];

        if (_matchBraces) {
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
    if (regex) flags |= SCFIND_REGEXP;

    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];

    sptr_t curPos = [_editor message: SCI_GETCURRENTPOS];
    sptr_t docLength = [_editor message: SCI_GETLENGTH];

    [_editor message: SCI_SETTARGETSTART wParam: curPos lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];

    const char* q = [query UTF8String];
    sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];

    if (pos == -1) {
        [_editor message: SCI_SETTARGETSTART wParam: 0 lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: curPos lParam: 0];
        pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];
    }

    if (pos != -1) {
        sptr_t tStart = [_editor message: SCI_GETTARGETSTART];
        sptr_t tEnd = [_editor message: SCI_GETTARGETEND];
        [_editor message: SCI_SETSEL wParam: tStart lParam: tEnd];
        [_editor message: SCI_SCROLLCARET];
    } else {
        NSBeep();
    }
}

- (void) findPrev: (NSString *) query matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    if (!query || query.length == 0) return;

    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;
    if (ww) flags |= SCFIND_WHOLEWORD;
    if (regex) flags |= SCFIND_REGEXP;

    [_editor message: SCI_SETSEARCHFLAGS wParam: flags lParam: 0];

    sptr_t curPos = [_editor message: SCI_GETSELECTIONSTART];

    [_editor message: SCI_SETTARGETSTART wParam: curPos lParam: 0];
    [_editor message: SCI_SETTARGETEND wParam: 0 lParam: 0];

    const char* q = [query UTF8String];
    sptr_t pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];

    if (pos == -1) {
        sptr_t docLength = [_editor message: SCI_GETLENGTH];
        [_editor message: SCI_SETTARGETSTART wParam: docLength lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: curPos lParam: 0];
        pos = [_editor message: SCI_SEARCHINTARGET wParam: strlen(q) lParam: reinterpret_cast<sptr_t>(q)];
    }

    if (pos != -1) {
        sptr_t tStart = [_editor message: SCI_GETTARGETSTART];
        sptr_t tEnd = [_editor message: SCI_GETTARGETEND];
        [_editor message: SCI_SETSEL wParam: tStart lParam: tEnd];
        [_editor message: SCI_SCROLLCARET];
    } else {
        NSBeep();
    }
}

- (void) replaceOne: (NSString *) query withText: (NSString *) rep matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];

    if (selEnd > selStart) {
        const char* r = [rep UTF8String];
        [_editor message: SCI_REPLACESEL wParam: 0 lParam: reinterpret_cast<sptr_t>(r)];
    }
    [self findNext: query matchCase: mc wholeWord: ww isRegex: regex];
}

- (void) replaceAll: (NSString *) query withText: (NSString *) rep matchCase: (BOOL) mc wholeWord: (BOOL) ww isRegex: (BOOL) regex {
    if (!query || query.length == 0) return;

    [_editor message: SCI_BEGINUNDOACTION];

    int flags = 0;
    if (mc) flags |= SCFIND_MATCHCASE;
    if (ww) flags |= SCFIND_WHOLEWORD;
    if (regex) flags |= SCFIND_REGEXP;

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
    if (regex) flags |= SCFIND_REGEXP;

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
        sptr_t line = [_editor message: SCI_LINEFROMPOSITION wParam: tStart];
        [_editor message: SCI_MARKERADD wParam: line lParam: 25];

        [_editor message: SCI_SETTARGETSTART wParam: tEnd lParam: 0];
        [_editor message: SCI_SETTARGETEND wParam: docLength lParam: 0];
        count++;
    }

    _statusBar.statusText = [NSString stringWithFormat: @"Marked %d match(es)", count];
    [_statusBar setNeedsDisplay: YES];
}

- (void) closeFindBar {
    _findBar.hidden = YES;
    [_rootContentView updateSplitLayout];
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

- (void) saveFile: (id) sender { [self saveDocumentAtIndex: mActiveIndex]; }
- (void) saveFileAs: (id) sender { [self saveDocumentAsAtIndex: mActiveIndex]; }
- (void) saveAllFiles: (id) sender {
    for (size_t i = 0; i < mDocuments.size(); ++i) [self saveDocumentAtIndex: i];
}
- (void) closeTab: (id) sender { [self closeDocumentAtIndex: mActiveIndex]; }
- (void) closeAllDocuments: (id) sender {
    while (!mDocuments.empty() && !(mDocuments.size() == 1 && mDocuments[0].isUntitled)) {
        [self closeDocumentAtIndex: 0];
    }
}
- (void) closeAllButActive: (id) sender {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    for (NSInteger i = static_cast<NSInteger>(mDocuments.size()) - 1; i >= 0; --i) {
        if (i != mActiveIndex) [self closeDocumentAtIndex: i];
    }
}
- (void) closeAllLeft: (id) sender {
    for (NSInteger i = mActiveIndex - 1; i >= 0; --i) [self closeDocumentAtIndex: i];
}
- (void) closeAllRight: (id) sender {
    for (NSInteger i = static_cast<NSInteger>(mDocuments.size()) - 1; i > mActiveIndex; --i) [self closeDocumentAtIndex: i];
}
- (void) togglePinTab: (id) sender {
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        mDocuments[mActiveIndex].isPinned = !mDocuments[mActiveIndex].isPinned;
        [_tabBar updateTabs: mDocuments selectedIndex: mActiveIndex];
    }
}

- (void) renameCurrentFile: (id) sender {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[mActiveIndex];

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename File";
    alert.informativeText = @"Enter new filename:";
    NSTextField* input = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 260, 24)];
    input.stringValue = [NSString stringWithUTF8String: wstring_to_utf8(doc.title).c_str()];
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
    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *>* sorted = [lines mutableCopy];
    [sorted sortUsingSelector: @selector(localizedCaseInsensitiveCompare:)];
    [_editor setString: [sorted componentsJoinedByString: @"\n"]];
}

- (void) sortLinesDescending: (id) sender {
    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *>* sorted = [lines mutableCopy];
    [sorted sortUsingComparator: ^NSComparisonResult(id obj1, id obj2) {
        return [obj2 localizedCaseInsensitiveCompare: obj1];
    }];
    [_editor setString: [sorted componentsJoinedByString: @"\n"]];
}

- (void) removeDuplicateLines: (id) sender {
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
    [_editor setString: [unique componentsJoinedByString: @"\n"]];
}

- (void) removeEmptyLines: (id) sender {
    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *>* nonEmpty = [NSMutableArray array];
    for (NSString* line in lines) {
        if (line.length > 0) [nonEmpty addObject: line];
    }
    [_editor setString: [nonEmpty componentsJoinedByString: @"\n"]];
}

- (void) removeEmptyLinesWithBlank: (id) sender {
    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *>* nonEmpty = [NSMutableArray array];
    for (NSString* line in lines) {
        NSString* trimmed = [line stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [nonEmpty addObject: line];
    }
    [_editor setString: [nonEmpty componentsJoinedByString: @"\n"]];
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
    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByString: @"\n"];
    NSMutableArray<NSString *>* trimmed = [NSMutableArray array];
    NSCharacterSet* ws = [NSCharacterSet whitespaceCharacterSet];
    for (NSString* line in lines) {
        NSUInteger len = line.length;
        while (len > 0 && [ws characterIsMember: [line characterAtIndex: len - 1]]) len--;
        [trimmed addObject: [line substringToIndex: len]];
    }
    [_editor setString: [trimmed componentsJoinedByString: @"\n"]];
}

- (void) trimLeadingSpace: (id) sender {
    NSString* text = [_editor string];
    NSArray<NSString *>* lines = [text componentsSeparatedByString: @"\n"];
    NSMutableArray<NSString *>* trimmed = [NSMutableArray array];
    NSCharacterSet* ws = [NSCharacterSet whitespaceCharacterSet];
    for (NSString* line in lines) {
        NSUInteger start = 0;
        while (start < line.length && [ws characterIsMember: [line characterAtIndex: start]]) start++;
        [trimmed addObject: [line substringFromIndex: start]];
    }
    [_editor setString: [trimmed componentsJoinedByString: @"\n"]];
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
    if (mIsRecordingMacro) mRecordedMacro.clear();
    [self updateStatusBar];
}

- (void) playbackMacro: (id) sender {
    if (mRecordedMacro.empty()) return;
    for (const auto& step : mRecordedMacro) {
        if (!step.textParam.empty()) {
            [_editor message: step.msg wParam: step.wParam lParam: reinterpret_cast<sptr_t>(step.textParam.c_str())];
        } else {
            [_editor message: step.msg wParam: step.wParam lParam: step.lParam];
        }
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
    _findBar.hidden = NO;
    [_rootContentView updateSplitLayout];
    [_window makeFirstResponder: _findBar.findField];
}

- (void) showReplace: (id) sender {
    _findBar.hidden = NO;
    [_rootContentView updateSplitLayout];
    [_window makeFirstResponder: _findBar.replaceField];
}

- (void) onFindNext: (id) sender {
    [self findNext: _findBar.findField.stringValue
         matchCase: (_findBar.matchCaseCheck.state == NSControlStateValueOn)
         wholeWord: (_findBar.wholeWordCheck.state == NSControlStateValueOn)
           isRegex: (_findBar.regexCheck.state == NSControlStateValueOn)];
}

- (void) onFindPrev: (id) sender {
    [self findPrev: _findBar.findField.stringValue
         matchCase: (_findBar.matchCaseCheck.state == NSControlStateValueOn)
         wholeWord: (_findBar.wholeWordCheck.state == NSControlStateValueOn)
           isRegex: (_findBar.regexCheck.state == NSControlStateValueOn)];
}

- (void) useSelectionForFind: (id) sender {
    sptr_t selStart = [_editor message: SCI_GETSELECTIONSTART];
    sptr_t selEnd = [_editor message: SCI_GETSELECTIONEND];
    if (selEnd > selStart) {
        std::vector<char> buf(selEnd - selStart + 1, 0);
        [_editor message: SCI_GETSELTEXT wParam: 0 lParam: reinterpret_cast<sptr_t>(buf.data())];
        NSString* selText = [NSString stringWithUTF8String: buf.data()];
        _findBar.findField.stringValue = selText;
    }
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
- (void) undo: (id) sender { [_editor message: SCI_UNDO]; }
- (void) redo: (id) sender { [_editor message: SCI_REDO]; }
- (void) cut: (id) sender { [_editor message: SCI_CUT]; }
- (void) copy: (id) sender { [_editor message: SCI_COPY]; }
- (void) paste: (id) sender { [_editor message: SCI_PASTE]; }
- (void) selectAll: (id) sender { [_editor message: SCI_SELECTALL]; }

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
        if (mods != 0) item.keyEquivalentModifierMask = mods;
        return item;
    };

    // 1. App Menu
    NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle: @"Notepad++"];
    [appMenu addItemWithTitle: [NSString stringWithFormat: @"%@ Notepad++", L(@"help", @"About")] action: @selector(showAbout:) keyEquivalent: @""].target = self;
    [appMenu addItem: [NSMenuItem separatorItem]];
    addItem(appMenu, [NSString stringWithFormat: @"%@ (Preferences)...", L(@"cmd_48005", @"Preferences")], @selector(showPreferences:), @",", 0);
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
    fileMenuItem.submenu = fileMenu;
    [menubar addItem: fileMenuItem];

    // 3. Edit Menu
    NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle: L(@"edit", @"Edit")];
    addItem(editMenu, L(@"cmd_42001", @"Undo"), @selector(undo:), @"z", 0);
    addItem(editMenu, L(@"cmd_42002", @"Redo"), @selector(redo:), @"Z", 0);
    [editMenu addItem: [NSMenuItem separatorItem]];
    addItem(editMenu, L(@"cmd_42003", @"Cut"), @selector(cut:), @"x", 0);
    addItem(editMenu, L(@"cmd_42004", @"Copy"), @selector(copy:), @"c", 0);
    addItem(editMenu, L(@"cmd_42005", @"Paste"), @selector(paste:), @"v", 0);
    addItem(editMenu, L(@"cmd_42007", @"Select All"), @selector(selectAll:), @"a", 0);
    [editMenu addItem: [NSMenuItem separatorItem]];

    // Column Mode & Column Editor
    addItem(editMenu, [NSString stringWithFormat: @"%@... (⌥Drag / ⌥⇧Arrows)", L(@"dlg_6523", @"Column Mode")], @selector(showColumnModeTip:), @"", 0);
    addItem(editMenu, [NSString stringWithFormat: @"%@...", L(@"dlg_title_ColumnEditor", @"Column Editor")], @selector(showColumnEditorDialog:), @"c", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    [editMenu addItem: [NSMenuItem separatorItem]];

    // Line Operations
    NSMenuItem* lineOpsItem = [editMenu addItemWithTitle: L(@"edit-lineOperations", @"Line Operations") action: nil keyEquivalent: @""];
    NSMenu* lineOpsMenu = [[NSMenu alloc] initWithTitle: L(@"edit-lineOperations", @"Line Operations")];
    addItem(lineOpsMenu, L(@"cmd_42029", @"Duplicate Current Line"), @selector(duplicateLine:), @"d", 0);
    addItem(lineOpsMenu, L(@"cmd_42030", @"Split Lines"), @selector(splitLines:), @"", 0);
    addItem(lineOpsMenu, L(@"cmd_42031", @"Join Lines"), @selector(joinLines:), @"j", NSEventModifierFlagControl);
    addItem(lineOpsMenu, L(@"cmd_42032", @"Move Selected Lines Up"), @selector(moveLineUp:), @"\x1E", NSEventModifierFlagOption);
    addItem(lineOpsMenu, L(@"cmd_42033", @"Move Selected Lines Down"), @selector(moveLineDown:), @"\x1F", NSEventModifierFlagOption);
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

    editMenuItem.submenu = editMenu;
    [menubar addItem: editMenuItem];

    // 4. Search Menu
    NSMenuItem* searchMenuItem = [[NSMenuItem alloc] init];
    NSMenu* searchMenu = [[NSMenu alloc] initWithTitle: L(@"search", @"Search")];
    addItem(searchMenu, L(@"cmd_43001", @"Find..."), @selector(openFindBar:), @"f", 0);
    addItem(searchMenu, L(@"cmd_43003", @"Replace..."), @selector(openReplaceBar:), @"F", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(searchMenu, L(@"dlg_Find_1701", @"Find Next"), @selector(onFindNext:), @"g", 0);
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
    addItem(viewMenu, L(@"dlg_6252", @"Show All Characters (White Space / EOL)"), @selector(toggleShowAllCharacters:), @"", 0);
    addItem(viewMenu, L(@"dlg_7161_guide", @"Show Indent Guide"), @selector(toggleIndentGuides:), @"", 0);
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

    // 8. Settings Menu
    NSMenuItem* settingsMenuItem = [[NSMenuItem alloc] init];
    NSMenu* settingsMenu = [[NSMenu alloc] initWithTitle: L(@"settings", @"Settings")];
    addItem(settingsMenu, [NSString stringWithFormat: @"%@...", L(@"cmd_48005", @"Preferences")], @selector(showPreferences:), @",", 0);
    addItem(settingsMenu, [NSString stringWithFormat: @"%@...", L(@"cmd_48006", @"Style Configurator")], @selector(showStyleConfigurator:), @"", 0);
    settingsMenuItem.submenu = settingsMenu;
    [menubar addItem: settingsMenuItem];

    // 9. Tools Menu
    NSMenuItem* toolsMenuItem = [[NSMenuItem alloc] init];
    NSMenu* toolsMenu = [[NSMenu alloc] initWithTitle: L(@"tools", @"Tools")];
    addItem(toolsMenu, @"Generate MD5 Hash", @selector(generateMD5:), @"", 0);
    addItem(toolsMenu, @"Generate SHA-256 Hash", @selector(generateSHA256:), @"", 0);
    toolsMenuItem.submenu = toolsMenu;
    [menubar addItem: toolsMenuItem];

    // 10. Window Menu
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
