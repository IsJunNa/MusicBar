// 文件说明：桌面歌词背景 runtime 视觉辅助函数

#ifndef NMLyricVisualHelpers_h
#define NMLyricVisualHelpers_h

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

static NSColor *NMColorFromHex(NSString *hex, CGFloat alpha) {
    NSString *cleanHex = [[hex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([cleanHex hasPrefix:@"#"]) {
        cleanHex = [cleanHex substringFromIndex:1];
    }
    if (cleanHex.length != 6) {
        return [NSColor colorWithCalibratedWhite:0.1 alpha:alpha];
    }

    unsigned int value = 0;
    [[NSScanner scannerWithString:cleanHex] scanHexInt:&value];
    CGFloat red = ((value >> 16) & 0xff) / 255.0;
    CGFloat green = ((value >> 8) & 0xff) / 255.0;
    CGFloat blue = (value & 0xff) / 255.0;
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static NSVisualEffectMaterial NMMaterialFromConfig(NSString *material) {
    // AppKit 当前 SDK 没有 SwiftUI 的 Ultra Thin/Thin/Regular 名称，这里映射到最接近的原生材质
    if ([material isEqualToString:@"thin"]) {
        return NSVisualEffectMaterialContentBackground;
    }
    if ([material isEqualToString:@"regular"]) {
        return NSVisualEffectMaterialWindowBackground;
    }
    if ([material isEqualToString:@"sidebar"]) {
        return NSVisualEffectMaterialSidebar;
    }
    if ([material isEqualToString:@"hudWindow"]) {
        return NSVisualEffectMaterialHUDWindow;
    }

    return NSVisualEffectMaterialUnderWindowBackground;
}

static CGFloat NMGradientAngleFromDirection(NSString *direction) {
    if ([direction isEqualToString:@"rightToLeft"]) {
        return 180.0;
    }
    if ([direction isEqualToString:@"topToBottom"]) {
        return -90.0;
    }
    if ([direction isEqualToString:@"bottomToTop"]) {
        return 90.0;
    }
    if ([direction isEqualToString:@"topLeftToBottomRight"] || [direction isEqualToString:@"diagonal"]) {
        return -45.0;
    }
    if ([direction isEqualToString:@"topRightToBottomLeft"]) {
        return -135.0;
    }

    return 0.0;
}

static NSFont *NMFontFromConfig(NSString *fontName, CGFloat fontSize) {
    NSFont *font = [NSFont fontWithName:fontName ?: @"PingFangSC-Semibold" size:fontSize];
    return font ?: [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
}

static NSColor *NMColorByMixing(NSColor *startColor, NSColor *endColor, CGFloat progress) {
    progress = MIN(MAX(progress, 0.0), 1.0);
    NSColor *startRGB = [startColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: startColor;
    NSColor *endRGB = [endColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: endColor;
    CGFloat red = startRGB.redComponent + (endRGB.redComponent - startRGB.redComponent) * progress;
    CGFloat green = startRGB.greenComponent + (endRGB.greenComponent - startRGB.greenComponent) * progress;
    CGFloat blue = startRGB.blueComponent + (endRGB.blueComponent - startRGB.blueComponent) * progress;
    CGFloat alpha = startRGB.alphaComponent + (endRGB.alphaComponent - startRGB.alphaComponent) * progress;
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static CGFloat NMGradientProgressForTextOffset(CGFloat offset, CGFloat totalWidth, NSString *direction) {
    CGFloat progress = totalWidth > 0.0 ? offset / totalWidth : 0.0;
    if ([direction isEqualToString:@"rightToLeft"] || [direction isEqualToString:@"topRightToBottomLeft"]) {
        return 1.0 - progress;
    }
    if ([direction isEqualToString:@"topToBottom"] || [direction isEqualToString:@"bottomToTop"]) {
        return [direction isEqualToString:@"bottomToTop"] ? 1.0 : 0.0;
    }

    return progress;
}

static CGFloat NMFittedFontSizeForText(NSString *text, NSString *fontName, CGFloat fontSize, CGFloat availableWidth) {
    if (text.length == 0 || availableWidth <= 0.0) {
        return fontSize;
    }

    // 大字号只在当前歌词控件放不下时缩小，配置里的原始字号仍然保留
    CGFloat maxTextWidth = MAX(1.0, availableWidth - 48.0);
    NSFont *font = NMFontFromConfig(fontName, fontSize);
    CGFloat textWidth = [text sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    CGFloat scale = MIN(1.0, maxTextWidth / MAX(textWidth, 1.0));
    return MAX(12.0, fontSize * scale);
}

// 根据字体指标估算歌词层最小高度，服务于大字号防裁切
static CGFloat NMMinimumTextHeightForFont(NSFont *font) {
    if (!font) {
        return 0.0;
    }

    // 大字号字体的实际字形会超过默认歌词层高度，这里预留一点上下余量避免被裁
    return ceil(font.ascender - font.descender + font.leading + 8.0);
}

// NSTextField/NSTextView 写入大字号后同步扩高，保持原中心位置不跳动
static void NMEnsureViewCanFitFont(NSView *view, NSFont *font) {
    CGFloat minimumHeight = NMMinimumTextHeightForFont(font);
    if (!view || minimumHeight <= 0.0 || NSHeight(view.frame) >= minimumHeight) {
        return;
    }

    NSRect frame = view.frame;
    CGFloat centerY = NSMidY(frame);
    frame.size.height = minimumHeight;
    frame.origin.y = centerY - minimumHeight / 2.0;
    view.frame = frame;
}

// CATextLayer 多用于歌词进度分层，需要单独扩高避免顶部字形被裁
static void NMEnsureTextLayerCanFitFont(CATextLayer *textLayer, NSFont *font) {
    CGFloat minimumHeight = NMMinimumTextHeightForFont(font);
    if (!textLayer || minimumHeight <= 0.0) {
        return;
    }

    CGRect bounds = textLayer.bounds;
    if (CGRectGetHeight(bounds) >= minimumHeight) {
        return;
    }

    bounds.size.height = minimumHeight;
    textLayer.bounds = bounds;
}

static CGFloat NMAvailableTextWidthForView(NSView *view) {
    CGFloat width = NSWidth(view.bounds);
    if (width <= 0.0) {
        width = NSWidth(view.frame);
    }
    if (width <= 0.0) {
        width = NSWidth(view.superview.bounds);
    }
    return width;
}

static CGFloat NMAvailableTextWidthForLayer(CALayer *layer) {
    CGFloat width = CGRectGetWidth(layer.bounds);
    if (width <= 0.0 && layer.presentationLayer) {
        width = CGRectGetWidth(layer.presentationLayer.bounds);
    }
    return width;
}

static BOOL NMIsLikelyBackgroundImageView(NSImageView *imageView) {
    NSImage *image = imageView.image;
    NSView *superview = imageView.superview;
    if (!image) {
        return NO;
    }

    // 网易云桌面歌词背景资源通常是极小图片拉伸成整块底图
    if (image.size.width <= 8.0 && image.size.height <= 8.0) {
        return YES;
    }

    if (!superview) {
        return NO;
    }

    CGFloat viewArea = NSWidth(imageView.frame) * NSHeight(imageView.frame);
    CGFloat parentArea = NSWidth(superview.bounds) * NSHeight(superview.bounds);
    return parentArea > 0.0 && viewArea >= parentArea * 0.6;
}

static void NMClearViewSurface(NSView *view) {
    if (view.wantsLayer || view.layer) {
        view.wantsLayer = YES;
        view.layer.backgroundColor = NSColor.clearColor.CGColor;
        view.layer.borderWidth = 0.0;
        view.layer.borderColor = NSColor.clearColor.CGColor;
        view.layer.shadowOpacity = 0.0;
    }

    if ([view isKindOfClass:[NSBox class]]) {
        NSBox *box = (NSBox *)view;
        box.fillColor = NSColor.clearColor;
        box.borderColor = NSColor.clearColor;
        box.borderWidth = 0.0;
    }
}

static BOOL NMIsPatchBackgroundHostView(NSView *view) {
    return [NSStringFromClass(object_getClass(view)) isEqualToString:@"NMLyricBackgroundHostView"];
}

static void NMClearOriginalBackgrounds(NSView *view, BOOL shouldHideOriginalSurface, BOOL rootView) {
    if (NMIsPatchBackgroundHostView(view)) {
        return;
    }

    // 自定义背景接管显示后，原始承载面需要清掉，否则会盖住纯色和渐变
    if (shouldHideOriginalSurface || rootView) {
        NMClearViewSurface(view);
    }

    if (shouldHideOriginalSurface && [view isKindOfClass:[NSVisualEffectView class]]) {
        view.hidden = YES;
    }

    if ([view isKindOfClass:[NSImageView class]] && NMIsLikelyBackgroundImageView((NSImageView *)view)) {
        view.hidden = shouldHideOriginalSurface;
    }

    for (NSView *subview in view.subviews) {
        NMClearOriginalBackgrounds(subview, shouldHideOriginalSurface, NO);
    }
}

static BOOL NMTextLooksLikeCloseLabel(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return NO;
    }

    NSString *lowerText = text.lowercaseString;
    return [lowerText containsString:@"close"] || [text containsString:@"关闭"] || [text containsString:@"×"];
}

static BOOL NMViewLooksLikeCloseControl(NSView *view) {
    if ([view isKindOfClass:[NSButton class]] || [view isKindOfClass:[NSImageView class]]) {
        return YES;
    }

    // 网易云有版本会用自定义 view 或 layer 画左上角的关闭叉
    NSString *className = NSStringFromClass(object_getClass(view));
    NSString *accessibilityLabel = [view accessibilityLabel];
    NSString *accessibilityTitle = [view accessibilityTitle];
    return NMTextLooksLikeCloseLabel(className) || NMTextLooksLikeCloseLabel(accessibilityLabel) || NMTextLooksLikeCloseLabel(accessibilityTitle);
}

static BOOL NMIsLikelyOriginalCloseButton(NSView *view, NSView *rootView) {
    if (!view || !rootView || view == rootView || !NMViewLooksLikeCloseControl(view)) {
        return NO;
    }

    NSRect frameInRoot = [view convertRect:view.bounds toView:rootView];
    CGFloat rootHeight = NSHeight(rootView.bounds);
    BOOL nearLeft = NSMinX(frameInRoot) <= 44.0;
    BOOL nearVerticalEdge = NSMinY(frameInRoot) <= 44.0 || NSMaxY(frameInRoot) >= rootHeight - 44.0;
    BOOL smallControl = NSWidth(frameInRoot) <= 44.0 && NSHeight(frameInRoot) <= 44.0;
    return nearLeft && nearVerticalEdge && smallControl;
}

static BOOL NMLayerLooksLikeCloseMark(CALayer *layer) {
    NSString *className = NSStringFromClass(object_getClass(layer));
    NSString *layerName = layer.name;
    return layer.contents || NMTextLooksLikeCloseLabel(className) || NMTextLooksLikeCloseLabel(layerName);
}

static BOOL NMIsLikelyOriginalCloseLayer(CALayer *layer, CALayer *rootLayer) {
    if (!layer || !rootLayer || layer == rootLayer || !NMLayerLooksLikeCloseMark(layer)) {
        return NO;
    }

    CGRect frameInRoot = [layer convertRect:layer.bounds toLayer:rootLayer];
    CGFloat rootHeight = CGRectGetHeight(rootLayer.bounds);
    BOOL nearLeft = CGRectGetMinX(frameInRoot) <= 44.0;
    BOOL nearVerticalEdge = CGRectGetMinY(frameInRoot) <= 44.0 || CGRectGetMaxY(frameInRoot) >= rootHeight - 44.0;
    BOOL smallControl = CGRectGetWidth(frameInRoot) <= 44.0 && CGRectGetHeight(frameInRoot) <= 44.0;
    return nearLeft && nearVerticalEdge && smallControl;
}

static void NMToggleOriginalCloseLayers(CALayer *layer, CALayer *rootLayer, BOOL shouldHide) {
    if (!layer || !rootLayer) {
        return;
    }

    // 有些版本的关闭叉不是 NSView，而是画在左上角的小 layer 上
    if (NMIsLikelyOriginalCloseLayer(layer, rootLayer)) {
        layer.hidden = shouldHide;
        return;
    }

    for (CALayer *sublayer in layer.sublayers) {
        NMToggleOriginalCloseLayers(sublayer, rootLayer, shouldHide);
    }
}

static void NMToggleOriginalCloseButtons(NSView *view, NSView *rootView, BOOL shouldHide) {
    if (!view || !rootView) {
        return;
    }

    // 透明背景没有底板承托时，隐藏网易云歌词窗口左上角自带关闭按钮
    if (NMIsLikelyOriginalCloseButton(view, rootView)) {
        view.hidden = shouldHide;
        return;
    }

    for (NSView *subview in view.subviews) {
        NMToggleOriginalCloseButtons(subview, rootView, shouldHide);
    }

    if (view == rootView) {
        NMToggleOriginalCloseLayers(rootView.layer, rootView.layer, shouldHide);
    }
}

static void NMPrepareTransparentWindow(NSWindow *window, BOOL transparentMode) {
    window.opaque = NO;
    window.backgroundColor = NSColor.clearColor;
    if (transparentMode) {
        window.hasShadow = NO;
    }
    window.contentView.wantsLayer = YES;
    window.contentView.layer.backgroundColor = NSColor.clearColor.CGColor;
    window.contentView.layer.borderWidth = 0.0;
    window.contentView.layer.shadowOpacity = 0.0;
}

static BOOL NMViewTreeContainsClass(NSView *view, Class targetClass) {
    if (!view || !targetClass) {
        return NO;
    }
    if ([view isKindOfClass:targetClass]) {
        return YES;
    }
    for (NSView *subview in view.subviews) {
        if (NMViewTreeContainsClass(subview, targetClass)) {
            return YES;
        }
    }
    return NO;
}

static NSString *NMTextLayerPlainString(CATextLayer *textLayer);
static void NMRemoveLyricOutlineAttributes(NSMutableAttributedString *mutableString, NSRange range);

static void NMApplyTextStyleToLayerTree(CALayer *layer, NSColor *color, NSString *fontName, CGFloat fontSize) {
    if (!layer) {
        return;
    }

    if ([layer isKindOfClass:[CATextLayer class]]) {
        CATextLayer *textLayer = (CATextLayer *)layer;
        NSString *plainString = NMTextLayerPlainString(textLayer);
        CGFloat fittedFontSize = NMFittedFontSizeForText(plainString, fontName, fontSize, NMAvailableTextWidthForLayer(textLayer));
        if (color) {
            textLayer.foregroundColor = color.CGColor;
        }
        textLayer.fontSize = fittedFontSize;
        textLayer.font = (__bridge CFTypeRef)(fontName ?: @"PingFangSC-Semibold");
        NMEnsureTextLayerCanFitFont(textLayer, NMFontFromConfig(fontName, fittedFontSize));
        textLayer.shadowOpacity = 0.0;
    }

    for (CALayer *sublayer in layer.sublayers) {
        NMApplyTextStyleToLayerTree(sublayer, color, fontName, fontSize);
    }
}

static NSAttributedString *NMAttributedStringByApplyingGradientTextStyle(NSAttributedString *source, NSFont *font, NSString *startHex, NSString *endHex, NSString *direction) {
    if (!source || source.length == 0) {
        return source;
    }

    NSMutableAttributedString *mutableString = [source mutableCopy];
    NSRange fullRange = NSMakeRange(0, mutableString.length);
    NSString *plainString = mutableString.string;
    NSColor *startColor = NMColorFromHex(startHex ?: @"#FFFFFF", 1.0);
    NSColor *endColor = NMColorFromHex(endHex ?: @"#9FD8FF", 1.0);
    NSFont *targetFont = font ?: NMFontFromConfig(nil, 23.0);
    NSDictionary *textAttributes = @{ NSFontAttributeName: targetFont };
    __block CGFloat textOffset = 0.0;
    CGFloat textWidth = MAX([plainString sizeWithAttributes:textAttributes].width, 1.0);

    NMRemoveLyricOutlineAttributes(mutableString, fullRange);
    [mutableString addAttribute:NSFontAttributeName value:targetFont range:fullRange];
    [plainString enumerateSubstringsInRange:NSMakeRange(0, plainString.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        CGFloat characterWidth = [substring sizeWithAttributes:textAttributes].width;
        CGFloat progress = NMGradientProgressForTextOffset(textOffset + characterWidth / 2.0, textWidth, direction ?: @"leftToRight");
        NSColor *color = NMColorByMixing(startColor, endColor, progress);
        [mutableString addAttribute:NSForegroundColorAttributeName value:color range:substringRange];
        textOffset += characterWidth;
    }];

    return mutableString;
}

static void NMApplyGradientTextStyleToLayerTree(CALayer *layer, NSString *fontName, CGFloat fontSize, NSString *startHex, NSString *endHex, NSString *direction) {
    if (!layer) {
        return;
    }

    if ([layer isKindOfClass:[CATextLayer class]]) {
        CATextLayer *textLayer = (CATextLayer *)layer;
        NSString *plainString = NMTextLayerPlainString(textLayer);
        CGFloat fittedFontSize = NMFittedFontSizeForText(plainString, fontName, fontSize, NMAvailableTextWidthForLayer(textLayer));
        NSFont *font = NMFontFromConfig(fontName, fittedFontSize);
        NSAttributedString *source = [textLayer.string isKindOfClass:[NSAttributedString class]]
            ? (NSAttributedString *)textLayer.string
            : [[NSAttributedString alloc] initWithString:plainString ?: @""];
        textLayer.string = NMAttributedStringByApplyingGradientTextStyle(source, font, startHex, endHex, direction);
        textLayer.fontSize = fittedFontSize;
        textLayer.font = (__bridge CFTypeRef)(fontName ?: @"PingFangSC-Semibold");
        NMEnsureTextLayerCanFitFont(textLayer, font);
        textLayer.shadowOpacity = 0.0;
    }

    for (CALayer *sublayer in layer.sublayers) {
        NMApplyGradientTextStyleToLayerTree(sublayer, fontName, fontSize, startHex, endHex, direction);
    }
}

static NSString *NMTextLayerPlainString(CATextLayer *textLayer) {
    if ([textLayer.string isKindOfClass:[NSAttributedString class]]) {
        return ((NSAttributedString *)textLayer.string).string;
    }
    if ([textLayer.string isKindOfClass:[NSString class]]) {
        return (NSString *)textLayer.string;
    }

    return nil;
}

static void NMCollectTextLayers(CALayer *layer, NSMutableArray<CATextLayer *> *textLayers) {
    if (!layer) {
        return;
    }

    if ([layer isKindOfClass:[CATextLayer class]]) {
        [textLayers addObject:(CATextLayer *)layer];
    }

    for (CALayer *sublayer in layer.sublayers) {
        NMCollectTextLayers(sublayer, textLayers);
    }
}

static void NMRemoveLyricOutlineAttributes(NSMutableAttributedString *mutableString, NSRange range) {
    // 网易云原有歌词描边会作为文字属性保留下来，这里只清掉描边不影响字体和颜色
    [mutableString removeAttribute:NSStrokeColorAttributeName range:range];
    [mutableString removeAttribute:NSStrokeWidthAttributeName range:range];
}

static NSAttributedString *NMAttributedStringByApplyingTextStyle(NSAttributedString *source, NSColor *color, NSFont *font) {
    if (!source || source.length == 0) {
        return source;
    }

    NSMutableAttributedString *mutableString = [source mutableCopy];
    NSRange range = NSMakeRange(0, mutableString.length);
    NMRemoveLyricOutlineAttributes(mutableString, range);
    if (color) {
        [mutableString addAttribute:NSForegroundColorAttributeName value:color range:range];
    }
    if (font) {
        [mutableString addAttribute:NSFontAttributeName value:font range:range];
    }
    return mutableString;
}

#endif
