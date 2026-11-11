#import "WQMMarkdownRenderer.h"
#import "WQMTheme.h"

@implementation WQMMarkdownRenderer

+ (UIFont *)boldFontForTextStyle:(UIFontTextStyle)textStyle
{
    UIFontDescriptor *descriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:textStyle];
    descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    return [UIFont fontWithDescriptor:descriptor size:0];
}

+ (NSMutableAttributedString *)inlineMarkdown:(NSString *)text
                                  attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
{
    NSMutableAttributedString *result =
        [[NSMutableAttributedString alloc] initWithString:text attributes:attributes];

    NSRegularExpression *linkPattern = [NSRegularExpression
        regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\((https?://[^)\\s]+)\\)"
                             options:0 error:nil];
    NSArray<NSTextCheckingResult *> *linkMatches =
        [linkPattern matchesInString:result.string options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in linkMatches.reverseObjectEnumerator) {
        NSString *label = [result.string substringWithRange:[match rangeAtIndex:1]];
        NSString *address = [result.string substringWithRange:[match rangeAtIndex:2]];
        NSURL *url = [NSURL URLWithString:address];
        if (!label.length || !url) continue;
        NSMutableDictionary *linkAttributes = [attributes mutableCopy];
        linkAttributes[NSForegroundColorAttributeName] = WQMTheme.textPrimaryColor;
        linkAttributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        linkAttributes[NSLinkAttributeName] = url;
        NSAttributedString *replacement =
            [[NSAttributedString alloc] initWithString:label attributes:linkAttributes];
        [result replaceCharactersInRange:match.range withAttributedString:replacement];
    }

    NSRegularExpression *boldPattern = [NSRegularExpression
        regularExpressionWithPattern:@"\\*\\*([^*\\n]+)\\*\\*" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *boldMatches =
        [boldPattern matchesInString:result.string options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in boldMatches.reverseObjectEnumerator) {
        NSRange contentRange = [match rangeAtIndex:1];
        NSString *content = [result.string substringWithRange:contentRange];
        NSMutableDictionary *boldAttributes = [attributes mutableCopy];
        UIFont *baseFont = attributes[NSFontAttributeName]
            ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        UIFontDescriptor *descriptor = [baseFont.fontDescriptor
            fontDescriptorWithSymbolicTraits:baseFont.fontDescriptor.symbolicTraits |
                                             UIFontDescriptorTraitBold];
        boldAttributes[NSFontAttributeName] = [UIFont fontWithDescriptor:descriptor size:baseFont.pointSize];
        [result replaceCharactersInRange:match.range
                      withAttributedString:[[NSAttributedString alloc] initWithString:content
                                                                           attributes:boldAttributes]];
    }

    NSRegularExpression *codePattern = [NSRegularExpression
        regularExpressionWithPattern:@"`([^`\\n]+)`" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *codeMatches =
        [codePattern matchesInString:result.string options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in codeMatches.reverseObjectEnumerator) {
        NSRange contentRange = [match rangeAtIndex:1];
        NSString *content = [result.string substringWithRange:contentRange];
        NSMutableDictionary *codeAttributes = [attributes mutableCopy];
        codeAttributes[NSFontAttributeName] = [UIFont monospacedSystemFontOfSize:14
                                                                          weight:UIFontWeightRegular];
        [result replaceCharactersInRange:match.range
                      withAttributedString:[[NSAttributedString alloc] initWithString:content
                                                                           attributes:codeAttributes]];
    }

    NSRegularExpression *urlPattern = [NSRegularExpression
        regularExpressionWithPattern:@"https?://[^\\s<>()]+" options:NSRegularExpressionCaseInsensitive
                               error:nil];
    NSArray<NSTextCheckingResult *> *urlMatches =
        [urlPattern matchesInString:result.string options:0 range:NSMakeRange(0, result.length)];
    for (NSTextCheckingResult *match in urlMatches) {
        if ([result attribute:NSLinkAttributeName atIndex:match.range.location
                effectiveRange:nil]) {
            continue;
        }
        NSURL *url = [NSURL URLWithString:[result.string substringWithRange:match.range]];
        if (!url) continue;
        [result addAttributes:@{
            NSLinkAttributeName: url,
            NSForegroundColorAttributeName: WQMTheme.textPrimaryColor,
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        } range:match.range];
    }
    return result;
}

+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown
{
    NSString *normalized = [[markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                            stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
    NSMutableArray<NSDictionary<NSString *, id> *> *blocks = [NSMutableArray new];
    NSMutableString *buffer = [NSMutableString new];
    __block BOOL inCodeFence = NO;

    void (^flush)(void) = ^{
        NSString *paragraph = [buffer stringByTrimmingCharactersInSet:
                               NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (paragraph.length) blocks[[blocks count]] = @{@"kind": @"body", @"text": paragraph};
        [buffer setString:@""];
    };

    NSRegularExpression *headingPattern = [NSRegularExpression
        regularExpressionWithPattern:@"^(#{1,6})\\s+(.+)$" options:0 error:nil];
    NSRegularExpression *bulletPattern = [NSRegularExpression
        regularExpressionWithPattern:@"^\\s*[-*+]\\s+(.+)$" options:0 error:nil];
    NSRegularExpression *orderedPattern = [NSRegularExpression
        regularExpressionWithPattern:@"^\\s*(\\d+)\\.\\s+(.+)$" options:0 error:nil];

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:
                          NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"```"]) {
            flush();
            inCodeFence = !inCodeFence;
            continue;
        }
        if (inCodeFence) {
            [buffer appendString:rawLine];
            [buffer appendString:@"\n"];
            continue;
        }
        if (!line.length) {
            flush();
            continue;
        }

        NSTextCheckingResult *heading =
            [headingPattern firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        NSTextCheckingResult *bullet =
            [bulletPattern firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        NSTextCheckingResult *ordered =
            [orderedPattern firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (heading) {
            flush();
            NSInteger level = (NSInteger)[heading rangeAtIndex:1].length;
            NSString *content = [line substringWithRange:[heading rangeAtIndex:2]];
            blocks[[blocks count]] = @{@"kind": @"heading", @"level": @(level), @"text": content};
            continue;
        }
        if (bullet || ordered) {
            flush();
            NSRange contentRange = bullet ? [bullet rangeAtIndex:1] : [ordered rangeAtIndex:2];
            NSString *content = [line substringWithRange:contentRange];
            NSString *marker = bullet ? @"•" : [NSString stringWithFormat:@"%@.",
                [line substringWithRange:[ordered rangeAtIndex:1]]];
            blocks[[blocks count]] = @{@"kind": @"list", @"marker": marker, @"text": content};
            continue;
        }
        if ([line hasPrefix:@"> "]) line = [line substringFromIndex:2];
        if (buffer.length) [buffer appendString:@" "];
        [buffer appendString:line];
    }
    flush();

    NSMutableAttributedString *result = [NSMutableAttributedString new];
    for (NSDictionary *block in blocks) {
        NSString *kind = block[@"kind"];
        NSString *text = block[@"text"];
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.lineSpacing = 4;
        style.paragraphSpacing = 10;
        NSMutableDictionary *attributes = [@{
            NSForegroundColorAttributeName: WQMTheme.textPrimaryColor,
            NSParagraphStyleAttributeName: style,
        } mutableCopy];

        if ([kind isEqualToString:@"heading"]) {
            NSInteger level = [block[@"level"] integerValue];
            if (level == 1) attributes[NSFontAttributeName] = [WQMTheme titleFont];
            else if (level == 2) attributes[NSFontAttributeName] =
                [self boldFontForTextStyle:UIFontTextStyleTitle3];
            else attributes[NSFontAttributeName] =
                [self boldFontForTextStyle:UIFontTextStyleHeadline];
            style.paragraphSpacing = level == 1 ? 14 : 10;
        } else if ([kind isEqualToString:@"list"]) {
            style.headIndent = 22;
            style.firstLineHeadIndent = 0;
            attributes[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            text = [NSString stringWithFormat:@"%@  %@", block[@"marker"], text];
        } else {
            attributes[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        }

        [result appendAttributedString:[self inlineMarkdown:text attributes:attributes]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    }
    return result;
}

@end
