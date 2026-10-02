#import "OakTextViewVariables.h"
#import <document/OakDocument.h>
#import <ns/ns.h>
#import <test/jail.h>

// Bundle commands that reflow text get the wrap column Reformat (⌃Q) uses,
// so the two agree (issue #91).
static std::map<std::string, std::string> variables_for (test::jail_t const& jail)
{
	// An untitled document takes its settings from its directory, the way one
	// does in a project; that keeps the test clear of the asynchronous file load.
	OakDocument* document = [OakDocument documentWithString:@"some text\n" fileType:@"text.plain" customName:@"notes"];
	document.directory = to_ns(jail.path());
	[document loadModalForWindow:nil completionHandler:nil];
	OAK_ASSERT(document.isLoaded);

	OakTextView* textView = [[OakTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
	textView.document = document;
	std::map<std::string, std::string> res = [textView variables];
	textView.document = nil;
	[document close];
	return res;
}

void test_wrap_column_variable_follows_the_setting ()
{
	test::jail_t jail;
	jail.set_content(".tm_properties", "wrapColumn = 60\n");
	OAK_ASSERT_EQ(variables_for(jail)["TM_WRAP_COLUMN"], "60");
}

void test_wrap_column_variable_is_a_real_column_for_window_width ()
{
	test::jail_t jail;
	std::string const value = variables_for(jail)["TM_WRAP_COLUMN"];
	OAK_ASSERT(!value.empty());
	OAK_ASSERT_GE(std::stoi(value), 10); // never the 0 that means “window width” in the setting
}
