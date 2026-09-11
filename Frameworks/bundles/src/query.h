#ifndef BUNDLES_QUERY_H_7L9NPR0I
#define BUNDLES_QUERY_H_7L9NPR0I

#include "item.h"

namespace bundles
{
	bool set_index (std::vector<item_ptr> const& items, std::map< oak::uuid_t, std::vector<oak::uuid_t> > const& menus);
	inline bool set_index (std::vector<item_ptr> const& items) { return set_index(items, std::map< oak::uuid_t, std::vector<oak::uuid_t> >()); }

	struct callback_t
	{
		virtual ~callback_t () { }
		virtual void bundles_will_change () { }
		virtual void bundles_did_change ()  { }
	};

	void add_callback (callback_t* cb);
	void remove_callback (callback_t* cb);
	void add_item (item_ptr item);
	void remove_item (item_ptr item);

	// Record item_uuid as a member of the menu identified by menu_uuid
	// (the bundle uuid addresses the top-level menu), placed directly after
	// after_uuid, or appended when after_uuid is nil or absent. The entry is
	// de-duplicated and the item’s parent menu is updated. This mutates the
	// in-memory index only; callers persist the change separately, e.g. via
	// insert_uuid_into_main_menu() on the bundle’s info.plist dictionary.
	void add_to_menu (oak::uuid_t const& menu_uuid, oak::uuid_t const& item_uuid, oak::uuid_t const& after_uuid = oak::uuid_t());

	std::vector<item_ptr> query (std::string const& field, std::string const& value, scope::context_t const& scope = scope::wildcard, int kind = kItemTypeMost, oak::uuid_t const& bundle = oak::uuid_t(), bool filter = true, bool includeDisabledItems = false, bool resolveProxyItems = true);
	std::vector<item_ptr> items_for_proxy (item_ptr proxyItem, scope::context_t const& scope = scope::wildcard, int kind = kItemTypeCommand|kItemTypeDragCommand|kItemTypeGrammar|kItemTypeMacro|kItemTypeSnippet|kItemTypeProxy|kItemTypeTheme, oak::uuid_t const& bundle = oak::uuid_t(), bool filter = true, bool includeDisabledItems = false);
	item_ptr lookup (oak::uuid_t const& uuid);
	std::string name_with_selection (item_ptr const& item, bool hasSelection);
	std::string menu_path (item_ptr item);
	std::string key_equivalent (item_ptr const& item);

} /* bundles */

#endif /* end of include guard: BUNDLES_QUERY_H_7L9NPR0I */
