#import "OTVStatusBar.h"
#import <OakAppKit/OakAppKit.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/NSMenuItem Additions.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakFoundation/NSString Additions.h>
#import <MenuBuilder/MenuBuilder.h>
#import <bundles/bundles.h>
#import <text/ctype.h>
#import <ns/ns.h>

static NSTextField* OakCreateTextField (NSString* label)
{
	NSTextField* res = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[res setBordered:NO];
	[res setEditable:NO];
	[res setSelectable:NO];
	[res setBezeled:NO];
	[res setDrawsBackground:NO];
	[res setFont:OakStatusBarFont()];
	[res setStringValue:label];
	[res setAlignment:NSTextAlignmentRight];
	[[res cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];

	// This is to match the other controls in the status bar
	if(@available(macos 10.14, *))
		res.textColor = NSColor.secondaryLabelColor;

	return res;
}

static NSPopUpButton* OakCreateStatusBarPopUpButton (NSString* initialItemTitle = nil, NSString* accessibilityLabel = nil)
{
	NSPopUpButton* res = OakCreatePopUpButton(NO, initialItemTitle);
	res.font     = OakStatusBarFont();
	res.bordered = NO;
	res.accessibilityLabel = accessibilityLabel;
	return res;
}

static NSButton* OakCreateImageToggleButton (NSImage* image, NSString* accessibilityLabel)
{
	NSButton* res = [NSButton new];
	res.accessibilityLabel = accessibilityLabel;
	[res setButtonType:NSButtonTypeToggle];
	[res setBordered:NO];
	[res setImage:image];
	[res setImagePosition:NSImageOnly];
	return res;
}

@interface OTVStatusBar () <NSMenuDelegate>
@property (nonatomic) CGFloat recordingTime;
@property (nonatomic) NSTimer* recordingTimer;

@property (nonatomic) NSTextField*   selectionField;
@property (nonatomic) NSPopUpButton* grammarPopUp;
@property (nonatomic) NSPopUpButton* tabSizePopUp;
@property (nonatomic) NSPopUpButton* bundleItemsPopUp;
@property (nonatomic) NSPopUpButton* symbolPopUp;
@property (nonatomic) NSButton*      macroRecordingButton;
@property (nonatomic) NSTextField*   lineLabel;
@property (nonatomic) NSView* dividerOne;
@property (nonatomic) NSView* dividerTwo;
@property (nonatomic) NSView* dividerThree;
@property (nonatomic) NSView* dividerFour;
@property (nonatomic) NSView* dividerFive;
@property (nonatomic) NSArray<NSLayoutConstraint*>* metricConstraints;
@property (nonatomic) NSImage* recordMacroBaseImage;
@property (nonatomic) NSImage* bundleItemsBaseImage;
@property (nonatomic) NSView* wrappedBundleItemsPopUpButton;
@end

@implementation OTVStatusBar
- (id)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		NSImage* recordMacroImage = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect dstRect){
			[NSColor.systemRedColor set];
			[[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dstRect, 2, 2)] fill];
			return YES;
		}];

		self.wantsLayer   = YES;
		self.material     = NSVisualEffectMaterialTitlebar;
		self.blendingMode = NSVisualEffectBlendingModeWithinWindow;
		self.state        = NSVisualEffectStateFollowsWindowActiveState;

		self.selectionField               = OakCreateTextField(@"1:1");
		self.grammarPopUp                 = OakCreateStatusBarPopUpButton(@"", @"Grammar");
		self.tabSizePopUp                 = OakCreateStatusBarPopUpButton();
		self.tabSizePopUp.pullsDown       = YES;
		self.bundleItemsPopUp             = OakCreateStatusBarPopUpButton(nil, @"Bundle Item");
		self.symbolPopUp                  = OakCreateStatusBarPopUpButton(@"", @"Symbol");
		self.recordMacroBaseImage         = recordMacroImage;
		self.macroRecordingButton         = OakCreateImageToggleButton(recordMacroImage, @"Record a macro");
		self.macroRecordingButton.action  = @selector(toggleMacroRecording:);
		self.macroRecordingButton.toolTip = @"Click to start recording a macro";

		[self setupTabSizeMenu:self];

		// ===========================
		// = Wrap/Clip Bundles PopUp =
		// ===========================

		NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
		item.image = self.bundleItemsBaseImage = [NSImage imageNamed:NSImageNameActionTemplate];
		[[self.bundleItemsPopUp cell] setUsesItemFromMenu:NO];
		[[self.bundleItemsPopUp cell] setMenuItem:item];

		NSView* wrappedBundleItemsPopUpButton = self.wrappedBundleItemsPopUpButton = [NSView new];
		OakAddAutoLayoutViewsToSuperview(@[ self.bundleItemsPopUp ], wrappedBundleItemsPopUpButton);
		[wrappedBundleItemsPopUpButton addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[popup]|" options:0 metrics:nil views:@{ @"popup": self.bundleItemsPopUp }]];
		[wrappedBundleItemsPopUpButton addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[popup]|" options:0 metrics:nil views:@{ @"popup": self.bundleItemsPopUp }]];

		NSView* topDivider   = OakCreateNSBoxSeparator();
		NSTextField* line    = self.lineLabel = OakCreateTextField(@"Line:");
		NSView* dividerOne   = self.dividerOne = OakCreateNSBoxSeparator();
		NSView* dividerTwo   = self.dividerTwo = OakCreateNSBoxSeparator();
		NSView* dividerThree = self.dividerThree = OakCreateNSBoxSeparator();
		NSView* dividerFour  = self.dividerFour = OakCreateNSBoxSeparator();
		NSView* dividerFive  = self.dividerFive = OakCreateNSBoxSeparator();

		NSDictionary* views = @{
			@"topDivider":   topDivider,
			@"line":         line,
			@"selection":    self.selectionField,
			@"dividerOne":   dividerOne,
			@"grammar":      self.grammarPopUp,
			@"dividerTwo":   dividerTwo,
			@"items":        wrappedBundleItemsPopUpButton,
			@"dividerThree": dividerThree,
			@"tabSize":      self.tabSizePopUp,
			@"dividerFour":  dividerFour,
			@"symbol":       self.symbolPopUp,
			@"dividerFive":  dividerFive,
			@"recording":    self.macroRecordingButton,
		};

		OakAddAutoLayoutViewsToSuperview([views allValues], self);
		OakSetupKeyViewLoop(@[ self, _grammarPopUp, _tabSizePopUp, _bundleItemsPopUp, _symbolPopUp, _macroRecordingButton ]);

		[self.selectionField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		[self.selectionField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow+2 forOrientation:NSLayoutConstraintOrientationHorizontal];
		[[self.selectionField cell] setLineBreakMode:NSLineBreakByTruncatingTail];

		[self.grammarPopUp setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow+1 forOrientation:NSLayoutConstraintOrientationHorizontal];

		[self.symbolPopUp setContentHuggingPriority:NSLayoutPriorityDefaultLow-1 forOrientation:NSLayoutConstraintOrientationHorizontal];
		[self.symbolPopUp setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow-1 forOrientation:NSLayoutConstraintOrientationHorizontal];

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[topDivider]|" options:0 metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[topDivider(==1)]" options:0 metrics:nil views:views]];

		// Baseline align text-controls
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[line]-[selection]-(>=1)-[grammar]-(>=1)-[tabSize]-(>=1)-[symbol]" options:NSLayoutFormatAlignAllBaseline metrics:nil views:views]];

		// Center non-text control
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[selection]-(>=1)-[dividerOne]-(>=1)-[dividerTwo]-(>=1)-[dividerThree]-(>=1)-[items]-(>=1)-[dividerFour]-(>=1)-[dividerFive]-(>=1)-[recording]" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
		[self updateFonts];
		[self updateMetricConstraints];

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(grammarPopUpButtonWillPopUp:) name:NSPopUpButtonWillPopUpNotification object:self.grammarPopUp];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(bundleItemsPopUpButtonWillPopUp:) name:NSPopUpButtonWillPopUpNotification object:self.bundleItemsPopUp];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(symbolPopUpButtonWillPopUp:) name:NSPopUpButtonWillPopUpNotification object:self.symbolPopUp];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(uiFontScaleFactorDidChange:) name:OakUIFontScaleFactorDidChangeNotification object:nil];
	}
	return self;
}

- (void)updateFonts
{
	NSFont* font = OakStatusBarFont();
	for(NSControl* control in @[ self.lineLabel, self.grammarPopUp, self.tabSizePopUp, self.bundleItemsPopUp, self.symbolPopUp ])
		control.font = font;

	// The dropped-down menus use the menu font, not the control’s.
	NSFont* menuFont = OakScaledUIFont([NSFont menuFontOfSize:0]);
	for(NSPopUpButton* popUp in @[ self.grammarPopUp, self.tabSizePopUp, self.bundleItemsPopUp, self.symbolPopUp ])
		popUp.menu.font = menuFont;

	NSFontDescriptor* descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
		NSFontFeatureSettingsAttribute: @[ @{ NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType), NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector) } ]
	}];
	self.selectionField.font = [NSFont fontWithDescriptor:descriptor size:0];

	self.macroRecordingButton.image = OakScaledUIImage(_recordMacroBaseImage);
	[[self.bundleItemsPopUp cell] menuItem].image = OakScaledUIImage(_bundleItemsBaseImage);
}

// The dividers set the bar's height: 15 pt tall with 5 pt above and below
// at the stock scale.
- (void)updateMetricConstraints
{
	if(_metricConstraints)
		[self removeConstraints:_metricConstraints];

	NSDictionary* metrics = @{ @"margin": @(OakScaledUIMetric(5)), @"height": @(OakScaledUIMetric(15)), @"items": @(OakScaledUIMetric(31)) };
	NSDictionary* views = @{
		@"line":         _lineLabel,
		@"selection":    _selectionField,
		@"dividerOne":   _dividerOne,
		@"grammar":      _grammarPopUp,
		@"dividerTwo":   _dividerTwo,
		@"tabSize":      _tabSizePopUp,
		@"dividerThree": _dividerThree,
		@"items":        _wrappedBundleItemsPopUpButton,
		@"dividerFour":  _dividerFour,
		@"symbol":       _symbolPopUp,
		@"dividerFive":  _dividerFive,
		@"recording":    _macroRecordingButton,
	};
	NSMutableArray* constraints = [NSMutableArray array];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[line]-[selection(>=50,<=225)]-8-[dividerOne(==1)]-2-[grammar(>=125@400,>=50,<=225)]-5-[dividerTwo(==1)]-2-[tabSize]-4-[dividerThree(==1)]-5-[items(==items)]-4-[dividerFour(==1)]-2-[symbol(>=125@450,>=50)]-5-[dividerFive(==1)]-6-[recording]-7-|" options:0 metrics:metrics views:views]];
	[constraints addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(margin)-[dividerOne(==height,==dividerTwo,==dividerThree,==dividerFour,==dividerFive)]-(margin)-|" options:0 metrics:metrics views:views]];
	_metricConstraints = constraints;
	[self addConstraints:_metricConstraints];
}

- (void)uiFontScaleFactorDidChange:(NSNotification*)aNotification
{
	[self updateFonts];
	[self updateMetricConstraints];
}

- (void)setupTabSizeMenu:(id)sender
{
	MBMenu const items = {
		{ @"Current Indent" },
		{ @"Indent Size",  @selector(nop:) },
		{ @"2",            @selector(takeTabSizeFrom:), .tag = 2, .indent = 1, .target = self.target },
		{ @"3",            @selector(takeTabSizeFrom:), .tag = 3, .indent = 1, .target = self.target },
		{ @"4",            @selector(takeTabSizeFrom:), .tag = 4, .indent = 1, .target = self.target },
		{ @"8",            @selector(takeTabSizeFrom:), .tag = 8, .indent = 1, .target = self.target },
		{ @"Other…",       @selector(showTabSizeSelectorPanel:),  .indent = 1, .target = self.target },
		{ /* -------- */ },
		{ @"Indent Using", @selector(nop:) },
		{ @"Tabs",         @selector(setIndentWithTabs:),         .indent = 1, .target = self.target },
		{ @"Spaces",       @selector(setIndentWithSpaces:),       .indent = 1, .target = self.target },
	};
	self.tabSizePopUp.menu = MBCreateMenu(items);
}

- (void)setTarget:(id)newTarget
{
	_target = newTarget;
	[self setupTabSizeMenu:self];
}

- (void)updateMacroRecordingAnimation:(NSTimer*)aTimer
{
	CGFloat fraction = std::clamp(0.70 + 0.30 * cos(M_PI + _recordingTime), 0.00, 1.0);
	self.macroRecordingButton.alphaValue = fraction;
	_recordingTime += 0.075;
}

- (void)grammarPopUpButtonWillPopUp:(NSNotification*)aNotification
{
	NSMenu* grammarMenu = self.grammarPopUp.menu;
	[grammarMenu removeAllItems];

	std::multimap<std::string, bundles::item_ptr, text::less_t> grammars;
	for(auto item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, bundles::kItemTypeGrammar))
	{
		if(item->value_for_field(bundles::kFieldGrammarScope) != NULL_STR)
			grammars.emplace(item->name(), item);
	}

	for(auto pair : grammars)
	{
		if(!pair.second->hidden_from_user())
		{
			NSMenuItem* item = [grammarMenu addItemWithTitle:[NSString stringWithCxxString:pair.first] action:@selector(takeGrammarUUIDFrom:) keyEquivalent:@""];
			[item setKeyEquivalentCxxString:key_equivalent(pair.second)];
			[item setRepresentedObject:[NSString stringWithCxxString:pair.second->uuid()]];
			[item setTarget:self.target];
		}
	}

	if(grammars.empty())
		[grammarMenu addItemWithTitle:@"No Grammars Loaded" action:@selector(nop:) keyEquivalent:@""];

	[grammarMenu update];

	for(NSMenuItem* item in grammarMenu.itemArray)
	{
		if([item state] == NSControlStateValueOn)
			[self.grammarPopUp selectItem:item];
	}
}

- (void)bundleItemsPopUpButtonWillPopUp:(NSNotification*)aNotification
{
	[self.delegate showBundleItemSelector:self.bundleItemsPopUp];
}

- (void)symbolPopUpButtonWillPopUp:(NSNotification*)aNotification
{
	[self.delegate showSymbolSelector:self.symbolPopUp];
}

// ===========
// = Actions =
// ===========

- (void)showBundlesMenu:(id)sender
{
	[self.bundleItemsPopUp performClick:self];
}

// ==============
// = Properties =
// ==============

- (void)setSelectionString:(NSString*)newSelectionString
{
	if(_selectionString == newSelectionString || [_selectionString isEqualToString:newSelectionString])
		return;
	_selectionString = newSelectionString;

	newSelectionString = [newSelectionString stringByReplacingOccurrencesOfString:@"&" withString:@", "];
	newSelectionString = [newSelectionString stringByReplacingOccurrencesOfString:@"x" withString:@"×"];
	self.selectionField.stringValue = newSelectionString;
}

- (void)setGrammarName:(NSString*)newGrammarName
{
	if(_grammarName == newGrammarName || [_grammarName isEqualToString:newGrammarName])
		return;
	_grammarName = newGrammarName;
	[self.grammarPopUp.menu removeAllItems];
	[self.grammarPopUp addItemWithTitle:newGrammarName ?: @"(no grammar)"];
}

- (void)setSymbolName:(NSString*)newSymbolName
{
	if(_symbolName == newSymbolName || [_symbolName isEqualToString:newSymbolName])
		return;
	_symbolName = newSymbolName;
	[self.symbolPopUp.menu removeAllItems];
	[self.symbolPopUp addItemWithTitle:newSymbolName ?: @"Symbols"];
}

- (void)setFileType:(NSString*)newFileType
{
	if(_fileType == newFileType)
		return;

	_fileType = newFileType;
	for(auto const& item : bundles::query(bundles::kFieldGrammarScope, to_s(newFileType)))
		self.grammarName = [NSString stringWithCxxString:item->name()];
}

- (void)setRecordingTimer:(NSTimer*)aTimer
{
	if(_recordingTimer != aTimer)
	{
		[_recordingTimer invalidate];
		_recordingTimer = aTimer;
	}
}

- (void)setRecordingMacro:(BOOL)flag
{
	_recordingMacro = flag;
	if(_recordingMacro)
	{
		self.recordingTimer = [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(updateMacroRecordingAnimation:) userInfo:nil repeats:YES];
	}
	else
	{
		self.recordingTimer = nil;
		_recordingTime = 0;
		[self updateMacroRecordingAnimation:nil];
	}
}

- (void)updateTabSettings
{
	self.tabSizePopUp.title = [NSString stringWithFormat:@"%@:\u2003%lu", _softTabs ? @"Soft Tabs" : @"Tab Size", _tabSize];
}

- (void)setTabSize:(NSUInteger)size
{
	_tabSize = size;
	[self updateTabSettings];
}

- (void)setSoftTabs:(BOOL)flag
{
	_softTabs = flag;
	[self updateTabSettings];
}

- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
	self.recordingTimer = nil;
}
@end
