title: TextMate Help
meta: AppleTitle="TextMate 2 Help", AppleIcon="TextMate Help/images/tm_small.png"

# TextMate Help

Some non-visible stuff.

## Mouse Gestures

 * ⌘-click to add a new caret.
 * ⌥-click close buttons to close other tabs.
 * Hold ⌃ when dropping file to text view to insert its path.

Holding ⌥ to “close other” also works in the file browser or when using ⌘T (and ⌘T now does multi-select).

One exception to “⌥ closes other” is when single-clicking the icon of a bundle (e.g. `.app`) in the file browser. In this case the single-click works as “Show Package Contents”.

## Completion (⎋)

The current word suffix is taken into consideration when hitting escape.

For example in this case:

	enum mark_t { kErrorMarkType, kWarningMarkType };
	mark_t m = ‸MarkType;

The resulting line will become:

	mark_t m = kWarning‸MarkType;

## Grammar

 * Scope names are format strings and can reference captures ($0, $1, $n).
 * `\G` matches end of parent rule’s `begin` — or end of last stacked `while`.
 * `begin`/`while` rule construct.
 * Includes can reference grammar#repos.

## Bundles

 * Shell variables are format strings and can e.g. reference `TM_SUPPORT_PATH`.
 * Completion commands have all variables set from current context.

## Discontinuous Selection

Activated by typing/deleting or using a leftward or rightward movement while a column selection is active. Alternatively use “Find All”

## Find History

Just like clipboard history: ⌃⌥⌘F.

## Other

Possible to enter e.g. `main.{cc,h}` in a Save As dialog for brace expansion (saves as first expansion, background tabs are created for further expansions).

⌘T can filter on full path by including `/`, extension by starting with `.`, can go to a line by suffixing with a line specification (see elsewhere for syntax)

Using ⌘T with find clipboard containing `«file»:«line»` will use that as default text.

## Interface Scale

The window chrome — tab bar, status bars, file browser, Find, the choosers, the dialogs and Preferences — can be scaled independently of the editor font, from View → Font:

 * Bigger Interface: ⌃⌘=
 * Smaller Interface: ⌃⌘−
 * Default Interface Size: ⌃⌘0

Each step is 0.1, from 0.8 to 3.0. The change applies at once, and the setting is kept across launches. The menu bar, alerts, the Open and Save panels, context menus and the Preferences toolbar are drawn by macOS at the system size and do not follow.

The scale can also be set from a terminal (any value outside 0.8–3.0 is clamped, and the key is removed when the scale returns to 1):

	defaults write com.macromates.TextMate uiFontScaleFactor 1.5

These older keys are still honoured. Those marked “× scale” give the base size that the interface scale multiplies:

	defaults write com.macromates.TextMate statusBarFontSize 13                          # status bar font, default 12 (× scale)
	defaults write com.macromates.TextMate OakBundleManagerDisambiguateMenuFontSize 12   # menu shown when several bundle items share a key, default 11 (× scale)
	defaults write com.macromates.TextMate tabItemMinWidth 120                           # narrowest tab, default 120 (× scale)
	defaults write com.macromates.TextMate tabItemMaxWidth 250                           # widest tab, default 250 (× scale)
	defaults write com.macromates.TextMate searchResultsFontName Menlo                   # Find results font, default the control font
	defaults write com.macromates.TextMate searchResultsFontSize -float 12               # Find results size, default 11 (the whole Find window zooms with the scale)
	defaults write com.macromates.TextMate lineNumberFontName Menlo                      # gutter font, default the editor font
	defaults write com.macromates.TextMate lineNumberScaleFactor -float 1                # gutter size relative to the editor font, default 0.8 (editor zoom, not the interface scale)

Keys named `OakScaledContainerScale …` are written by TextMate next to each zoomed window’s saved frame and are not meant to be edited.

## Syntax / API

* [Bundle Dependencies][]
* [Format String Syntax][]
* [Glob String Syntax][]
* [JavaScript Object][]
* [Scope Selector Syntax][]
* [Selection String Syntax][]
* [Folder Specific Properties][]
* [Non-Content Scopes][]
* [Events / Filters][]
* [mate & rmate](mate_and_rmate.html)

[Bundle Dependencies]:        bundle_dependencies.html
[Format String Syntax]:       format_string_syntax.html
[Glob String Syntax]:         glob_string_syntax.html
[JavaScript Object]:          javascript_object.html
[Scope Selector Syntax]:      scope_selector_syntax.html
[Selection String Syntax]:    selection_string_syntax.html
[Folder Specific Properties]: properties.html
[Non-Content Scopes]:         non-content_scopes.html
[Events / Filters]:           events.html
