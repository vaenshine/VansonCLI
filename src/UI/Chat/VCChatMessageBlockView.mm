/**
 * VCChatMessageBlockView -- Resolves a single chat block into a UIKit view
 */

#import "VCChatMessageBlockView.h"
#import "VCChatMarkdownView.h"
#import "VCChatReferenceCardView.h"
#import "VCChatStatusBannerView.h"
#import "VCMermaidPreviewView.h"
#import "VCToolCallBlock.h"
#import "../../../VansonCLI.h"
#import "../../AI/ToolCall/VCToolCallParser.h"

static NSString *VCChatBlockSafeString(id value) {
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

@interface VCChatMessageBlockView ()
@property (nonatomic, strong) UIView *contentViewContainer;
@property (nonatomic, copy) NSString *currentBlockType;
@property (nonatomic, copy) NSString *currentToolID;
@end

@implementation VCChatMessageBlockView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)configureWithBlock:(NSDictionary *)block
                      role:(NSString *)role
            toolCallLookup:(NSDictionary<NSString *, VCToolCall *> *)toolCallLookup {
    NSString *type = VCChatBlockSafeString(block[@"type"]);
    UIView *existingView = self.contentViewContainer;
    UIView *nextView = nil;

    if ([type isEqualToString:@"reference"]) {
        VCChatReferenceCardView *card = [existingView isKindOfClass:[VCChatReferenceCardView class]] ? (VCChatReferenceCardView *)existingView : [[VCChatReferenceCardView alloc] initWithFrame:CGRectZero];
        NSDictionary *payload = [block[@"payload"] isKindOfClass:[NSDictionary class]] ? block[@"payload"] : @{};
        [card configureWithKind:VCChatBlockSafeString(block[@"kind"])
                          title:VCChatBlockSafeString(block[@"title"])
                        payload:payload
                           role:role];
        nextView = card;
        self.currentToolID = nil;
    } else if ([type isEqualToString:@"status"]) {
        VCChatStatusBannerView *banner = [existingView isKindOfClass:[VCChatStatusBannerView class]] ? (VCChatStatusBannerView *)existingView : [[VCChatStatusBannerView alloc] initWithFrame:CGRectZero];
        [banner configureWithTitle:VCChatBlockSafeString(block[@"title"])
                           content:VCChatBlockSafeString(block[@"content"])
                              tone:VCChatBlockSafeString(block[@"tone"])];
        nextView = banner;
        self.currentToolID = nil;
    } else if ([type isEqualToString:@"diagram"]) {
        VCMermaidPreviewView *preview = [existingView isKindOfClass:[VCMermaidPreviewView class]] ? (VCMermaidPreviewView *)existingView : [[VCMermaidPreviewView alloc] initWithFrame:CGRectZero];
        [preview configureWithTitle:VCChatBlockSafeString(block[@"title"])
                            summary:VCChatBlockSafeString(block[@"summary"])
                            content:VCChatBlockSafeString(block[@"content"])
                        diagramType:VCChatBlockSafeString(block[@"diagramType"])];
        nextView = preview;
        self.currentToolID = nil;
    } else if ([type isEqualToString:@"tool_call"]) {
        NSString *toolID = VCChatBlockSafeString(block[@"toolID"]);
        if ([existingView isKindOfClass:[VCToolCallBlock class]] &&
            (self.currentToolID == toolID || [self.currentToolID isEqualToString:toolID])) {
            nextView = existingView;
        } else {
            VCToolCall *toolCall = toolCallLookup[toolID];
            if (toolCall) {
                nextView = [[VCToolCallBlock alloc] initWithToolCall:toolCall];
            }
        }
        self.currentToolID = toolID;
    } else {
        VCChatMarkdownView *markdownView = [existingView isKindOfClass:[VCChatMarkdownView class]] ? (VCChatMarkdownView *)existingView : [[VCChatMarkdownView alloc] initWithFrame:CGRectZero];
        [markdownView configureWithMarkdown:VCChatBlockSafeString(block[@"content"]) role:role];
        nextView = markdownView;
        self.currentToolID = nil;
    }

    if (!nextView) {
        UILabel *fallback = [existingView isKindOfClass:[UILabel class]] ? (UILabel *)existingView : [[UILabel alloc] init];
        fallback.text = VCTextLiteral(@"This block could not be rendered.");
        fallback.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        fallback.textColor = kVCTextMuted;
        fallback.numberOfLines = 0;
        nextView = fallback;
        self.currentToolID = nil;
    }

    if (existingView != nextView) {
        [self.contentViewContainer removeFromSuperview];
        self.contentViewContainer = nil;
        nextView.translatesAutoresizingMaskIntoConstraints = NO;
        self.contentViewContainer = nextView;
        [self addSubview:nextView];
        [NSLayoutConstraint activateConstraints:@[
            [nextView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [nextView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [nextView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [nextView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    self.currentBlockType = type;
}

@end
