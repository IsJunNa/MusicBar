// 文件说明：桌面歌词 overlay 兼容层视图，专门处理新版本网易云自绘歌词

#ifndef NMLyricPlaybackOverlayView_h
#define NMLyricPlaybackOverlayView_h

#import <AppKit/AppKit.h>

@interface NMLyricPlaybackOverlayView : NSView

// 当前高亮歌词，来源于网易云窗口里的单行歌词模型
@property (nonatomic, copy) NSString *currentText;

// 已播放宽度，直接复用网易云桌面歌词窗口里的 lyricsOffset
@property (nonatomic, assign) CGFloat playedWidth;

// 播放部分颜色，未开启渐变时直接使用这个颜色绘制已播放文字
@property (nonatomic, strong) NSColor *playedColor;

// 未播放部分颜色，先整句绘制一遍，再让已播放部分覆盖上去
@property (nonatomic, strong) NSColor *unplayedColor;

// 字体配置直接沿用 patch 配置，避免出现预览和实机不一致
@property (nonatomic, copy) NSString *fontName;
@property (nonatomic, assign) CGFloat fontSize;

// 播放部分支持沿用现有歌词渐变配置
@property (nonatomic, assign) BOOL gradientEnabled;
@property (nonatomic, copy) NSString *gradientStartColor;
@property (nonatomic, copy) NSString *gradientEndColor;
@property (nonatomic, copy) NSString *gradientDirection;

@end

@implementation NMLyricPlaybackOverlayView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)setCurrentText:(NSString *)currentText {
    _currentText = [currentText copy];
    self.needsDisplay = YES;
}

- (void)setPlayedWidth:(CGFloat)playedWidth {
    _playedWidth = playedWidth;
    self.needsDisplay = YES;
}

- (void)setPlayedColor:(NSColor *)playedColor {
    _playedColor = playedColor;
    self.needsDisplay = YES;
}

- (void)setUnplayedColor:(NSColor *)unplayedColor {
    _unplayedColor = unplayedColor;
    self.needsDisplay = YES;
}

- (void)setFontName:(NSString *)fontName {
    _fontName = [fontName copy];
    self.needsDisplay = YES;
}

- (void)setFontSize:(CGFloat)fontSize {
    _fontSize = fontSize;
    self.needsDisplay = YES;
}

- (void)setGradientEnabled:(BOOL)gradientEnabled {
    _gradientEnabled = gradientEnabled;
    self.needsDisplay = YES;
}

- (void)setGradientStartColor:(NSString *)gradientStartColor {
    _gradientStartColor = [gradientStartColor copy];
    self.needsDisplay = YES;
}

- (void)setGradientEndColor:(NSString *)gradientEndColor {
    _gradientEndColor = [gradientEndColor copy];
    self.needsDisplay = YES;
}

- (void)setGradientDirection:(NSString *)gradientDirection {
    _gradientDirection = [gradientDirection copy];
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    if (self.currentText.length == 0) {
        return;
    }

    CGFloat fittedFontSize = NMFittedFontSizeForText(self.currentText, self.fontName, self.fontSize, NSWidth(self.bounds));
    NSFont *font = NMFontFromConfig(self.fontName, fittedFontSize);
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary<NSAttributedStringKey, id> *measureAttributes = @{
        NSFontAttributeName: font,
        NSParagraphStyleAttributeName: paragraphStyle
    };
    CGFloat textWidth = ceil([self.currentText sizeWithAttributes:@{ NSFontAttributeName: font }].width);
    CGFloat textHeight = ceil(font.ascender - font.descender + font.leading);
    NSRect textRect = NSMakeRect(
        floor((NSWidth(self.bounds) - textWidth) / 2.0),
        floor((NSHeight(self.bounds) - textHeight) / 2.0),
        MIN(textWidth, NSWidth(self.bounds)),
        MIN(MAX(textHeight, 1.0), NSHeight(self.bounds))
    );

    NSMutableAttributedString *unplayedText = [[NSMutableAttributedString alloc] initWithString:self.currentText attributes:measureAttributes];
    [unplayedText addAttribute:NSForegroundColorAttributeName value:(self.unplayedColor ?: NSColor.whiteColor) range:NSMakeRange(0, unplayedText.length)];
    [unplayedText drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine];

    CGFloat playedWidth = MIN(MAX(self.playedWidth, 0.0), textRect.size.width);
    if (playedWidth <= 0.0) {
        return;
    }

    NSMutableAttributedString *playedText = nil;
    if (self.gradientEnabled) {
        playedText = [NMAttributedStringByApplyingGradientTextStyle(
            [[NSAttributedString alloc] initWithString:self.currentText attributes:measureAttributes],
            font,
            self.gradientStartColor,
            self.gradientEndColor,
            self.gradientDirection
        ) mutableCopy];
        [playedText addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, playedText.length)];
    } else {
        playedText = [[NSMutableAttributedString alloc] initWithString:self.currentText attributes:measureAttributes];
        [playedText addAttribute:NSForegroundColorAttributeName value:(self.playedColor ?: NSColor.whiteColor) range:NSMakeRange(0, playedText.length)];
    }

    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSMakeRect(textRect.origin.x, 0.0, playedWidth, NSHeight(self.bounds)));
    [playedText drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine];
    [NSGraphicsContext restoreGraphicsState];
}

@end

#endif
