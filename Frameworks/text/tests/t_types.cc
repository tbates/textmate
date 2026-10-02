#include <text/types.h>

void test_selection_string ()
{
	OAK_ASSERT_EQ(std::string(text::selection_t("")),          "1");
	OAK_ASSERT_EQ(std::string(text::selection_t("1")),         "1");
	OAK_ASSERT_EQ(std::string(text::selection_t("1:2-3:4")),   "1:2-3:4");
	OAK_ASSERT_EQ(std::string(text::selection_t("1:2-3:4&5")), "1:2-3:4&5");
}
