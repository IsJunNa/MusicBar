// 文件说明：网易云音乐桌面歌词背景 native runtime 补丁

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "NMLyricVisualHelpers.h"
#import "NMLyricPlaybackOverlayView.h"

typedef NS_ENUM(NSInteger, NMLyricPatchMode) {
    NMLyricPatchModeTransparent,
    NMLyricPatchModeSolid,
    NMLyricPatchModeGradient
};

typedef struct {
    NMLyricPatchMode mode;
    CGFloat cornerRadius;
    CGFloat opacity;
    __unsafe_unretained NSString *targetBundleVersion;
    __unsafe_unretained NSString *blurMaterial;
    __unsafe_unretained NSString *gradientStartColor;
    __unsafe_unretained NSString *gradientEndColor;
    __unsafe_unretained NSString *gradientDirection;
    __unsafe_unretained NSString *lyricColor;
    __unsafe_unretained NSString *lyricPlayedColor;
    __unsafe_unretained NSString *lyricUnplayedColor;
    __unsafe_unretained NSString *lyricFontName;
    CGFloat lyricFontSize;
    BOOL lyricGradientEnabled;
    __unsafe_unretained NSString *lyricGradientStartColor;
    __unsafe_unretained NSString *lyricGradientEndColor;
    __unsafe_unretained NSString *lyricGradientDirection;
} NMLyricPatchConfig;

@interface NMLyricBackgroundHostView : NSView
@property (nonatomic, strong) NSVisualEffectView *effectView;
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@end

@implementation NMLyricBackgroundHostView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)layout {
    [super layout];
    self.effectView.frame = self.bounds;
    self.gradientLayer.frame = self.bounds;
}

@end

static const NSInteger NMMaxHookRetryCount = 80;
static char NMHostViewKey;
static char NMPlaybackOverlayViewKey;
static char NMLyricStyleRefreshPendingKey;
static IMP NMOriginalViewDidMoveToWindow = NULL;
static IMP NMOriginalLayout = NULL;
static IMP NMOriginalMouseMoved = NULL;
static IMP NMOriginalMouseEntered = NULL;
static IMP NMOriginalMouseExited = NULL;
static IMP NMOriginalWindowSetCurrentText = NULL;
static IMP NMOriginalWindowSetLyricsOffset = NULL;
static IMP NMOriginalWindowSetLastHighlightedLineModel = NULL;
static IMP NMOriginalWindowSetLyricsModel = NULL;
static BOOL NMHookInstalled = NO;
static BOOL NMWindowHookInstalled = NO;
static BOOL NMLyricStyleRefreshStarted = NO;
static BOOL NMLyricHoverMonitorStarted = NO;
static BOOL NMLyricLayerDiagnosticLogged = NO;
static BOOL NMLyricViewTreeDiagnosticLogged = NO;
static id NMLyricHoverMonitor = nil;
static NMLyricPatchConfig NMRuntimeConfig;

static NSString *NMConfigPath(void) {
    // sandbox 签名后优先读 App Bundle 内配置，避免触发其他 App 数据访问
    NSString *bundleConfigPath = [[NSBundle mainBundle] pathForResource:@"NMLyricBackgroundPatchConfig" ofType:@"json"];
    if (bundleConfigPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:bundleConfigPath]) {
        return bundleConfigPath;
    }

    NSString *supportPath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [[supportPath stringByAppendingPathComponent:@"NMLyricBackgroundPatch"] stringByAppendingPathComponent:@"config.json"];
}

static NSString *NMLogPath(void) {
    NSString *logsPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [[logsPath stringByAppendingPathComponent:@"Logs/NMLyricBackgroundPatch"] stringByAppendingPathComponent:@"patch.log"];
}

static void NMLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *path = NMLogPath();
    NSString *directory = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

static NMLyricPatchConfig NMDefaultConfig(void) {
    NMLyricPatchConfig config;
    config.mode = NMLyricPatchModeSolid;
    config.cornerRadius = 8.0;
    config.opacity = 0.8;
    config.targetBundleVersion = @"3401";
    config.blurMaterial = @"ultraThin";
    config.gradientStartColor = @"#111827";
    config.gradientEndColor = @"#2563EB";
    config.gradientDirection = @"leftToRight";
    config.lyricColor = @"#FFFFFF";
    config.lyricPlayedColor = @"#FFFFFF";
    config.lyricUnplayedColor = @"#8A8A8A";
    config.lyricFontName = @"PingFangSC-Semibold";
    config.lyricFontSize = 23.0;
    config.lyricGradientEnabled = NO;
    config.lyricGradientStartColor = @"#FFFFFF";
    config.lyricGradientEndColor = @"#9FD8FF";
    config.lyricGradientDirection = @"leftToRight";
    return config;
}

static NMLyricPatchConfig NMReadConfig(void) {
    NMLyricPatchConfig config = NMDefaultConfig();
    NSData *data = [NSData dataWithContentsOfFile:NMConfigPath()];
    if (!data) {
        NMLog(@"config not found, using default solid mode");
        return config;
    }

    NSError *error = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        NMLog(@"config parse failed: %@", error.localizedDescription ?: @"unknown error");
        return config;
    }

    NSString *mode = json[@"mode"];
    if ([mode isEqualToString:@"transparent"]) {
        config.mode = NMLyricPatchModeTransparent;
    } else if ([mode isEqualToString:@"gradient"]) {
        config.mode = NMLyricPatchModeGradient;
    } else {
        config.mode = NMLyricPatchModeSolid;
    }

    NSNumber *cornerRadius = json[@"cornerRadius"];
    NSNumber *opacity = json[@"opacity"];
    NSString *targetBundleVersion = json[@"targetBundleVersion"];
    NSString *blurMaterial = json[@"blurMaterial"];
    NSString *startColor = json[@"gradientStartColor"];
    NSString *endColor = json[@"gradientEndColor"];
    NSString *direction = json[@"gradientDirection"];
    NSString *lyricColor = json[@"lyricColor"];
    NSString *lyricPlayedColor = json[@"lyricPlayedColor"];
    NSString *lyricUnplayedColor = json[@"lyricUnplayedColor"];
    NSString *lyricFontName = json[@"lyricFontName"];
    NSNumber *lyricFontSize = json[@"lyricFontSize"];
    NSNumber *lyricGradientEnabled = json[@"lyricGradientEnabled"];
    NSString *lyricGradientStartColor = json[@"lyricGradientStartColor"];
    NSString *lyricGradientEndColor = json[@"lyricGradientEndColor"];
    NSString *lyricGradientDirection = json[@"lyricGradientDirection"];

    if ([cornerRadius respondsToSelector:@selector(doubleValue)]) {
        config.cornerRadius = cornerRadius.doubleValue;
    }
    if ([opacity respondsToSelector:@selector(doubleValue)]) {
        config.opacity = MIN(MAX(opacity.doubleValue, 0.0), 1.0);
    }
    if ([targetBundleVersion isKindOfClass:[NSString class]]) {
        config.targetBundleVersion = targetBundleVersion;
    }
    if ([blurMaterial isKindOfClass:[NSString class]]) {
        config.blurMaterial = blurMaterial;
    }
    if ([startColor isKindOfClass:[NSString class]]) {
        config.gradientStartColor = startColor;
    }
    if ([endColor isKindOfClass:[NSString class]]) {
        config.gradientEndColor = endColor;
    }
    if ([direction isKindOfClass:[NSString class]]) {
        config.gradientDirection = direction;
    }
    if ([lyricColor isKindOfClass:[NSString class]] && lyricColor.length > 0) {
        config.lyricColor = lyricColor;
    }
    if ([lyricPlayedColor isKindOfClass:[NSString class]] && lyricPlayedColor.length > 0) {
        config.lyricPlayedColor = lyricPlayedColor;
    } else if (config.lyricColor.length > 0) {
        config.lyricPlayedColor = config.lyricColor;
    }
    if ([lyricUnplayedColor isKindOfClass:[NSString class]] && lyricUnplayedColor.length > 0) {
        config.lyricUnplayedColor = lyricUnplayedColor;
    }
    if ([lyricFontName isKindOfClass:[NSString class]] && lyricFontName.length > 0) {
        config.lyricFontName = lyricFontName;
    }
    if ([lyricFontSize respondsToSelector:@selector(doubleValue)]) {
        config.lyricFontSize = MIN(MAX(lyricFontSize.doubleValue, 12.0), 72.0);
    }
    if ([lyricGradientEnabled respondsToSelector:@selector(boolValue)]) {
        config.lyricGradientEnabled = lyricGradientEnabled.boolValue;
    }
    if ([lyricGradientStartColor isKindOfClass:[NSString class]]) {
        config.lyricGradientStartColor = lyricGradientStartColor;
    }
    if ([lyricGradientEndColor isKindOfClass:[NSString class]]) {
        config.lyricGradientEndColor = lyricGradientEndColor;
    }
    if ([lyricGradientDirection isKindOfClass:[NSString class]]) {
        config.lyricGradientDirection = lyricGradientDirection;
    }

    return config;
}

static NSColor *NMPrimaryLyricColor(void) {
    NSString *hex = NMRuntimeConfig.lyricColor.length > 0 ? NMRuntimeConfig.lyricColor : NMRuntimeConfig.lyricPlayedColor;
    return NMColorFromHex(hex, 1.0);
}

static NSAttributedString *NMAttributedStringByApplyingSingleLyricStyle(NSAttributedString *source, NSColor *color, NSFont *font) {
    if (!source || source.length == 0) {
        return source;
    }

    NSMutableAttributedString *mutableString = [source mutableCopy];
    NSRange fullRange = NSMakeRange(0, mutableString.length);
    NMRemoveLyricOutlineAttributes(mutableString, fullRange);
    if (font) {
        [mutableString addAttribute:NSFontAttributeName value:font range:fullRange];
    }
    [mutableString addAttribute:NSForegroundColorAttributeName value:color range:fullRange];
    return mutableString;
}

static NSString *NMLoggableLyricText(NSString *text) {
    if (text.length <= 80) {
        return text ?: @"";
    }

    return [[text substringToIndex:80] stringByAppendingString:@"..."];
}

static NSString *NMStringTypeForTextLayer(CATextLayer *textLayer) {
    if ([textLayer.string isKindOfClass:[NSAttributedString class]]) {
        return @"attributed";
    }
    if ([textLayer.string isKindOfClass:[NSString class]]) {
        return @"plain";
    }
    return NSStringFromClass(object_getClass(textLayer.string)) ?: @"nil";
}

static id NMObjectIvar(id object, const char *ivarName);

static void NMLogTextViewDiagnostics(NSView *view, NSUInteger depth) {
    if ([view isKindOfClass:[NSTextField class]] && ![view isKindOfClass:[NSButton class]]) {
        NSTextField *textField = (NSTextField *)view;
        NSString *text = NMLoggableLyricText(textField.attributedStringValue.string ?: textField.stringValue);
        NMLog(@"lyric-diagnostic view NSTextField depth=%lu frame=%@ text=%@", (unsigned long)depth, NSStringFromRect(textField.frame), text);
    } else if ([view isKindOfClass:[NSTextView class]]) {
        NSTextView *textView = (NSTextView *)view;
        NSString *text = NMLoggableLyricText(textView.textStorage.string);
        NMLog(@"lyric-diagnostic view NSTextView depth=%lu frame=%@ text=%@", (unsigned long)depth, NSStringFromRect(textView.frame), text);
    }

    for (NSView *subview in view.subviews) {
        NMLogTextViewDiagnostics(subview, depth + 1);
    }
}

static void NMLogTextLayerDiagnostics(NSView *rootView) {
    if (NMLyricLayerDiagnosticLogged || !rootView.layer) {
        return;
    }

    NMLyricLayerDiagnosticLogged = YES;
    NSMutableArray<CATextLayer *> *textLayers = [NSMutableArray array];
    NMCollectTextLayers(rootView.layer, textLayers);
    NMLog(
        @"lyric-diagnostic begin lyricColor=%@ gradient=%@ textLayerCount=%lu",
        NMPrimaryLyricColor(),
        NMRuntimeConfig.lyricGradientEnabled ? @"true" : @"false",
        (unsigned long)textLayers.count
    );
    NMLogTextViewDiagnostics(rootView, 0);

    [textLayers enumerateObjectsUsingBlock:^(CATextLayer *textLayer, NSUInteger index, BOOL *stop) {
        NSString *text = NMLoggableLyricText(NMTextLayerPlainString(textLayer));
        CGRect bounds = textLayer.presentationLayer ? textLayer.presentationLayer.bounds : textLayer.bounds;
        CGRect frame = textLayer.presentationLayer ? textLayer.presentationLayer.frame : textLayer.frame;
        NMLog(
            @"lyric-diagnostic layer index=%lu type=%@ frame=%@ bounds=%@ hidden=%@ opacity=%.2f text=%@",
            (unsigned long)index,
            NMStringTypeForTextLayer(textLayer),
            NSStringFromRect(NSRectFromCGRect(frame)),
            NSStringFromRect(NSRectFromCGRect(bounds)),
            textLayer.hidden ? @"true" : @"false",
            textLayer.opacity,
            text
        );
        if (index >= 24) {
            *stop = YES;
        }
    }];
    NMLog(@"lyric-diagnostic end");
}

static void NMLogLayerTree(CALayer *layer, NSUInteger depth, NSUInteger *lineCount) {
    if (!layer || depth > 4 || *lineCount >= 120) {
        return;
    }

    NSString *className = NSStringFromClass(object_getClass(layer));
    NSString *delegateName = layer.delegate ? NSStringFromClass(object_getClass(layer.delegate)) : @"nil";
    NMLog(
        @"lyric-tree layer depth=%lu class=%@ delegate=%@ frame=%@ bounds=%@ hidden=%@ opacity=%.2f sublayers=%lu contents=%@",
        (unsigned long)depth,
        className,
        delegateName,
        NSStringFromRect(NSRectFromCGRect(layer.frame)),
        NSStringFromRect(NSRectFromCGRect(layer.bounds)),
        layer.hidden ? @"true" : @"false",
        layer.opacity,
        (unsigned long)layer.sublayers.count,
        layer.contents ? @"yes" : @"no"
    );
    *lineCount += 1;

    for (CALayer *sublayer in layer.sublayers) {
        NMLogLayerTree(sublayer, depth + 1, lineCount);
    }
}

static void NMLogViewTree(NSView *view, NSUInteger depth, NSUInteger *lineCount) {
    if (!view || depth > 5 || *lineCount >= 160) {
        return;
    }

    NSString *className = NSStringFromClass(object_getClass(view));
    NSString *accessibilityLabel = [view accessibilityLabel] ?: @"";
    NSString *accessibilityTitle = [view accessibilityTitle] ?: @"";
    NMLog(
        @"lyric-tree view depth=%lu class=%@ frame=%@ bounds=%@ hidden=%@ alpha=%.2f wantsLayer=%@ layer=%@ subviews=%lu axLabel=%@ axTitle=%@",
        (unsigned long)depth,
        className,
        NSStringFromRect(view.frame),
        NSStringFromRect(view.bounds),
        view.hidden ? @"true" : @"false",
        view.alphaValue,
        view.wantsLayer ? @"true" : @"false",
        view.layer ? NSStringFromClass(object_getClass(view.layer)) : @"nil",
        (unsigned long)view.subviews.count,
        NMLoggableLyricText(accessibilityLabel),
        NMLoggableLyricText(accessibilityTitle)
    );
    *lineCount += 1;

    for (NSView *subview in view.subviews) {
        NMLogViewTree(subview, depth + 1, lineCount);
    }
}

static void NMLogViewTreeDiagnostics(NSWindow *window) {
    if (NMLyricViewTreeDiagnosticLogged || !window.contentView) {
        return;
    }

    NMLyricViewTreeDiagnosticLogged = YES;
    NSUInteger lineCount = 0;
    NMLog(
        @"lyric-tree begin windowClass=%@ frame=%@ contentClass=%@",
        NSStringFromClass(object_getClass(window)),
        NSStringFromRect(window.frame),
        NSStringFromClass(object_getClass(window.contentView))
    );
    id lyricsTextField = NMObjectIvar(window, "_lyricsTextField");
    id controlSuperView = NMObjectIvar(window, "_controlSuperView");
    NMLog(
        @"lyric-tree window-ivar lyricsTextField=%@ controlSuperView=%@",
        lyricsTextField ? NSStringFromClass(object_getClass(lyricsTextField)) : @"nil",
        controlSuperView ? NSStringFromClass(object_getClass(controlSuperView)) : @"nil"
    );
    NMLogViewTree(window.contentView, 0, &lineCount);
    NMLogLayerTree(window.contentView.layer, 0, &lineCount);
    NMLog(@"lyric-tree end lines=%lu", (unsigned long)lineCount);
}

static void NMApplyLyricStyleInView(NSView *view, BOOL shouldApplyLayerTree) {
    NSColor *color = NMPrimaryLyricColor();

    if ([view isKindOfClass:[NSTextField class]] && ![view isKindOfClass:[NSButton class]]) {
        NSTextField *textField = (NSTextField *)view;
        NSString *plainText = textField.attributedStringValue.string ?: textField.stringValue;
        CGFloat fittedFontSize = NMFittedFontSizeForText(plainText, NMRuntimeConfig.lyricFontName, NMRuntimeConfig.lyricFontSize, NMAvailableTextWidthForView(textField));
        NSFont *font = NMFontFromConfig(NMRuntimeConfig.lyricFontName, fittedFontSize);
        textField.textColor = color;
        textField.font = font;
        NMEnsureViewCanFitFont(textField, font);
        if (NMRuntimeConfig.lyricGradientEnabled) {
            textField.attributedStringValue = NMAttributedStringByApplyingGradientTextStyle(
                textField.attributedStringValue,
                font,
                NMRuntimeConfig.lyricGradientStartColor,
                NMRuntimeConfig.lyricGradientEndColor,
                NMRuntimeConfig.lyricGradientDirection
            );
        } else {
            textField.attributedStringValue = NMAttributedStringByApplyingSingleLyricStyle(textField.attributedStringValue, color, font);
        }
    } else if ([view isKindOfClass:[NSTextView class]]) {
        NSTextView *textView = (NSTextView *)view;
        NSRange textRange = NSMakeRange(0, textView.textStorage.length);
        CGFloat fittedFontSize = NMFittedFontSizeForText(textView.textStorage.string, NMRuntimeConfig.lyricFontName, NMRuntimeConfig.lyricFontSize, NMAvailableTextWidthForView(textView));
        NSFont *font = NMFontFromConfig(NMRuntimeConfig.lyricFontName, fittedFontSize);
        NMRemoveLyricOutlineAttributes(textView.textStorage, textRange);
        textView.font = font;
        NMEnsureViewCanFitFont(textView, font);
        textView.textColor = color;
        if (NMRuntimeConfig.lyricGradientEnabled) {
            NSAttributedString *styledString = NMAttributedStringByApplyingGradientTextStyle(
                textView.textStorage,
                font,
                NMRuntimeConfig.lyricGradientStartColor,
                NMRuntimeConfig.lyricGradientEndColor,
                NMRuntimeConfig.lyricGradientDirection
            );
            [textView.textStorage setAttributedString:styledString];
        } else {
            NSAttributedString *styledString = NMAttributedStringByApplyingSingleLyricStyle(textView.textStorage, color, font);
            [textView.textStorage setAttributedString:styledString];
        }
    }

    if (shouldApplyLayerTree) {
        if (NMRuntimeConfig.lyricGradientEnabled) {
            NMApplyGradientTextStyleToLayerTree(
                view.layer,
                NMRuntimeConfig.lyricFontName,
                NMRuntimeConfig.lyricFontSize,
                NMRuntimeConfig.lyricGradientStartColor,
                NMRuntimeConfig.lyricGradientEndColor,
                NMRuntimeConfig.lyricGradientDirection
            );
        } else {
            NMApplyTextStyleToLayerTree(view.layer, color, NMRuntimeConfig.lyricFontName, NMRuntimeConfig.lyricFontSize);
        }
        NMLogTextLayerDiagnostics(view);
    }

    for (NSView *subview in view.subviews) {
        NMApplyLyricStyleInView(subview, NO);
    }
}

static void NMApplyLyricStyle(NSView *view) {
    NMApplyLyricStyleInView(view, YES);
}

static id NMObjectIvar(id object, const char *ivarName) {
    if (!object || !ivarName) {
        return nil;
    }

    Ivar ivar = class_getInstanceVariable(object_getClass(object), ivarName);
    if (!ivar) {
        return nil;
    }

    return object_getIvar(object, ivar);
}

static void NMApplyLyricStyleToTextField(NSTextField *textField) {
    if (!textField || [textField isKindOfClass:[NSButton class]]) {
        return;
    }

    NSColor *color = NMPrimaryLyricColor();
    NSString *plainText = textField.attributedStringValue.string ?: textField.stringValue;
    CGFloat fittedFontSize = NMFittedFontSizeForText(plainText, NMRuntimeConfig.lyricFontName, NMRuntimeConfig.lyricFontSize, NMAvailableTextWidthForView(textField));
    NSFont *font = NMFontFromConfig(NMRuntimeConfig.lyricFontName, fittedFontSize);

    textField.textColor = color;
    textField.font = font;
    NMEnsureViewCanFitFont(textField, font);
    if (NMRuntimeConfig.lyricGradientEnabled) {
        textField.attributedStringValue = NMAttributedStringByApplyingGradientTextStyle(
            textField.attributedStringValue,
            font,
            NMRuntimeConfig.lyricGradientStartColor,
            NMRuntimeConfig.lyricGradientEndColor,
            NMRuntimeConfig.lyricGradientDirection
        );
    } else {
        textField.attributedStringValue = NMAttributedStringByApplyingSingleLyricStyle(textField.attributedStringValue, color, font);
    }
    textField.needsDisplay = YES;
}

static NSString *NMCurrentLineTextFromWindow(NSWindow *window) {
    // 新版网易云会把当前高亮行挂在窗口 ivar 上，这里优先复用它避免拿到整份 LRC 文本
    id lineModel = NMObjectIvar(window, "_lastHighlightedLineModel");
    if ([lineModel respondsToSelector:@selector(lyricsLineString)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id lineText = [lineModel performSelector:@selector(lyricsLineString)];
#pragma clang diagnostic pop
        if ([lineText isKindOfClass:[NSString class]] && ((NSString *)lineText).length > 0) {
            return lineText;
        }
    }

    id plainText = NMObjectIvar(window, "_LRCPlainText");
    if ([plainText isKindOfClass:[NSString class]] && ![(NSString *)plainText containsString:@"\n"]) {
        return plainText;
    }

    return nil;
}

static CGFloat NMLyricsOffsetFromWindow(NSWindow *window) {
    id rawOffset = [window respondsToSelector:@selector(lyricsOffset)]
        ? @(((CGFloat (*)(id, SEL))objc_msgSend)(window, @selector(lyricsOffset)))
        : nil;
    return [rawOffset respondsToSelector:@selector(doubleValue)] ? ((NSNumber *)rawOffset).doubleValue : 0.0;
}

static NMLyricPlaybackOverlayView *NMEnsurePlaybackOverlayView(NSWindow *window) {
    if (!window.contentView) {
        return nil;
    }

    NMLyricPlaybackOverlayView *overlayView = objc_getAssociatedObject(window.contentView, &NMPlaybackOverlayViewKey);
    if (overlayView) {
        overlayView.frame = window.contentView.bounds;
        return overlayView;
    }

    overlayView = [[NMLyricPlaybackOverlayView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:overlayView positioned:NSWindowAbove relativeTo:nil];
    objc_setAssociatedObject(window.contentView, &NMPlaybackOverlayViewKey, overlayView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return overlayView;
}

static void NMSetOriginalControlViewHiddenState(NSWindow *window, BOOL shouldHide) {
    // 26.5.1 的歌词是控件内部自绘，直接把 layer 透明掉能避免看到两层歌词
    id controlSuperView = NMObjectIvar(window, "_controlSuperView");
    if ([controlSuperView isKindOfClass:[NSView class]]) {
        NSView *controlView = (NSView *)controlSuperView;
        controlView.wantsLayer = YES;
        controlView.layer.opacity = shouldHide ? 0.0 : 1.0;
    }
}

static void NMRefreshPlaybackOverlayForWindow(NSWindow *window) {
    if (!window || !window.contentView) {
        return;
    }

    id lyricsTextField = NMObjectIvar(window, "_lyricsTextField");
    BOOL needsOverlay = ![lyricsTextField isKindOfClass:[NSTextField class]];
    NMLyricPlaybackOverlayView *overlayView = NMEnsurePlaybackOverlayView(window);
    if (!overlayView) {
        return;
    }

    if (!needsOverlay) {
        overlayView.hidden = YES;
        overlayView.currentText = nil;
        NMSetOriginalControlViewHiddenState(window, NO);
        return;
    }

    NSString *currentText = NMCurrentLineTextFromWindow(window);
    if (currentText.length == 0) {
        overlayView.hidden = YES;
        overlayView.currentText = nil;
        NMSetOriginalControlViewHiddenState(window, NO);
        return;
    }

    overlayView.hidden = NO;
    overlayView.currentText = currentText;
    overlayView.playedWidth = NMLyricsOffsetFromWindow(window);
    overlayView.playedColor = NMColorFromHex(NMRuntimeConfig.lyricPlayedColor, 1.0);
    overlayView.unplayedColor = NMColorFromHex(NMRuntimeConfig.lyricUnplayedColor, 1.0);
    overlayView.fontName = NMRuntimeConfig.lyricFontName;
    overlayView.fontSize = NMRuntimeConfig.lyricFontSize;
    overlayView.gradientEnabled = NMRuntimeConfig.lyricGradientEnabled;
    overlayView.gradientStartColor = NMRuntimeConfig.lyricGradientStartColor;
    overlayView.gradientEndColor = NMRuntimeConfig.lyricGradientEndColor;
    overlayView.gradientDirection = NMRuntimeConfig.lyricGradientDirection;
    NMSetOriginalControlViewHiddenState(window, YES);
}

static void NMApplyLyricStyleToWindowIvars(NSWindow *window) {
    id lyricsTextField = NMObjectIvar(window, "_lyricsTextField");
    if ([lyricsTextField isKindOfClass:[NSTextField class]]) {
        NMApplyLyricStyleToTextField((NSTextField *)lyricsTextField);
    }

    id controlSuperView = NMObjectIvar(window, "_controlSuperView");
    if ([controlSuperView isKindOfClass:[NSView class]]) {
        ((NSView *)controlSuperView).needsDisplay = YES;
    }

    NMRefreshPlaybackOverlayForWindow(window);
}

static void NMRemoveHostView(NSView *contentView) {
    NMLyricBackgroundHostView *hostView = objc_getAssociatedObject(contentView, &NMHostViewKey);
    if (hostView) {
        [hostView removeFromSuperview];
        objc_setAssociatedObject(contentView, &NMHostViewKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
}

static NMLyricBackgroundHostView *NMEnsureHostView(NSView *contentView) {
    NMLyricBackgroundHostView *hostView = objc_getAssociatedObject(contentView, &NMHostViewKey);
    if (hostView) {
        hostView.frame = contentView.bounds;
        return hostView;
    }

    hostView = [[NMLyricBackgroundHostView alloc] initWithFrame:contentView.bounds];
    [contentView addSubview:hostView positioned:NSWindowBelow relativeTo:nil];
    objc_setAssociatedObject(contentView, &NMHostViewKey, hostView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return hostView;
}

static void NMConfigureSolid(NMLyricBackgroundHostView *hostView) {
    [hostView.effectView removeFromSuperview];
    hostView.effectView = nil;
    [hostView.gradientLayer removeFromSuperlayer];
    hostView.gradientLayer = nil;

    NSColor *backgroundColor = NMColorFromHex(NMRuntimeConfig.gradientStartColor, NMRuntimeConfig.opacity);
    hostView.layer.backgroundColor = backgroundColor.CGColor;
    hostView.alphaValue = 1.0;
    hostView.layer.cornerRadius = NMRuntimeConfig.cornerRadius;
    hostView.layer.masksToBounds = YES;
}

static void NMConfigureGradient(NMLyricBackgroundHostView *hostView) {
    [hostView.effectView removeFromSuperview];
    hostView.effectView = nil;

    if (!hostView.gradientLayer) {
        hostView.gradientLayer = [CAGradientLayer layer];
        [hostView.layer insertSublayer:hostView.gradientLayer atIndex:0];
    }

    NSColor *startColor = NMColorFromHex(NMRuntimeConfig.gradientStartColor, NMRuntimeConfig.opacity);
    NSColor *endColor = NMColorFromHex(NMRuntimeConfig.gradientEndColor, NMRuntimeConfig.opacity);
    hostView.gradientLayer.colors = @[(__bridge id)startColor.CGColor, (__bridge id)endColor.CGColor];
    hostView.gradientLayer.frame = hostView.bounds;
    hostView.alphaValue = 1.0;

    if ([NMRuntimeConfig.gradientDirection isEqualToString:@"topToBottom"]) {
        hostView.gradientLayer.startPoint = CGPointMake(0.5, 0.0);
        hostView.gradientLayer.endPoint = CGPointMake(0.5, 1.0);
    } else if ([NMRuntimeConfig.gradientDirection isEqualToString:@"bottomToTop"]) {
        hostView.gradientLayer.startPoint = CGPointMake(0.5, 1.0);
        hostView.gradientLayer.endPoint = CGPointMake(0.5, 0.0);
    } else if ([NMRuntimeConfig.gradientDirection isEqualToString:@"topLeftToBottomRight"] || [NMRuntimeConfig.gradientDirection isEqualToString:@"diagonal"]) {
        hostView.gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        hostView.gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    } else if ([NMRuntimeConfig.gradientDirection isEqualToString:@"topRightToBottomLeft"]) {
        hostView.gradientLayer.startPoint = CGPointMake(1.0, 0.0);
        hostView.gradientLayer.endPoint = CGPointMake(0.0, 1.0);
    } else if ([NMRuntimeConfig.gradientDirection isEqualToString:@"rightToLeft"]) {
        hostView.gradientLayer.startPoint = CGPointMake(1.0, 0.5);
        hostView.gradientLayer.endPoint = CGPointMake(0.0, 0.5);
    } else {
        hostView.gradientLayer.startPoint = CGPointMake(0.0, 0.5);
        hostView.gradientLayer.endPoint = CGPointMake(1.0, 0.5);
    }

    hostView.layer.cornerRadius = NMRuntimeConfig.cornerRadius;
    hostView.layer.masksToBounds = YES;
}

static void NMApplyBackgroundToWindow(NSWindow *window) {
    if (!window || !window.contentView) {
        return;
    }

    NSView *contentView = window.contentView;
    BOOL transparentMode = NMRuntimeConfig.mode == NMLyricPatchModeTransparent;
    NMPrepareTransparentWindow(window, transparentMode);
    // 部分网易云版本会把左上角关闭叉挂在窗口标准按钮区域，不在 contentView 子树里
    [window standardWindowButton:NSWindowCloseButton].hidden = transparentMode;
    NMClearOriginalBackgrounds(contentView, YES, YES);
    NMToggleOriginalCloseButtons(contentView, contentView, transparentMode);
    NMLogViewTreeDiagnostics(window);
    NMApplyLyricStyle(contentView);
    NMApplyLyricStyleToWindowIvars(window);

    if (NMRuntimeConfig.mode == NMLyricPatchModeTransparent) {
        NMRemoveHostView(contentView);
        NMLog(@"transparent background applied");
        return;
    }

    NMLyricBackgroundHostView *hostView = NMEnsureHostView(contentView);
    if (NMRuntimeConfig.mode == NMLyricPatchModeGradient) {
        NMConfigureGradient(hostView);
        NMLog(@"gradient background applied");
    } else {
        NMConfigureSolid(hostView);
        NMLog(@"solid background applied");
    }
}

static void NMApplyToExistingWindows(Class controlClass) {
    Class windowClass = objc_getClass("YYYDesktopLyricsWindow");
    for (NSWindow *window in NSApp.windows) {
        if ((windowClass && [window isKindOfClass:windowClass]) || NMViewTreeContainsClass(window.contentView, controlClass)) {
            NMApplyBackgroundToWindow(window);
        }
    }
}

static void NMReapplyTransparentCloseControls(Class controlClass) {
    if (NMRuntimeConfig.mode != NMLyricPatchModeTransparent) {
        return;
    }

    Class windowClass = objc_getClass("YYYDesktopLyricsWindow");
    for (NSWindow *window in NSApp.windows) {
        if ((windowClass && [window isKindOfClass:windowClass]) || NMViewTreeContainsClass(window.contentView, controlClass)) {
            [window standardWindowButton:NSWindowCloseButton].hidden = YES;
            NMToggleOriginalCloseButtons(window.contentView, window.contentView, YES);
        }
    }
}

static void NMRefreshLyricStyleInExistingWindows(Class controlClass) {
    Class windowClass = objc_getClass("YYYDesktopLyricsWindow");
    for (NSWindow *window in NSApp.windows) {
        if ((windowClass && [window isKindOfClass:windowClass]) || NMViewTreeContainsClass(window.contentView, controlClass)) {
            NMApplyLyricStyle(window.contentView);
            NMApplyLyricStyleToWindowIvars(window);
            NMRefreshPlaybackOverlayForWindow(window);
        }
    }
    NMReapplyTransparentCloseControls(controlClass);
}

static void NMRefreshLyricStyleLater(Class controlClass) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NMRefreshLyricStyleInExistingWindows(controlClass);
        NMRefreshLyricStyleLater(controlClass);
    });
}

static void NMStartLyricStyleRefresh(Class controlClass) {
    if (NMLyricStyleRefreshStarted) {
        return;
    }

    NMLyricStyleRefreshStarted = YES;
    NMRefreshLyricStyleInExistingWindows(controlClass);
    // 网易云会在切歌或刷新歌词时重设文字样式，定时补写可以避免又变回默认
    NMRefreshLyricStyleLater(controlClass);
}

static void NMStartHoverCloseControlRefresh(Class controlClass) {
    if (NMLyricHoverMonitorStarted) {
        return;
    }

    NMLyricHoverMonitorStarted = YES;
    NSEventMask eventMask = NSEventMaskMouseMoved | NSEventMaskMouseEntered | NSEventMaskMouseExited;
    NMLyricHoverMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:eventMask handler:^NSEvent *(NSEvent *event) {
        // hover 后网易云会重新显示左上角关闭叉，这里等当前事件处理完再压回隐藏态
        dispatch_async(dispatch_get_main_queue(), ^{
            NMReapplyTransparentCloseControls(controlClass);
        });
        return event;
    }];
}

static BOOL NMClassDeclaresSelector(Class targetClass, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(targetClass, &count);
    BOOL found = NO;
    for (unsigned int index = 0; index < count; index++) {
        if (method_getName(methods[index]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

static void NMCallOriginalViewDidMoveToWindow(NSView *view) {
    SEL selector = @selector(viewDidMoveToWindow);
    if (NMOriginalViewDidMoveToWindow) {
        ((void (*)(id, SEL))NMOriginalViewDidMoveToWindow)(view, selector);
        return;
    }

    struct objc_super superInfo = {
        .receiver = view,
        .super_class = class_getSuperclass(object_getClass(view))
    };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&superInfo, selector);
}

static void NMCallOriginalLayout(NSView *view) {
    SEL selector = @selector(layout);
    if (NMOriginalLayout) {
        ((void (*)(id, SEL))NMOriginalLayout)(view, selector);
        return;
    }

    struct objc_super superInfo = {
        .receiver = view,
        .super_class = class_getSuperclass(object_getClass(view))
    };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&superInfo, selector);
}

static void NMScheduleImmediateLyricStyleRefresh(NSView *view) {
    if (!view.window || [objc_getAssociatedObject(view, &NMLyricStyleRefreshPendingKey) boolValue]) {
        return;
    }

    // 歌词刚刷新时网易云会先按原始尺寸布局，下一轮主线程再补样式可以消掉短暂裁切
    objc_setAssociatedObject(view, &NMLyricStyleRefreshPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak NSView *weakView = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSView *strongView = weakView;
        if (!strongView) {
            return;
        }

        if (strongView.window.contentView) {
            NMApplyLyricStyle(strongView.window.contentView);
            NMApplyLyricStyleToWindowIvars(strongView.window);
            NMRefreshPlaybackOverlayForWindow(strongView.window);
        }
        objc_setAssociatedObject(strongView, &NMLyricStyleRefreshPendingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static void NMInstallWindowTextHook(Class windowClass, SEL selector, IMP *originalStorage, const char *typeEncoding) {
    IMP replacement = NULL;

    if (selector == @selector(setCurrentText:)) {
        replacement = imp_implementationWithBlock(^(NSWindow *window, NSString *currentText) {
            ((void (*)(id, SEL, id))*originalStorage)(window, selector, currentText);
            NMRefreshPlaybackOverlayForWindow(window);
        });
    } else if (selector == @selector(setLastHighlightedLineModel:)) {
        replacement = imp_implementationWithBlock(^(NSWindow *window, id lineModel) {
            ((void (*)(id, SEL, id))*originalStorage)(window, selector, lineModel);
            NMRefreshPlaybackOverlayForWindow(window);
        });
    } else if (selector == @selector(setLyricsModel:)) {
        replacement = imp_implementationWithBlock(^(NSWindow *window, id lyricsModel) {
            ((void (*)(id, SEL, id))*originalStorage)(window, selector, lyricsModel);
            NMRefreshPlaybackOverlayForWindow(window);
        });
    } else if (selector == @selector(setLyricsOffset:)) {
        replacement = imp_implementationWithBlock(^(NSWindow *window, double lyricsOffset) {
            ((void (*)(id, SEL, double))*originalStorage)(window, selector, lyricsOffset);
            NMRefreshPlaybackOverlayForWindow(window);
        });
    }

    if (!replacement) {
        return;
    }

    Method method = class_getInstanceMethod(windowClass, selector);
    *originalStorage = method_getImplementation(method);
    method_setImplementation(method, replacement);
}

static void NMInstallWindowHooks(void) {
    if (NMWindowHookInstalled) {
        return;
    }

    Class windowClass = objc_getClass("YYYDesktopLyricsWindow");
    if (!windowClass) {
        return;
    }

    NMInstallWindowTextHook(windowClass, @selector(setCurrentText:), &NMOriginalWindowSetCurrentText, "v@:@");
    NMInstallWindowTextHook(windowClass, @selector(setLastHighlightedLineModel:), &NMOriginalWindowSetLastHighlightedLineModel, "v@:@");
    NMInstallWindowTextHook(windowClass, @selector(setLyricsModel:), &NMOriginalWindowSetLyricsModel, "v@:@");
    NMInstallWindowTextHook(windowClass, @selector(setLyricsOffset:), &NMOriginalWindowSetLyricsOffset, "v@:d");

    NMWindowHookInstalled = YES;
    NMLog(@"window hooks installed for %@", NSStringFromClass(windowClass));
}

static void NMCallOriginalMouseEvent(NSView *view, SEL selector, NSEvent *event, IMP originalImplementation) {
    if (originalImplementation) {
        ((void (*)(id, SEL, NSEvent *))originalImplementation)(view, selector, event);
        return;
    }

    struct objc_super superInfo = {
        .receiver = view,
        .super_class = class_getSuperclass(object_getClass(view))
    };
    ((void (*)(struct objc_super *, SEL, NSEvent *))objc_msgSendSuper)(&superInfo, selector, event);
}

static void NMInstallMouseEventHook(Class controlClass, SEL selector, IMP *originalStorage) {
    IMP replacement = imp_implementationWithBlock(^(NSView *view, NSEvent *event) {
        NMCallOriginalMouseEvent(view, selector, event, *originalStorage);
        if (view.window) {
            // 网易云 hover 处理会恢复左上角关闭叉，原逻辑执行完马上压回隐藏态
            NMReapplyTransparentCloseControls(controlClass);
        }
    });

    if (NMClassDeclaresSelector(controlClass, selector)) {
        Method method = class_getInstanceMethod(controlClass, selector);
        *originalStorage = method_getImplementation(method);
        method_setImplementation(method, replacement);
    } else {
        class_addMethod(controlClass, selector, replacement, "v@:@");
    }
}

static void NMInstallLayoutHook(Class controlClass) {
    SEL selector = @selector(layout);
    IMP replacement = imp_implementationWithBlock(^(NSView *view) {
        NMCallOriginalLayout(view);
        NMScheduleImmediateLyricStyleRefresh(view);
    });

    if (NMClassDeclaresSelector(controlClass, selector)) {
        Method method = class_getInstanceMethod(controlClass, selector);
        NMOriginalLayout = method_getImplementation(method);
        method_setImplementation(method, replacement);
    } else {
        class_addMethod(controlClass, selector, replacement, "v@:");
    }
}

static void NMInstallControlViewHook(Class controlClass) {
    if (NMHookInstalled) {
        return;
    }

    SEL selector = @selector(viewDidMoveToWindow);
    IMP replacement = imp_implementationWithBlock(^(NSView *view) {
        NMCallOriginalViewDidMoveToWindow(view);
        if (view.window) {
            NMApplyBackgroundToWindow(view.window);
        }
    });

    if (NMClassDeclaresSelector(controlClass, selector)) {
        Method method = class_getInstanceMethod(controlClass, selector);
        NMOriginalViewDidMoveToWindow = method_getImplementation(method);
        method_setImplementation(method, replacement);
    } else {
        class_addMethod(controlClass, selector, replacement, "v@:");
    }

    NMInstallMouseEventHook(controlClass, @selector(mouseMoved:), &NMOriginalMouseMoved);
    NMInstallMouseEventHook(controlClass, @selector(mouseEntered:), &NMOriginalMouseEntered);
    NMInstallMouseEventHook(controlClass, @selector(mouseExited:), &NMOriginalMouseExited);
    NMInstallLayoutHook(controlClass);

    NMHookInstalled = YES;
    NMLog(@"hook installed for %@", NSStringFromClass(controlClass));
}

static BOOL NMIsTargetVersionAllowed(void) {
    NSString *currentBuild = [NSBundle mainBundle].infoDictionary[@"CFBundleVersion"];
    if (NMRuntimeConfig.targetBundleVersion.length == 0 || currentBuild.length == 0) {
        return YES;
    }
    if ([currentBuild isEqualToString:NMRuntimeConfig.targetBundleVersion]) {
        return YES;
    }

    NMLog(@"bundle version mismatch, current=%@ target=%@", currentBuild, NMRuntimeConfig.targetBundleVersion);
    return NO;
}

static void NMTryInstallHooks(NSInteger retryCount) {
    Class controlClass = objc_getClass("YYYDesktopLyricsControlSuperView");
    if (controlClass) {
        NMInstallWindowHooks();
        NMInstallControlViewHook(controlClass);
        NMApplyToExistingWindows(controlClass);
        NMStartLyricStyleRefresh(controlClass);
        NMStartHoverCloseControlRefresh(controlClass);
        return;
    }

    if (retryCount >= NMMaxHookRetryCount) {
        NMLog(@"target class not found after retries");
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NMTryInstallHooks(retryCount + 1);
    });
}

__attribute__((constructor))
static void NMLyricBackgroundPatchEntry(void) {
    NMRuntimeConfig = NMReadConfig();
    NMLog(@"patch loaded");

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!NMIsTargetVersionAllowed()) {
            return;
        }
        NMTryInstallHooks(0);
    });
}
