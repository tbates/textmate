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

	NSSplitView* columnsView;
	NSScrollView* columnsScrollView;
	NSMutableArray* paneTables; // NSTableView per Miller pane
	std::vector<std::vector<be::entry_ptr>> paneEntries;
	OakDocumentView* documentView;

	be::entry_ptr bundles;
	std::map<bundles::item_ptr, plist::dictionary_t> changes;

	BOOL propertiesChanged;

	bundles::item_ptr bundleItem;
	OakDocument* bundleItemContent;
}
- (void)didChangeBundleItems;
- (void)didChangeModifiedState;
- (void)resetPanes;
- (void)appendPaneWithEntries:(std::vector<be::entry_ptr> const&)entries;
- (void)truncatePanesAfter:(NSInteger)pane;
- (void)layoutPanes;
- (NSInteger)columnIndexForTableView:(NSTableView*)tableView;
- (void)selectIdentifierPath:(NSArray*)path scroll:(BOOL)scroll;
- (be::entry_ptr)selectedEntryInPane:(NSInteger)pane;
- (oak::uuid_t)menuContextForPane:(NSInteger)pane;
- (size_t)rowForItemUUID:(oak::uuid_t const&)uuid inPane:(NSInteger)pane;
- (void)updateEditedItemFromSelection;
- (NSArray*)identifierPathForItem:(bundles::item_ptr const&)anItem;
- (BOOL)moveBundleItems:(NSArray*)uuidStrings toMenu:(oak::uuid_t const&)targetMenu atIndex:(size_t)index inBundle:(bundles::item_ptr const&)bundle;
- (NSView*)cellViewForEntry:(be::entry_ptr const&)entry inTableView:(NSTableView*)tableView;
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
		[self resetPanes];

		if([paneTables count] != 0)
			[self.window makeFirstResponder:paneTables[0]];
	}
	return self;
}

static CGFloat const kPaneWidth = 190;

- (NSViewController*)browserViewController
{
	if(!_browserViewController)
	{
		_browserViewController = [[NSViewController alloc] initWithNibName:nil bundle:nil];

		columnsScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		columnsScrollView.hasHorizontalScroller = YES;
		columnsScrollView.hasVerticalScroller = NO;
		columnsScrollView.autohidesScrollers = YES;

		columnsView = [[NSSplitView alloc] initWithFrame:NSZeroRect];
		columnsView.vertical = YES;
		columnsView.dividerStyle = NSSplitViewDividerStyleThin;
		columnsView.autosaveName = @"Bundle Editor Columns";
		columnsView.autoresizingMask = NSViewHeightSizable;

		columnsScrollView.documentView = columnsView;
		_browserViewController.view = columnsScrollView;

		paneTables = [NSMutableArray array];
		[self resetPanes];
	}
	return _browserViewController;
}

// Miller columns: pane 0 lists bundles; each pane shows the children of the
// previous pane’s selection, so the panes slide along the selection path for
// arbitrarily deep menu nesting.
- (NSTableView*)newPaneTableView
{
	NSScrollView* scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kPaneWidth, 100)];
	scrollView.hasVerticalScroller = YES;
	scrollView.autohidesScrollers = YES;

	NSTableView* tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
	NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"Items"];
	column.resizingMask = NSTableColumnAutoresizingMask;
	[tableView addTableColumn:column];
	tableView.headerView = nil;
	tableView.delegate = self;
	tableView.dataSource = self;
	tableView.allowsEmptySelection = YES;
	[tableView registerForDraggedTypes:@[ kBundleItemUUIDsPboardType ]];
	[tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];

	scrollView.documentView = tableView;
	[columnsView addArrangedSubview:scrollView];
	[paneTables addObject:tableView];
	[self layoutPanes];
	return tableView;
}

- (void)layoutPanes
{
	NSRect frame = columnsView.frame;
	frame.size.width = kPaneWidth * [paneTables count];
	columnsView.frame = frame;
	for(NSTableView* tableView in paneTables)
		tableView.allowsMultipleSelection = (tableView == [paneTables lastObject]);
	[columnsScrollView scrollToEndOfDocument:nil];
}

- (void)resetPanes
{
	if(!columnsView || !paneTables)
	{
		paneEntries.clear();
		return;
	}
	for(NSTableView* tableView in paneTables)
		[tableView.enclosingScrollView removeFromSuperview];
	[paneTables removeAllObjects];
	paneEntries.clear();
	if(bundles)
		[self appendPaneWithEntries:bundles->children()];
}

- (void)appendPaneWithEntries:(std::vector<be::entry_ptr> const&)entries
{
	NSTableView* tableView = [self newPaneTableView];
	paneEntries.push_back(entries);
	[tableView reloadData];
	[self layoutPanes];
}

- (void)truncatePanesAfter:(NSInteger)pane
{
	while((NSInteger)[paneTables count] > pane + 1)
	{
		NSTableView* tableView = [paneTables lastObject];
		[tableView.enclosingScrollView removeFromSuperview];
		[paneTables removeLastObject];
		paneEntries.pop_back();
	}
	[self layoutPanes];
}

// The editing panes follow the deepest selection; rows without an editable
// item (menus, groups, Support files) leave the current document in place,
// exactly like the old browser’s deepest column did.
- (void)updateEditedItemFromSelection
{
	for(NSInteger pane = [paneTables count] - 1; pane >= 0; --pane)
	{
		if(be::entry_ptr entry = [self selectedEntryInPane:pane])
		{
			if(bundles::item_ptr item = entry->represented_item())
			{
				if(item->kind() != bundles::kItemTypeMenu && item->kind() != bundles::kItemTypeMenuItemSeparator)
					[self setBundleItem:item];
				return;
			}
		}
	}
}

- (be::entry_ptr)selectedEntryInPane:(NSInteger)pane
{
	if(pane < 0 || pane >= (NSInteger)[paneTables count])
		return be::entry_ptr();
	NSInteger row = [paneTables[pane] selectedRow];
	if(row == -1 || row >= (NSInteger)paneEntries[pane].size())
		return be::entry_ptr();
	return paneEntries[pane][row];
}

// Selection restore walks one identifier path (first selection per pane), so
// rebuilds keep the user where they were. Selecting a row cascades: panes
// past it are truncated and a child pane appended when it has children.
- (void)selectIdentifierPath:(NSArray*)path scroll:(BOOL)scroll
{
	for(NSInteger pane = 0; pane < (NSInteger)[path count]; ++pane)
	{
		if(pane >= (NSInteger)[paneTables count])
			break;
		NSString* identifier = path[pane];
		for(size_t row = 0; row < paneEntries[pane].size(); ++row)
		{
			if(paneEntries[pane][row]->identifier() == to_s(identifier))
			{
				[paneTables[pane] selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
				if(scroll && pane == (NSInteger)[path count] - 1)
					[paneTables[pane] scrollRowToVisible:row];
				break;
			}
		}
	}
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
	NSMutableArray* savedPath = [NSMutableArray array];
	for(NSInteger pane = 0; pane < (NSInteger)[paneTables count]; ++pane)
	{
		NSInteger row = [paneTables[pane] selectedRow];
		if(row == -1 || row >= (NSInteger)paneEntries[pane].size())
			break;
		[savedPath addObject:[NSString stringWithCxxString:paneEntries[pane][row]->identifier()]];
	}

	bundles = be::bundle_entries();
	[self resetPanes];
	[self selectIdentifierPath:savedPath scroll:NO];
}

// Identifier path (bundle, component, item) locating anItem in the tree, or
// nil when it is not on display. Drives reveal without any widget state.
- (NSArray*)identifierPathForItem:(bundles::item_ptr const&)anItem
{
	std::vector<be::entry_ptr> const& allBundles = bundles->children();
	iterate(bundle, allBundles)
	{
		if((anItem->bundle() ?: anItem) != (*bundle)->represented_item())
			continue;

		NSMutableArray* base = [NSMutableArray arrayWithObject:[NSString stringWithCxxString:(*bundle)->identifier()]];
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
					NSMutableArray* path = [base mutableCopy];
					for(size_t j = 0; j < stack.size(); ++j)
						[path addObject:[NSString stringWithCxxString:stack[j].first[stack[j].second]->identifier()]];
					return path;
				}
			}
		}
	}
	return nil;
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

	// Walk the selection path for the deepest menu context: a submenu becomes
	// the parent, a plain leaf means “below this item” when it already lives
	// in the context menu. Anything else — bundle-only, kind groups, Support
	// files — keeps the legacy behavior.
	oak::uuid_t targetMenu;
	oak::uuid_t afterItem;
	for(NSInteger pane = 1; pane < (NSInteger)[paneTables count]; ++pane)
	{
		be::entry_ptr entry = [self selectedEntryInPane:pane];
		if(!entry)
			break;
		if(bundles::item_ptr represented = entry->represented_item())
		{
			if(represented->kind() == bundles::kItemTypeMenu)
			{
				targetMenu = represented->uuid();
				afterItem = oak::uuid_t();
			}
			else if(entry->has_children())
			{
				return;
			}
			else if(targetMenu && represented->parent_menu() == targetMenu)
			{
				afterItem = represented->uuid();
			}
			else if(targetMenu)
			{
				afterItem = oak::uuid_t();
			}
			else
			{
				return;
			}
		}
		else if(entry->identifier() == "Menu Actions")
		{
			// Reached only at pane 1 with the bundle behind it.
			if(be::entry_ptr bundleEntry = [self selectedEntryInPane:0])
			{
				if(bundles::item_ptr bundleItem = bundleEntry->represented_item())
					targetMenu = bundleItem->uuid();
			}
			afterItem = oak::uuid_t();
		}
		else
		{
			return;
		}
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
	if(be::entry_ptr selected = [self selectedEntryInPane:0])
		bundle = selected->represented_item();
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
		NSInteger deepPane = -1;
		for(NSInteger pane = [paneTables count] - 1; pane >= 0; --pane)
		{
			if([paneTables[pane] selectedRow] != -1)
			{
				deepPane = pane;
				break;
			}
		}
		if(deepPane != -1)
		{
			for(auto const& entry : paneEntries[deepPane])
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

	[self selectIdentifierPath:[self identifierPathForItem:anItem] scroll:YES];
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

// =====================
// = Column data source =
// =====================

- (NSInteger)columnIndexForTableView:(NSTableView*)tableView
{
	NSUInteger index = [paneTables indexOfObject:tableView];
	return index == NSNotFound ? -1 : (NSInteger)index;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
	NSInteger pane = [self columnIndexForTableView:tableView];
	if(pane == -1 || pane >= (NSInteger)paneEntries.size())
		return 0;
	return paneEntries[pane].size();
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
	NSInteger pane = [self columnIndexForTableView:tableView];
	if(pane == -1 || pane >= (NSInteger)paneEntries.size() || row < 0 || row >= (NSInteger)paneEntries[pane].size())
		return nil;
	return [self cellViewForEntry:paneEntries[pane][row] inTableView:tableView];
}

- (NSView*)cellViewForEntry:(be::entry_ptr const&)entry inTableView:(NSTableView*)tableView
{
	NSTableCellView* cell = [tableView makeViewWithIdentifier:@"BundleItemCell" owner:self];
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

// Menu owning a pane’s rows: the selected entry of the previous pane names it
// (Menu Actions root → bundle uuid, submenu → its uuid). Anything else (kind
// groups, Other Actions, Support files, bundles, nothing) is not a menu.
- (oak::uuid_t)menuContextForPane:(NSInteger)pane
{
	if(pane < 1 || pane >= (NSInteger)[paneTables count])
		return oak::uuid_t();
	be::entry_ptr container = [self selectedEntryInPane:pane - 1];
	if(!container)
		return oak::uuid_t();
	if(bundles::item_ptr represented = container->represented_item())
	{
		if(represented->kind() == bundles::kItemTypeMenu)
			return represented->uuid();
		if(container->identifier() == "Menu Actions" && represented->kind() == bundles::kItemTypeBundle)
			return represented->uuid();
	}
	return oak::uuid_t();
}

// Position of an item among a pane’s rows by uuid, or SIZE_MAX.
- (size_t)rowForItemUUID:(oak::uuid_t const&)uuid inPane:(NSInteger)pane
{
	if(pane < 0 || pane >= (NSInteger)[paneTables count])
		return SIZE_MAX;
	for(size_t row = 0; row < paneEntries[pane].size(); ++row)
	{
		if(bundles::item_ptr item = paneEntries[pane][row]->represented_item())
		{
			if(item->uuid() == uuid)
				return row;
		}
	}
	return SIZE_MAX;
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

// Only the last pane drags out, and only menu-type rows travel: bundles,
// menus, groups, Support files, and separators refuse the whole drag.
- (BOOL)tableView:(NSTableView*)tableView writeRowsWithIndexes:(NSIndexSet*)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	NSInteger pane = [self columnIndexForTableView:tableView];
	if(pane == -1 || pane != (NSInteger)[paneTables count] - 1)
		return NO;
	NSMutableArray* uuids = [NSMutableArray array];
	for(size_t row = [rowIndexes firstIndex]; row != NSNotFound; row = [rowIndexes indexGreaterThanIndex:row])
	{
		if(row >= paneEntries[pane].size())
			return NO;
		bundles::item_ptr item = paneEntries[pane][row]->represented_item();
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

// Drops land in two places: between last-pane rows (reorder within that
// pane’s menu) or onto a menu row in any pane (append into it). Bundles,
// kind groups, Other Actions, and Support files never accept.
- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	NSInteger pane = [self columnIndexForTableView:tableView];
	NSInteger lastPane = (NSInteger)[paneTables count] - 1;
	if(pane == -1 || info.draggingSource != paneTables[lastPane])
		return NSDragOperationNone;

	// The payload names the bundle; every dragged item must live in it and
	// the drop target must belong to it too.
	bundles::item_ptr bundle;
	NSArray* strings = [info.draggingPasteboard propertyListForType:kBundleItemUUIDsPboardType];
	if([strings isKindOfClass:[NSArray class]] && [strings count] != 0 && [strings[0] isKindOfClass:[NSString class]])
	{
		if(bundles::item_ptr first = bundles::lookup(to_s((NSString*)strings[0])))
			bundle = first->bundle();
	}
	be::entry_ptr shownBundle = [self selectedEntryInPane:0];
	if(!bundle || !shownBundle || shownBundle->represented_item() != bundle)
		return NSDragOperationNone;
	NSArray* uuids = [self draggedUUIDsFromPasteboard:info.draggingPasteboard inBundle:bundle];
	if(!uuids)
		return NSDragOperationNone;

	oak::uuid_t menu;
	size_t index = 0;
	if(pane == lastPane)
	{
		menu = [self menuContextForPane:pane];
		if(!menu)
			return NSDragOperationNone;
		if(operation == NSTableViewDropOn)
		{
			// Onto a submenu row moves into it; onto a plain row behaves as
			// dropping above that row.
			if(row >= 0 && row < (NSInteger)paneEntries[pane].size())
			{
				if(bundles::item_ptr anchor = paneEntries[pane][row]->represented_item())
				{
					if(anchor->kind() == bundles::kItemTypeMenu)
					{
						menu = anchor->uuid();
						index = anchor->menu(true).size();
					}
					else
					{
						index = row;
					}
				}
				else
				{
					return NSDragOperationNone;
				}
			}
			else
			{
				index = paneEntries[pane].size();
			}
		}
		else
		{
			index = std::min<size_t>(row < 0 ? paneEntries[pane].size() : row, paneEntries[pane].size());
		}
	}
	else
	{
		if(row < 0 || row >= (NSInteger)paneEntries[pane].size())
			return NSDragOperationNone;
		be::entry_ptr target = paneEntries[pane][row];
		if(bundles::item_ptr represented = target->represented_item())
		{
			if(represented->kind() == bundles::kItemTypeMenu)
				menu = represented->uuid();
			else if(target->identifier() == "Menu Actions" && represented->kind() == bundles::kItemTypeBundle)
				menu = represented->uuid();
			else
				return NSDragOperationNone;
		}
		else
		{
			return NSDragOperationNone;
		}
		index = target->has_children() ? target->children().size() : 0;
	}

	// The target menu must belong to the payload’s bundle.
	BOOL sameBundle = (menu == bundle->uuid());
	if(!sameBundle)
	{
		if(bundles::item_ptr menuItem = bundles::lookup(menu))
			sameBundle = menuItem->kind() == bundles::kItemTypeMenu && menuItem->bundle() == bundle;
	}
	if(!sameBundle)
		return NSDragOperationNone;

	// Dropping a single item onto its own slot is a no-op, not a move.
	if([uuids count] == 1 && pane == lastPane && operation != NSTableViewDropOn)
	{
		bundles::item_ptr item = bundles::lookup(to_s((NSString*)uuids[0]));
		if(item && item->parent_menu() == menu && index == [self rowForItemUUID:item->uuid() inPane:pane])
			return NSDragOperationNone;
	}
	return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	NSInteger pane = [self columnIndexForTableView:tableView];
	NSInteger lastPane = (NSInteger)[paneTables count] - 1;
	if(pane == -1)
		return NO;

	oak::uuid_t menu;
	size_t at = 0;
	if(pane == lastPane)
	{
		menu = [self menuContextForPane:pane];
		if(!menu)
			return NO;
		if(operation == NSTableViewDropOn && row >= 0 && row < (NSInteger)paneEntries[pane].size())
		{
			if(bundles::item_ptr anchor = paneEntries[pane][row]->represented_item())
			{
				if(anchor->kind() == bundles::kItemTypeMenu)
				{
					menu = anchor->uuid();
					at = anchor->menu(true).size();
				}
				else
				{
					at = row;
				}
			}
			else
			{
				return NO;
			}
		}
		else
		{
			at = std::min<size_t>(row < 0 ? paneEntries[pane].size() : row, paneEntries[pane].size());
		}
	}
	else
	{
		if(row < 0 || row >= (NSInteger)paneEntries[pane].size())
			return NO;
		be::entry_ptr target = paneEntries[pane][row];
		if(bundles::item_ptr represented = target->represented_item())
		{
			if(represented->kind() == bundles::kItemTypeMenu)
				menu = represented->uuid();
			else if(target->identifier() == "Menu Actions" && represented->kind() == bundles::kItemTypeBundle)
				menu = represented->uuid();
			else
				return NO;
		}
		else
		{
			return NO;
		}
		at = target->has_children() ? target->children().size() : 0;
	}

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
	if(pane == lastPane && operation != NSTableViewDropOn)
	{
		size_t above = 0;
		for(size_t i = 0; i < at && i < paneEntries[pane].size(); ++i)
		{
			if(bundles::item_ptr sibling = paneEntries[pane][i]->represented_item())
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
// = Column selection =
// ===================

- (void)tableViewSelectionDidChange:(NSNotification*)notification
{
	NSTableView* table = notification.object;
	NSInteger pane = [self columnIndexForTableView:table];
	if(pane == -1)
		return;
	[self truncatePanesAfter:pane];
	if(be::entry_ptr selected = [self selectedEntryInPane:pane])
	{
		if(selected->has_children())
			[self appendPaneWithEntries:selected->children()];
	}
	[self updateEditedItemFromSelection];
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
