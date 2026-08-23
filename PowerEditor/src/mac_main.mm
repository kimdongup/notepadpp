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
    [self addSubview: _findField];

    NSTextField* repLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(10, y + 28, 50, 18)];
    repLabel.stringValue = @"Replace:";
    repLabel.bezeled = NO;
    repLabel.drawsBackground = NO;
    repLabel.editable = NO;
    repLabel.font = [NSFont systemFontOfSize: 12];
    [self addSubview: repLabel];

    _replaceField = [[NSTextField alloc] initWithFrame: NSMakeRect(60, y + 26, 220, 22)];
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
- (void) loadChildrenIfNeeded;
@end

@implementation NppFileNode
- (instancetype) init {
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
        _childrenLoaded = NO;
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
            if ([item hasPrefix: @"."]) continue; // Skip hidden
            NSString* subPath = [_path stringByAppendingPathComponent: item];
            BOOL isSubDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath: subPath isDirectory: &isSubDir]) {
                NppFileNode* subNode = [[NppFileNode alloc] init];
                subNode.path = subPath;
                subNode.name = item;
                subNode.isDirectory = isSubDir;
                subNode.icon = [[NSWorkspace sharedWorkspace] iconForFile: subPath];
                [subNode.icon setSize: NSMakeSize(16, 16)];
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

@interface NppFileExplorerView : NSView <NSOutlineViewDelegate, NSOutlineViewDataSource>
@property (nonatomic, weak) id<NppFileExplorerDelegate> delegate;
@property (nonatomic, strong) NSString* rootDirectory;
@property (nonatomic, strong) NSOutlineView* outlineView;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, assign) BOOL isDarkMode;
- (void) setDirectoryPath: (NSString *) dirPath;
- (void) refreshDirectory;
@end

@implementation NppFileExplorerView {
    NppFileNode* mRootNode;
}

- (BOOL) isFlipped { return YES; }

- (instancetype) initWithFrame: (NSRect) frameRect {
    self = [super initWithFrame: frameRect];
    if (self) {
        _isDarkMode = NO;
        _rootDirectory = NSHomeDirectory(); // Default to ~/
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    // 1. Header View (Finder Style)
    NSView* header = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, self.bounds.size.width, 30)];
    header.autoresizingMask = NSViewWidthSizable;
    [self addSubview: header];

    _titleLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(8, 6, self.bounds.size.width - 50, 18)];
    _titleLabel.stringValue = @"📁 Finder: ~";
    _titleLabel.bezeled = NO; _titleLabel.drawsBackground = NO; _titleLabel.editable = NO;
    _titleLabel.font = [NSFont systemFontOfSize: 11 weight: NSFontWeightBold];
    [header addSubview: _titleLabel];

    NSButton* btnRefresh = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 26, 5, 20, 20)];
    btnRefresh.bezelStyle = NSBezelStyleInline;
    btnRefresh.title = @"↻";
    btnRefresh.target = self;
    btnRefresh.action = @selector(onRefreshClicked:);
    btnRefresh.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnRefresh];

    // 2. Outline ScrollView
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 30, self.bounds.size.width, self.bounds.size.height - 30)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview: scroll];

    _outlineView = [[NSOutlineView alloc] initWithFrame: scroll.bounds];
    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier: @"FinderCol"];
    col.title = @"Finder";
    col.width = self.bounds.size.width - 10;
    [_outlineView addTableColumn: col];
    _outlineView.outlineTableColumn = col;
    _outlineView.headerView = nil;
    _outlineView.delegate = self;
    _outlineView.dataSource = self;
    _outlineView.target = self;
    _outlineView.doubleAction = @selector(onItemDoubleClicked:);
    scroll.documentView = _outlineView;

    [self refreshDirectory];
}

- (void) setDirectoryPath: (NSString *) dirPath {
    if (!dirPath || dirPath.length == 0) dirPath = NSHomeDirectory();
    if ([_rootDirectory isEqualToString: dirPath]) return;

    _rootDirectory = dirPath;
    NSString* display = [dirPath isEqualToString: NSHomeDirectory()] ? @"~" : [dirPath lastPathComponent];
    _titleLabel.stringValue = [NSString stringWithFormat: @"📁 Finder: %@", display];
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
    [_outlineView reloadData];
}

- (NSInteger) outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem: (id) item {
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
    if (!item) {
        [mRootNode loadChildrenIfNeeded];
        return mRootNode.children[index];
    }
    NppFileNode* node = (NppFileNode *)item;
    [node loadChildrenIfNeeded];
    return node.children[index];
}

- (BOOL) outlineView: (NSOutlineView *) outlineView isItemExpandable: (id) item {
    if (!item) return YES;
    NppFileNode* node = (NppFileNode *)item;
    return node.isDirectory;
}

- (NSView *) outlineView: (NSOutlineView *) outlineView viewForTableColumn: (NSTableColumn *) tableColumn item: (id) item {
    NppFileNode* node = (NppFileNode *)item;
    NSTableCellView* cell = [outlineView makeViewWithIdentifier: @"FinderCell" owner: self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, 200, 22)];
        cell.identifier = @"FinderCell";

        NSImageView* iv = [[NSImageView alloc] initWithFrame: NSMakeRect(2, 3, 16, 16)];
        cell.imageView = iv;
        [cell addSubview: iv];

        NSTextField* tf = [[NSTextField alloc] initWithFrame: NSMakeRect(22, 2, 175, 18)];
        tf.bezeled = NO; tf.drawsBackground = NO; tf.editable = NO;
        tf.font = [NSFont systemFontOfSize: 12];
        cell.textField = tf;
        [cell addSubview: tf];
    }

    cell.textField.stringValue = node.name ?: @"";
    cell.imageView.image = node.icon ?: [[NSWorkspace sharedWorkspace] iconForFileType: NSFileTypeForHFSTypeCode(kGenericDocumentIcon)];
    return cell;
}

- (CGFloat) outlineView: (NSOutlineView *) outlineView heightOfRowByItem: (id) item { return 22.0; }

- (void) onItemDoubleClicked: (id) sender {
    NSInteger row = _outlineView.clickedRow;
    if (row < 0) return;
    NppFileNode* node = [_outlineView itemAtRow: row];
    if (node) {
        if (node.isDirectory) {
            if ([_outlineView isItemExpanded: node]) [_outlineView collapseItem: node];
            else [_outlineView expandItem: node];
        } else {
            [_delegate fileExplorerOpenFile: node.path];
        }
    }
}

- (void) onRefreshClicked: (id) sender { [self refreshDirectory]; }

- (void) drawRect: (NSRect) dirtyRect {
    [super drawRect: dirtyRect];
    NSColor* bg = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.14 green: 0.14 blue: 0.15 alpha: 1.0]
                              : [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];
    [bg setFill];
    NSRectFill(self.bounds);

    NSColor* border = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.20 green: 0.20 blue: 0.22 alpha: 1.0]
                                  : [NSColor colorWithCalibratedRed: 0.80 green: 0.80 blue: 0.82 alpha: 1.0];
    [border setFill];
    NSRectFill(NSMakeRect(self.bounds.size.width - 1, 0, 1, self.bounds.size.height));
}

@end

// ============================================================================
// Panel 2: Bottom Panel - Authentic macOS Terminal-Style Embedded Console Pane
// ============================================================================

@protocol NppTerminalPanelDelegate <NSObject>
- (void) terminalPanelCloseRequested;
- (void) terminalPanelOpenExternalRequested: (NSString *) dirPath;
@end

@interface NppTerminalPanelView : NSView <NSTextFieldDelegate>
@property (nonatomic, weak) id<NppTerminalPanelDelegate> delegate;
@property (nonatomic, strong) NSString* workingDirectory;
@property (nonatomic, strong) NSTextView* outputTextView;
@property (nonatomic, strong) NSTextField* inputField;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, assign) BOOL isDarkMode;
- (void) setWorkingDirectoryPath: (NSString *) dirPath;
- (void) appendOutput: (NSString *) text;
- (void) executeCommand: (NSString *) cmd;
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
        _workingDirectory = NSHomeDirectory();
        mCommandHistory = [NSMutableArray array];
        mHistoryIndex = -1;
        [self buildUI];
    }
    return self;
}

- (void) buildUI {
    // 1. Terminal Title Bar (Authentic macOS Terminal style)
    NSView* header = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, self.bounds.size.width, 28)];
    header.autoresizingMask = NSViewWidthSizable;
    [self addSubview: header];

    _titleLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(8, 5, self.bounds.size.width - 240, 18)];
    _titleLabel.stringValue = [NSString stringWithFormat: @"%@@Mac: ~ — -zsh", NSUserName()];
    _titleLabel.bezeled = NO; _titleLabel.drawsBackground = NO; _titleLabel.editable = NO;
    _titleLabel.font = [NSFont systemFontOfSize: 11 weight: NSFontWeightBold];
    [header addSubview: _titleLabel];

    NSButton* btnExt = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 225, 4, 140, 20)];
    btnExt.bezelStyle = NSBezelStyleInline;
    btnExt.title = @"Open in Terminal.app";
    btnExt.target = self;
    btnExt.action = @selector(onOpenExternalClicked:);
    btnExt.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnExt];

    NSButton* btnClear = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 80, 4, 50, 20)];
    btnClear.bezelStyle = NSBezelStyleInline;
    btnClear.title = @"Clear";
    btnClear.target = self;
    btnClear.action = @selector(onClearClicked:);
    btnClear.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClear];

    NSButton* btnClose = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 25, 4, 20, 20)];
    btnClose.bezelStyle = NSBezelStyleInline;
    btnClose.title = @"×";
    btnClose.target = self;
    btnClose.action = @selector(onCloseClicked:);
    btnClose.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClose];

    // 2. Terminal Console Output Screen
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 28, self.bounds.size.width, self.bounds.size.height - 54)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview: scroll];

    _outputTextView = [[NSTextView alloc] initWithFrame: scroll.bounds];
    _outputTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _outputTextView.editable = NO;
    _outputTextView.backgroundColor = [NSColor colorWithCalibratedRed: 0.11 green: 0.11 blue: 0.12 alpha: 1.0];
    _outputTextView.textColor = [NSColor colorWithCalibratedRed: 0.90 green: 0.90 blue: 0.90 alpha: 1.0];
    _outputTextView.font = [NSFont monospacedSystemFontOfSize: 12 weight: NSFontWeightRegular];
    scroll.documentView = _outputTextView;

    [self appendOutput: [NSString stringWithFormat: @"Last login: %@ on ttys001\nNotepad++ macOS Embedded Terminal (zsh)\n\n", [NSDate date]]];

    // 3. Input Prompt Bar
    NSTextField* promptLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(6, self.bounds.size.height - 24, 18, 20)];
    promptLabel.stringValue = @"$";
    promptLabel.bezeled = NO; promptLabel.drawsBackground = NO; promptLabel.editable = NO;
    promptLabel.font = [NSFont boldSystemFontOfSize: 13];
    promptLabel.textColor = [NSColor colorWithCalibratedRed: 0.22 green: 0.70 blue: 0.98 alpha: 1.0];
    promptLabel.autoresizingMask = NSViewMinYMargin;
    [self addSubview: promptLabel];

    _inputField = [[NSTextField alloc] initWithFrame: NSMakeRect(24, self.bounds.size.height - 24, self.bounds.size.width - 30, 22)];
    _inputField.placeholderString = @"Type command (e.g. ls -la, git status, make) and press Enter...";
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
    _titleLabel.stringValue = [NSString stringWithFormat: @"%@@Mac: %@ — -zsh", NSUserName(), display];
}

- (NSAttributedString *) parseAnsiText: (NSString *) rawText isDarkMode: (BOOL) isDark {
    NSMutableAttributedString* result = [[NSMutableAttributedString alloc] init];
    NSColor* defaultFg = isDark ? [NSColor colorWithCalibratedWhite: 0.90 alpha: 1.0]
                                : [NSColor colorWithCalibratedWhite: 0.15 alpha: 1.0];
    NSFont* defaultFont = [NSFont monospacedSystemFontOfSize: 12 weight: NSFontWeightRegular];

    NSArray<NSColor *>* standardColors = @[
        [NSColor blackColor],
        [NSColor colorWithCalibratedRed: 0.85 green: 0.25 blue: 0.25 alpha: 1.0], // Red
        [NSColor colorWithCalibratedRed: 0.25 green: 0.75 blue: 0.30 alpha: 1.0], // Green
        [NSColor colorWithCalibratedRed: 0.85 green: 0.70 blue: 0.15 alpha: 1.0], // Yellow
        [NSColor colorWithCalibratedRed: 0.25 green: 0.60 blue: 0.95 alpha: 1.0], // Blue
        [NSColor colorWithCalibratedRed: 0.80 green: 0.35 blue: 0.85 alpha: 1.0], // Magenta
        [NSColor colorWithCalibratedRed: 0.25 green: 0.75 blue: 0.85 alpha: 1.0], // Cyan
        [NSColor colorWithCalibratedWhite: 0.92 alpha: 1.0]                       // White
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
        NSAttributedString* attrStr = [self parseAnsiText: text isDarkMode: self->_isDarkMode];
        [storage appendAttributedString: attrStr];
        [self->_outputTextView scrollRangeToVisible: NSMakeRange(storage.length, 0)];
    });
}

- (BOOL) control: (NSControl *) control textView: (NSTextView *) textView doCommandBySelector: (SEL) commandSelector {
    if (control == _inputField) {
        if (commandSelector == @selector(moveUp:)) {
            if (mCommandHistory.count > 0) {
                if (mHistoryIndex > 0) mHistoryIndex--;
                else mHistoryIndex = 0;
                _inputField.stringValue = mCommandHistory[mHistoryIndex];
            }
            return YES;
        } else if (commandSelector == @selector(moveDown:)) {
            if (mCommandHistory.count > 0) {
                if (mHistoryIndex < (NSInteger)mCommandHistory.count - 1) {
                    mHistoryIndex++;
                    _inputField.stringValue = mCommandHistory[mHistoryIndex];
                } else {
                    mHistoryIndex = mCommandHistory.count;
                    _inputField.stringValue = @"";
                }
            }
            return YES;
        }
    }
    return NO;
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

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask* task = [[NSTask alloc] init];
        task.launchPath = @"/bin/zsh";
        task.arguments = @[@"-c", cmd];
        task.currentDirectoryPath = self->_workingDirectory;

        NSMutableDictionary* env = [[[NSProcessInfo processInfo] environment] mutableCopy];
        env[@"TERM"] = @"xterm-256color";
        env[@"CLICOLOR"] = @"1";
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

// ============================================================================
// Panel 3: Secondary Side Panel (Right) - Language Guide & Live WebKit Preview
// ============================================================================

@protocol NppSecondaryPreviewDelegate <NSObject>
- (void) secondaryPreviewCloseRequested;
- (void) secondaryPreviewLanguageSelected: (NSString *) lexerName;
@end

@interface NppSecondaryPreviewView : NSView <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, weak) id<NppSecondaryPreviewDelegate> delegate;
@property (nonatomic, strong) WKWebView* webView;
@property (nonatomic, strong) NSTextField* titleLabel;
@property (nonatomic, assign) BOOL isDarkMode;
- (void) renderDocumentContent: (NSString *) content fileName: (NSString *) fileName lexerName: (NSString *) lexer;
@end

@implementation NppSecondaryPreviewView

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
    // 1. Header
    NSView* header = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, self.bounds.size.width, 28)];
    header.autoresizingMask = NSViewWidthSizable;
    [self addSubview: header];

    _titleLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(8, 5, self.bounds.size.width - 60, 18)];
    _titleLabel.stringValue = @"PREVIEW";
    _titleLabel.bezeled = NO; _titleLabel.drawsBackground = NO; _titleLabel.editable = NO;
    _titleLabel.font = [NSFont systemFontOfSize: 11 weight: NSFontWeightBold];
    [header addSubview: _titleLabel];

    NSButton* btnClose = [[NSButton alloc] initWithFrame: NSMakeRect(self.bounds.size.width - 24, 4, 20, 20)];
    btnClose.bezelStyle = NSBezelStyleInline;
    btnClose.title = @"×";
    btnClose.target = self;
    btnClose.action = @selector(onCloseClicked:);
    btnClose.autoresizingMask = NSViewMinXMargin;
    [header addSubview: btnClose];

    // 2. WebKit Live Preview View
    WKUserContentController* userContent = [[WKUserContentController alloc] init];
    [userContent addScriptMessageHandler: self name: @"selectLang"];

    WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userContent;

    _webView = [[WKWebView alloc] initWithFrame: NSMakeRect(0, 28, self.bounds.size.width, self.bounds.size.height - 28) configuration: config];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.navigationDelegate = self;
    [self addSubview: _webView];
}

- (void) userContentController: (WKUserContentController *) userContentController didReceiveScriptMessage: (WKScriptMessage *) message {
    if ([message.name isEqualToString: @"selectLang"] && [message.body isKindOfClass: [NSString class]]) {
        if ([_delegate respondsToSelector: @selector(secondaryPreviewLanguageSelected:)]) {
            [_delegate secondaryPreviewLanguageSelected: message.body];
        }
    }
}

- (void) renderDocumentContent: (NSString *) content fileName: (NSString *) fileName lexerName: (NSString *) lexer {
    if (!content) content = @"";

    NSString* bgCss = _isDarkMode ? @"background-color: #1a1a1c; color: #e6e6e6;" : @"background-color: #ffffff; color: #1f1f1f;";
    NSString* codeBg = _isDarkMode ? @"#242428" : @"#f4f4f6";
    NSString* badgeBg = _isDarkMode ? @"#005fb8" : @"#e1effe";
    NSString* badgeFg = _isDarkMode ? @"#ffffff" : @"#1e429f";

    NSString* htmlBody = @"";
    NSString* ext = [[fileName pathExtension] lowercaseString];

    if ((!lexer || [lexer isEqualToString: @"text"]) && ![ext isEqualToString: @"md"] && ![ext isEqualToString: @"html"] && ![ext isEqualToString: @"htm"]) {
        _titleLabel.stringValue = @"PREVIEW: Select Language";

        htmlBody = [NSString stringWithFormat:
            @"<div style='padding: 24px 16px; text-align: center; font-family: -apple-system, BlinkMacSystemFont, sans-serif;'>"
            @"  <div style='font-size: 34px; margin-bottom: 12px;'>🎨</div>"
            @"  <h3 style='margin: 0 0 8px 0; color: #007aff;'>실시간 렌더링 미리보기</h3>"
            @"  <p style='color: %@; font-size: 12px; line-height: 1.5; margin-bottom: 20px;'>"
            @"    상단 메뉴의 <b>Language (언어)</b>에서 원하는 언어를 선택하면 실시간 렌더링이 시작됩니다.<br/>"
            @"    (Please select a Language from the menu to preview)"
            @"  </p>"
            @"  <div style='font-size: 11px; font-weight: bold; color: %@; margin-bottom: 10px;'>빠른 언어 선택 (Quick Select):</div>"
            @"  <div style='display: flex; flex-wrap: wrap; gap: 8px; justify-content: center;'>"
            @"    <button onclick=\"window.webkit.messageHandlers.selectLang.postMessage('markdown')\" style='cursor:pointer; background:%@; color:%@; border: 1px solid rgba(0,122,255,0.3); border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 500;'>📝 Markdown</button>"
            @"    <button onclick=\"window.webkit.messageHandlers.selectLang.postMessage('hypertext')\" style='cursor:pointer; background:%@; color:%@; border: 1px solid rgba(0,122,255,0.3); border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 500;'>🌐 HTML</button>"
            @"    <button onclick=\"window.webkit.messageHandlers.selectLang.postMessage('json')\" style='cursor:pointer; background:%@; color:%@; border: 1px solid rgba(0,122,255,0.3); border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 500;'>📦 JSON</button>"
            @"    <button onclick=\"window.webkit.messageHandlers.selectLang.postMessage('xml')\" style='cursor:pointer; background:%@; color:%@; border: 1px solid rgba(0,122,255,0.3); border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 500;'>📄 XML / SVG</button>"
            @"    <button onclick=\"window.webkit.messageHandlers.selectLang.postMessage('cpp')\" style='cursor:pointer; background:%@; color:%@; border: 1px solid rgba(0,122,255,0.3); border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 500;'>⚡ C / C++</button>"
            @"    <button onclick=\"window.webkit.messageHandlers.selectLang.postMessage('python')\" style='cursor:pointer; background:%@; color:%@; border: 1px solid rgba(0,122,255,0.3); border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 500;'>🐍 Python</button>"
            @"    <button onclick=\"window.webkit.messageHandlers.selectLang.postMessage('sql')\" style='cursor:pointer; background:%@; color:%@; border: 1px solid rgba(0,122,255,0.3); border-radius: 6px; padding: 6px 12px; font-size: 12px; font-weight: 500;'>🗄️ SQL</button>"
            @"  </div>"
            @"</div>",
            _isDarkMode ? @"#a0a0a0" : @"#555555",
            _isDarkMode ? @"#cccccc" : @"#444444",
            badgeBg, badgeFg, badgeBg, badgeFg, badgeBg, badgeFg, badgeBg, badgeFg, badgeBg, badgeFg, badgeBg, badgeFg, badgeBg, badgeFg];
    } else if ([lexer isEqualToString: @"hypertext"] || [ext isEqualToString: @"html"] || [ext isEqualToString: @"htm"]) {
        _titleLabel.stringValue = @"PREVIEW: HTML";
        htmlBody = content;
    } else if ([lexer isEqualToString: @"markdown"] || [ext isEqualToString: @"md"] || [ext isEqualToString: @"markdown"]) {
        _titleLabel.stringValue = @"PREVIEW: GFM MARKDOWN";
        NSMutableString* mdHtml = [NSMutableString string];
        [mdHtml appendFormat: @"<div style='margin-bottom: 12px;'><span style='background:%@; color:%@; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold;'>GFM Markdown Render</span></div>", badgeBg, badgeFg];

        NSArray<NSString *>* lines = [content componentsSeparatedByString: @"\n"];
        BOOL inCodeBlock = NO;
        BOOL inList = NO;
        BOOL inTable = NO;

        for (NSString* rawLine in lines) {
            NSString* line = rawLine;
            if ([line hasPrefix: @"```"]) {
                inCodeBlock = !inCodeBlock;
                if (inCodeBlock) [mdHtml appendString: @"<pre style='position:relative;'><code>"];
                else [mdHtml appendString: @"</code></pre>"];
                continue;
            }
            if (inCodeBlock) {
                NSString* escaped = [[line stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                            stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
                [mdHtml appendFormat: @"%@\n", escaped];
                continue;
            }

            // GFM Table parsing
            if ([line hasPrefix: @"|"] && [line hasSuffix: @"|"]) {
                if (!inTable) {
                    [mdHtml appendString: @"<table style='border-collapse:collapse; width:100%; margin:12px 0;'>"];
                    inTable = YES;
                }
                if ([line containsString: @"---"]) continue; // Table header separator line

                NSArray<NSString *>* cells = [line componentsSeparatedByString: @"|"];
                [mdHtml appendString: @"<tr>"];
                for (size_t c = 1; c + 1 < cells.count; ++c) {
                    NSString* cellVal = [cells[c] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
                    [mdHtml appendFormat: @"<td style='border:1px solid rgba(128,128,128,0.3); padding:6px 10px;'>%@</td>", cellVal];
                }
                [mdHtml appendString: @"</tr>"];
                continue;
            } else if (inTable) {
                [mdHtml appendString: @"</table>"];
                inTable = NO;
            }

            // Alert Callouts
            if ([line hasPrefix: @"> [!NOTE]"]) { [mdHtml appendString: @"<div style='border-left:4px solid #007aff; background:rgba(0,122,255,0.08); padding:8px 12px; margin:8px 0; border-radius:4px;'><b>ℹ️ NOTE</b><br/>"]; continue; }
            if ([line hasPrefix: @"> [!TIP]"]) { [mdHtml appendString: @"<div style='border-left:4px solid #34c759; background:rgba(52,199,89,0.08); padding:8px 12px; margin:8px 0; border-radius:4px;'><b>💡 TIP</b><br/>"]; continue; }
            if ([line hasPrefix: @"> [!IMPORTANT]"]) { [mdHtml appendString: @"<div style='border-left:4px solid #af52de; background:rgba(175,82,222,0.08); padding:8px 12px; margin:8px 0; border-radius:4px;'><b>🟣 IMPORTANT</b><br/>"]; continue; }
            if ([line hasPrefix: @"> [!WARNING]"]) { [mdHtml appendString: @"<div style='border-left:4px solid #ff9500; background:rgba(255,149,0,0.08); padding:8px 12px; margin:8px 0; border-radius:4px;'><b>⚠️ WARNING</b><br/>"]; continue; }

            if ([line hasPrefix: @"# "]) [mdHtml appendFormat: @"<h1>%@</h1>", [line substringFromIndex: 2]];
            else if ([line hasPrefix: @"## "]) [mdHtml appendFormat: @"<h2>%@</h2>", [line substringFromIndex: 3]];
            else if ([line hasPrefix: @"### "]) [mdHtml appendFormat: @"<h3>%@</h3>", [line substringFromIndex: 4]];
            else if ([line hasPrefix: @"#### "]) [mdHtml appendFormat: @"<h4>%@</h4>", [line substringFromIndex: 5]];
            else if ([line hasPrefix: @"- [ ] "] || [line hasPrefix: @"* [ ] "]) [mdHtml appendFormat: @"<div style='margin:4px 0;'><input type='checkbox' disabled> %@</div>", [line substringFromIndex: 6]];
            else if ([line hasPrefix: @"- [x] "] || [line hasPrefix: @"* [x] "]) [mdHtml appendFormat: @"<div style='margin:4px 0;'><input type='checkbox' checked disabled> <strike>%@</strike></div>", [line substringFromIndex: 6]];
            else if ([line hasPrefix: @"- "] || [line hasPrefix: @"* "]) {
                if (!inList) { [mdHtml appendString: @"<ul>"]; inList = YES; }
                [mdHtml appendFormat: @"<li>%@</li>", [line substringFromIndex: 2]];
            }
            else if ([line hasPrefix: @"> "]) [mdHtml appendFormat: @"<blockquote style='border-left:4px solid #888; margin:6px 0; padding-left:10px; opacity:0.85;'>%@</blockquote>", [line substringFromIndex: 2]];
            else if ([line hasPrefix: @"---"] || [line hasPrefix: @"***"]) [mdHtml appendString: @"<hr style='border: 0; border-top: 1px solid rgba(128,128,128,0.3); margin: 16px 0;'>"];
            else {
                if (inList) { [mdHtml appendString: @"</ul>"]; inList = NO; }
                if (line.length == 0) [mdHtml appendString: @"<p style='margin: 6px 0;'></p>"];
                else {
                    NSString* escaped = [[line stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                                stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];
                    [mdHtml appendFormat: @"<p style='margin: 4px 0;'>%@</p>", escaped];
                }
            }
        }
        if (inList) [mdHtml appendString: @"</ul>"];
        if (inTable) [mdHtml appendString: @"</table>"];
        htmlBody = mdHtml;
    } else {
        _titleLabel.stringValue = [NSString stringWithFormat: @"PREVIEW: %@", lexer.uppercaseString];
        NSString* escaped = [[content stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
                                    stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"];

        htmlBody = [NSString stringWithFormat:
            @"<div style='display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;'>"
            @"  <span style='background:%@; color:%@; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold;'>%@ Preview</span>"
            @"  <span style='font-size: 11px; opacity: 0.7;'>%@</span>"
            @"</div>"
            @"<pre style='margin: 0;'><code>%@</code></pre>",
            badgeBg, badgeFg, lexer.uppercaseString, fileName ?: @"Document", escaped];
    }

    NSString* fullHtml = [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
        @"<style>"
        @"body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 13px; line-height: 1.6; padding: 14px; margin: 0; %@ }"
        @"pre, code { font-family: 'SF Mono', Menlo, Monaco, Consolas, monospace; font-size: 12px; background: %@; padding: 4px 6px; border-radius: 4px; }"
        @"pre { padding: 12px; overflow-x: auto; white-space: pre-wrap; word-break: break-all; }"
        @"h1, h2, h3, h4 { border-bottom: 1px solid rgba(128,128,128,0.2); padding-bottom: 4px; margin-top: 14px; margin-bottom: 8px; }"
        @"blockquote { border-left: 4px solid #007aff; margin: 8px 0; padding-left: 12px; color: #888; }"
        @"ul { padding-left: 20px; margin: 6px 0; }"
        @"table { border-collapse: collapse; width: 100%%; margin: 12px 0; }"
        @"th, td { border: 1px solid rgba(128,128,128,0.3); padding: 6px 10px; text-align: left; }"
        @"th { background: rgba(128,128,128,0.1); }"
        @"</style></head><body>%@</body></html>", bgCss, codeBg, htmlBody];

    [_webView loadHTMLString: fullHtml baseURL: nil];
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

// ============================================================================
// Main Window Content View with Resizable NSSplitView
// ============================================================================

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

- (NSString *) getDirectoryForActiveTab;
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
    NSView* content = self.window.contentView;

    // Mode 1: Text to Insert Box
    NSBox* boxText = [[NSBox alloc] initWithFrame: NSMakeRect(16, 180, 408, 85)];
    boxText.title = @"Text to Insert";
    [content addSubview: boxText];

    _radioText = [[NSButton alloc] initWithFrame: NSMakeRect(12, 40, 160, 20)];
    _radioText.buttonType = NSButtonTypeRadio;
    _radioText.title = @"Text to Insert:";
    _radioText.state = NSControlStateValueOn;
    _radioText.target = self;
    _radioText.action = @selector(onRadioModeChanged:);
    [boxText.contentView addSubview: _radioText];

    _textToInsertField = [[NSTextField alloc] initWithFrame: NSMakeRect(160, 38, 220, 22)];
    _textToInsertField.placeholderString = @"e.g. prefix_ or text";
    [boxText.contentView addSubview: _textToInsertField];

    // Mode 2: Number to Insert Box
    NSBox* boxNum = [[NSBox alloc] initWithFrame: NSMakeRect(16, 50, 408, 125)];
    boxNum.title = @"Number to Insert";
    [content addSubview: boxNum];

    _radioNumber = [[NSButton alloc] initWithFrame: NSMakeRect(12, 78, 160, 20)];
    _radioNumber.buttonType = NSButtonTypeRadio;
    _radioNumber.title = @"Number to Insert";
    _radioNumber.state = NSControlStateValueOff;
    _radioNumber.target = self;
    _radioNumber.action = @selector(onRadioModeChanged:);
    [boxNum.contentView addSubview: _radioNumber];

    NSTextField* lblInit = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 50, 80, 18)];
    lblInit.stringValue = @"Initial number:";
    lblInit.bezeled = NO; lblInit.drawsBackground = NO; lblInit.editable = NO;
    lblInit.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblInit];

    _startNumField = [[NSTextField alloc] initWithFrame: NSMakeRect(105, 48, 80, 20)];
    _startNumField.stringValue = @"1";
    [boxNum.contentView addSubview: _startNumField];

    NSTextField* lblInc = [[NSTextField alloc] initWithFrame: NSMakeRect(200, 50, 80, 18)];
    lblInc.stringValue = @"Increase by:";
    lblInc.bezeled = NO; lblInc.drawsBackground = NO; lblInc.editable = NO;
    lblInc.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblInc];

    _increaseNumField = [[NSTextField alloc] initWithFrame: NSMakeRect(280, 48, 80, 20)];
    _increaseNumField.stringValue = @"1";
    [boxNum.contentView addSubview: _increaseNumField];

    NSTextField* lblRep = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 20, 80, 18)];
    lblRep.stringValue = @"Repeat:";
    lblRep.bezeled = NO; lblRep.drawsBackground = NO; lblRep.editable = NO;
    lblRep.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblRep];

    _repeatNumField = [[NSTextField alloc] initWithFrame: NSMakeRect(105, 18, 80, 20)];
    _repeatNumField.stringValue = @"1";
    [boxNum.contentView addSubview: _repeatNumField];

    NSTextField* lblFmt = [[NSTextField alloc] initWithFrame: NSMakeRect(200, 20, 50, 18)];
    lblFmt.stringValue = @"Format:";
    lblFmt.bezeled = NO; lblFmt.drawsBackground = NO; lblFmt.editable = NO;
    lblFmt.font = [NSFont systemFontOfSize: 11];
    [boxNum.contentView addSubview: lblFmt];

    _formatPopUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(255, 16, 65, 22) pullsDown: NO];
    [_formatPopUp addItemsWithTitles: @[@"Dec", @"Hex", @"Oct", @"Bin"]];
    [boxNum.contentView addSubview: _formatPopUp];

    _leadingPopUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(325, 16, 70, 22) pullsDown: NO];
    [_leadingPopUp addItemsWithTitles: @[@"None", @"Zeros", @"Spaces"]];
    [boxNum.contentView addSubview: _leadingPopUp];

    // Buttons
    NSButton* btnOK = [[NSButton alloc] initWithFrame: NSMakeRect(230, 12, 90, 28)];
    btnOK.title = @"OK";
    btnOK.bezelStyle = NSBezelStyleRounded;
    btnOK.keyEquivalent = @"\r";
    btnOK.target = self;
    btnOK.action = @selector(onOK:);
    [content addSubview: btnOK];

    NSButton* btnCancel = [[NSButton alloc] initWithFrame: NSMakeRect(330, 12, 90, 28)];
    btnCancel.title = @"Cancel";
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
        _categories = @[
            @"⚙️ General",
            @"✏️ Editing & Column Mode",
            @"📐 Margins & Border",
            @"📄 New Document",
            @"⇥ Indentation & Tabs",
            @"🎨 Themes & Dark Mode",
            @"💡 Highlighting",
            @"⚡ Auto-Completion",
            @"🔍 Searching",
            @"💾 Backup & Session",
            @"🚀 Performance"
        ];
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
    [self.window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    if (categoryIndex >= 0 && categoryIndex < static_cast<NSInteger>(_categories.count)) {
        [_categoryTable selectRowIndexes: [NSIndexSet indexSetWithIndex: categoryIndex] byExtendingSelection: NO];
        [self loadCategoryPage: categoryIndex];
    }
}

- (void) onClose: (id) sender { [self.window close]; }

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

    switch (category) {
        case 0: { // General
            addTitle(@"General Settings");
            NSBox* box1 = addBox(@"Tab Bar & Window", r.size.height - 180, 130);
            addCheck(box1, @"Show close button on each tab", 75, YES, nil);
            addCheck(box1, @"Double click to close tab", 50, YES, nil);
            addCheck(box1, @"Pin Tab support", 25, YES, nil);
            addCheck(box1, @"Reduce tab bar height", 0, NO, nil);

            NSBox* box2 = addBox(@"Status Bar, Panels & Toolbar", r.size.height - 320, 120);
            addCheck(box2, @"Show Segmented Status Bar", 65, YES, nil);
            addCheck(box2, @"Show Resizable 3-Panel Layout Toolbar Icons (VS Code Style)", 40, YES, nil);
            addCheck(box2, @"Enable Unified macOS Window Titlebar", 15, YES, nil);
            break;
        }
        case 1: { // Editing & Column Mode
            addTitle(@"Editor, Multi-Selection & Column Mode");
            NSBox* box1 = addBox(@"Column Mode & Multi-Selection", r.size.height - 190, 140);
            addCheck(box1, @"Enable Multi-Selection & Multi-Caret (⌘ + Click)", 85, YES, nil);
            addCheck(box1, @"Enable Column Mode / Rectangular Selection (⌥ + Drag or ⌥⇧ + Arrows)", 60, YES, nil);
            addCheck(box1, @"Enable Virtual Space on Rectangular Selection", 35, YES, nil);
            addCheck(box1, @"Multi-Paste into each selected column line", 10, YES, nil);

            NSBox* box2 = addBox(@"Non-Printing Characters", r.size.height - 310, 100);
            addCheck(box2, @"Show White Space characters", 45, _appController.showWhiteSpace, @selector(onToggleWhiteSpace:));
            addCheck(box2, @"Show End of Line (EOL) marks", 15, _appController.showEOL, @selector(onToggleEOL:));
            break;
        }
        case 2: { // Margins
            addTitle(@"Margins, Border & Column Edge");
            NSBox* box1 = addBox(@"Margins Display", r.size.height - 180, 130);
            addCheck(box1, @"Display Line Numbers Margin", 75, _appController.showLineNumbers, @selector(onToggleLineNumbers:));
            addCheck(box1, @"Display Bookmark & Symbol Margin", 50, _appController.showBookmarksMargin, nil);
            addCheck(box1, @"Display Code Folding Margin", 25, _appController.showFoldingMargin, nil);

            NSBox* box2 = addBox(@"Vertical Column Guide Line", r.size.height - 300, 100);
            addCheck(box2, @"Show Vertical Column Guide (Edge Line)", 45, _appController.showColumnGuide, @selector(onToggleColumnGuide:));

            NSTextField* lblEdge = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 15, 120, 20)];
            lblEdge.stringValue = @"Column Position:";
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
            addTitle(@"New Document Defaults");
            NSBox* box1 = addBox(@"Default Format / Line Endings (EOL)", r.size.height - 160, 110);
            NSPopUpButton* popEOL = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popEOL addItemsWithTitles: @[@"Unix (LF) - macOS Standard", @"Windows (CR LF)", @"Macintosh (CR)"]];
            [popEOL selectItemAtIndex: _appController.defaultNewEOL == 2 ? 0 : (_appController.defaultNewEOL == 0 ? 1 : 2)];
            popEOL.target = self; popEOL.action = @selector(onSelectNewEOL:);
            [box1.contentView addSubview: popEOL];

            NSBox* box2 = addBox(@"Default Encoding", r.size.height - 290, 110);
            NSPopUpButton* popEnc = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(15, 45, 260, 24) pullsDown: NO];
            [popEnc addItemsWithTitles: @[@"UTF-8 (macOS Default)", @"UTF-8 with BOM", @"UTF-16 LE", @"UTF-16 BE", @"ANSI / Windows-1252", @"Korean (EUC-KR)", @"Japanese (Shift-JIS)"]];
            [popEnc selectItemAtIndex: _appController.defaultNewEncoding];
            popEnc.target = self; popEnc.action = @selector(onSelectNewEncoding:);
            [box2.contentView addSubview: popEnc];
            addCheck(box2, @"Apply UTF-8 encoding to opened ANSI files", 15, YES, nil);
            break;
        }
        case 4: { // Indentation
            addTitle(@"Indentation & Tab Settings");
            NSBox* box1 = addBox(@"Tab Configuration", r.size.height - 180, 130);
            NSTextField* lblTab = [[NSTextField alloc] initWithFrame: NSMakeRect(15, 75, 120, 20)];
            lblTab.stringValue = @"Tab Size (spaces):";
            lblTab.bezeled = NO; lblTab.drawsBackground = NO; lblTab.editable = NO;
            [box1.contentView addSubview: lblTab];

            NSPopUpButton* popTab = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(140, 73, 100, 24) pullsDown: NO];
            [popTab addItemsWithTitles: @[@"2", @"4", @"8"]];
            [popTab selectItemWithTitle: [NSString stringWithFormat: @"%d", _appController.currentTabWidth]];
            popTab.target = self; popTab.action = @selector(onSelectTabWidth:);
            [box1.contentView addSubview: popTab];

            addCheck(box1, @"Replace tabs by spaces (Soft Tabs)", 45, _appController.useSpacesForTabs, @selector(onToggleUseSpaces:));
            addCheck(box1, @"Backspace unindents", 15, YES, nil);

            NSBox* box2 = addBox(@"Indentation Guides & Smart Indent", r.size.height - 300, 100);
            addCheck(box2, @"Show Indentation Guides", 45, _appController.showIndentGuides, @selector(onToggleIndentGuides:));
            addCheck(box2, @"Smart Auto-Indentation on Enter", 15, YES, nil);
            break;
        }
        case 5: { // Themes
            addTitle(@"Color Themes & Typography");
            NSBox* box1 = addBox(@"Color Theme", r.size.height - 160, 110);
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

            NSBox* box2 = addBox(@"Editor Font & Size", r.size.height - 310, 130);
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
            addTitle(@"Highlighting & Matching");
            NSBox* box1 = addBox(@"Brace & Tag Matching", r.size.height - 180, 130);
            addCheck(box1, @"Highlight matching braces () [] {}", 75, _appController.matchBraces, @selector(onToggleMatchBraces:));
            addCheck(box1, @"Highlight matching HTML/XML tags", 50, YES, nil);
            addCheck(box1, @"Highlight current line background (Neutral Gray)", 25, _appController.highlightCurrentLine, @selector(onToggleHighlightLine:));

            NSBox* box2 = addBox(@"Smart Highlighting", r.size.height - 300, 100);
            addCheck(box2, @"Smart Highlighting (Highlight matching word occurrences)", 45, _appController.smartHighlighting, @selector(onToggleSmartHighlight:));
            addCheck(box2, @"Match case for Smart Highlighting", 15, YES, nil);
            break;
        }
        case 7: { // Auto-Completion
            addTitle(@"Auto-Completion & Pair Insertion");
            NSBox* box1 = addBox(@"Auto-Insert Matching Pairs", r.size.height - 180, 130);
            addCheck(box1, @"Parentheses () and Brackets []", 75, _appController.autoClosePairs, @selector(onToggleAutoPairs:));
            addCheck(box1, @"Braces {}", 50, _appController.autoClosePairs, nil);
            addCheck(box1, @"Double Quotes \"\" and Single Quotes ''", 25, _appController.autoClosePairs, nil);
            addCheck(box1, @"HTML/XML Tags <>", 0, _appController.autoClosePairs, nil);

            NSBox* box2 = addBox(@"Word Completion & Hints", r.size.height - 300, 100);
            addCheck(box2, @"Enable Word Auto-Completion from document", 45, _appController.autoWordCompletion, @selector(onToggleWordCompletion:));
            addCheck(box2, @"Function parameter calltip hints", 15, YES, nil);
            break;
        }
        case 8: { // Searching
            addTitle(@"Search & Replace Options");
            NSBox* box1 = addBox(@"Default Search Behavior", r.size.height - 200, 150);
            addCheck(box1, @"Wrap around document on search reach end", 95, YES, nil);
            addCheck(box1, @"Auto-fill 'Find What' with selected text (⌘E)", 70, YES, nil);
            addCheck(box1, @"Match case by default", 45, NO, nil);
            addCheck(box1, @"Whole word by default", 20, NO, nil);
            break;
        }
        case 9: { // Backup & Session
            addTitle(@"Backup & Session Management");
            NSBox* box1 = addBox(@"Session Recovery", r.size.height - 180, 130);
            addCheck(box1, @"Remember current session for next launch (Restore open tabs)", 75, _appController.rememberSession, @selector(onToggleRememberSession:));
            addCheck(box1, @"Periodic Snapshot & Auto-Save every 7 seconds", 50, YES, nil);
            addCheck(box1, @"Backup on save (Create .bak copy)", 25, NO, nil);

            NSBox* box2 = addBox(@"Default Working Directory", r.size.height - 300, 100);
            addCheck(box2, @"Follow current active document folder", 45, YES, nil);
            addCheck(box2, @"Remember last opened/saved directory", 15, YES, nil);
            break;
        }
        case 10: { // Performance
            addTitle(@"Performance & Large Files");
            NSBox* box1 = addBox(@"Large File Restrictions", r.size.height - 180, 130);
            addCheck(box1, @"Enable Large File Optimization (Limit: 200 MB)", 75, YES, nil);
            addCheck(box1, @"Auto-disable Syntax Highlighting for large files", 50, YES, nil);
            addCheck(box1, @"Auto-disable Word Wrap for large files", 25, YES, nil);
            addCheck(box1, @"Use Fast Memory Mapping for File IO", 0, YES, nil);
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

- (void) applicationDidFinishLaunching: (NSNotification *) notification {
    [self createMainWindow];
    [self setupToolbar];

    NSString* appearanceName = [[NSApp effectiveAppearance] name];
    _isDarkMode = [appearanceName containsString: @"Dark"];
    _currentThemeName = _isDarkMode ? @"🌙 Notepad++ Dark (Default Dark)" : @"☀️ Default Light (Classic)";

    [self applyAllSettings];
    [self newDocumentWithTitle: @"new 1"];

    NSArray* args = [[NSProcessInfo processInfo] arguments];
    for (NSUInteger i = 1; i < args.count; ++i) {
        NSString* arg = args[i];
        if (![arg hasPrefix: @"-"]) [self openFileAtPath: arg];
    }

    [_window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
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
    if (!dirPath || dirPath.length == 0) dirPath = [self getDirectoryForActiveTab];

    NSString* escapedPath = [dirPath stringByReplacingOccurrencesOfString: @"\"" withString: @"\\\""];
    NSString* scriptSource = [NSString stringWithFormat:
        @"tell application \"Terminal\"\n"
        @"  do script \"cd \\\"%@\\\"\"\n"
        @"  activate\n"
        @"end tell", escapedPath];

    NSAppleScript* appleScript = [[NSAppleScript alloc] initWithSource: scriptSource];
    NSDictionary* errDict = nil;
    if (![appleScript executeAndReturnError: &errDict]) {
        NSTask* task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/open";
        task.arguments = @[@"-a", @"Terminal", dirPath];
        [task launch];
    }

    _statusBar.statusText = [NSString stringWithFormat: @"Opened Mac Terminal: %@", [dirPath lastPathComponent]];
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

    // Fold markers
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDEROPEN lParam: SC_MARK_BOXMINUS];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDER lParam: SC_MARK_BOXPLUS];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDERSUB lParam: SC_MARK_VLINE];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDERTAIL lParam: SC_MARK_LCORNER];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDEREND lParam: SC_MARK_BOXPLUSCONNECTED];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDEROPENMID lParam: SC_MARK_BOXMINUSCONNECTED];
    [_editor message: SCI_MARKERDEFINE wParam: SC_MARKNUM_FOLDERMIDTAIL lParam: SC_MARK_TCORNER];

    // Bookmark marker
    [_editor message: SCI_MARKERDEFINE wParam: 1 lParam: SC_MARK_SHORTARROW];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: 1 value: [NSColor colorWithCalibratedRed: 0.2 green: 0.6 blue: 1.0 alpha: 1.0]];

    // Mark styles (25..29)
    for (int m = 25; m <= 29; ++m) [_editor message: SCI_MARKERDEFINE wParam: m lParam: SC_MARK_BACKGROUND];
    [_editor setColorProperty: SCI_MARKERSETBACK parameter: 25 value: [NSColor colorWithCalibratedRed: 1.0 green: 0.8 blue: 0.2 alpha: 0.4]];

    // Column Mode & Rectangular Selection Configuration
    [_editor message: SCI_SETMULTIPLESELECTION wParam: 1 lParam: 0];
    [_editor message: SCI_SETADDITIONALSELECTIONTYPING wParam: 1 lParam: 0];
    [_editor message: SCI_SETMULTIPASTE wParam: SC_MULTIPASTE_EACH lParam: 0];
    [_editor message: SCI_SETRECTANGULARSELECTIONMODIFIER wParam: SCMOD_ALT lParam: 0];
    [_editor message: SCI_SETVIRTUALSPACEOPTIONS wParam: SCVS_RECTANGULARSELECTION lParam: 0];

    // Tabs & Indentation
    [_editor message: SCI_SETTABWIDTH wParam: _currentTabWidth lParam: 0];
    [_editor message: SCI_SETUSETABS wParam: _useSpacesForTabs ? 0 : 1 lParam: 0];
    [_editor message: SCI_SETTABINDENTS wParam: 1 lParam: 0];
    [_editor message: SCI_SETBACKSPACEUNINDENTS wParam: 1 lParam: 0];
    [_editor message: SCI_SETINDENTATIONGUIDES wParam: _showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE lParam: 0];

    // Caret & Line
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
    NSColor* caretLineCol = [NSColor colorWithCalibratedRed: 0.90 green: 0.91 blue: 0.93 alpha: 1.0]; // Neutral Gray
    NSColor* selCol = [NSColor colorWithCalibratedRed: 0.78 green: 0.80 blue: 0.84 alpha: 1.0];       // Gray Selection
    NSColor* marginBg = [NSColor colorWithCalibratedRed: 0.94 green: 0.94 blue: 0.95 alpha: 1.0];
    NSColor* marginFore = [NSColor colorWithCalibratedRed: 0.45 green: 0.45 blue: 0.45 alpha: 1.0];

    if ([_currentThemeName containsString: @"Monokai"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.16 green: 0.15 blue: 0.17 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.97 green: 0.97 blue: 0.94 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.28 green: 0.27 blue: 0.30 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.38 green: 0.37 blue: 0.42 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.17 blue: 0.19 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.55 green: 0.55 blue: 0.55 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Dracula"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.16 green: 0.17 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.95 green: 0.95 blue: 0.96 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.28 green: 0.29 blue: 0.35 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.36 green: 0.38 blue: 0.48 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.19 blue: 0.23 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.50 green: 0.52 blue: 0.60 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Solarized Dark"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.00 green: 0.17 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.51 green: 0.58 blue: 0.59 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.10 green: 0.26 blue: 0.30 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.14 green: 0.34 blue: 0.40 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.04 green: 0.19 blue: 0.23 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.40 green: 0.48 blue: 0.50 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Solarized Light"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.99 green: 0.96 blue: 0.89 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.40 green: 0.48 blue: 0.51 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.90 green: 0.88 blue: 0.82 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.84 green: 0.82 blue: 0.74 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.94 green: 0.91 blue: 0.84 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.58 green: 0.63 blue: 0.63 alpha: 1.0];
    } else if ([_currentThemeName containsString: @"Obsidian"]) {
        bgCol = [NSColor colorWithCalibratedRed: 0.18 green: 0.20 blue: 0.21 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.88 green: 0.88 blue: 0.88 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.28 green: 0.30 blue: 0.32 alpha: 1.0];
        selCol = [NSColor colorWithCalibratedRed: 0.36 green: 0.42 blue: 0.48 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.20 blue: 0.21 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.50 green: 0.52 blue: 0.54 alpha: 1.0];
    } else if (_isDarkMode) {
        bgCol = [NSColor colorWithCalibratedRed: 0.13 green: 0.13 blue: 0.14 alpha: 1.0];
        foreCol = [NSColor colorWithCalibratedRed: 0.90 green: 0.90 blue: 0.90 alpha: 1.0];
        caretLineCol = [NSColor colorWithCalibratedRed: 0.27 green: 0.27 blue: 0.29 alpha: 1.0]; // Clean Gray
        selCol = [NSColor colorWithCalibratedRed: 0.35 green: 0.37 blue: 0.42 alpha: 1.0];
        marginBg = [NSColor colorWithCalibratedRed: 0.18 green: 0.18 blue: 0.20 alpha: 1.0];
        marginFore = [NSColor colorWithCalibratedRed: 0.60 green: 0.60 blue: 0.60 alpha: 1.0];
    }

    [_editor setColorProperty: SCI_STYLESETFORE parameter: STYLE_DEFAULT value: foreCol];
    [_editor setColorProperty: SCI_STYLESETBACK parameter: STYLE_DEFAULT value: bgCol];
    [_editor message: SCI_STYLECLEARALL];

    [_editor setColorProperty: SCI_STYLESETBACK parameter: STYLE_LINENUMBER value: marginBg];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: STYLE_LINENUMBER value: marginFore];

    [_editor setColorProperty: SCI_SETCARETFORE parameter: 0 value: _isDarkMode ? [NSColor whiteColor] : [NSColor blackColor]];
    [_editor setColorProperty: SCI_SETCARETLINEBACK parameter: 0 value: caretLineCol];

    [_editor message: SCI_SETSELFORE wParam: 0 lParam: 0];
    [_editor setColorProperty: SCI_SETSELBACK parameter: 1 value: selCol];

    [_editor setColorProperty: SCI_SETFOLDMARGINCOLOUR parameter: 1 value: marginBg];
    [_editor setColorProperty: SCI_SETFOLDMARGINHICOLOUR parameter: 1 value: marginBg];

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
    size_t dot = pathUtf8.find_last_of('.');
    if (dot == std::string::npos) return "text";
    std::string ext = pathUtf8.substr(dot + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

    if (ext == "cpp" || ext == "cxx" || ext == "cc" || ext == "c" || ext == "h" || ext == "hpp" || ext == "hxx" || ext == "m" || ext == "mm")
        return "cpp";
    if (ext == "py" || ext == "pyw") return "python";
    if (ext == "js" || ext == "jsx" || ext == "ts" || ext == "tsx") return "javascript";
    if (ext == "html" || ext == "htm" || ext == "xhtml") return "hypertext";
    if (ext == "xml" || ext == "plist" || ext == "svg" || ext == "xaml" || ext == "vcxproj" || ext == "props") return "xml";
    if (ext == "json") return "json";
    if (ext == "css" || ext == "scss" || ext == "less") return "css";
    if (ext == "md" || ext == "markdown") return "markdown";
    if (ext == "sql") return "sql";
    if (ext == "rs") return "rust";
    if (ext == "go") return "go";
    if (ext == "java") return "java";
    if (ext == "php" || ext == "phtml") return "phpscript";
    if (ext == "yaml" || ext == "yml") return "yaml";
    if (ext == "sh" || ext == "bash" || ext == "zsh") return "bash";
    if (ext == "ini" || ext == "cfg" || ext == "conf" || ext == "properties") return "props";
    if (ext == "bat" || ext == "cmd") return "batch";
    if (ext == "lua") return "lua";
    if (ext == "rb") return "ruby";
    if (ext == "pl" || ext == "pm") return "perl";
    if (ext == "mak" || ext == "mk") return "makefile";
    if (ext == "zig") return "zig";
    if (ext == "toml") return "toml";

    return "text";
}

- (void) configureLexerForActiveDocument {
    if (mActiveIndex < 0 || mActiveIndex >= static_cast<NSInteger>(mDocuments.size())) return;
    NppDocument& doc = mDocuments[mActiveIndex];

    Scintilla::ILexer5* pLexer = CreateLexer(doc.lexerName.c_str());
    if (pLexer) {
        [_editor setReferenceProperty: SCI_SETILEXER parameter: 0 value: pLexer];
    } else {
        [_editor setReferenceProperty: SCI_SETILEXER parameter: 0 value: nullptr];
    }

    [self configureStylesForLexer: doc.lexerName];
}

- (void) configureStylesForLexer: (const std::string&) lexer {
    [_editor suspendDrawing: YES];

    NSColor* commentCol = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.42 green: 0.68 blue: 0.42 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.00 green: 0.50 blue: 0.00 alpha: 1.0];
    NSColor* keywordCol = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.35 green: 0.68 blue: 0.95 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.00 green: 0.00 blue: 0.85 alpha: 1.0];
    NSColor* stringCol  = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.90 green: 0.58 blue: 0.48 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.65 green: 0.12 blue: 0.12 alpha: 1.0];
    NSColor* numberCol  = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.95 green: 0.75 blue: 0.35 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.80 green: 0.40 blue: 0.00 alpha: 1.0];
    NSColor* opCol      = _isDarkMode ? [NSColor colorWithCalibratedRed: 0.85 green: 0.85 blue: 0.85 alpha: 1.0]
                                      : [NSColor colorWithCalibratedRed: 0.10 green: 0.10 blue: 0.10 alpha: 1.0];

    // C / C++
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_COMMENTLINE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_COMMENTDOC value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_WORD2 value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_CHARACTER value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_OPERATOR value: opCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_C_PREPROCESSOR value: [NSColor colorWithCalibratedRed: 0.65 green: 0.45 blue: 0.85 alpha: 1.0]];

    // Python
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_COMMENTLINE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_COMMENTBLOCK value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_WORD2 value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_CHARACTER value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_P_OPERATOR value: opCol];

    // HTML / XML
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_TAG value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_TAGUNKNOWN value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_ATTRIBUTE value: [NSColor colorWithCalibratedRed: 0.6 green: 0.4 blue: 0.8 alpha: 1.0]];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_DOUBLESTRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_SINGLESTRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_H_COMMENT value: commentCol];

    // JSON
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_NUMBER value: numberCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_KEYWORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_JSON_PROPERTYNAME value: [NSColor colorWithCalibratedRed: 0.4 green: 0.7 blue: 0.9 alpha: 1.0]];

    // SQL
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_COMMENT value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_COMMENTLINE value: commentCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_WORD value: keywordCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_STRING value: stringCol];
    [_editor setColorProperty: SCI_STYLESETFORE parameter: SCE_SQL_NUMBER value: numberCol];

    if (lexer == "cpp") {
        [_editor setReferenceProperty: SCI_SETKEYWORDS parameter: 0 value:
            "alignas alignof and and_eq asm auto bitand bitor bool break case catch char char8_t char16_t char32_t class compl concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit export extern false float for friend goto if inline int int8_t int16_t int32_t int64_t long mutable namespace new noexcept not not_eq nullptr operator or or_eq private protected public register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid typename uint8_t uint16_t uint32_t uint64_t union unsigned using virtual void volatile wchar_t while xor xor_eq override final"];
    } else if (lexer == "python") {
        [_editor setReferenceProperty: SCI_SETKEYWORDS parameter: 0 value:
            "and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield"];
    }

    [_editor suspendDrawing: NO];
}

// ============================================================================
// File Operations
// ============================================================================

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
    if (notification->nmhdr.code == SCN_MODIFIED) {
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
    if (mActiveIndex >= 0 && mActiveIndex < static_cast<NSInteger>(mDocuments.size())) {
        const NppDocument& doc = mDocuments[mActiveIndex];
        if (!doc.isUntitled) {
            NSString* path = [NSString stringWithUTF8String: wstring_to_utf8(doc.filePath).c_str()];
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs: @[[NSURL fileURLWithPath: path]]];
        }
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

- (void) joinLines: (id) sender { [_editor message: SCI_LINESJOIN]; }
- (void) splitLines: (id) sender { [_editor message: SCI_LINESSPLIT]; }
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
            mDocuments[mActiveIndex].lexerName = [item.representedObject UTF8String];
            [self configureLexerForActiveDocument];
            [self updateStatusBar];
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

- (void) createMainMenu {
    NSMenu* menubar = [[NSMenu alloc] init];

    auto addItem = [&](NSMenu* menu, NSString* title, SEL action, NSString* key, NSEventModifierFlags mods) -> NSMenuItem* {
        NSMenuItem* item = [menu addItemWithTitle: title action: action keyEquivalent: key];
        item.target = self;
        if (mods != 0) item.keyEquivalentModifierMask = mods;
        return item;
    };

    // 1. App Menu
    NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle: @"Notepad++"];
    [appMenu addItemWithTitle: @"About Notepad++" action: @selector(showAbout:) keyEquivalent: @""].target = self;
    [appMenu addItem: [NSMenuItem separatorItem]];
    addItem(appMenu, @"Preferences...", @selector(showPreferences:), @",", 0);
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
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle: @"File"];
    addItem(fileMenu, @"New", @selector(newFile:), @"n", 0);
    addItem(fileMenu, @"Open...", @selector(openFile:), @"o", 0);
    addItem(fileMenu, @"Reload from Disk", @selector(reloadFromDisk:), @"r", 0);
    [fileMenu addItem: [NSMenuItem separatorItem]];
    addItem(fileMenu, @"Save", @selector(saveFile:), @"s", 0);
    addItem(fileMenu, @"Save As...", @selector(saveFileAs:), @"S", 0);
    addItem(fileMenu, @"Save All", @selector(saveAllFiles:), @"s", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    [fileMenu addItem: [NSMenuItem separatorItem]];
    addItem(fileMenu, @"Rename...", @selector(renameCurrentFile:), @"", 0);
    addItem(fileMenu, @"Reveal in Finder", @selector(revealInFinder:), @"R", 0);
    addItem(fileMenu, @"Open in Terminal", @selector(openInTerminal:), @"T", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(fileMenu, @"Copy Full Path", @selector(copyFullPath:), @"C", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(fileMenu, @"Copy Filename", @selector(copyFilename:), @"", 0);
    addItem(fileMenu, @"Copy Directory Path", @selector(copyDirectoryPath:), @"", 0);
    [fileMenu addItem: [NSMenuItem separatorItem]];
    addItem(fileMenu, @"Close Tab", @selector(closeTab:), @"w", 0);
    addItem(fileMenu, @"Close All", @selector(closeAllDocuments:), @"W", 0);
    addItem(fileMenu, @"Close All BUT Active", @selector(closeAllButActive:), @"", 0);
    fileMenuItem.submenu = fileMenu;
    [menubar addItem: fileMenuItem];

    // 3. Edit Menu (Including Column Editor ⌥⌘C)
    NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
    NSMenu* editMenu = [[NSMenu alloc] initWithTitle: @"Edit"];
    addItem(editMenu, @"Undo", @selector(undo:), @"z", 0);
    addItem(editMenu, @"Redo", @selector(redo:), @"Z", 0);
    [editMenu addItem: [NSMenuItem separatorItem]];
    addItem(editMenu, @"Cut", @selector(cut:), @"x", 0);
    addItem(editMenu, @"Copy", @selector(copy:), @"c", 0);
    addItem(editMenu, @"Paste", @selector(paste:), @"v", 0);
    addItem(editMenu, @"Select All", @selector(selectAll:), @"a", 0);
    [editMenu addItem: [NSMenuItem separatorItem]];

    // Column Editor Menu Item (⌥⌘C)
    addItem(editMenu, @"Column Editor... (열 편집기)", @selector(showColumnEditorDialog:), @"c", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    [editMenu addItem: [NSMenuItem separatorItem]];

    NSMenuItem* lineOpsItem = [editMenu addItemWithTitle: @"Line Operations" action: nil keyEquivalent: @""];
    NSMenu* lineOpsMenu = [[NSMenu alloc] initWithTitle: @"Line Operations"];
    addItem(lineOpsMenu, @"Duplicate Current Line", @selector(duplicateLine:), @"d", 0);
    addItem(lineOpsMenu, @"Split Lines", @selector(splitLines:), @"", 0);
    addItem(lineOpsMenu, @"Join Lines", @selector(joinLines:), @"j", NSEventModifierFlagControl);
    addItem(lineOpsMenu, @"Move Selected Lines Up", @selector(moveLineUp:), @"\x1E", NSEventModifierFlagOption);
    addItem(lineOpsMenu, @"Move Selected Lines Down", @selector(moveLineDown:), @"\x1F", NSEventModifierFlagOption);
    [lineOpsMenu addItem: [NSMenuItem separatorItem]];
    addItem(lineOpsMenu, @"Sort Lines Ascending", @selector(sortLinesAscending:), @"", 0);
    addItem(lineOpsMenu, @"Sort Lines Descending", @selector(sortLinesDescending:), @"", 0);
    addItem(lineOpsMenu, @"Remove Duplicate Lines", @selector(removeDuplicateLines:), @"", 0);
    addItem(lineOpsMenu, @"Remove Empty Lines", @selector(removeEmptyLines:), @"", 0);
    lineOpsItem.submenu = lineOpsMenu;

    NSMenuItem* blankOpsItem = [editMenu addItemWithTitle: @"Blank Operations" action: nil keyEquivalent: @""];
    NSMenu* blankOpsMenu = [[NSMenu alloc] initWithTitle: @"Blank Operations"];
    addItem(blankOpsMenu, @"Trim Trailing Space", @selector(trimTrailingSpace:), @"", 0);
    addItem(blankOpsMenu, @"Trim Leading Space", @selector(trimLeadingSpace:), @"", 0);
    blankOpsItem.submenu = blankOpsMenu;

    NSMenuItem* caseItem = [editMenu addItemWithTitle: @"Convert Case" action: nil keyEquivalent: @""];
    NSMenu* caseMenu = [[NSMenu alloc] initWithTitle: @"Convert Case"];
    addItem(caseMenu, @"UPPERCASE", @selector(upperCase:), @"u", NSEventModifierFlagCommand | NSEventModifierFlagShift);
    addItem(caseMenu, @"lowercase", @selector(lowerCase:), @"u", 0);
    caseItem.submenu = caseMenu;

    NSMenuItem* insertItem = [editMenu addItemWithTitle: @"Insert" action: nil keyEquivalent: @""];
    NSMenu* insertMenu = [[NSMenu alloc] initWithTitle: @"Insert"];
    addItem(insertMenu, @"Date Time (Short)", @selector(insertDateTimeShort:), @"", 0);
    addItem(insertMenu, @"Date Time (Long)", @selector(insertDateTimeLong:), @"", 0);
    insertItem.submenu = insertMenu;

    [editMenu addItem: [NSMenuItem separatorItem]];
    addItem(editMenu, @"Toggle Line Comment", @selector(toggleLineComment:), @"/", 0);
    editMenuItem.submenu = editMenu;
    [menubar addItem: editMenuItem];

    // 4. Search Menu
    NSMenuItem* searchMenuItem = [[NSMenuItem alloc] init];
    NSMenu* searchMenu = [[NSMenu alloc] initWithTitle: @"Search"];
    addItem(searchMenu, @"Find...", @selector(showFind:), @"f", 0);
    addItem(searchMenu, @"Find Next", @selector(onFindNext:), @"g", 0);
    addItem(searchMenu, @"Find Previous", @selector(onFindPrev:), @"G", 0);
    addItem(searchMenu, @"Replace...", @selector(showReplace:), @"F", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(searchMenu, @"Use Selection for Find", @selector(useSelectionForFind:), @"e", 0);
    [searchMenu addItem: [NSMenuItem separatorItem]];
    addItem(searchMenu, @"Go to Line...", @selector(goToLine:), @"l", 0);
    addItem(searchMenu, @"Go to Matching Brace", @selector(goToMatchingBrace:), @"b", 0);
    [searchMenu addItem: [NSMenuItem separatorItem]];

    NSMenuItem* bmItem = [searchMenu addItemWithTitle: @"Bookmark" action: nil keyEquivalent: @""];
    NSMenu* bmMenu = [[NSMenu alloc] initWithTitle: @"Bookmark"];
    addItem(bmMenu, @"Toggle Bookmark", @selector(toggleBookmark:), @"\x10", NSEventModifierFlagCommand);
    addItem(bmMenu, @"Next Bookmark", @selector(nextBookmark:), @"\x10", 0);
    addItem(bmMenu, @"Previous Bookmark", @selector(prevBookmark:), @"\x10", NSEventModifierFlagShift);
    addItem(bmMenu, @"Clear All Bookmarks", @selector(clearAllBookmarks:), @"", 0);
    bmItem.submenu = bmMenu;

    searchMenuItem.submenu = searchMenu;
    [menubar addItem: searchMenuItem];

    // 5. View Menu (Including 3 VS Code Panel Toggles)
    NSMenuItem* viewMenuItem = [[NSMenuItem alloc] init];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle: @"View"];
    addItem(viewMenu, @"Toggle Primary Side Bar (Finder Tree)", @selector(togglePrimarySidePanel:), @"b", 0);
    addItem(viewMenu, @"Toggle Bottom Panel (Embedded Terminal)", @selector(toggleBottomPanel:), @"`", NSEventModifierFlagControl);
    addItem(viewMenu, @"Toggle Secondary Side Bar (Language Preview)", @selector(toggleSecondarySidePanel:), @"P", 0);
    [viewMenu addItem: [NSMenuItem separatorItem]];
    addItem(viewMenu, @"Word Wrap", @selector(toggleWordWrap:), @"w", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(viewMenu, @"Line Numbers", @selector(toggleLineNumbers:), @"", 0);
    addItem(viewMenu, @"Show All Characters (White Space / EOL)", @selector(toggleShowAllCharacters:), @"", 0);
    addItem(viewMenu, @"Show Indent Guide", @selector(toggleIndentGuides:), @"", 0);
    [viewMenu addItem: [NSMenuItem separatorItem]];
    addItem(viewMenu, @"Fold All", @selector(foldAll:), @"0", NSEventModifierFlagCommand | NSEventModifierFlagOption);
    addItem(viewMenu, @"Unfold All", @selector(unfoldAll:), @"0", NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift);
    [viewMenu addItem: [NSMenuItem separatorItem]];
    addItem(viewMenu, @"Document Summary...", @selector(showSummaryDialog:), @"", 0);
    addItem(viewMenu, @"Toggle Dark Mode", @selector(toggleDarkMode:), @"D", 0);
    viewMenuItem.submenu = viewMenu;
    [menubar addItem: viewMenuItem];

    // 6. Encoding Menu
    NSMenuItem* encMenuItem = [[NSMenuItem alloc] init];
    NSMenu* encMenu = [[NSMenu alloc] initWithTitle: @"Encoding"];
    struct EncItem { NSString* title; int tag; };
    std::vector<EncItem> encList = {
        {@"UTF-8 (macOS Default)", 0},
        {@"UTF-8 with BOM", 1},
        {@"UTF-16 LE", 2},
        {@"UTF-16 BE", 3},
        {@"ANSI / Windows-1252", 4},
        {@"Korean (EUC-KR)", 5},
        {@"Japanese (Shift-JIS)", 6},
        {@"Traditional Chinese (Big5)", 7},
        {@"Simplified Chinese (GB2312)", 8}
    };
    for (const auto& e : encList) {
        NSMenuItem* item = [encMenu addItemWithTitle: e.title action: @selector(selectEncoding:) keyEquivalent: @""];
        item.target = self;
        item.tag = e.tag;
    }
    [encMenu addItem: [NSMenuItem separatorItem]];
    addItem(encMenu, @"Convert to Unix (LF)", @selector(convertToLF:), @"", 0);
    addItem(encMenu, @"Convert to Windows (CRLF)", @selector(convertToCRLF:), @"", 0);
    addItem(encMenu, @"Convert to Macintosh (CR)", @selector(convertToCR:), @"", 0);
    encMenuItem.submenu = encMenu;
    [menubar addItem: encMenuItem];

    // 7. Language Menu
    NSMenuItem* langMenuItem = [[NSMenuItem alloc] init];
    NSMenu* langMenu = [[NSMenu alloc] initWithTitle: @"Language"];
    struct LangDef { const char* name; const char* lexer; };
    std::vector<LangDef> langs = {
        {"Plain Text", "text"},
        {"C / C++", "cpp"},
        {"Python", "python"},
        {"JavaScript / TypeScript", "javascript"},
        {"HTML", "hypertext"},
        {"XML", "xml"},
        {"JSON", "json"},
        {"CSS", "css"},
        {"Markdown", "markdown"},
        {"SQL", "sql"},
        {"Rust", "rust"},
        {"Go", "go"},
        {"Java", "java"},
        {"PHP", "phpscript"},
        {"YAML", "yaml"},
        {"Shell / Bash", "bash"},
        {"Properties / INI", "props"},
        {"Batch", "batch"},
        {"Lua", "lua"},
        {"Ruby", "ruby"},
        {"Perl", "perl"},
        {"Makefile", "makefile"},
        {"TOML", "toml"},
        {"Zig", "zig"}
    };

    for (const auto& l : langs) {
        NSMenuItem* item = [langMenu addItemWithTitle: [NSString stringWithUTF8String: l.name] action: @selector(selectLanguage:) keyEquivalent: @""];
        item.target = self;
        item.representedObject = [NSString stringWithUTF8String: l.lexer];
    }
    langMenuItem.submenu = langMenu;
    [menubar addItem: langMenuItem];

    // 8. Settings Menu
    NSMenuItem* settingsMenuItem = [[NSMenuItem alloc] init];
    NSMenu* settingsMenu = [[NSMenu alloc] initWithTitle: @"Settings"];
    addItem(settingsMenu, @"Preferences...", @selector(showPreferences:), @",", 0);
    addItem(settingsMenu, @"Style Configurator...", @selector(showStyleConfigurator:), @"", 0);
    settingsMenuItem.submenu = settingsMenu;
    [menubar addItem: settingsMenuItem];

    // 9. Tools Menu
    NSMenuItem* toolsMenuItem = [[NSMenuItem alloc] init];
    NSMenu* toolsMenu = [[NSMenu alloc] initWithTitle: @"Tools"];
    addItem(toolsMenu, @"Generate MD5 Hash", @selector(generateMD5:), @"", 0);
    addItem(toolsMenu, @"Generate SHA-256 Hash", @selector(generateSHA256:), @"", 0);
    [toolsMenu addItem: [NSMenuItem separatorItem]];
    addItem(toolsMenu, @"Base64 Encode Selection", @selector(base64EncodeSelection:), @"", 0);
    addItem(toolsMenu, @"Base64 Decode Selection", @selector(base64DecodeSelection:), @"", 0);
    [toolsMenu addItem: [NSMenuItem separatorItem]];
    addItem(toolsMenu, @"URL Encode Selection", @selector(urlEncodeSelection:), @"", 0);
    addItem(toolsMenu, @"URL Decode Selection", @selector(urlDecodeSelection:), @"", 0);
    toolsMenuItem.submenu = toolsMenu;
    [menubar addItem: toolsMenuItem];

    // 10. Macro Menu
    NSMenuItem* macroMenuItem = [[NSMenuItem alloc] init];
    NSMenu* macroMenu = [[NSMenu alloc] initWithTitle: @"Macro"];
    addItem(macroMenu, @"Start / Stop Recording", @selector(toggleMacroRecording:), @"r", NSEventModifierFlagCommand | NSEventModifierFlagControl);
    addItem(macroMenu, @"Playback Recorded Macro", @selector(playbackMacro:), @"p", NSEventModifierFlagCommand | NSEventModifierFlagControl);
    macroMenuItem.submenu = macroMenu;
    [menubar addItem: macroMenuItem];

    // 11. Window Menu
    NSMenuItem* windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu* windowMenu = [[NSMenu alloc] initWithTitle: @"Window"];
    [windowMenu addItemWithTitle: @"Minimize" action: @selector(performMiniaturize:) keyEquivalent: @"m"];
    [windowMenu addItemWithTitle: @"Zoom" action: @selector(performZoom:) keyEquivalent: @""];
    [windowMenu addItem: [NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle: @"Bring All to Front" action: @selector(arrangeInFront:) keyEquivalent: @""];
    windowMenuItem.submenu = windowMenu;
    [menubar addItem: windowMenuItem];
    [NSApp setWindowsMenu: windowMenu];

    // 12. Help Menu
    NSMenuItem* helpMenuItem = [[NSMenuItem alloc] init];
    NSMenu* helpMenu = [[NSMenu alloc] initWithTitle: @"Help"];
    [helpMenu addItemWithTitle: @"About Notepad++" action: @selector(showAbout:) keyEquivalent: @""].target = self;
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
