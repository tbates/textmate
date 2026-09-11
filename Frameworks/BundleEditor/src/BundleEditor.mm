#import "BundleEditor.h"
#import "PropertiesViewController.h"
#import "OakRot13Transformer.h"
#import "be_entry.h"
#import <OakFoundation/NSString Additions.h>
#import <OakFoundation/OakStringListTransformer.h>
#import <OakAppKit/NSAlert Additions.h>
#import <OakAppKit/NSImage Additions.h>
#import <OakAppKit/OakSound.h>
#import <OakAppKit/OakUIConstructionFunctions.h>
#import <OakTextView/OakDocumentView.h>
#import <TMFileReference/TMFileReference.h>
#import <document/OakDocument.h>
#import <document/OakDocumentController.h>
#import <BundlesManager/BundlesManager.h>
#import <command/runner.h> // fix_shebang
#import <plist/ascii.h>
#import <plist/delta.h>
#import <regexp/format_string.h>
#import <text/decode.h>
#import <cf/cf.h>
#import <ns/ns.h>
#import <io/environment.h>
#import <settings/settings.h>
#import <oak/debug.h>

@class OakCommand;
@class BEOutlineEntry;

@interface BundleEditor () <NSWindowDelegate, OakTextViewDelegate>
{
	NSViewController*      _browserViewController;
	NSViewController*      _documentViewController;
	NSSplitViewController* _splitViewController;
	NSViewController*      _propertiesViewController;
	NSLayoutConstraint*    _propertiesHeightConstraint;
	NSSplitViewController* _windowSplitViewController;

	CGFloat _maxLabelWidth;
	CGFloat _minPropertiesViewWidth;

	NSOutlineView* outlineView;
	NSMutableDictionary* entryCache; // identifier-path → BEOutlineEntry, one generation per reloadData
	NSMutableSet* expandedPaths;
	OakDocumentView* documentView;

	be::entry_ptr bundles;
	std::map<bundles::item_ptr, plist::dictionary_t> changes;

	BOOL propertiesChanged;

	bundles::item_ptr bundleItem;
	OakDocument* bundleItemContent;
}
- (void)didChangeBundleItems;
- (void)didChangeModifiedState;
- (BEOutlineEntry*)wrapperForPath:(NSString*)path create:(BOOL)create;
- (void)expandAncestorsOfPath:(NSString*)path;
- (NSInteger)rowForPath:(NSString*)path;
- (void)outlineSelectionDidChange:(NSNotification*)notification;
- (BOOL)moveBundleItems:(NSArray*)uuidStrings toMenu:(oak::uuid_t const&)targetMenu atIndex:(size_t)index inBundle:(bundles::item_ptr const&)bundle;
@property (nonatomic) PropertiesViewController* sharedPropertiesViewController;
@property (nonatomic) PropertiesViewController* extraPropertiesViewController;
@property (nonatomic) NSMutableDictionary* bundleItemProperties;
- (bundles::item_ptr const&)bundleItem;
- (void)setBundleItem:(bundles::item_ptr const&)aBundleItem;
@end

namespace
{
	static bundles::kind_t const PlistItemKinds[] = { bundles::kItemTypeSettings, bundles::kItemTypeMacro, bundles::kItemTypeTheme };

	static std::vector<std::string> const& PlistKeySortOrder ()
	{
		static auto const res = new std::vector<std::string>{ "shellVariables", "disabled", "name", "value", "comment", "match", "begin", "while", "end", "applyEndPatternLast", "captures", "beginCaptures", "whileCaptures", "endCaptures", "contentName", "injections", "patterns", "repository", "include", "increaseIndentPattern", "decreaseIndentPattern", "indentNextLinePattern", "unIndentedLinePattern", "disableIndentCorrections", "indentOnPaste", "indentedSoftWrap", "format", "foldingStartMarker", "foldingStopMarker", "foldingIndentedBlockStart", "foldingIndentedBlockIgnore", "characterClass", "smartTypingPairs", "highlightPairs", "showInSymbolList", "symbolTransformation", "disableDefaultCompletion", "completions", "completionCommand", "spellChecking", "softWrap", "fontName", "fontStyle", "fontSize", "foreground", "background", "bold", "caret", "invisibles", "italic", "misspelled", "selection", "underline" };
		return *res;
	}

	static struct item_info_t { bundles::kind_t kind; std::string plist_key; std::string grammar; std::string file_type; std::string kind_string; NSString* scope; NSString* view_controller; NSString* file; } item_infos[] =
	{
		{ bundles::kItemTypeBundle,       "description", "text.html.basic",                "tmBundle",       "bundle",         @"attr.bundle-editor.bundle",         @"BundleProperties",     @"Bundle"       },
		{ bundles::kItemTypeCommand,      "command",     NULL_STR,                         "tmCommand",      "command",        @"attr.bundle-editor.command",        @"CommandProperties",    @"Command"      },
		{ bundles::kItemTypeDragCommand,  "command",     NULL_STR,                         "tmDragCommand",  "dragCommand",    @"attr.bundle-editor.command.drop",   @"FileDropProperties",   @"Drag Command" },
		{ bundles::kItemTypeSnippet,      "content",     "text.tm-snippet",                "tmSnippet",      "snippet",        @"attr.bundle-editor.snippet",        @"SnippetProperties",    @"Snippet"      },
		{ bundles::kItemTypeSettings,     "settings",    "source.plist.textmate.settings", "tmPreferences",  "settings",       @"attr.bundle-editor.settings",       nil,                     @"Settings"     },
		{ bundles::kItemTypeGrammar,      NULL_STR,      "source.plist.textmate.grammar",  "tmLanguage",     "grammar",        @"attr.bundle-editor.grammar",        @"GrammarProperties",    @"Grammar"      },
		{ bundles::kItemTypeProxy,        "content",     "text.plain",                     "tmProxy",        "proxy",          @"attr.bundle-editor.proxy",          nil,                     @"Proxy"        },
		{ bundles::kItemTypeTheme,        NULL_STR,      "source.plist",                   "tmTheme",        "theme",          @"attr.bundle-editor.theme",          @"ThemeProperties",      @"Theme"        },
		{ bundles::kItemTypeMacro,        "commands",    "source.plist",                   "tmMacro",        "macro",          @"attr.bundle-editor.macro",          @"MacroProperties",      @"Macro"        },
	};

	item_info_t const& info_for (bundles::kind_t kind)
	{
		for(auto const& it : item_infos)
		{
			if(it.kind == kind)
				return it;
		}

		static item_info_t dummy;
		return dummy;
	}
}

static NSMutableArray* wrap_array (std::vector<std::string> const& array, NSString* key)
{
	NSMutableArray* res = [NSMutableArray array];
	for(auto const& str : array)
		[res addObject:[NSMutableDictionary dictionaryWithObject:[NSString stringWithCxxString:str] forKey:key]];
	return res;
}

static plist::array_t unwrap_array (NSArray* array, NSString* key)
{
	plist::array_t res;
	for(NSDictionary* dict in array)
		res.push_back(to_s([dict objectForKey:key]));
	return res;
}

namespace
{
	struct expand_visitor_t
	{
		expand_visitor_t (std::map<std::string, std::string> const& variables) : _variables(variables) { }

		void operator() (bool value) const                     { }
		void operator() (int32_t value) const                  { }
		void operator() (uint64_t value) const                 { }
		void operator() (oak::date_t const& value) const       { }
		void operator() (std::vector<char> const& value) const { }
		void operator() (std::string& str) const               { str = format_string::expand(str, _variables); }
		void operator() (plist::array_t& array) const          { for(auto& item : array) std::visit(*this, item.data); }
		void operator() (plist::dictionary_t& dict) const      { for(auto& pair : dict)  std::visit(*this, pair.second.data); }

	private:
		std::map<std::string, std::string> const& _variables;
	};
}

// NSOutlineView items must be Objective-C objects. The wrapper retains shared
// ownership of its C++ browser entry; the entry cache is thrown away on every
// reloadData, so wrappers never outlive their generation. Paths join entry
// identifiers with \x1F from the invisible root, which keeps even same-named
// submenus in different bundles distinct.
@interface BEOutlineEntry : NSObject
{
@public
	be::entry_ptr _entry;
	NSString* _path;
}
- (instancetype)initWithEntry:(be::entry_ptr const&)anEntry path:(NSString*)aPath;
@end

@implementation BEOutlineEntry
- (instancetype)initWithEntry:(be::entry_ptr const&)anEntry path:(NSString*)aPath
{
	if(self = [super init])
	{
		_entry = anEntry;
		_path = aPath;
	}
	return self;
}

// Wrappers are re-created across data-source calls and generations; the
// outline must treat any two wrappers for one identifier path as the node.
- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[BEOutlineEntry class]] && [((BEOutlineEntry*)other)->_path isEqualToString:_path];
}

- (NSUInteger)hash
{
	return [_path hash];
}
@end

static NSString* const kPathSeparator = @"\x1F";

// Private pasteboard type for intra-editor drags: an array of item UUID strings.
static NSString* const kBundleItemUUIDsPboardType = @"com.textmate.BundleItemUUIDs";

@implementation BundleEditor
+ (instancetype)sharedInstance
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		static struct { NSString* name; NSArray* array; } const converters[] =
		{
			{ @"OakSaveStringListTransformer",                  @[ @"nop", @"saveActiveFile", @"saveModifiedFiles" ] },
			{ @"OakInputStringListTransformer",                 @[ @"selection", @"document", @"scope", @"line", @"word", @"character", @"none" ] },
			{ @"OakInputFormatStringListTransformer",           @[ @"text", @"xml" ] },
			{ @"OakOutputLocationStringListTransformer",        @[ @"replaceInput", @"replaceDocument", @"atCaret", @"afterInput", @"newWindow", @"toolTip", @"discard", @"replaceSelection" ] },
			{ @"OakOutputFormatStringListTransformer",          @[ @"text", @"snippet", @"html", @"completionList" ] },
			{ @"OakOutputCaretStringListTransformer",           @[ @"afterOutput", @"selectOutput", @"interpolateByChar", @"interpolateByLine", @"heuristic" ] },
		};

		[OakRot13Transformer register];
		for(auto const& converter : converters)
			[OakStringListTransformer createTransformerWithName:converter.name andObjectsArray:converter.array];
	});

	static BundleEditor* sharedInstance = [self new];
	return sharedInstance;
}

- (id)init
{
	if(self = [super initWithWindow:nil])
	{
		struct callback_t : bundles::callback_t
		{
			callback_t (BundleEditor* self) : self(self) { }
			void bundles_did_change ()                   { [self didChangeBundleItems]; }
		private:
			BundleEditor* self;
		};

		static callback_t cb(self);
		bundles::add_callback(&cb);

		self.window = [NSWindow windowWithContentViewController:self.windowSplitViewController];
		self.window.delegate = self;

		NSRect r = self.window.screen.visibleFrame;
		[self.window setFrame:NSInsetRect(r, MAX(0, round((NSWidth(r)-1200)/2)), MAX(0, round((NSHeight(r)-700)/2))) display:NO];
		self.windowFrameAutosaveName = @"Bundle Editor";

		[self.splitViewController.splitView setPosition:round(NSHeight(self.splitViewController.splitView.frame) / 3) ofDividerAtIndex:0];
		self.splitViewController.splitView.autosaveName = @"Bundle Editor";

		[self.windowSplitViewController.splitView setPosition:NSWidth(self.windowSplitViewController.splitView.frame) - _minPropertiesViewWidth ofDividerAtIndex:0];
		self.windowSplitViewController.splitView.autosaveName = @"Bundle Editor Properties";

		bundles = be::bundle_entries();
		entryCache = [NSMutableDictionary dictionary];
		expandedPaths = [NSMutableSet set];
		[outlineView reloadData];
		[outlineView expandItem:nil expandChildren:YES];

		[self.window makeFirstResponder:outlineView];
	}
	return self;
}

- (NSViewController*)browserViewController
{
	if(!_browserViewController)
	{
		_browserViewController = [[NSViewController alloc] initWithNibName:nil bundle:nil];

		NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		scrollView.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		scrollView.hasVerticalScroller = YES;
		scrollView.autohidesScrollers = YES;

		outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
		NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"Items"];
		[outlineView addTableColumn:column];
		outlineView.outlineTableColumn = column;
		outlineView.headerView = nil;
		outlineView.delegate = self;
		outlineView.dataSource = self;
		outlineView.allowsMultipleSelection = YES;
		outlineView.allowsEmptySelection = YES;
		[outlineView registerForDraggedTypes:@[ kBundleItemUUIDsPboardType ]];
		[outlineView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

		scrollView.documentView = outlineView;
		_browserViewController.view = scrollView;

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(outlineSelectionDidChange:) name:NSOutlineViewSelectionDidChangeNotification object:outlineView];
	}
	return _browserViewController;
}

// The entry cache is filled lazily by the data source; this resolves any
// identifier path (creating the wrapper when asked) so selection restore and
// reveal can address rows that were never displayed.
- (BEOutlineEntry*)wrapperForPath:(NSString*)path create:(BOOL)create
{
	if(BEOutlineEntry* wrapper = entryCache[path])
		return wrapper;
	if(!create || !bundles)
		return nil;

	be::entry_ptr entry = bundles;
	NSString* built = @"";
	for(NSString* identifier in [path componentsSeparatedByString:kPathSeparator])
	{
		be::entry_ptr match;
		for(auto const& child : entry->children())
		{
			if(child->identifier() == to_s(identifier))
			{
				match = child;
				break;
			}
		}
		if(!match)
			return nil;
		entry = match;
		built = [built length] == 0 ? identifier : [built stringByAppendingFormat:@"%C%@", (unichar)0x1F, identifier];
	}
	if(![built isEqualToString:path])
		return nil;

	BEOutlineEntry* wrapper = [[BEOutlineEntry alloc] initWithEntry:entry path:path];
	entryCache[path] = wrapper;
	return wrapper;
}

- (void)expandAncestorsOfPath:(NSString*)path
{
	NSArray* components = [path componentsSeparatedByString:kPathSeparator];
	NSMutableString* prefix = [NSMutableString string];
	for(size_t i = 0; i + 1 < components.count; ++i)
	{
		if([prefix length] != 0)
			[prefix appendFormat:@"%C", (unichar)0x1F];
		[prefix appendString:components[i]];
		if(BEOutlineEntry* ancestor = [self wrapperForPath:prefix create:YES])
			[outlineView expandItem:ancestor];
	}
}

- (NSInteger)rowForPath:(NSString*)path
{
	if(BEOutlineEntry* wrapper = [self wrapperForPath:path create:YES])
		return [outlineView rowForItem:wrapper];
	return -1;
}

- (NSViewController*)documentViewController
{
	if(!_documentViewController)
	{
		documentView = [[OakDocumentView alloc] initWithFrame:NSZeroRect];
		documentView.textView.delegate = self;

		_documentViewController = [[NSViewController alloc] initWithNibName:nil bundle:nil];
		_documentViewController.view = documentView;
	}
	return _documentViewController;
}

- (NSSplitViewController*)splitViewController
{
	if(!_splitViewController)
	{
		_splitViewController = [[NSSplitViewController alloc] init];
		_splitViewController.splitView.vertical = NO;
		_splitViewController.splitView.dividerStyle = NSSplitViewDividerStylePaneSplitter;

		[_splitViewController addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.browserViewController]];
		[_splitViewController addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.documentViewController]];

		_splitViewController.splitViewItems[0].minimumThickness = 50;
		_splitViewController.splitViewItems[0].canCollapse      = YES;
	}
	return _splitViewController;
}

- (NSSplitViewController*)windowSplitViewController
{
	if(!_windowSplitViewController)
	{
		CGFloat maxWidth = 0, maxLabelWidth = 0;

		NSArray<NSString*>* viewControllerNames = @[ @"SharedProperties", @"BundleProperties", @"CommandProperties", @"FileDropProperties", @"SnippetProperties", @"GrammarProperties", @"ThemeProperties", @"MacroProperties" ];
		for(NSString* name in viewControllerNames)
		{
			if(PropertiesViewController* viewController = [[PropertiesViewController alloc] initWithName:name])
			{
				if(NSView* view = viewController.view)
				{
					maxWidth      = MAX(maxWidth, NSWidth(view.frame) - viewController.labelWidth);
					maxLabelWidth = MAX(maxLabelWidth, viewController.labelWidth);
				}
			}
		}

		_maxLabelWidth          = maxLabelWidth;
		_minPropertiesViewWidth = maxLabelWidth + maxWidth;

		_propertiesViewController = [[NSViewController alloc] init];
		_propertiesViewController.view = [[NSView alloc] initWithFrame:NSZeroRect];

		[_propertiesViewController.view.widthAnchor constraintGreaterThanOrEqualToConstant:_minPropertiesViewWidth].active = YES;
		_propertiesHeightConstraint = [_propertiesViewController.view.heightAnchor constraintGreaterThanOrEqualToConstant:0];

		// ==========================
		// = Create Main Split View =
		// ==========================

		_windowSplitViewController = [[NSSplitViewController alloc] init];
		_windowSplitViewController.splitView.vertical = YES;

		[_windowSplitViewController addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:self.splitViewController]];
		[_windowSplitViewController addSplitViewItem:[NSSplitViewItem splitViewItemWithViewController:_propertiesViewController]];

		_windowSplitViewController.splitViewItems[0].holdingPriority = NSLayoutPriorityDefaultLow - 1;
	}
	return _windowSplitViewController;
}

- (NSString*)scopeAttributes
{
	return bundleItem && bundleItemContent ? info_for(bundleItem->kind()).scope : nil;
}

- (void)didChangeBundleItems
{
	NSMutableArray* selection = [NSMutableArray array];
	NSIndexSet* selectedRows = [outlineView selectedRowIndexes];
	for(size_t i = [selectedRows firstIndex]; i != NSNotFound; i = [selectedRows indexGreaterThanIndex:i])
	{
		if(BEOutlineEntry* wrapper = [outlineView itemAtRow:i])
			[selection addObject:wrapper->_path];
	}
	NSSet* expanded = [expandedPaths copy];

	bundles = be::bundle_entries();
	entryCache = [NSMutableDictionary dictionary];
	[outlineView reloadData];
	[outlineView expandItem:nil expandChildren:YES];

	for(NSString* path in expanded)
	{
		if(BEOutlineEntry* wrapper = [self wrapperForPath:path create:YES])
			[outlineView expandItem:wrapper];
	}

	NSMutableIndexSet* rows = [NSMutableIndexSet indexSet];
	for(NSString* path in selection)
	{
		[self expandAncestorsOfPath:path];
		NSInteger row = [self rowForPath:path];
		if(row != -1)
			[rows addIndex:row];
	}
	if([rows count] != 0)
		[outlineView selectRowIndexes:rows byExtendingSelection:NO];
}

- (void)didChangeModifiedState
{
	[self setDocumentEdited:bundleItem && (changes.find(bundleItem) != changes.end() || propertiesChanged || bundleItemContent.isDocumentEdited)];
}

// ==================
// = Action Methods =
// ==================

// Place a newly created menu-type item into the selected menu: a selected
// menu (or “Menu Actions”) becomes the parent, a selected leaf means “below
// this item”. Anything else — kind groups, Support files, an empty or
// group-level selection — keeps the legacy behavior. Both the in-memory index
// (via add_to_menu) and the bundle’s info.plist mainMenu (via the changes map,
// so it is saved by saveDocument:) are updated; if the plist edit fails the
// in-memory index is left untouched so a reload cannot lose the placement.
- (void)placeNewBundleItem:(bundles::item_ptr const&)item ofType:(bundles::kind_t)aType inBundle:(bundles::item_ptr const&)bundle
{
	if(!(aType & bundles::kItemTypeMenuTypes) || !bundle)
		return;

	NSInteger selectedRow = [outlineView selectedRow];
	if(selectedRow == -1)
		return;

	BEOutlineEntry* selected = [outlineView itemAtRow:selectedRow];
	NSArray* components = [selected->_path componentsSeparatedByString:kPathSeparator];
	if(components.count < 2)
		return; // bundle itself selected: legacy top-level placement

	oak::uuid_t menuContext;
	NSMutableString* prefix = [NSMutableString string];
	for(size_t i = 0; i + 1 < components.count; ++i)
	{
		if([prefix length] != 0)
			[prefix appendFormat:@"%C", (unichar)0x1F];
		[prefix appendString:components[i]];
		if(BEOutlineEntry* ancestor = [self wrapperForPath:prefix create:YES])
		{
			if(bundles::item_ptr represented = ancestor->_entry->represented_item())
			{
				if(represented->kind() == bundles::kItemTypeMenu)
					menuContext = represented->uuid();
				else if(ancestor->_entry->identifier() == "Menu Actions" && represented->kind() == bundles::kItemTypeBundle)
					menuContext = represented->uuid();
			}
		}
	}
	be::entry_ptr entry = selected->_entry;

	oak::uuid_t targetMenu;
	oak::uuid_t afterItem;
	if(bundles::item_ptr represented = entry->represented_item())
	{
		if(represented->kind() == bundles::kItemTypeMenu)
			targetMenu = represented->uuid();
		else if(menuContext && !entry->has_children())
		{
			targetMenu = menuContext;
			if(represented->parent_menu() == menuContext)
				afterItem = represented->uuid();
		}
	}
	else if(entry->identifier() == "Menu Actions")
	{
		targetMenu = bundle->uuid();
	}
	if(!targetMenu)
		return;

	std::string const afterUUID = afterItem ? to_s(afterItem) : std::string();
	auto base = changes.find(bundle);
	plist::dictionary_t infoPlist = base != changes.end() ? base->second : bundle->plist();
	if(!bundles::insert_uuid_into_main_menu(infoPlist, to_s(bundle->uuid()), to_s(targetMenu), to_s(item->uuid()), afterUUID))
		return;
	if(!plist::equal(infoPlist, bundle->plist()))
		changes[bundle] = infoPlist;
	bundles::add_to_menu(targetMenu, item->uuid(), afterItem);
}

- (void)createItemOfType:(bundles::kind_t)aType
{
	NSString* path = [[NSBundle bundleForClass:[self class]] pathForResource:info_for(aType).file ofType:@"plist"];
	if(!path || ![NSFileManager.defaultManager fileExistsAtPath:path])
		return;

	bundles::item_ptr bundle;
	if([outlineView selectedRow] != -1)
	{
		BEOutlineEntry* selected = [outlineView itemAtRow:[outlineView selectedRow]];
		NSString* topIdentifier = [selected->_path componentsSeparatedByString:kPathSeparator][0];
		if(BEOutlineEntry* bundleEntry = [self wrapperForPath:topIdentifier create:YES])
			bundle = bundleEntry->_entry->represented_item();
	}
	if(aType == bundles::kItemTypeBundle || bundle)
	{
		std::map<std::string, std::string> environment = variables_for_path(oak::basic_environment());
		ABMutableMultiValue* value = [[[ABAddressBook sharedAddressBook] me] valueForProperty:kABEmailProperty];
		if(NSString* email = [value valueAtIndex:[value indexForIdentifier:[value primaryIdentifier]]])
			environment.emplace("TM_ROT13_EMAIL", decode::rot13(to_s(email)));

		auto item = std::make_shared<bundles::item_t>(oak::uuid_t().generate(), aType == bundles::kItemTypeBundle ? bundles::item_ptr() : bundle, aType);
		plist::dictionary_t plist = plist::load(to_s(path));
		expand_visitor_t visitor(environment);
		visitor(plist);
		plist[bundles::kFieldUUID] = to_s(item->uuid());
		if(plist.find(bundles::kFieldName) == plist.end())
			plist[bundles::kFieldName] = std::string("untitled");
		item->set_plist(plist);
		changes.emplace(item, plist);
		bundles::add_item(item);
		[self placeNewBundleItem:item ofType:aType inBundle:bundle];
		[self revealBundleItem:item];
		[self didChangeModifiedState];
	}
}

- (void)newDocument:(id)sender
{
	// kItemTypeMacro, kItemTypeMenu, kItemTypeMenuItemSeparator

	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Item Types"];
	for(auto const& it : item_infos)
	{
		static int const types = bundles::kItemTypeBundle|bundles::kItemTypeCommand|bundles::kItemTypeDragCommand|bundles::kItemTypeSnippet|bundles::kItemTypeSettings|bundles::kItemTypeGrammar|bundles::kItemTypeProxy|bundles::kItemTypeTheme;
		if((it.kind & types) == it.kind)
			[[menu addItemWithTitle:it.file action:NULL keyEquivalent:@""] setTag:it.kind];
	}

	NSAlert* alert = [NSAlert tmAlertWithMessageText:@"Create New Item" informativeText:@"Please choose what you want to create:" buttons:@"Create", @"Cancel", nil];
	NSPopUpButton* typeChooser = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
	[typeChooser setMenu:menu];
	[typeChooser sizeToFit];
	[alert setAccessoryView:typeChooser];
	[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){
		if(returnCode == NSAlertFirstButtonReturn)
			[self createItemOfType:(bundles::kind_t)[[(NSPopUpButton*)[alert accessoryView] selectedItem] tag]];
	}];
	[[alert window] recalculateKeyViewLoop];
	[[alert window] makeFirstResponder:typeChooser];
}

- (void)delete:(id)sender
{
	if(bundleItem && bundleItem->move_to_trash())
	{
		OakPlayUISound(OakSoundDidTrashItemUISound);
		bundles::item_ptr trashedItem = bundleItem;

		bundles::item_ptr newSelectedItem;
		bool foundItem = false;
		be::entry_ptr siblings;
		if(BEOutlineEntry* selected = [outlineView itemAtRow:[outlineView selectedRow]])
		{
			NSString* path = selected->_path;
			NSRange lastSeparator = [path rangeOfString:kPathSeparator options:NSBackwardsSearch];
			NSString* parentPath = lastSeparator.location == NSNotFound ? nil : [path substringToIndex:lastSeparator.location];
			if(!parentPath)
			{
				siblings = bundles;
			}
			else if(BEOutlineEntry* parent = [self wrapperForPath:parentPath create:YES])
			{
				siblings = parent->_entry;
			}
		}
		if(siblings)
		{
			for(auto const& entry : siblings->children())
			{
				if(bundles::item_ptr item = entry->represented_item())
				{
					if(item->uuid() == bundleItem->uuid())
						foundItem = true;
					else if(item->kind() != bundles::kItemTypeMenu && item->kind() != bundles::kItemTypeMenuItemSeparator)
						newSelectedItem = item;

					if(foundItem && newSelectedItem)
						break;
				}
			}
		}

		if(newSelectedItem)
			[self revealBundleItem:newSelectedItem];

		changes.erase(trashedItem);
		bundles::remove_item(trashedItem);
		[self didChangeModifiedState];

		if(!trashedItem->paths().empty())
		{
			std::string itemFolder = path::parent(trashedItem->paths().front());
			if(trashedItem->kind() == bundles::kItemTypeBundle && trashedItem->paths().size() == 1)
				itemFolder = path::parent(itemFolder);
			[BundlesManager.sharedInstance reloadPath:[NSString stringWithCxxString:itemFolder]];
		}
	}
}

- (void)revealBundleItem:(bundles::item_ptr const&)anItem
{
	if(!anItem)
		return;

	[self showWindow:self];
	[self setBundleItem:anItem];

	if(anItem->paths().empty())
	{
		changes.emplace(anItem, anItem->plist());
		[self didChangeModifiedState];
	}

	std::vector<be::entry_ptr> const& allBundles = bundles->children();
	iterate(bundle, allBundles)
	{
		if((anItem->bundle() ?: anItem) != (*bundle)->represented_item())
			continue;

		for(std::vector< std::pair<std::vector<be::entry_ptr>, int> > stack(1, std::make_pair((*bundle)->children(), -1)); !stack.empty(); stack.pop_back())
		{
			for(++stack.back().second; stack.back().second < stack.back().first.size(); ++stack.back().second)
			{
				be::entry_ptr entry = stack.back().first[stack.back().second];
				if(entry->has_children())
				{
					stack.emplace_back(entry->children(), -1);
				}
				else if(entry->represented_item() == anItem)
				{
					// The stack records one (children, index) frame per level
					// below the bundle; replay it into an identifier path.
					NSMutableString* path = [NSMutableString stringWithString:[NSString stringWithCxxString:(*bundle)->identifier()]];
					for(size_t j = 0; j < stack.size(); ++j)
					{
						be::entry_ptr step = stack[j].first[stack[j].second];
						[path appendFormat:@"%C%s", (unichar)0x1F, step->identifier().c_str()];
					}
					[self expandAncestorsOfPath:path];
					NSInteger row = [self rowForPath:path];
					if(row != -1)
					{
						[outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
						[outlineView scrollRowToVisible:row];
					}
					return;
				}
			}
		}
	}
}

- (BOOL)commitEditing
{
	if(!bundleItem || !bundleItemContent)
		return YES;

	[_sharedPropertiesViewController commitEditing];
	[_extraPropertiesViewController commitEditing];

	if(!propertiesChanged && bundleItemContent.isDocumentEdited == NO)
		return YES;

	plist::dictionary_t plist = plist::convert((__bridge CFPropertyListRef)_bundleItemProperties);

	std::string const content = to_s(bundleItemContent.content);
	item_info_t const& info = info_for(bundleItem->kind());

	plist::any_t parsedContent;
	if(info.plist_key == NULL_STR || oak::contains(std::begin(PlistItemKinds), std::end(PlistItemKinds), info.kind))
	{
		bool success = false;
		parsedContent = plist::parse_ascii(content, &success);
		if(!success)
		{
			NSAlert* alert = [NSAlert tmAlertWithMessageText:@"Error Parsing Property List" informativeText:@"The property list is not valid.\n\nUnfortunately I am presently unable to point to where the parser failed." buttons:@"OK", nil];
			[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){ }];
			return NO;
		}
	}

	if(info.plist_key == NULL_STR)
	{
		if(plist::dictionary_t const* plistSubset = plist::get<plist::dictionary_t>(&parsedContent))
		{
			std::vector<std::string> keys;
			if(info.kind == bundles::kItemTypeGrammar)
				keys = { "comment", "patterns", "repository", "injections" };
			else if(info.kind == bundles::kItemTypeTheme)
				keys = { "gutterSettings", "settings", "colorSpaceName" };

			for(auto const& key : keys)
			{
				if(plistSubset->find(key) != plistSubset->end())
						plist[key] = plistSubset->find(key)->second;
				else	plist.erase(key);
			}
		}
	}
	else
	{
		if(oak::contains(std::begin(PlistItemKinds), std::end(PlistItemKinds), info.kind))
				plist[info.plist_key] = parsedContent;
		else	plist[info.plist_key] = content;
	}

	switch(info.kind)
	{
		case bundles::kItemTypeGrammar:
			plist[bundles::kFieldGrammarExtension] = unwrap_array([_bundleItemProperties objectForKey:[NSString stringWithCxxString:bundles::kFieldGrammarExtension]], @"extension");
		break;

		case bundles::kItemTypeDragCommand:
			plist[bundles::kFieldDropExtension] = unwrap_array([_bundleItemProperties objectForKey:[NSString stringWithCxxString:bundles::kFieldDropExtension]], @"extension");
		break;
	}

	if(plist::equal(plist, bundleItem->plist()))
			changes.erase(bundleItem);
	else	changes[bundleItem] = plist;

	propertiesChanged = NO;
	[bundleItemContent markDocumentSaved];

	[self didChangeModifiedState];
	return YES;
}

- (void)saveDocument:(id)sender
{
	[self commitEditing];
	std::map<bundles::item_ptr, plist::dictionary_t> failedToSave;
	for(auto const& pair : changes)
	{
		auto item = pair.first;

		item->set_plist(pair.second);
		if(item->save())
		{
			[BundlesManager.sharedInstance reloadPath:[NSString stringWithCxxString:item->paths().front()]];
		}
		else
		{
			failedToSave.insert(pair);
		}
	}
	changes.swap(failedToSave);

	if(!changes.empty())
	{
		NSAlert* alert = [NSAlert tmAlertWithMessageText:@"Error Saving Bundle Item" informativeText:@"Sorry, but something went wrong while trying to save your changes. More info may be available via the console." buttons:@"OK", nil];
		[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){
			if(returnCode == NSAlertSecondButtonReturn) // Discard Changes
			{
				changes.clear();
				[self didChangeModifiedState];
			}
		}];
	}

	[self didChangeModifiedState];
}

// ========================
// = NSOutlineView support =
// ========================

- (NSInteger)outlineView:(NSOutlineView*)anOutlineView numberOfChildrenOfItem:(id)item
{
	be::entry_ptr entry = item ? ((BEOutlineEntry*)item)->_entry : bundles;
	return entry && entry->has_children() ? entry->children().size() : 0;
}

- (id)outlineView:(NSOutlineView*)anOutlineView child:(NSInteger)index ofItem:(id)item
{
	be::entry_ptr parent = item ? ((BEOutlineEntry*)item)->_entry : bundles;
	be::entry_ptr child = parent->children()[index];
	NSString* parentPath = item ? ((BEOutlineEntry*)item)->_path : @"";
	NSString* path = [parentPath length] == 0
		? [NSString stringWithCxxString:child->identifier()]
		: [parentPath stringByAppendingFormat:@"%C%s", (unichar)0x1F, child->identifier().c_str()];
	if(BEOutlineEntry* wrapper = entryCache[path])
		return wrapper;
	BEOutlineEntry* wrapper = [[BEOutlineEntry alloc] initWithEntry:child path:path];
	entryCache[path] = wrapper;
	return wrapper;
}

- (BOOL)outlineView:(NSOutlineView*)anOutlineView isItemExpandable:(id)item
{
	return ((BEOutlineEntry*)item)->_entry->has_children();
}

- (NSView*)outlineView:(NSOutlineView*)anOutlineView viewForTableColumn:(NSTableColumn*)tableColumn item:(id)item
{
	NSTableCellView* cell = [anOutlineView makeViewWithIdentifier:@"BundleItemCell" owner:self];
	if(!cell)
	{
		cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
		cell.identifier = @"BundleItemCell";

		NSImageView* imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 2, 16, 16)];
		NSTextField* textField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 0, 180, 20)];
		textField.editable = NO;
		textField.bordered = NO;
		textField.drawsBackground = NO;
		textField.autoresizingMask = NSViewWidthSizable;
		[cell addSubview:imageView];
		[cell addSubview:textField];
		cell.imageView = imageView;
		cell.textField = textField;
	}

	be::entry_ptr entry = ((BEOutlineEntry*)item)->_entry;

	static NSMutableParagraphStyle* paragraphStyle = nil;
	if(!paragraphStyle)
	{
		paragraphStyle = [[NSMutableParagraphStyle alloc] init];
		[paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
	}

	NSDictionary* attrs = @{
		NSForegroundColorAttributeName: entry->disabled() ? [NSColor tertiaryLabelColor] : [NSColor controlTextColor],
		NSParagraphStyleAttributeName:  paragraphStyle
	};
	cell.textField.attributedStringValue = [[NSAttributedString alloc] initWithString:[NSString stringWithCxxString:entry->name()] attributes:attrs];

	NSMenu* menu = [NSMenu new];
	if(bundles::item_ptr item = entry->represented_item())
	{
		NSString* imageName = entry->identifier() == "Menu Actions" ? @"MenuItem" : info_for(item->kind()).file;
		NSImage* srcImage   = [NSImage imageNamed:imageName inSameBundleAsClass:[self class]];

		cell.imageView.image = [NSImage imageWithSize:NSMakeSize(srcImage.size.width + 2, srcImage.size.height) flipped:NO drawingHandler:^BOOL(NSRect dstRect){
			[srcImage drawInRect:NSMakeRect(NSMinX(dstRect)+2, NSMinY(dstRect), NSWidth(dstRect)-2, NSHeight(dstRect)) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1];
			return YES;
		}];

		if(entry->identifier() == "Menu Actions")
			return cell;

		if(item->kind() == bundles::kItemTypeBundle)
		{
			NSMenuItem* menuItem = [menu addItemWithTitle:@"Export Bundle…" action:@selector(exportBundle:) keyEquivalent:@""];
			menuItem.target = self;
			menuItem.representedObject = [NSString stringWithCxxString:item->uuid()];
		}

		auto paths = item->paths();
		if(paths.size() == 1)
		{
			[menu addItem:[self createMenuItemForCxxPath:paths.front()]];
		}
		else if(paths.size() > 1)
		{
			NSMenu* submenu = [NSMenu new];
			for(std::string const& path : paths)
			{
				NSMenuItem* item = [self createMenuItemForCxxPath:path];
				item.title = [[NSString stringWithCxxString:path] stringByAbbreviatingWithTildeInPath];
				[submenu addItem:item];
			}

			NSMenuItem* submenuItem = [menu addItemWithTitle:@"Show in Finder" action:nil keyEquivalent:@""];
			submenuItem.submenu = submenu;
		}

		NSMenuItem* menuItem = [menu addItemWithTitle:@"Copy UUID" action:@selector(copyUUID:) keyEquivalent:@""];
		menuItem.target = self;
		menuItem.representedObject = [NSString stringWithCxxString:item->uuid()];
	}
	else
	{
		std::string const& path = entry->represented_path();
		if(path != NULL_STR)
		{
			cell.imageView.image = [TMFileReference imageForURL:[NSURL fileURLWithPath:[NSFileManager.defaultManager stringWithFileSystemRepresentation:path.data() length:path.size()]] size:NSMakeSize(16, 16)];
			[menu addItem:[self createMenuItemForCxxPath:path]];
		}
	}
	cell.menu = menu;
	return cell;
}

- (void)outlineViewItemDidExpand:(NSNotification*)notification
{
	if(BEOutlineEntry* wrapper = notification.userInfo[@"NSObject"])
		[expandedPaths addObject:wrapper->_path];
}

- (void)outlineViewItemDidCollapse:(NSNotification*)notification
{
	if(BEOutlineEntry* wrapper = notification.userInfo[@"NSObject"])
		[expandedPaths removeObject:wrapper->_path];
}

// Apply a validated drop: plist edits first (per item, so memory and disk
// stay consistent even if a later item fails), then the in-memory index.
// The caller computed index against the pre-drop listing.
- (BOOL)moveBundleItems:(NSArray*)uuidStrings toMenu:(oak::uuid_t const&)targetMenu atIndex:(size_t)index inBundle:(bundles::item_ptr const&)bundle
{
	if(!bundle || [uuidStrings count] == 0)
		return NO;

	std::vector<std::pair<oak::uuid_t, oak::uuid_t>> moves;
	for(NSString* uuidString in uuidStrings)
	{
		oak::uuid_t uuid = to_s(uuidString);
		bundles::item_ptr item = bundles::lookup(uuid);
		if(!item || item->bundle() != bundle)
			return NO;
		moves.emplace_back(uuid, item->parent_menu());
	}

	auto base = changes.find(bundle);
	plist::dictionary_t infoPlist = base != changes.end() ? base->second : bundle->plist();

	size_t at = index;
	for(auto const& move : moves)
	{
		// Removal is best-effort: items never explicitly listed (fresh
		// leftovers) or a missing top-level array have no entry to remove.
		// Insertion gates the move — it fails only for unknown menus.
		std::string const itemStr = to_s(move.first), oldStr = to_s(move.second), newStr = to_s(targetMenu);
		bundles::remove_uuid_from_main_menu(infoPlist, to_s(bundle->uuid()), oldStr, itemStr);
		if(!bundles::insert_uuid_into_main_menu_at_index(infoPlist, to_s(bundle->uuid()), newStr, itemStr, at++))
			return NO;
		bundles::remove_from_menu(move.second, move.first);
		bundles::add_to_menu_at_index(targetMenu, move.first, at - 1);
	}

	if(!plist::equal(infoPlist, bundle->plist()))
		changes[bundle] = infoPlist;
	[self didChangeModifiedState];
	return YES;
}

// The drop parent is the outline parent for Above drops (or the row itself
// for On drops). Only menu contexts accept: the Menu Actions root (addressed
// by the bundle uuid) or a submenu. Everything else — kind groups, Other
// Actions, Support files, bundle rows — keeps kind-driven placement.
- (BOOL)dropTargetForParent:(BEOutlineEntry*)parent anchor:(BEOutlineEntry*)anchor appending:(BOOL)appending intoMenu:(oak::uuid_t*)outMenu atIndex:(size_t*)outIndex
{
	if(!parent)
		return NO;

	be::entry_ptr entry = parent->_entry;
	bundles::item_ptr represented = entry->represented_item();
	oak::uuid_t menu;
	if(entry->identifier() == "Menu Actions" && represented && represented->kind() == bundles::kItemTypeBundle)
		menu = represented->uuid();
	else if(represented && represented->kind() == bundles::kItemTypeMenu)
		menu = represented->uuid();
	else
		return NO;

	size_t index = entry->children().size();
	if(!appending && anchor)
	{
		for(size_t i = 0; i < entry->children().size(); ++i)
		{
			if(entry->children()[i]->identifier() == anchor->_entry->identifier())
			{
				index = i;
				break;
			}
		}
	}
	*outMenu = menu;
	*outIndex = index;
	return YES;
}

- (NSArray*)draggedUUIDsFromPasteboard:(NSPasteboard*)pboard inBundle:(bundles::item_ptr const&)bundle
{
	NSArray* strings = [pboard propertyListForType:kBundleItemUUIDsPboardType];
	if(![strings isKindOfClass:[NSArray class]] || [strings count] == 0)
		return nil;
	NSMutableArray* uuids = [NSMutableArray array];
	for(id value in strings)
	{
		if(![value isKindOfClass:[NSString class]])
			return nil;
		bundles::item_ptr item = bundles::lookup(to_s((NSString*)value));
		if(!item || !(item->kind() & bundles::kItemTypeMenuTypes) || item->bundle() != bundle)
			return nil;
		[uuids addObject:value];
	}
	return uuids;
}

- (BOOL)outlineView:(NSOutlineView*)anOutlineView writeItems:(NSArray*)items toPasteboard:(NSPasteboard*)pboard
{
	NSMutableArray* uuids = [NSMutableArray array];
	for(BEOutlineEntry* wrapper in items)
	{
		bundles::item_ptr item = wrapper->_entry->represented_item();
		if(!item || !(item->kind() & bundles::kItemTypeMenuTypes))
			return NO;
		[uuids addObject:[NSString stringWithCxxString:to_s(item->uuid())]];
	}
	if([uuids count] == 0)
		return NO;
	[pboard declareTypes:@[ kBundleItemUUIDsPboardType ] owner:self];
	[pboard setPropertyList:uuids forType:kBundleItemUUIDsPboardType];
	return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView*)anOutlineView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	if(info.draggingSource != anOutlineView)
		return NSDragOperationNone;

	BEOutlineEntry* anchor = row < [anOutlineView numberOfRows] ? [anOutlineView itemAtRow:row] : nil;
	BEOutlineEntry* parent = nil;
	BOOL appending = NO;
	if(operation == NSTableViewDropOn)
	{
		if(!anchor)
			return NSDragOperationNone;
		parent = anchor;
		appending = YES;
	}
	else
	{
		if(row >= [anOutlineView numberOfRows])
		{
			// Below the last row: append to that row’s parent menu.
			if([anOutlineView numberOfRows] == 0)
				return NSDragOperationNone;
			anchor = [anOutlineView itemAtRow:[anOutlineView numberOfRows] - 1];
			parent = [anOutlineView parentForItem:anchor];
			appending = YES;
		}
		else
		{
			if(!anchor)
				return NSDragOperationNone;
			parent = [anOutlineView parentForItem:anchor];
		}
	}

	oak::uuid_t menu;
	size_t index = 0;
	if(![self dropTargetForParent:parent anchor:appending ? nil : anchor appending:appending intoMenu:&menu atIndex:&index])
		return NSDragOperationNone;

	// The payload names the bundle: submenu uuids are not bundles, so the
	// target menu alone cannot identify it.
	bundles::item_ptr bundle;
	NSArray* strings = [info.draggingPasteboard propertyListForType:kBundleItemUUIDsPboardType];
	if([strings isKindOfClass:[NSArray class]] && [strings count] != 0 && [strings[0] isKindOfClass:[NSString class]])
	{
		if(bundles::item_ptr first = bundles::lookup(to_s((NSString*)strings[0])))
			bundle = first->bundle();
	}
	if(!bundle)
		return NSDragOperationNone;

	// The target menu must belong to the payload’s bundle.
	BOOL sameBundle = (menu == bundle->uuid());
	if(!sameBundle)
	{
		if(bundles::item_ptr menuItem = bundles::lookup(menu))
			sameBundle = menuItem->kind() == bundles::kItemTypeMenu && menuItem->bundle() == bundle;
	}
	if(!sameBundle)
		return NSDragOperationNone;

	NSArray* uuids = [self draggedUUIDsFromPasteboard:info.draggingPasteboard inBundle:bundle];
	if(!uuids)
		return NSDragOperationNone;

	// Dropping a single item onto its own slot is a no-op, not a move.
	if([uuids count] == 1 && parent)
	{
		bundles::item_ptr item = bundles::lookup(to_s((NSString*)uuids[0]));
		if(item && item->parent_menu() == menu)
		{
			size_t current = 0;
			bool found = false;
			for(auto const& sibling : parent->_entry->children())
			{
				if(sibling->represented_item() && sibling->represented_item()->uuid() == item->uuid())
				{
					found = true;
					break;
				}
				++current;
			}
			if(found && (appending ? current + 1 >= parent->_entry->children().size() : index == current))
				return NSDragOperationNone;
		}
	}
	return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView*)anOutlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)targetItem childIndex:(NSInteger)index
{
	BEOutlineEntry* parent = nil;
	BOOL appending = NO;
	if(index == NSOutlineViewDropOnItemIndex)
	{
		parent = targetItem;
		appending = YES;
	}
	else
	{
		parent = targetItem;
	}

	oak::uuid_t menu;
	size_t at = 0;
	if(![self dropTargetForParent:parent anchor:nil appending:appending intoMenu:&menu atIndex:&at])
		return NO;
	if(!appending)
		at = index < 0 ? at : (size_t)index;

	// Resolve the bundle through the payload (submenus are not bundles).
	bundles::item_ptr bundle;
	NSArray* strings = [info.draggingPasteboard propertyListForType:kBundleItemUUIDsPboardType];
	if([strings isKindOfClass:[NSArray class]] && [strings count] != 0 && [strings[0] isKindOfClass:[NSString class]])
	{
		if(bundles::item_ptr first = bundles::lookup(to_s((NSString*)strings[0])))
			bundle = first->bundle();
	}
	NSArray* uuids = bundle ? [self draggedUUIDsFromPasteboard:info.draggingPasteboard inBundle:bundle] : nil;
	if(!uuids)
		return NO;

	// Adjust for dragged rows above the drop point within the same menu.
	if(!appending)
	{
		be::entry_ptr entry = parent->_entry;
		size_t above = 0;
		for(size_t i = 0; i < (size_t)index && i < entry->children().size(); ++i)
		{
			if(bundles::item_ptr sibling = entry->children()[i]->represented_item())
			{
				NSString* siblingUUID = [NSString stringWithCxxString:to_s(sibling->uuid())];
				if([uuids containsObject:siblingUUID])
					++above;
			}
		}
		at = at >= above ? at - above : 0;
	}

	if(![self moveBundleItems:uuids toMenu:menu atIndex:at inBundle:bundle])
		return NO;

	if(bundles::item_ptr first = bundles::lookup(to_s((NSString*)uuids[0])))
		[self revealBundleItem:first];
	return YES;
}

- (NSMenuItem*)createMenuItemForCxxPath:(std::string const&)path
{
	NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Show “%@” in Finder", [NSString stringWithCxxString:path::display_name(path)]] action:@selector(showInFinder:) keyEquivalent:@""];
	item.target = self;
	item.representedObject = [NSString stringWithCxxString:path];
	return item;
}

- (void)copyUUID:(NSMenuItem*)sender
{
	[[NSPasteboard generalPasteboard] declareTypes:@[ NSPasteboardTypeString ] owner:nil];
	[[NSPasteboard generalPasteboard] setString:[sender representedObject] forType:NSPasteboardTypeString];
}

- (void)exportBundle:(id)sender
{
	oak::uuid_t const uuid = to_s((NSString*)[sender representedObject]);
	if(bundles::item_ptr bundle = bundles::lookup(uuid))
	{
		std::string name = bundle->name();
		std::replace(name.begin(), name.end(), '/', ':');
		std::replace(name.begin(), name.end(), '.', '_');

		NSSavePanel* savePanel = [NSSavePanel savePanel];
		[savePanel setNameFieldStringValue:[NSString stringWithCxxString:name + ".tmbundle"]];
		[savePanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
			if(result == NSModalResponseOK)
			{
				NSString* path = [[savePanel.URL filePathURL] path];
				if([NSFileManager.defaultManager fileExistsAtPath:path])
				{
					NSError* error;
					if(![NSFileManager.defaultManager removeItemAtPath:path error:&error])
					{
						[self.window presentError:error];
						return;
					}
				}

				std::string const dest = to_s(path);
				bool res = true;
				for(auto const& item : bundles::query(bundles::kFieldAny, NULL_STR, scope::wildcard, ~(bundles::kItemTypeMenu|bundles::kItemTypeMenuItemSeparator), uuid, false, true, false))
					res = res && item->save_to(dest);

				if(!res)
				{
					NSAlert* alert        = [[NSAlert alloc] init];
					alert.messageText     = @"Failed to Save Bundle";
					alert.informativeText = [NSString stringWithFormat:@"Unknown error while saving bundle as “%@”.", [path stringByAbbreviatingWithTildeInPath]];
					[alert addButtonWithTitle:@"OK"];
					[alert runModal];
				}
			}
		}];
	}
}

- (void)showInFinder:(id)sender
{
	if(![sender respondsToSelector:@selector(representedObject)])
		return;
	if(NSString* path = [sender representedObject])
		[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:path] ]];
}

// ===================
// = Outline selection =
// ===================

- (void)outlineSelectionDidChange:(NSNotification*)notification
{
	NSInteger row = [outlineView selectedRow];
	if(row != -1)
	{
		if(bundles::item_ptr item = ((BEOutlineEntry*)[outlineView itemAtRow:row])->_entry->represented_item())
		{
			if(item->kind() != bundles::kItemTypeMenu && item->kind() != bundles::kItemTypeMenuItemSeparator)
				[self setBundleItem:item];
		}
	}
}

// =======================
// = Setting Bundle Item =
// =======================

- (void)observeValueForKeyPath:(NSString*)aKeyPath ofObject:(id)anObject change:(NSDictionary*)someChange context:(void*)context
{
	if(![aKeyPath isEqualToString:@"documentEdited"])
		propertiesChanged = YES;
	[self didChangeModifiedState];
}

- (void)setBundleItemProperties:(NSMutableDictionary*)someProperties
{
	static std::string const BindingKeys[] = { bundles::kFieldIsDisabled, bundles::kFieldName, bundles::kFieldKeyEquivalent, bundles::kFieldTabTrigger, bundles::kFieldScopeSelector, bundles::kFieldSemanticClass, bundles::kFieldContentMatch, bundles::kFieldHideFromUser, bundles::kFieldDropExtension, bundles::kFieldGrammarExtension, bundles::kFieldGrammarFirstLineMatch, bundles::kFieldGrammarScope, bundles::kFieldGrammarInjectionSelector, "beforeRunningCommand", "input", "inputFormat", "outputLocation", "outputFormat", "outputCaret", "autoScrollOutput", "contactName", "contactEmailRot13", "description", "disableAutoIndent", "useGlobalClipboard", "author", "comment" };

	NSMutableDictionary* oldProperties = _bundleItemProperties;
	_bundleItemProperties = someProperties;
	for(auto const& str : BindingKeys)
	{
		NSString* key = [NSString stringWithCxxString:str];
		[oldProperties removeObserver:self forKeyPath:key];
		[someProperties addObserver:self forKeyPath:key options:0 context:NULL];
	}
	propertiesChanged = NO;
}

static NSMutableDictionary* DictionaryForBundleItem (bundles::item_ptr const& aBundleItem)
{
	NSMutableDictionary* res = ns::to_mutable_dictionary(aBundleItem->plist());
	switch(info_for(aBundleItem->kind()).kind)
	{
		case bundles::kItemTypeCommand:
		{
			bundle_command_t cmd = parse_command(aBundleItem);

			struct { NSString* key; int index; NSArray* array; } const popups[] =
			{
				{ @"beforeRunningCommand",  cmd.pre_exec,      @[ @"nop", @"saveActiveFile", @"saveModifiedFiles" ] },
				{ @"input",                 cmd.input,         @[ @"selection", @"document", @"scope", @"line", @"word", @"character", @"none" ] },
				{ @"inputFormat",           cmd.input_format,  @[ @"text", @"xml" ] },
				{ @"outputLocation",        cmd.output,        @[ @"replaceInput", @"replaceDocument", @"atCaret", @"afterInput", @"newWindow", @"toolTip", @"discard", @"replaceSelection" ] },
				{ @"outputFormat",          cmd.output_format, @[ @"text", @"snippet", @"html", @"completionList" ] },
				{ @"outputCaret",           cmd.output_caret,  @[ @"afterOutput", @"selectOutput", @"interpolateByChar", @"interpolateByLine", @"heuristic" ] },
			};

			[res removeObjectForKey:@"output"];
			[res removeObjectForKey:@"dontFollowNewOutput"];
			[res setObject:@2 forKey:@"version"];
			if(cmd.auto_scroll_output)
				[res setObject:@YES forKey:@"autoScrollOutput"];
			for(auto const& popup : popups)
				[res setObject:[popup.array objectAtIndex:popup.index] forKey:popup.key];
		}
		break;

		case bundles::kItemTypeGrammar:
		{
			[res setObject:wrap_array(aBundleItem->values_for_field(bundles::kFieldGrammarExtension), @"extension") forKey:[NSString stringWithCxxString:bundles::kFieldGrammarExtension]];
		}
		break;

		case bundles::kItemTypeDragCommand:
		{
			[res setObject:wrap_array(aBundleItem->values_for_field(bundles::kFieldDropExtension), @"extension") forKey:[NSString stringWithCxxString:bundles::kFieldDropExtension]];
		}
		break;
	}
	return res;
}

static NSMutableDictionary* DictionaryForPropertyList (plist::dictionary_t const& plist, bundles::item_ptr const& aBundleItem)
{
	NSMutableDictionary* res = ns::to_mutable_dictionary(plist);
	switch(info_for(aBundleItem->kind()).kind)
	{
		case bundles::kItemTypeGrammar:
			[res setObject:wrap_array(aBundleItem->values_for_field(bundles::kFieldGrammarExtension), @"extension") forKey:[NSString stringWithCxxString:bundles::kFieldGrammarExtension]];
		break;

		case bundles::kItemTypeDragCommand:
			[res setObject:wrap_array(aBundleItem->values_for_field(bundles::kFieldDropExtension), @"extension") forKey:[NSString stringWithCxxString:bundles::kFieldDropExtension]];
		break;
	}
	return res;
}

- (bundles::item_ptr const&)bundleItem
{
	return bundleItem;
}

- (BOOL)window:(NSWindow*)aWindow shouldDragDocumentWithEvent:(NSEvent*)anEvent from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard*)aPasteboard
{
	return bundleItem && bundleItem->paths().size() == 1;
}

- (BOOL)window:(NSWindow*)aWindow shouldPopUpDocumentPathMenu:(NSMenu*)menu
{
	if(!bundleItem)
		return NO;

	auto const& paths = bundleItem->paths();
	if(paths.size() == 1)
		return YES;

	[menu removeAllItems];
	for(std::string const& path : paths)
	{
		NSMenuItem* item = [self createMenuItemForCxxPath:path];
		item.title = [[NSString stringWithCxxString:path] stringByAbbreviatingWithTildeInPath];
		item.state = NSControlStateValueOff;
		[menu addItem:item];
	}
	return YES;
}

- (void)setBundleItem:(bundles::item_ptr const&)aBundleItem
{
	if(bundleItem == aBundleItem)
		return;

	[self commitEditing];

	if(bundleItemContent)
		[bundleItemContent removeObserver:self forKeyPath:@"documentEdited"];

	bundleItem        = aBundleItem;
	bundleItemContent = nil;

	std::map<bundles::item_ptr, plist::dictionary_t>::const_iterator it = changes.find(bundleItem);
	self.bundleItemProperties = it != changes.end() ? DictionaryForPropertyList(it->second, bundleItem) : DictionaryForBundleItem(bundleItem);

	item_info_t const& info = info_for(bundleItem->kind());

	[[self window] setTitle:[NSString stringWithCxxString:bundleItem->name_with_bundle()]];
	NSString* bundleItemTitle = [NSString stringWithCxxString:bundleItem->name()];

	auto const& paths = bundleItem->paths();
	if(paths.size() == 1)
	{
		self.window.representedURL = [NSURL fileURLWithPath:[NSString stringWithCxxString:paths.front()]];
	}
	else
	{
		self.window.representedFilename = NSHomeDirectory();
		[self.window standardWindowButton:NSWindowDocumentIconButton].image = [NSWorkspace.sharedWorkspace iconForFileType:[NSString stringWithCxxString:info.file_type]];
	}

	plist::dictionary_t const& plist = it != changes.end() ? it->second : bundleItem->plist();
	if(info.plist_key == NULL_STR)
	{
		std::vector<std::string> keys;
		if(info.kind == bundles::kItemTypeGrammar)
			keys = { "comment", "patterns", "repository", "injections" };
		else if(info.kind == bundles::kItemTypeTheme)
			keys = { "gutterSettings", "settings", "colorSpaceName" };

		plist::dictionary_t plistSubset;
		for(auto const& key : keys)
		{
			if(plist.find(key) != plist.end())
				plistSubset[key] = plist.find(key)->second;
		}
		bundleItemContent = [OakDocument documentWithString:to_ns(to_s(plistSubset, plist::kPreferSingleQuotedStrings, PlistKeySortOrder())) fileType:to_ns(info.grammar) customName:bundleItemTitle];
	}
	else if(oak::contains(std::begin(PlistItemKinds), std::end(PlistItemKinds), info.kind))
	{
		if(plist.find(info.plist_key) != plist.end())
			bundleItemContent = [OakDocument documentWithString:to_ns(to_s(plist.find(info.plist_key)->second, plist::kPreferSingleQuotedStrings, PlistKeySortOrder())) fileType:to_ns(info.grammar) customName:bundleItemTitle];
	}
	else
	{
		std::string str;
		if(plist::get_key_path(plist, info.plist_key, str))
		{
			if(info.kind == bundles::kItemTypeCommand || info.kind == bundles::kItemTypeDragCommand)
				command::fix_shebang(&str);
			bundleItemContent = [OakDocument documentWithString:to_ns(str) fileType:to_ns(info.grammar) customName:bundleItemTitle];
		}
	}

	bundleItemContent = bundleItemContent ?: [OakDocument documentWithString:@"" fileType:nil customName:bundleItemTitle];
	documentView.document = bundleItemContent;
	[bundleItemContent addObserver:self forKeyPath:@"documentEdited" options:0 context:nullptr];

	_propertiesHeightConstraint.active = NO;
	[_propertiesViewController.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

	_sharedPropertiesViewController = nil;
	_extraPropertiesViewController  = nil;

	NSView* contentView = _propertiesViewController.view;
	CGFloat maxY = NSHeight(contentView.frame);

	if(info.kind != bundles::kItemTypeBundle)
	{
		_sharedPropertiesViewController = [[PropertiesViewController alloc] initWithName:@"SharedProperties"];
		[_sharedPropertiesViewController setProperties:_bundleItemProperties];

		NSView* propertiesView = [_sharedPropertiesViewController view];
		maxY -= NSHeight(propertiesView.frame);
		CGFloat indent = _maxLabelWidth - _sharedPropertiesViewController.labelWidth;
		[propertiesView setFrame:NSMakeRect(indent, maxY, NSWidth(contentView.frame) - indent, NSHeight(propertiesView.frame))];
		[contentView addSubview:propertiesView];
	}

	if(info.view_controller)
	{
		_extraPropertiesViewController = [[PropertiesViewController alloc] initWithName:info.view_controller];
		[_extraPropertiesViewController setProperties:_bundleItemProperties];

		NSView* extraView = [_extraPropertiesViewController view];
		maxY -= NSHeight(extraView.frame);
		CGFloat indent = _maxLabelWidth - _extraPropertiesViewController.labelWidth;
		[extraView setFrame:NSMakeRect(indent, maxY, NSWidth(contentView.frame) - indent, NSHeight(extraView.frame))];
		[contentView addSubview:extraView];
	}

	_propertiesHeightConstraint.constant = NSHeight(contentView.frame) + -maxY;

	if(maxY < 0)
	{
		NSRect frame = NSOffsetRect(contentView.window.frame, 0, maxY);
		frame.size.height += -maxY;
		[contentView.window setFrame:frame display:YES animate:YES];
	}

	_propertiesHeightConstraint.active = YES;
}

static NSString* DescriptionForChanges (std::map<bundles::item_ptr, plist::dictionary_t> const& changes)
{
	NSString* res = [NSString stringWithCxxString:text::format("Do you want to save the changes made to %zu items?", changes.size())];
	if(changes.size() == 1)
	{
		bundles::item_ptr item = changes.begin()->first;
		NSString* name = [NSString stringWithCxxString:item->name()];
		if(item->kind() == bundles::kItemTypeBundle)
		{
			res = [NSString stringWithFormat:@"Do you want to save the changes made to the bundle named “%@”?", name];
		}
		else
		{
			NSString* bundleName = [NSString stringWithCxxString:item->bundle()->name()];
			NSString* type = [info_for(item->kind()).file lowercaseString];
			res = [NSString stringWithFormat:@"Do you want to save the changes made to the %@ item named “%@” in the “%@” bundle?", type, name, bundleName];
		}
	}
	return res;
}

- (BOOL)windowShouldClose:(id)sender
{
	[self commitEditing];
	if(changes.empty())
		return YES;

	NSAlert* alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSAlertStyleWarning];
	[alert setMessageText:DescriptionForChanges(changes)];
	[alert setInformativeText:@"Your changes will be lost if you don’t save them."];
	[alert addButtons:@"Save", @"Cancel", @"Don’t Save", nil];
	[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){
		if(returnCode != NSAlertSecondButtonReturn) // Not "Cancel"
		{
			if(returnCode == NSAlertFirstButtonReturn) // "Save"
				[self saveDocument:self];
			else if(returnCode == NSAlertThirdButtonReturn) // "Don’t Save"
				changes.clear();
			[self close];
		}
	}];
	return NO;
}

// ====================
// = Running Commands =
// ====================

- (void)updateEnvironment:(std::map<std::string, std::string>&)res forCommand:(OakCommand*)aCommand
{
	[documentView.textView updateEnvironment:res];
}
@end
