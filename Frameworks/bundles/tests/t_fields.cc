#include <bundles/bundles.h>
#include <test/bundle_index.h>

// A grammar lists its extensions in order of preference; the first one names new files
void test_first_of_an_array_field_is_its_value ()
{
	// The item alone is enough; committing the fixture would replace the shared index the query tests rely on
	test::bundle_index_t bundleIndex;
	bundles::item_ptr grammar = bundleIndex.add(bundles::kItemTypeGrammar, "{ name = 'Markdown'; scopeName = 'text.html.markdown'; fileTypes = ( 'md', 'mdown', 'markdown', 'markdn' ); }");

	OAK_ASSERT_EQ(grammar->value_for_field(bundles::kFieldGrammarExtension), "md");
	OAK_ASSERT_EQ(grammar->values_for_field(bundles::kFieldGrammarExtension), std::vector<std::string>({ "md", "mdown", "markdown", "markdn" }));
	OAK_ASSERT_EQ(grammar->value_for_field(bundles::kFieldGrammarScope), "text.html.markdown");
	OAK_ASSERT_EQ(grammar->value_for_field("noSuchField"), NULL_STR);
}
