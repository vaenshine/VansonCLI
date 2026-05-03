/**
 * VCConsoleTab -- Console Tab
 * Terminal-style: output log + input bar + history + tab completion
 */

#import "VCConsoleTab.h"
#import "../../../VansonCLI.h"
#import "../../Console/VCCommandRouter.h"
#import "../Panel/VCPanel.h"

@interface VCConsoleTab () <UITextFieldDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UITextView *outputView;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *lastCopyButton;
@property (nonatomic, strong) UIButton *allCopyButton;
@property (nonatomic, strong) UIStackView *headerButtonStack;
@property (nonatomic, strong) UIScrollView *completionBar;
@property (nonatomic, strong) NSLayoutConstraint *completionHeightConstraint;
@property (nonatomic, strong) NSMutableAttributedString *outputBuffer;
@property (nonatomic, assign) NSInteger historyIndex;
@property (nonatomic, copy) NSString *draftCommand;
@property (nonatomic, copy) NSString *lastOutputLine;
@property (nonatomic, assign) BOOL defaultHelpLoaded;
@property (nonatomic, strong) NSLayoutConstraint *inputBarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputBarBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *inputFieldHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sendButtonWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerCardHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *headerButtonStackWidthConstraint;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *headerButtonWidthConstraints;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *headerButtonHeightConstraints;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@end

@implementation VCConsoleTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    _outputBuffer = [[NSMutableAttributedString alloc] init];
    _historyIndex = -1;
    _draftCommand = @"";
    _lastOutputLine = @"";
    _currentLayoutMode = VCPanelLayoutModePortrait;

    [self _setupOutputView];
    [self _setupCompletionBar];
    [self _setupInputBar];
    [self _applyCurrentLayoutMode];
    VCInstallKeyboardDismissAccessory(self.view);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _showDefaultHelpOutput];
    });

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)_setupOutputView {
    self.headerCard = [[UIView alloc] init];
    VCApplyPanelSurface(self.headerCard, 12.0);
    self.headerCard.userInteractionEnabled = YES;
    self.headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerCard];

    _outputView = [[UITextView alloc] init];
    VCApplyInputSurface(_outputView, 12.0);
    _outputView.textColor = kVCTextPrimary;
    _outputView.font = kVCFontMono;
    _outputView.editable = NO;
    _outputView.selectable = YES;
    _outputView.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12);
    _outputView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_outputView];

    UILabel *header = [[UILabel alloc] init];
    header.text = VCTextLiteral(@"LIVE CONSOLE");
    header.textColor = kVCTextSecondary;
    header.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    header.lineBreakMode = NSLineBreakByTruncatingTail;
    [header setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    UIButton *(^headerButton)(NSString *, NSString *, SEL) = ^UIButton *(NSString *title, NSString *symbolName, SEL action) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:title forState:UIControlStateNormal];
        VCSetButtonSymbol(button, symbolName);
        VCApplyCompactSecondaryButtonStyle(button);
        button.contentEdgeInsets = UIEdgeInsetsMake(3, 7, 3, 7);
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
            [button setPreferredSymbolConfiguration:config forImageInState:UIControlStateNormal];
        }
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.72;
        button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        return button;
    };

    self.clearButton = headerButton(@"Clear", @"trash", @selector(_clearOutputTapped));
    self.lastCopyButton = headerButton(@"Last", @"doc.on.doc", @selector(_copyLastOutputTapped));
    self.allCopyButton = headerButton(@"All", @"doc.on.clipboard", @selector(_copyAllOutputTapped));
    self.clearButton.tag = 1;
    self.lastCopyButton.tag = 2;
    self.allCopyButton.tag = 3;
    self.headerButtonStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.clearButton, self.lastCopyButton, self.allCopyButton]];
    self.headerButtonStack.axis = UILayoutConstraintAxisHorizontal;
    self.headerButtonStack.alignment = UIStackViewAlignmentCenter;
    self.headerButtonStack.spacing = 6.0;
    self.headerButtonStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerButtonStack setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.headerCard addSubview:header];
    [self.headerCard addSubview:self.headerButtonStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [header.topAnchor constraintEqualToAnchor:self.headerCard.topAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:12],
        [self.headerButtonStack.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],
        [self.headerButtonStack.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [header.trailingAnchor constraintLessThanOrEqualToAnchor:self.headerButtonStack.leadingAnchor constant:-10],
        [self.headerCard.bottomAnchor constraintGreaterThanOrEqualToAnchor:header.bottomAnchor constant:9],
        [self.headerCard.bottomAnchor constraintGreaterThanOrEqualToAnchor:self.headerButtonStack.bottomAnchor constant:6],
        [self.headerButtonStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.headerCard.topAnchor constant:6],
        [_outputView.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:8],
        [_outputView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [_outputView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
    ]];
    self.headerCardHeightConstraint = [self.headerCard.heightAnchor constraintEqualToConstant:50.0];
    self.headerCardHeightConstraint.active = YES;
    self.headerButtonStackWidthConstraint = [self.headerButtonStack.widthAnchor constraintLessThanOrEqualToAnchor:self.headerCard.widthAnchor multiplier:0.68];
    self.headerButtonStackWidthConstraint.active = YES;
    NSMutableArray<NSLayoutConstraint *> *widths = [NSMutableArray array];
    NSMutableArray<NSLayoutConstraint *> *heights = [NSMutableArray array];
    for (UIButton *button in self.headerButtonStack.arrangedSubviews) {
        NSLayoutConstraint *width = [button.widthAnchor constraintEqualToConstant:76.0];
        NSLayoutConstraint *height = [button.heightAnchor constraintEqualToConstant:30.0];
        width.active = YES;
        height.active = YES;
        [widths addObject:width];
        [heights addObject:height];
    }
    self.headerButtonWidthConstraints = widths;
    self.headerButtonHeightConstraints = heights;
    [self _showDefaultHelpOutput];
}

- (void)_setupCompletionBar {
    _completionBar = [[UIScrollView alloc] init];
    _completionBar.backgroundColor = [UIColor clearColor];
    _completionBar.showsHorizontalScrollIndicator = NO;
    _completionBar.alpha = 0.0;
    _completionBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_completionBar];

    _completionHeightConstraint = [_completionBar.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [_completionBar.topAnchor constraintEqualToAnchor:_outputView.bottomAnchor],
        [_completionBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [_completionBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        _completionHeightConstraint,
    ]];
}

- (void)_setupInputBar {
    UIView *bar = [[UIView alloc] init];
    VCApplyPanelSurface(bar, 12.0);
    bar.backgroundColor = [kVCBgSecondary colorWithAlphaComponent:0.96];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];
    UITapGestureRecognizer *focusInputTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_focusInputField)];
    focusInputTap.cancelsTouchesInView = NO;
    [bar addGestureRecognizer:focusInputTap];

    UILabel *promptLabel = [[UILabel alloc] init];
    promptLabel.text = @"$";
    promptLabel.textColor = kVCAccent;
    promptLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightBold];
    promptLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:promptLabel];

    _inputField = [[UITextField alloc] init];
    VCApplyInputSurface(_inputField, 10.0);
    _inputField.backgroundColor = [UIColor clearColor];
    _inputField.layer.borderWidth = 0.0;
    _inputField.textColor = kVCGreen;
    _inputField.font = kVCFontMono;
    VCApplyReadablePlaceholder(_inputField, @"Enter command");
    _inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    _inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _inputField.returnKeyType = UIReturnKeySend;
    _inputField.textAlignment = NSTextAlignmentLeft;
    _inputField.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _inputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _inputField.delegate = self;
    _inputField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 2, 10)];
    _inputField.leftViewMode = UITextFieldViewModeAlways;
    [_inputField setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [_inputField setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _inputField.translatesAutoresizingMaskIntoConstraints = NO;
    [_inputField addTarget:self action:@selector(_inputChanged) forControlEvents:UIControlEventEditingChanged];
    [bar addSubview:_inputField];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_sendButton setTitle:nil forState:UIControlStateNormal];
    VCSetButtonSymbol(_sendButton, @"paperplane.fill");
    VCApplyCompactSecondaryButtonStyle(_sendButton);
    _sendButton.backgroundColor = [kVCAccent colorWithAlphaComponent:0.18];
    _sendButton.layer.borderColor = [kVCAccent colorWithAlphaComponent:0.55].CGColor;
    _sendButton.layer.cornerRadius = 15.0;
    _sendButton.tintColor = kVCAccent;
    _sendButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [_sendButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold];
        [_sendButton setPreferredSymbolConfiguration:config forImageInState:UIControlStateNormal];
    }
    _sendButton.contentEdgeInsets = UIEdgeInsetsZero;
    [_sendButton addTarget:self action:@selector(_executeCommand) forControlEvents:UIControlEventTouchUpInside];
    _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:_sendButton];

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:_completionBar.bottomAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [promptLabel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [promptLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [promptLabel.widthAnchor constraintEqualToConstant:12.0],
        [_inputField.leadingAnchor constraintEqualToAnchor:promptLabel.trailingAnchor constant:2],
        [_inputField.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [_sendButton.leadingAnchor constraintEqualToAnchor:_inputField.trailingAnchor constant:8],
        [_sendButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-10],
        [_sendButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [_sendButton.heightAnchor constraintEqualToConstant:32],
    ]];
    self.inputBarBottomConstraint = [bar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10];
    self.inputBarBottomConstraint.active = YES;
    self.inputBarHeightConstraint = [bar.heightAnchor constraintEqualToConstant:58];
    self.inputBarHeightConstraint.active = YES;
    self.inputFieldHeightConstraint = [_inputField.heightAnchor constraintEqualToConstant:40];
    self.inputFieldHeightConstraint.active = YES;
    self.sendButtonWidthConstraint = [_sendButton.widthAnchor constraintEqualToConstant:64];
    self.sendButtonWidthConstraint.active = YES;
}

- (void)_applyCurrentLayoutMode {
    BOOL landscape = (self.currentLayoutMode == VCPanelLayoutModeLandscape);
    self.headerCardHeightConstraint.constant = landscape ? 44.0 : 50.0;
    self.inputBarHeightConstraint.constant = landscape ? 48.0 : 58.0;
    self.inputFieldHeightConstraint.constant = landscape ? 34.0 : 40.0;
    self.sendButtonWidthConstraint.constant = landscape ? 58.0 : 64.0;
    self.sendButton.layer.cornerRadius = 15.0;
    [self.sendButton setTitle:nil forState:UIControlStateNormal];
    self.sendButton.contentEdgeInsets = UIEdgeInsetsZero;
    self.sendButton.imageEdgeInsets = UIEdgeInsetsZero;
    self.sendButton.titleEdgeInsets = UIEdgeInsetsZero;
    self.outputView.textContainerInset = landscape ? UIEdgeInsetsMake(10, 10, 10, 10) : UIEdgeInsetsMake(14, 12, 14, 12);
    self.headerButtonStack.spacing = landscape ? 5.0 : 6.0;
    self.headerButtonStackWidthConstraint.active = YES;
    for (UIButton *button in self.headerButtonStack.arrangedSubviews) {
        NSString *title = @"";
        if (button.tag == 1) title = @"Clear";
        if (button.tag == 2) title = @"Last";
        if (button.tag == 3) title = @"All";
        [button setTitle:title forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 10.5) weight:UIFontWeightSemibold];
        button.contentEdgeInsets = landscape ? UIEdgeInsetsMake(3, 6, 3, 6) : UIEdgeInsetsMake(4, 7, 4, 7);
        button.imageEdgeInsets = UIEdgeInsetsMake(0, -1.0, 0, 1.0);
        button.titleEdgeInsets = UIEdgeInsetsMake(0, 4.0, 0, -4.0);
        VCPrepareButtonTitle(button, NSLineBreakByTruncatingTail, 0.72);
    }
    NSArray<NSNumber *> *widths = landscape ? @[@64.0, @58.0, @50.0] : @[@70.0, @62.0, @56.0];
    [self.headerButtonWidthConstraints enumerateObjectsUsingBlock:^(NSLayoutConstraint *constraint, NSUInteger idx, BOOL *stop) {
        if (idx < widths.count) constraint.constant = widths[idx].doubleValue;
    }];
    for (NSLayoutConstraint *constraint in self.headerButtonHeightConstraints) {
        constraint.constant = landscape ? 28.0 : 30.0;
    }
}

- (void)_focusInputField {
    [self.inputField becomeFirstResponder];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    [self _applyCurrentLayoutMode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self.view bringSubviewToFront:self.headerCard];
    [self _showDefaultHelpOutput];
}

#pragma mark - Command Execution

- (void)_executeCommand {
    NSString *cmd = _inputField.text;
    if (!cmd.length) return;
    [self _runCommand:cmd];
}

- (void)_runCommand:(NSString *)cmd {
    [self _appendOutput:[NSString stringWithFormat:@"$ %@\n", cmd] color:kVCAccent];
    _inputField.text = @"";
    _draftCommand = @"";
    [self _setCompletionVisible:NO];
    _historyIndex = -1;

    [[VCCommandRouter shared] addToHistory:cmd];
    [[VCCommandRouter shared] executeCommand:cmd output:^(NSString *text) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([text isEqualToString:@"\x1B[CLEAR]"]) {
                [self _clearOutputTapped];
                return;
            }
            UIColor *outputColor = [self _colorForConsoleOutput:text];
            NSString *prefix = @"";
            if ([text hasPrefix:@"Unknown command:"]) prefix = @"ERR: ";
            else if ([text hasPrefix:@"Usage:"] || [text hasPrefix:@"Export error:"]) prefix = @"WARN: ";
            [self _appendOutput:[NSString stringWithFormat:@"%@%@\n", prefix, text] color:outputColor];
        });
    }];
}

- (void)_showDefaultHelpOutput {
    if (self.defaultHelpLoaded && self.outputView.attributedText.length > 0) {
        self.outputView.contentOffset = CGPointZero;
        return;
    }
    self.defaultHelpLoaded = YES;
    NSMutableAttributedString *helpBuffer = [[NSMutableAttributedString alloc] init];
    void (^appendHelpLine)(NSString *, UIColor *) = ^(NSString *text, UIColor *color) {
        NSDictionary *attrs = @{NSFontAttributeName: kVCFontMono, NSForegroundColorAttributeName: color};
        [helpBuffer appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attrs]];
    };
    appendHelpLine(@"$ help\n", kVCAccent);

    NSArray<NSDictionary *> *commands = [[VCCommandRouter shared] allCommandsHelp];
    if (commands.count == 0) {
        appendHelpLine(@"  help           -- Show available commands or help for a specific command\n", kVCTextPrimary);
    } else {
        for (NSDictionary *entry in commands) {
            NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
            NSString *help = [entry[@"help"] isKindOfClass:[NSString class]] ? entry[@"help"] : @"";
            appendHelpLine([NSString stringWithFormat:@"  %-14s -- %@\n", name.UTF8String, help], kVCTextPrimary);
        }
    }

    self.outputBuffer = helpBuffer;
    self.outputView.font = kVCFontMono;
    self.outputView.textColor = kVCTextPrimary;
    self.outputView.attributedText = helpBuffer;
    self.lastOutputLine = helpBuffer.string.length > 0 ? [helpBuffer.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
    [self.outputView layoutIfNeeded];
    [self.outputView setContentOffset:CGPointZero animated:NO];
    [self.outputView setNeedsDisplay];
}

- (void)_appendOutput:(NSString *)text color:(UIColor *)color {
    NSDictionary *attrs = @{NSFontAttributeName: kVCFontMono, NSForegroundColorAttributeName: color};
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    [_outputBuffer appendAttributedString:as];
    _outputView.font = kVCFontMono;
    _outputView.textColor = kVCTextPrimary;
    _outputView.attributedText = _outputBuffer;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) {
        _lastOutputLine = trimmed;
    }
    // Auto-scroll to bottom
    if (_outputView.contentSize.height > _outputView.bounds.size.height) {
        [_outputView scrollRangeToVisible:NSMakeRange(_outputBuffer.length - 1, 1)];
    }
}

#pragma mark - Tab Completion

- (void)_inputChanged {
    NSString *partial = _inputField.text;
    if (partial.length == 0) { [self _setCompletionVisible:NO]; return; }

    NSArray *completions = [[VCCommandRouter shared] completionsForPartial:partial];
    if (completions.count == 0) { [self _setCompletionVisible:NO]; return; }

    // Build completion chips
    for (UIView *v in _completionBar.subviews) [v removeFromSuperview];
    CGFloat x = 4;
    for (NSString *c in completions) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        [chip setTitle:c forState:UIControlStateNormal];
        VCApplyCompactSecondaryButtonStyle(chip);
        chip.titleLabel.font = kVCFontMonoSm;
        VCPrepareButtonTitle(chip, NSLineBreakByTruncatingMiddle, 0.78);
        chip.contentEdgeInsets = UIEdgeInsetsMake(3, 9, 3, 9);
        [chip sizeToFit];
        chip.frame = CGRectMake(chip.frame.origin.x, chip.frame.origin.y, MIN(chip.frame.size.width, 180.0), chip.frame.size.height);
        chip.frame = CGRectMake(x, 6, chip.frame.size.width, 22);
        [chip addTarget:self action:@selector(_completionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_completionBar addSubview:chip];
        x += chip.frame.size.width + 6;
    }
    _completionBar.contentSize = CGSizeMake(x, 34);
    [self _setCompletionVisible:YES];
}

- (void)_completionTapped:(UIButton *)btn {
    _inputField.text = btn.currentTitle;
    [self _setCompletionVisible:NO];
}

#pragma mark - History Navigation

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self _executeCommand];
    return NO;
}

- (void)_showPreviousHistory {
    NSArray<NSString *> *history = [[VCCommandRouter shared] commandHistory];
    if (history.count == 0) return;
    if (_historyIndex == -1) {
        _draftCommand = _inputField.text ?: @"";
        _historyIndex = (NSInteger)history.count - 1;
    } else {
        _historyIndex = MAX(0, _historyIndex - 1);
    }
    _inputField.text = history[_historyIndex];
    [self _setCompletionVisible:NO];
}

- (void)_showNextHistory {
    NSArray<NSString *> *history = [[VCCommandRouter shared] commandHistory];
    if (history.count == 0 || _historyIndex == -1) return;
    if (_historyIndex >= (NSInteger)history.count - 1) {
        _historyIndex = -1;
        _inputField.text = _draftCommand ?: @"";
    } else {
        _historyIndex += 1;
        _inputField.text = history[_historyIndex];
    }
    [self _setCompletionVisible:NO];
}

- (void)_setCompletionVisible:(BOOL)visible {
    self.completionHeightConstraint.constant = visible ? 34.0 : 0.0;
    [UIView animateWithDuration:0.18 animations:^{
        self.completionBar.alpha = visible ? 1.0 : 0.0;
        [self.view layoutIfNeeded];
    }];
}

- (UIColor *)_colorForConsoleOutput:(NSString *)text {
    if ([text hasPrefix:@"Unknown command:"]) return kVCRed;
    if ([text hasPrefix:@"Usage:"] || [text hasPrefix:@"Export error:"]) return kVCYellow;
    if ([text containsString:@"removed."] || [text containsString:@"saved"] || [text containsString:@"Alias '"] || [text containsString:@"Shortcut '"]) return kVCGreen;
    return kVCTextPrimary;
}

- (void)_clearOutputTapped {
    self.outputBuffer = [[NSMutableAttributedString alloc] init];
    self.outputView.attributedText = self.outputBuffer;
    self.lastOutputLine = @"";
}

- (void)_copyLastOutputTapped {
    if (_lastOutputLine.length == 0) return;
    [UIPasteboard generalPasteboard].string = _lastOutputLine;
}

- (void)_copyAllOutputTapped {
    if (_outputBuffer.length == 0) return;
    [UIPasteboard generalPasteboard].string = _outputBuffer.string ?: @"";
}

#pragma mark - Keyboard

- (void)_keyboardWillShow:(NSNotification *)note {
    CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect kbInView = [self.view convertRect:kbFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(kbInView));
    self.inputBarBottomConstraint.constant = -10.0 - overlap;
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap + self.inputBarHeightConstraint.constant + 12.0, 0);
    _outputView.contentInset = insets;
    _outputView.scrollIndicatorInsets = insets;
    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] ?: 0.25;
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)_keyboardWillHide:(NSNotification *)note {
    self.inputBarBottomConstraint.constant = -10.0;
    _outputView.contentInset = UIEdgeInsetsZero;
    _outputView.scrollIndicatorInsets = UIEdgeInsetsZero;
    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] ?: 0.25;
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

@end
