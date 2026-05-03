/**
 * VCCodeTab -- Code Editor Tab
 * Left: file tree, Right: editor with syntax highlighting
 * Bottom: snippet picker + template selector
 */

#import "VCCodeTab.h"
#import "../Panel/VCPanel.h"
#import "../../../VansonCLI.h"
#import "../../Core/VCConfig.h"
#import "../../Runtime/VCRuntimeEngine.h"
#import "../../Runtime/VCRuntimeModels.h"
#import "../../Patches/VCPatchManager.h"
#import "../../Patches/VCPatchItem.h"
#import "../../Patches/VCHookItem.h"
#import <spawn.h>
#import <sys/wait.h>

static NSString *const kFileCellID = @"FileCell";
NSNotificationName const VCCodeTabRequestOpenFileNotification = @"VCCodeTabRequestOpenFileNotification";
NSString *const VCCodeTabOpenFilePathKey = @"path";
NSString *const VCCodeTabOpenFileLineKey = @"line";
extern char **environ;

@interface VCCodeTab () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, UISearchBarDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UIView *contentDividerView;
@property (nonatomic, strong) UITableView *fileTree;
@property (nonatomic, strong) UITextView *editorView;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UIButton *createFileBtn;
@property (nonatomic, strong) UIButton *saveBtn;
@property (nonatomic, strong) UIButton *snippetBtn;
@property (nonatomic, strong) UIButton *exportBtn;
@property (nonatomic, strong) UIStackView *toolbarStack;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *files; // {name, path, isDir}
@property (nonatomic, copy) NSArray<VCClassInfo *> *runtimeClasses;
@property (nonatomic, copy) NSArray<VCClassInfo *> *visibleRuntimeClasses;
@property (nonatomic, strong) VCClassInfo *selectedRuntimeClass;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, copy) NSString *currentFilePath;
@property (nonatomic, copy) NSString *projectRoot;
@property (nonatomic, assign) BOOL hasUnsavedChanges;
@property (nonatomic, strong) UIView *fileCreateOverlay;
@property (nonatomic, strong) UIView *fileCreateCard;
@property (nonatomic, strong) UITextField *fileCreateField;
@property (nonatomic, strong) UISegmentedControl *templateControl;
@property (nonatomic, strong) UIView *snippetOverlay;
@property (nonatomic, strong) UIView *snippetCard;
@property (nonatomic, strong) UILabel *snippetStatusLabel;
@property (nonatomic, strong) NSLayoutConstraint *fileTreeWidthConstraint;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) CGRect availableLayoutBounds;
@end

@implementation VCCodeTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;

    _projectRoot = [[[VCConfig shared] sandboxPath] stringByAppendingPathComponent:@"CodeEditor"];
    [[NSFileManager defaultManager] createDirectoryAtPath:_projectRoot withIntermediateDirectories:YES attributes:nil error:nil];
    _files = [NSMutableArray new];
    _runtimeClasses = @[];
    _visibleRuntimeClasses = @[];
    _searchText = @"";
    _availableLayoutBounds = CGRectZero;

    [self _setupHeaderCard];
    [self _setupToolbar];
    [self _setupFileTree];
    [self _setupEditor];
    [self _setupNewFileOverlay];
    [self _setupSnippetOverlay];
    VCInstallKeyboardDismissAccessory(self.view);
    [self _refreshFileTree];
    [self _reloadRuntimeClassesIfNeeded];
    [self _refreshRuntimeModeDisplay];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_patchManagerDidUpdate:) name:VCPatchManagerDidUpdateNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self _flushPendingChangesWithReason:@"leaving Code Lab"];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL landscape = self.currentLayoutMode == VCPanelLayoutModeLandscape;
    CGFloat boundsWidth = CGRectIsEmpty(self.availableLayoutBounds) ? CGRectGetWidth(self.view.bounds) : CGRectGetWidth(self.availableLayoutBounds);
    CGFloat ratio = landscape ? 0.30 : 0.30;
    CGFloat minWidth = landscape ? 188.0 : 164.0;
    CGFloat maxWidth = landscape ? 320.0 : 236.0;
    CGFloat targetWidth = MAX(minWidth, MIN(maxWidth, floor(boundsWidth * ratio)));
    self.fileTreeWidthConstraint.constant = targetWidth;
    self.toolbarStack.spacing = landscape ? 8.0 : 12.0;
    self.contentDividerView.hidden = !landscape;
    self.contentDividerView.alpha = landscape ? 1.0 : 0.0;
    self.statusLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusLabel.numberOfLines = 1;
    UITextField *searchField = [self.searchBar valueForKey:@"searchField"];
    if (searchField) {
        searchField.font = [UIFont systemFontOfSize:(landscape ? 12.0 : 13.0)];
    }
    UIEdgeInsets buttonInsets = landscape ? UIEdgeInsetsMake(6, 8, 6, 8) : UIEdgeInsetsMake(7, 10, 7, 10);
    for (UIButton *button in @[self.createFileBtn, self.saveBtn, self.snippetBtn, self.exportBtn]) {
        button.contentEdgeInsets = buttonInsets;
        button.titleLabel.font = [UIFont systemFontOfSize:(landscape ? 11.0 : 12.0) weight:UIFontWeightSemibold];
    }
}

- (void)_setupHeaderCard {
    _headerCard = [[UIView alloc] init];
    VCApplyPanelSurface(_headerCard, 12.0);
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = VCTextLiteral(@"CODE LAB");
    titleLabel.textColor = kVCTextSecondary;
    titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:titleLabel];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.textColor = kVCTextMuted;
    _statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    _statusLabel.textAlignment = NSTextAlignmentRight;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusLabel.numberOfLines = 1;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_statusLabel];

    _modeControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"Classes"), VCTextLiteral(@"Methods"), VCTextLiteral(@"Hooks"), VCTextLiteral(@"Patches")]];
    _modeControl.selectedSegmentIndex = 0;
    _modeControl.selectedSegmentTintColor = kVCAccent;
    [_modeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCTextPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold]
    } forState:UIControlStateNormal];
    [_modeControl setTitleTextAttributes:@{
        NSForegroundColorAttributeName: kVCBgPrimary,
        NSFontAttributeName: [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold]
    } forState:UIControlStateSelected];
    [_modeControl addTarget:self action:@selector(_modeChanged) forControlEvents:UIControlEventValueChanged];
    _modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_modeControl];

    _searchBar = [[UISearchBar alloc] init];
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    VCApplyReadableSearchPlaceholder(_searchBar, VCTextLiteral(@"Class, selector, symbol, IMP"));
    UITextField *searchField = [_searchBar valueForKey:@"searchField"];
    if (searchField) {
        VCApplyInputSurface(searchField, 11.0);
        searchField.textColor = kVCTextPrimary;
        searchField.font = [UIFont systemFontOfSize:13];
        searchField.layer.masksToBounds = YES;
    }
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_searchBar];

    [NSLayoutConstraint activateConstraints:@[
        [_headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [titleLabel.topAnchor constraintEqualToAnchor:_headerCard.topAnchor constant:10],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_statusLabel.leadingAnchor constant:-8],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [_statusLabel.widthAnchor constraintLessThanOrEqualToAnchor:_headerCard.widthAnchor multiplier:0.58],
        [_searchBar.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
        [_searchBar.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:6],
        [_searchBar.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-6],
        [_searchBar.heightAnchor constraintEqualToConstant:36],
        [_modeControl.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:8],
        [_modeControl.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_modeControl.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_modeControl.heightAnchor constraintEqualToConstant:28],
    ]];
}

- (void)_setupToolbar {
    _toolbar = [[UIView alloc] init];
    _toolbar.backgroundColor = [UIColor clearColor];
    _toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_toolbar];

    _createFileBtn = [self _toolbarButton:VCTextLiteral(@"New") symbol:@"plus"];
    [_createFileBtn addTarget:self action:@selector(_newFile) forControlEvents:UIControlEventTouchUpInside];
    _saveBtn = [self _toolbarButton:VCTextLiteral(@"Save") symbol:@"tray.and.arrow.down"];
    [_saveBtn addTarget:self action:@selector(_saveCurrentFile) forControlEvents:UIControlEventTouchUpInside];
    _snippetBtn = [self _toolbarButton:VCTextLiteral(@"Snips") symbol:@"curlybraces"];
    [_snippetBtn addTarget:self action:@selector(_showSnippets) forControlEvents:UIControlEventTouchUpInside];
    _exportBtn = [self _toolbarButton:VCTextLiteral(@"Export") symbol:@"square.and.arrow.up"];
    [_exportBtn addTarget:self action:@selector(_exportProject) forControlEvents:UIControlEventTouchUpInside];

    _toolbarStack = [[UIStackView alloc] initWithArrangedSubviews:@[_createFileBtn, _saveBtn, _snippetBtn, _exportBtn]];
    _toolbarStack.axis = UILayoutConstraintAxisHorizontal;
    _toolbarStack.spacing = 12;
    _toolbarStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_toolbar addSubview:_toolbarStack];

    [NSLayoutConstraint activateConstraints:@[
        [_toolbar.topAnchor constraintEqualToAnchor:self.modeControl.bottomAnchor constant:8],
        [_toolbar.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:12],
        [_toolbar.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-12],
        [_toolbar.heightAnchor constraintEqualToConstant:34],
        [_toolbar.bottomAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:-10],
        [_toolbarStack.centerYAnchor constraintEqualToAnchor:_toolbar.centerYAnchor],
        [_toolbarStack.leadingAnchor constraintEqualToAnchor:_toolbar.leadingAnchor],
        [_toolbarStack.trailingAnchor constraintLessThanOrEqualToAnchor:_toolbar.trailingAnchor],
    ]];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    self.availableLayoutBounds = bounds;
    [self.view setNeedsLayout];
}

#pragma mark - Runtime Mode

- (void)_modeChanged {
    [self _reloadRuntimeClassesIfNeeded];
    if (self.modeControl.selectedSegmentIndex == 1 && !self.selectedRuntimeClass && self.runtimeClasses.count > 0) {
        VCClassInfo *first = self.visibleRuntimeClasses.firstObject ?: self.runtimeClasses.firstObject;
        self.selectedRuntimeClass = [[VCRuntimeEngine shared] classInfoForName:first.className];
    }
    [self _applySearchFilter];
    [self.fileTree reloadData];
    [self _refreshRuntimeModeDisplay];
}

- (void)_patchManagerDidUpdate:(NSNotification *)notification {
    if (self.modeControl.selectedSegmentIndex >= 2) {
        [self.fileTree reloadData];
        [self _refreshRuntimeModeDisplay];
    }
}

- (void)_reloadRuntimeClassesIfNeeded {
    if (self.runtimeClasses.count > 0) return;
    self.runtimeClasses = [[VCRuntimeEngine shared] allClassesFilteredBy:nil module:nil offset:0 limit:80] ?: @[];
    [self _applySearchFilter];
}

- (BOOL)_string:(NSString *)value containsSearch:(NSString *)search {
    if (search.length == 0) return YES;
    return [[value ?: @"" lowercaseString] containsString:search];
}

- (void)_applySearchFilter {
    NSString *needle = [[self.searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (needle.length == 0) {
        self.visibleRuntimeClasses = self.runtimeClasses ?: @[];
        return;
    }
    NSMutableArray<VCClassInfo *> *classes = [NSMutableArray new];
    for (VCClassInfo *info in self.runtimeClasses ?: @[]) {
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@",
                              info.className ?: @"",
                              info.moduleName ?: @"",
                              info.superClassName ?: @""];
        if ([self _string:haystack containsSearch:needle]) {
            [classes addObject:info];
        }
    }
    self.visibleRuntimeClasses = classes;
}

- (NSArray<VCMethodInfo *> *)_visibleMethods {
    NSArray<VCMethodInfo *> *instanceMethods = self.selectedRuntimeClass.instanceMethods ?: @[];
    NSArray<VCMethodInfo *> *classMethods = self.selectedRuntimeClass.classMethods ?: @[];
    NSMutableArray<VCMethodInfo *> *methods = [NSMutableArray arrayWithCapacity:instanceMethods.count + classMethods.count];
    [methods addObjectsFromArray:instanceMethods];
    [methods addObjectsFromArray:classMethods];
    NSString *needle = [[self.searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (needle.length > 0) {
        NSIndexSet *matches = [methods indexesOfObjectsPassingTest:^BOOL(VCMethodInfo *method, NSUInteger idx, BOOL *stop) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ 0x%llx 0x%llx",
                                  method.selector ?: @"",
                                  method.typeEncoding ?: @"",
                                  (unsigned long long)method.impAddress,
                                  (unsigned long long)method.rva];
            return [self _string:haystack containsSearch:needle];
        }];
        return [methods objectsAtIndexes:matches];
    }
    return methods;
}

- (NSArray<VCHookItem *> *)_visibleHooks {
    NSArray<VCHookItem *> *hooks = [[VCPatchManager shared] allHooks] ?: @[];
    NSString *needle = [[self.searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (needle.length == 0) return hooks;
    NSIndexSet *matches = [hooks indexesOfObjectsPassingTest:^BOOL(VCHookItem *hook, NSUInteger idx, BOOL *stop) {
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@",
                              hook.className ?: @"",
                              hook.selector ?: @"",
                              hook.hookType ?: @"",
                              hook.remark ?: @""];
        return [self _string:haystack containsSearch:needle];
    }];
    return [hooks objectsAtIndexes:matches];
}

- (NSArray<VCPatchItem *> *)_visiblePatches {
    NSArray<VCPatchItem *> *patches = [[VCPatchManager shared] allPatches] ?: @[];
    NSString *needle = [[self.searchText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (needle.length == 0) return patches;
    NSIndexSet *matches = [patches indexesOfObjectsPassingTest:^BOOL(VCPatchItem *patch, NSUInteger idx, BOOL *stop) {
        NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@",
                              patch.className ?: @"",
                              patch.selector ?: @"",
                              patch.patchType ?: @"",
                              patch.customCode ?: @"",
                              patch.remark ?: @""];
        return [self _string:haystack containsSearch:needle];
    }];
    return [patches objectsAtIndexes:matches];
}

- (NSString *)_detailTextForSelectedClass {
    VCClassInfo *info = self.selectedRuntimeClass ?: self.runtimeClasses.firstObject;
    if (!info) return @"Classes\nRuntime classes will appear here once the target app exposes Objective-C metadata.";
    return [NSString stringWithFormat:@"CLASS\n%@\n\nMODULE\n%@\n\nSUPER\n%@\n\nCOUNTS\nInstance methods: %@\nClass methods: %@\nIvars: %@\nProperties: %@\nProtocols: %@\n\nCHAIN\n%@",
            info.className ?: @"--",
            info.moduleName ?: @"--",
            info.superClassName ?: @"--",
            @((info.instanceMethods ?: @[]).count),
            @((info.classMethods ?: @[]).count),
            @((info.ivars ?: @[]).count),
            @((info.properties ?: @[]).count),
            @((info.protocols ?: @[]).count),
            [(info.inheritanceChain ?: @[]) componentsJoinedByString:@" -> "]];
}

- (NSString *)_detailTextForMethod:(VCMethodInfo *)method {
    if (!method) {
        return self.selectedRuntimeClass
            ? [NSString stringWithFormat:@"METHODS\nSelect a method in %@.", self.selectedRuntimeClass.className ?: @"class"]
            : @"METHODS\nSelect a class first.";
    }
    return [NSString stringWithFormat:@"METHOD\n%@\n\nSIGNATURE\n%@\n\nTYPE ENCODING\n%@\n\nADDRESSES\nIMP: 0x%llx\nRVA: 0x%llx\n\nACTIONS\nUse Patches to install hooks, swizzles, or return-value patches.",
            method.selector ?: @"--",
            method.decodedSignature ?: @"--",
            method.typeEncoding ?: @"--",
            (unsigned long long)method.impAddress,
            (unsigned long long)method.rva];
}

- (NSString *)_detailTextForHook:(VCHookItem *)hook {
    if (!hook) {
        NSUInteger count = [[VCPatchManager shared] allHooks].count;
        return [NSString stringWithFormat:@"HOOKS\n%@ hook draft(s).\nSelect one to inspect its target and state.", @(count)];
    }
    return [NSString stringWithFormat:@"HOOK\n%@ %@\n\nTYPE\n%@\n\nSTATE\n%@%@\nHit count: %@\n\nREMARK\n%@",
            hook.className ?: @"--",
            hook.selector ?: @"--",
            hook.hookType ?: @"--",
            hook.enabled ? @"Enabled" : @"Disabled",
            hook.isDisabledBySafeMode ? @" • Safe Mode" : @"",
            @(hook.hitCount),
            hook.remark ?: @"--"];
}

- (NSString *)_detailTextForPatch:(VCPatchItem *)patch {
    if (!patch) {
        NSUInteger count = [[VCPatchManager shared] allPatches].count;
        return [NSString stringWithFormat:@"PATCHES\n%@ patch draft(s).\nSelect one to inspect its target and state.", @(count)];
    }
    return [NSString stringWithFormat:@"PATCH\n%@ %@\n\nTYPE\n%@\n\nSTATE\n%@%@\n\nCUSTOM CODE\n%@\n\nREMARK\n%@",
            patch.className ?: @"--",
            patch.selector ?: @"--",
            patch.patchType ?: @"--",
            patch.enabled ? @"Enabled" : @"Disabled",
            patch.isDisabledBySafeMode ? @" • Safe Mode" : @"",
            patch.customCode.length ? patch.customCode : @"--",
            patch.remark ?: @"--"];
}

- (void)_refreshRuntimeModeDisplay {
    NSInteger mode = self.modeControl.selectedSegmentIndex;
    if (mode == 0) {
        self.editorView.text = [self _detailTextForSelectedClass];
        self.statusLabel.text = [NSString stringWithFormat:@"%@ / %@ classes", @(self.visibleRuntimeClasses.count), @(self.runtimeClasses.count)];
        self.statusLabel.textColor = kVCTextMuted;
    } else if (mode == 1) {
        self.editorView.text = [self _detailTextForMethod:nil];
        self.statusLabel.text = self.selectedRuntimeClass.className ?: @"Methods";
        self.statusLabel.textColor = kVCTextMuted;
    } else if (mode == 2) {
        self.editorView.text = [self _detailTextForHook:nil];
        self.statusLabel.text = [NSString stringWithFormat:@"%@ hooks", @([self _visibleHooks].count)];
        self.statusLabel.textColor = kVCTextMuted;
    } else {
        self.editorView.text = [self _detailTextForPatch:nil];
        self.statusLabel.text = [NSString stringWithFormat:@"%@ patches", @([self _visiblePatches].count)];
        self.statusLabel.textColor = kVCTextMuted;
    }
}

- (void)_setupNewFileOverlay {
    _fileCreateOverlay = [[UIView alloc] init];
    _fileCreateOverlay.alpha = 0.0;
    _fileCreateOverlay.hidden = YES;
    _fileCreateOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    _fileCreateOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_fileCreateOverlay];

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideNewFileOverlay) forControlEvents:UIControlEventTouchUpInside];
    [_fileCreateOverlay addSubview:backdrop];

    _fileCreateCard = [[UIView alloc] init];
    _fileCreateCard.backgroundColor = [kVCBgSurface colorWithAlphaComponent:0.98];
    _fileCreateCard.layer.cornerRadius = 18.0;
    _fileCreateCard.layer.borderWidth = 1.0;
    _fileCreateCard.layer.borderColor = kVCBorder.CGColor;
    _fileCreateCard.translatesAutoresizingMaskIntoConstraints = NO;
    [_fileCreateOverlay addSubview:_fileCreateCard];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = VCTextLiteral(@"New File");
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_fileCreateCard addSubview:titleLabel];

    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = VCTextLiteral(@"Pick a starter template so new files open with useful scaffolding.");
    hintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    hintLabel.textColor = kVCTextSecondary;
    hintLabel.numberOfLines = 2;
    hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_fileCreateCard addSubview:hintLabel];

    _fileCreateField = [[UITextField alloc] init];
    VCApplyReadablePlaceholder(_fileCreateField, @"filename.mm");
    _fileCreateField.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _fileCreateField.textColor = kVCTextPrimary;
    _fileCreateField.backgroundColor = kVCBgInput;
    _fileCreateField.layer.cornerRadius = 12.0;
    _fileCreateField.layer.borderWidth = 1.0;
    _fileCreateField.layer.borderColor = kVCBorder.CGColor;
    _fileCreateField.autocorrectionType = UITextAutocorrectionTypeNo;
    _fileCreateField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _fileCreateField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    _fileCreateField.leftViewMode = UITextFieldViewModeAlways;
    _fileCreateField.translatesAutoresizingMaskIntoConstraints = NO;
    [_fileCreateCard addSubview:_fileCreateField];

    _templateControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"Empty"), VCTextLiteral(@"Hook"), VCTextLiteral(@"Class")]];
    _templateControl.selectedSegmentIndex = 0;
    _templateControl.selectedSegmentTintColor = kVCAccent;
    [_templateControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary} forState:UIControlStateNormal];
    [_templateControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    _templateControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_fileCreateCard addSubview:_templateControl];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:VCTextLiteral(@"Cancel") forState:UIControlStateNormal];
    [cancelButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    cancelButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    cancelButton.titleLabel.minimumScaleFactor = 0.76;
    cancelButton.backgroundColor = kVCAccentDim;
    cancelButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    cancelButton.layer.cornerRadius = 13.0;
    cancelButton.layer.borderWidth = 1.0;
    cancelButton.layer.borderColor = kVCBorder.CGColor;
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self action:@selector(_hideNewFileOverlay) forControlEvents:UIControlEventTouchUpInside];
    [_fileCreateCard addSubview:cancelButton];

    UIButton *createButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [createButton setTitle:VCTextLiteral(@"Create File") forState:UIControlStateNormal];
    [createButton setTitleColor:kVCBgPrimary forState:UIControlStateNormal];
    createButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    createButton.titleLabel.minimumScaleFactor = 0.72;
    createButton.backgroundColor = kVCAccent;
    createButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    createButton.layer.cornerRadius = 13.0;
    createButton.translatesAutoresizingMaskIntoConstraints = NO;
    [createButton addTarget:self action:@selector(_confirmNewFile) forControlEvents:UIControlEventTouchUpInside];
    [_fileCreateCard addSubview:createButton];

    [NSLayoutConstraint activateConstraints:@[
        [_fileCreateOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_fileCreateOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_fileCreateOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_fileCreateOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:_fileCreateOverlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:_fileCreateOverlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:_fileCreateOverlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:_fileCreateOverlay.bottomAnchor],

        [_fileCreateCard.leadingAnchor constraintEqualToAnchor:_fileCreateOverlay.leadingAnchor constant:10],
        [_fileCreateCard.trailingAnchor constraintEqualToAnchor:_fileCreateOverlay.trailingAnchor constant:-10],
        [_fileCreateCard.bottomAnchor constraintEqualToAnchor:_fileCreateOverlay.bottomAnchor constant:-10],

        [titleLabel.topAnchor constraintEqualToAnchor:_fileCreateCard.topAnchor constant:14],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_fileCreateCard.leadingAnchor constant:14],
        [titleLabel.trailingAnchor constraintEqualToAnchor:_fileCreateCard.trailingAnchor constant:-14],

        [hintLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
        [hintLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [hintLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [_fileCreateField.topAnchor constraintEqualToAnchor:hintLabel.bottomAnchor constant:12],
        [_fileCreateField.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [_fileCreateField.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [_fileCreateField.heightAnchor constraintEqualToConstant:38],

        [_templateControl.topAnchor constraintEqualToAnchor:_fileCreateField.bottomAnchor constant:12],
        [_templateControl.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [_templateControl.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [_templateControl.heightAnchor constraintEqualToConstant:32],

        [cancelButton.topAnchor constraintEqualToAnchor:_templateControl.bottomAnchor constant:14],
        [cancelButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [cancelButton.heightAnchor constraintEqualToConstant:40],
        [cancelButton.bottomAnchor constraintEqualToAnchor:_fileCreateCard.bottomAnchor constant:-14],

        [createButton.leadingAnchor constraintEqualToAnchor:cancelButton.trailingAnchor constant:10],
        [createButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [createButton.widthAnchor constraintEqualToAnchor:cancelButton.widthAnchor],
        [createButton.centerYAnchor constraintEqualToAnchor:cancelButton.centerYAnchor],
        [createButton.heightAnchor constraintEqualToAnchor:cancelButton.heightAnchor],
    ]];
}

- (NSArray<NSDictionary *> *)_snippetCatalog {
    return @[
        @{@"title": VCTextLiteral(@"Hook Template"), @"subtitle": VCTextLiteral(@"Function-level Logos hook scaffold"), @"code": @"%hookf(void, ClassName, selectorName) {\n    %orig;\n}\n"},
        @{@"title": VCTextLiteral(@"Logos Hook"), @"subtitle": VCTextLiteral(@"Class hook with method override"), @"code": @"%hook ClassName\n- (void)method {\n    %orig;\n}\n%end\n"},
        @{@"title": VCTextLiteral(@"ObjC++ Class"), @"subtitle": VCTextLiteral(@"Minimal implementation shell"), @"code": @"@interface VCMyClass : NSObject\n@end\n\n@implementation VCMyClass\n@end\n"},
        @{@"title": VCTextLiteral(@"Singleton"), @"subtitle": VCTextLiteral(@"dispatch_once shared instance"), @"code": @"+ (instancetype)shared {\n    static id inst;\n    static dispatch_once_t onceToken;\n    dispatch_once(&onceToken, ^{ inst = [[self alloc] init]; });\n    return inst;\n}\n"},
    ];
}

- (void)_setupSnippetOverlay {
    _snippetOverlay = [[UIView alloc] init];
    _snippetOverlay.alpha = 0.0;
    _snippetOverlay.hidden = YES;
    _snippetOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    _snippetOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_snippetOverlay];

    UIControl *backdrop = [[UIControl alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [backdrop addTarget:self action:@selector(_hideSnippetOverlay) forControlEvents:UIControlEventTouchUpInside];
    [_snippetOverlay addSubview:backdrop];

    _snippetCard = [[UIView alloc] init];
    VCApplyPanelSurface(_snippetCard, 12.0);
    _snippetCard.translatesAutoresizingMaskIntoConstraints = NO;
    [_snippetOverlay addSubview:_snippetCard];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = VCTextLiteral(@"Snippet Library");
    titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    titleLabel.textColor = kVCTextPrimary;
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_snippetCard addSubview:titleLabel];

    _snippetStatusLabel = [[UILabel alloc] init];
    _snippetStatusLabel.text = VCTextLiteral(@"Insert reusable code blocks without leaving the editor.");
    _snippetStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    _snippetStatusLabel.textColor = kVCTextSecondary;
    _snippetStatusLabel.numberOfLines = 2;
    _snippetStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_snippetCard addSubview:_snippetStatusLabel];

    UIView *lastView = _snippetStatusLabel;
    NSArray<NSDictionary *> *snippets = [self _snippetCatalog];
    for (NSUInteger idx = 0; idx < snippets.count; idx++) {
        NSDictionary *snippet = snippets[idx];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = idx;
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
        VCApplyButtonChrome(button,
                            kVCTextPrimary,
                            kVCAccent,
                            [kVCBgHover colorWithAlphaComponent:0.76],
                            kVCBorder,
                            10.0,
                            [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]);
        [button addTarget:self action:@selector(_snippetButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.translatesAutoresizingMaskIntoConstraints = NO;

        NSString *title = snippet[@"title"] ?: VCTextLiteral(@"Snippet");
        NSString *subtitle = snippet[@"subtitle"] ?: @"";
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", title, subtitle]
                                                                                 attributes:@{
                                                                                     NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold],
                                                                                     NSForegroundColorAttributeName: kVCTextPrimary
                                                                                 }];
        [text addAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium],
            NSForegroundColorAttributeName: kVCTextSecondary
        } range:NSMakeRange(title.length + 1, subtitle.length)];
        [button setAttributedTitle:text forState:UIControlStateNormal];
        button.titleLabel.numberOfLines = 2;
        [_snippetCard addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [button.topAnchor constraintEqualToAnchor:lastView.bottomAnchor constant:12],
            [button.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
            [button.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
            [button.heightAnchor constraintEqualToConstant:58],
        ]];
        lastView = button;
    }

    UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [dismissButton setTitle:VCTextLiteral(@"Done") forState:UIControlStateNormal];
    [dismissButton setTitleColor:kVCTextPrimary forState:UIControlStateNormal];
    dismissButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    dismissButton.titleLabel.minimumScaleFactor = 0.76;
    dismissButton.backgroundColor = kVCAccentDim;
    dismissButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    dismissButton.layer.cornerRadius = 13.0;
    dismissButton.layer.borderWidth = 1.0;
    dismissButton.layer.borderColor = kVCBorder.CGColor;
    dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
    [dismissButton addTarget:self action:@selector(_hideSnippetOverlay) forControlEvents:UIControlEventTouchUpInside];
    [_snippetCard addSubview:dismissButton];

    [NSLayoutConstraint activateConstraints:@[
        [_snippetOverlay.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_snippetOverlay.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_snippetOverlay.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_snippetOverlay.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [backdrop.topAnchor constraintEqualToAnchor:_snippetOverlay.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:_snippetOverlay.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:_snippetOverlay.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:_snippetOverlay.bottomAnchor],

        [_snippetCard.leadingAnchor constraintEqualToAnchor:_snippetOverlay.leadingAnchor constant:10],
        [_snippetCard.trailingAnchor constraintEqualToAnchor:_snippetOverlay.trailingAnchor constant:-10],
        [_snippetCard.bottomAnchor constraintEqualToAnchor:_snippetOverlay.bottomAnchor constant:-10],

        [titleLabel.topAnchor constraintEqualToAnchor:_snippetCard.topAnchor constant:14],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_snippetCard.leadingAnchor constant:14],
        [titleLabel.trailingAnchor constraintEqualToAnchor:_snippetCard.trailingAnchor constant:-14],

        [_snippetStatusLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4],
        [_snippetStatusLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [_snippetStatusLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [dismissButton.topAnchor constraintEqualToAnchor:lastView.bottomAnchor constant:14],
        [dismissButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [dismissButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [dismissButton.heightAnchor constraintEqualToConstant:40],
        [dismissButton.bottomAnchor constraintEqualToAnchor:_snippetCard.bottomAnchor constant:-14],
    ]];
}

- (void)_hideSnippetOverlay {
    [UIView animateWithDuration:0.18 animations:^{
        self.snippetOverlay.alpha = 0.0;
        self.snippetOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    } completion:^(BOOL finished) {
        self.snippetOverlay.hidden = YES;
    }];
}

- (UIButton *)_toolbarButton:(NSString *)title symbol:(NSString *)symbol {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(btn);
    VCPrepareButtonTitle(btn, NSLineBreakByTruncatingTail, 0.78);
    VCSetButtonSymbol(btn, symbol);
    btn.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    return btn;
}

- (void)_setupFileTree {
    _fileTree = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _fileTree.dataSource = self;
    _fileTree.delegate = self;
    VCApplyPanelSurface(_fileTree, 12.0);
    _fileTree.separatorStyle = UITableViewCellSeparatorStyleNone;
    _fileTree.rowHeight = 30;
    _fileTree.contentInset = UIEdgeInsetsMake(6, 0, 6, 0);
    [_fileTree registerClass:[UITableViewCell class] forCellReuseIdentifier:kFileCellID];
    _fileTree.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_fileTree];

    _contentDividerView = [[UIView alloc] init];
    _contentDividerView.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.34];
    _contentDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentDividerView.hidden = YES;
    _contentDividerView.alpha = 0.0;
    [self.view addSubview:_contentDividerView];

    [NSLayoutConstraint activateConstraints:@[
        [_fileTree.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8],
        [_fileTree.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [_fileTree.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
        [_contentDividerView.leadingAnchor constraintEqualToAnchor:_fileTree.trailingAnchor constant:3.5],
        [_contentDividerView.widthAnchor constraintEqualToConstant:1.0],
        [_contentDividerView.topAnchor constraintEqualToAnchor:_fileTree.topAnchor constant:4.0],
        [_contentDividerView.bottomAnchor constraintEqualToAnchor:_fileTree.bottomAnchor constant:-4.0],
    ]];
    self.fileTreeWidthConstraint = [_fileTree.widthAnchor constraintEqualToConstant:164];
    self.fileTreeWidthConstraint.active = YES;
}

- (void)_setupEditor {
    _editorView = [[UITextView alloc] init];
    _editorView.backgroundColor = kVCBgInput;
    _editorView.textColor = kVCTextPrimary;
    _editorView.font = kVCFontMono;
    _editorView.autocorrectionType = UITextAutocorrectionTypeNo;
    _editorView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    VCApplyInputSurface(_editorView, 12.0);
    _editorView.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12);
    _editorView.delegate = self;
    _editorView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_editorView];

    [NSLayoutConstraint activateConstraints:@[
        [_editorView.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:8],
        [_editorView.leadingAnchor constraintEqualToAnchor:_contentDividerView.trailingAnchor constant:3.5],
        [_editorView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [_editorView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
    ]];
}

#pragma mark - File Operations

- (void)_refreshFileTree {
    [_files removeAllObjects];
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_projectRoot error:nil];
    for (NSString *name in [contents sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *path = [_projectRoot stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
        [_files addObject:@{@"name": name, @"path": path, @"isDir": @(isDir)}];
    }
    [self _updateStatusLabel];
    [_fileTree reloadData];
}

- (void)_loadFile:(NSString *)path {
    _currentFilePath = path;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    _editorView.attributedText = [self _highlightedCode:content ?: @""];
    _hasUnsavedChanges = NO;
    [self _updateStatusLabel];
}

- (NSUInteger)_characterIndexForLine:(NSUInteger)line inText:(NSString *)text {
    NSString *source = text ?: @"";
    if (line <= 1 || source.length == 0) return 0;

    NSUInteger currentLine = 1;
    for (NSUInteger idx = 0; idx < source.length; idx++) {
        if ([source characterAtIndex:idx] == '\n') {
            currentLine += 1;
            if (currentLine == line) {
                return idx + 1;
            }
        }
    }
    return source.length;
}

- (void)_scrollEditorToLine:(NSUInteger)line {
    if (line == 0) return;
    NSString *text = self.editorView.text ?: @"";
    NSUInteger location = [self _characterIndexForLine:line inText:text];
    if (location > text.length) location = text.length;
    NSRange range = NSMakeRange(location, 0);
    self.editorView.selectedRange = range;
    [self.editorView scrollRangeToVisible:range];
}

- (void)openFileAtPath:(NSString *)path line:(NSUInteger)line {
    NSString *targetPath = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (targetPath.length == 0) return;

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath isDirectory:&isDirectory] || isDirectory) {
        [self _setStatusMessage:@"Linked file could not be opened." warning:YES];
        return;
    }

    [self _flushPendingChangesWithReason:@"opening a linked file"];
    [self _loadFile:targetPath];
    [self.fileTree reloadData];

    NSUInteger fileIndex = [self.files indexOfObjectPassingTest:^BOOL(NSDictionary *file, NSUInteger idx, BOOL *stop) {
        return [file[@"path"] isEqualToString:targetPath];
    }];
    if (fileIndex != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:fileIndex inSection:0];
        [self.fileTree selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
    } else {
        NSIndexPath *selectedPath = [self.fileTree indexPathForSelectedRow];
        if (selectedPath) {
            [self.fileTree deselectRowAtIndexPath:selectedPath animated:NO];
        }
    }

    if (line > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _scrollEditorToLine:line];
        });
    }
}

- (void)_saveCurrentFile {
    if (!_currentFilePath) return;
    [_editorView.text writeToFile:_currentFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    _hasUnsavedChanges = NO;
    [self _updateStatusLabel];
}

- (void)_updateStatusLabel {
    NSString *base = _currentFilePath.lastPathComponent ?: [NSString stringWithFormat:@"%lu files", (unsigned long)_files.count];
    NSString *state = _hasUnsavedChanges ? @"Edited" : (_currentFilePath ? @"Saved" : @"Workspace");
    _statusLabel.text = [NSString stringWithFormat:@"%@ • %@", base, state];
    _statusLabel.textColor = _hasUnsavedChanges ? kVCOrange : kVCTextMuted;
    _saveBtn.alpha = _currentFilePath ? 1.0 : 0.55;
}

- (void)_setStatusMessage:(NSString *)message warning:(BOOL)warning {
    if (message.length == 0) {
        [self _updateStatusLabel];
        return;
    }
    _statusLabel.text = message;
    _statusLabel.textColor = warning ? kVCOrange : kVCGreen;
}

- (void)_flushPendingChangesWithReason:(NSString *)reason {
    if (!_hasUnsavedChanges || !_currentFilePath.length) return;
    [self _saveCurrentFile];
    if (reason.length) {
        [self _setStatusMessage:[NSString stringWithFormat:@"Auto-saved before %@", reason] warning:NO];
    }
}

- (NSString *)_shellQuotedPath:(NSString *)path {
    NSString *escaped = [path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

- (int)_runShellCommand:(NSString *)command {
    pid_t pid = 0;
    const char *argv[] = {"/bin/sh", "-lc", command.UTF8String, NULL};
    int spawnError = posix_spawn(&pid, "/bin/sh", NULL, NULL, (char *const *)argv, environ);
    if (spawnError != 0) return spawnError;

    int status = 0;
    if (waitpid(pid, &status, 0) == -1) {
        return -1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return status;
}

- (NSString *)_templateContentForSelection {
    switch (_templateControl.selectedSegmentIndex) {
        case 1:
            return @"%hook ClassName\n- (void)method {\n    %orig;\n}\n%end\n";
        case 2:
            return @"@interface VCNewClass : NSObject\n@end\n\n@implementation VCNewClass\n@end\n";
        default:
            return @"";
    }
}

- (void)_hideNewFileOverlay {
    [self.view endEditing:YES];
    [UIView animateWithDuration:0.18 animations:^{
        self.fileCreateOverlay.alpha = 0.0;
        self.fileCreateOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.0];
    } completion:^(BOOL finished) {
        self.fileCreateOverlay.hidden = YES;
    }];
}

- (void)_confirmNewFile {
    NSString *name = [self.fileCreateField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) return;
    [self _flushPendingChangesWithReason:@"creating a new file"];
    NSString *path = [self->_projectRoot stringByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self _setStatusMessage:@"A file with that name already exists." warning:YES];
        return;
    }
    NSString *templateContent = [self _templateContentForSelection];
    [templateContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self _refreshFileTree];
    [self _loadFile:path];
    [self _hideNewFileOverlay];
    [self.fileTree reloadData];
}

#pragma mark - Syntax Highlighting (basic regex)

- (NSAttributedString *)_highlightedCode:(NSString *)code {
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:code
        attributes:@{NSFontAttributeName: kVCFontMono, NSForegroundColorAttributeName: kVCTextPrimary}];

    // Keywords
    NSArray *keywords = @[@"@interface", @"@implementation", @"@end", @"@property", @"@protocol",
                          @"@class", @"@import", @"#import", @"#include", @"#define", @"#pragma",
                          @"if", @"else", @"for", @"while", @"return", @"self", @"super",
                          @"nil", @"YES", @"NO", @"NULL", @"void", @"static", @"const",
                          @"typedef", @"enum", @"struct", @"class", @"namespace"];
    for (NSString *kw in keywords) {
        NSString *pattern = [NSString stringWithFormat:@"\\b%@\\b", [NSRegularExpression escapedPatternForString:kw]];
        if ([kw hasPrefix:@"@"] || [kw hasPrefix:@"#"]) pattern = [NSRegularExpression escapedPatternForString:kw];
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        [regex enumerateMatchesInString:code options:0 range:NSMakeRange(0, code.length)
            usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            [as addAttribute:NSForegroundColorAttributeName value:kVCAccent range:result.range];
        }];
    }

    // Strings
    NSRegularExpression *strRegex = [NSRegularExpression regularExpressionWithPattern:@"@?\"[^\"]*\"" options:0 error:nil];
    [strRegex enumerateMatchesInString:code options:0 range:NSMakeRange(0, code.length)
        usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        [as addAttribute:NSForegroundColorAttributeName value:kVCGreen range:result.range];
    }];

    // Comments
    NSRegularExpression *commentRegex = [NSRegularExpression regularExpressionWithPattern:@"//[^\n]*" options:0 error:nil];
    [commentRegex enumerateMatchesInString:code options:0 range:NSMakeRange(0, code.length)
        usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        [as addAttribute:NSForegroundColorAttributeName value:kVCTextMuted range:result.range];
    }];

    return as;
}

#pragma mark - Actions

- (void)_newFile {
    [self _flushPendingChangesWithReason:@"creating a new file"];
    self.fileCreateField.text = @"";
    self.templateControl.selectedSegmentIndex = 0;
    self.fileCreateOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.fileCreateOverlay];
    [UIView animateWithDuration:0.2 animations:^{
        self.fileCreateOverlay.alpha = 1.0;
        self.fileCreateOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.22];
    }];
}

- (void)_showSnippets {
    self.snippetOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.snippetOverlay];
    [UIView animateWithDuration:0.2 animations:^{
        self.snippetOverlay.alpha = 1.0;
        self.snippetOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.22];
    }];
}

- (void)_exportProject {
    [self _flushPendingChangesWithReason:@"export"];

    NSString *tempRoot = NSTemporaryDirectory();
    NSString *zipPath = [tempRoot stringByAppendingPathComponent:@"VCProject.zip"];
    NSString *tgzPath = [tempRoot stringByAppendingPathComponent:@"VCProject.tar.gz"];
    [[NSFileManager defaultManager] removeItemAtPath:zipPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:tgzPath error:nil];

    NSString *zipCommand = [NSString stringWithFormat:@"cd %@ && /usr/bin/zip -qry %@ .",
                            [self _shellQuotedPath:_projectRoot],
                            [self _shellQuotedPath:zipPath]];
    int zipStatus = [self _runShellCommand:zipCommand];
    NSString *exportPath = nil;
    if (zipStatus == 0 && [[NSFileManager defaultManager] fileExistsAtPath:zipPath]) {
        exportPath = zipPath;
    } else {
        NSString *tarCommand = [NSString stringWithFormat:@"cd %@ && /bin/tar -czf %@ .",
                                [self _shellQuotedPath:_projectRoot],
                                [self _shellQuotedPath:tgzPath]];
        int tarStatus = [self _runShellCommand:tarCommand];
        if (tarStatus == 0 && [[NSFileManager defaultManager] fileExistsAtPath:tgzPath]) {
            exportPath = tgzPath;
        }
    }

    if (!exportPath) {
        [self _setStatusMessage:@"Export failed: zip/tar tool unavailable" warning:YES];
        return;
    }

    NSURL *url = [NSURL fileURLWithPath:exportPath];
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    [self presentViewController:avc animated:YES completion:nil];
    [self _setStatusMessage:[NSString stringWithFormat:@"Prepared %@", exportPath.lastPathComponent] warning:NO];
}

- (void)_snippetButtonTapped:(UIButton *)sender {
    NSArray<NSDictionary *> *snippets = [self _snippetCatalog];
    if (sender.tag < 0 || sender.tag >= (NSInteger)snippets.count) return;
    if (!self.currentFilePath.length) {
        self.snippetStatusLabel.text = VCTextLiteral(@"Open or create a file before inserting snippets.");
        self.snippetStatusLabel.textColor = kVCOrange;
        return;
    }
    NSString *code = snippets[sender.tag][@"code"] ?: @"";
    NSMutableString *text = [self->_editorView.text mutableCopy] ?: [NSMutableString new];
    if (text.length > 0 && ![text hasSuffix:@"\n"]) {
        [text appendString:@"\n"];
    }
    [text appendString:code];
    self->_editorView.attributedText = [self _highlightedCode:text];
    self.hasUnsavedChanges = YES;
    [self _updateStatusLabel];
    self.snippetStatusLabel.text = [NSString stringWithFormat:@"Inserted %@.", snippets[sender.tag][@"title"] ?: @"snippet"];
    self.snippetStatusLabel.textColor = kVCGreen;
    [self _hideSnippetOverlay];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidEndEditing:(UITextView *)textView {
    [self _saveCurrentFile];
}

- (void)textViewDidChange:(UITextView *)textView {
    if (!self.currentFilePath) return;
    self.hasUnsavedChanges = YES;
    [self _updateStatusLabel];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText ?: @"";
    [self _applySearchFilter];
    if (self.modeControl.selectedSegmentIndex == 1 && !self.selectedRuntimeClass && self.visibleRuntimeClasses.count > 0) {
        self.selectedRuntimeClass = [[VCRuntimeEngine shared] classInfoForName:self.visibleRuntimeClasses.firstObject.className];
    }
    [self.fileTree reloadData];
    [self _refreshRuntimeModeDisplay];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (self.modeControl.selectedSegmentIndex) {
        case 0: return (NSInteger)self.visibleRuntimeClasses.count;
        case 1: return (NSInteger)[self _visibleMethods].count;
        case 2: return (NSInteger)[self _visibleHooks].count;
        case 3: return (NSInteger)[self _visiblePatches].count;
        default: return (NSInteger)_files.count;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFileCellID forIndexPath:indexPath];
    cell.backgroundColor = [UIColor clearColor];
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.textLabel.font = [UIFont systemFontOfSize:12];
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSInteger mode = self.modeControl.selectedSegmentIndex;
    BOOL highlighted = NO;
    if (mode == 0) {
        VCClassInfo *info = indexPath.row < self.visibleRuntimeClasses.count ? self.visibleRuntimeClasses[indexPath.row] : nil;
        cell.textLabel.text = [NSString stringWithFormat:@"C  %@\n%@     %@ methods",
                               info.className ?: @"--",
                               info.moduleName.length ? info.moduleName : @"runtime",
                               @((info.instanceMethods ?: @[]).count + (info.classMethods ?: @[]).count)];
        cell.textLabel.numberOfLines = 2;
        highlighted = [info.className isEqualToString:self.selectedRuntimeClass.className];
    } else if (mode == 1) {
        NSArray<VCMethodInfo *> *methods = [self _visibleMethods];
        VCMethodInfo *method = indexPath.row < methods.count ? methods[indexPath.row] : nil;
        cell.textLabel.text = [NSString stringWithFormat:@"m  %@\nIMP 0x%llx     RVA 0x%llx",
                               method.selector ?: @"--",
                               (unsigned long long)method.impAddress,
                               (unsigned long long)method.rva];
        cell.textLabel.numberOfLines = 2;
    } else if (mode == 2) {
        NSArray<VCHookItem *> *hooks = [self _visibleHooks];
        VCHookItem *hook = indexPath.row < hooks.count ? hooks[indexPath.row] : nil;
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %@\n%@     %@ hits",
                               hook.enabled ? @"ON" : @"OFF",
                               hook.className ?: @"--",
                               hook.selector ?: @"--",
                               @(hook.hitCount)];
        cell.textLabel.numberOfLines = 2;
        highlighted = hook.enabled;
    } else if (mode == 3) {
        NSArray<VCPatchItem *> *patches = [self _visiblePatches];
        VCPatchItem *patch = indexPath.row < patches.count ? patches[indexPath.row] : nil;
        cell.textLabel.text = [NSString stringWithFormat:@"%@  %@\n%@     %@",
                               patch.enabled ? @"ON" : @"OFF",
                               patch.className ?: @"--",
                               patch.selector ?: @"--",
                               patch.patchType ?: @"patch"];
        cell.textLabel.numberOfLines = 2;
        highlighted = patch.enabled;
    } else {
        NSDictionary *file = _files[indexPath.row];
        BOOL isDir = [file[@"isDir"] boolValue];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", isDir ? @">" : @" ", file[@"name"]];
        highlighted = [file[@"path"] isEqualToString:_currentFilePath];
    }
    cell.textLabel.textColor = highlighted ? kVCAccent : kVCTextPrimary;
    UIView *selectedBg = [[UIView alloc] init];
    selectedBg.backgroundColor = kVCAccentDim;
    selectedBg.layer.cornerRadius = 10.0;
    cell.selectedBackgroundView = selectedBg;
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (tableView == _fileTree) {
        cell.frame = UIEdgeInsetsInsetRect(cell.frame, UIEdgeInsetsMake(2, 6, 2, 6));
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger mode = self.modeControl.selectedSegmentIndex;
    if (mode == 0) {
        VCClassInfo *info = indexPath.row < self.visibleRuntimeClasses.count ? self.visibleRuntimeClasses[indexPath.row] : nil;
        if (info.className.length > 0) {
            self.selectedRuntimeClass = [[VCRuntimeEngine shared] classInfoForName:info.className];
            self.editorView.text = [self _detailTextForSelectedClass];
            self.statusLabel.text = self.selectedRuntimeClass.className ?: @"Class";
            self.statusLabel.textColor = kVCAccent;
            [tableView reloadData];
        }
        return;
    }
    if (mode == 1) {
        NSArray<VCMethodInfo *> *methods = [self _visibleMethods];
        VCMethodInfo *method = indexPath.row < methods.count ? methods[indexPath.row] : nil;
        self.editorView.text = [self _detailTextForMethod:method];
        self.statusLabel.text = method.selector ?: @"Method";
        self.statusLabel.textColor = kVCAccent;
        return;
    }
    if (mode == 2) {
        NSArray<VCHookItem *> *hooks = [self _visibleHooks];
        VCHookItem *hook = indexPath.row < hooks.count ? hooks[indexPath.row] : nil;
        self.editorView.text = [self _detailTextForHook:hook];
        self.statusLabel.text = hook.selector ?: @"Hook";
        self.statusLabel.textColor = hook.enabled ? kVCGreen : kVCTextMuted;
        return;
    }
    if (mode == 3) {
        NSArray<VCPatchItem *> *patches = [self _visiblePatches];
        VCPatchItem *patch = indexPath.row < patches.count ? patches[indexPath.row] : nil;
        self.editorView.text = [self _detailTextForPatch:patch];
        self.statusLabel.text = patch.selector ?: @"Patch";
        self.statusLabel.textColor = patch.enabled ? kVCGreen : kVCTextMuted;
        return;
    }
    NSDictionary *file = _files[indexPath.row];
    if ([file[@"isDir"] boolValue]) return;
    [self _flushPendingChangesWithReason:@"switching files"];
    [self _loadFile:file[@"path"]];
    [tableView reloadData];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
               trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.modeControl.selectedSegmentIndex >= 0) {
        return nil;
    }
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:VCTextLiteral(@"Delete") handler:^(UIContextualAction *action, UIView *sv, void (^done)(BOOL)) {
        NSDictionary *file = self->_files[indexPath.row];
        if ([file[@"path"] isEqualToString:self->_currentFilePath]) {
            [self _flushPendingChangesWithReason:@"deleting the current file"];
        }
        [[NSFileManager defaultManager] removeItemAtPath:file[@"path"] error:nil];
        if ([file[@"path"] isEqualToString:self->_currentFilePath]) {
            self->_currentFilePath = nil;
            self->_editorView.text = @"";
            self->_hasUnsavedChanges = NO;
        }
        [self _refreshFileTree];
        done(YES);
    }];
    deleteAction.backgroundColor = kVCRed;
    return [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
}

@end
