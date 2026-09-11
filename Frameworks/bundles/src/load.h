#ifndef LOAD_H_C8BVI372
#define LOAD_H_C8BVI372

#include "item.h"
#include <plist/fs_cache.h>

std::pair<std::vector<bundles::item_ptr>, std::map< oak::uuid_t, std::vector<oak::uuid_t>>> create_bundle_index (std::vector<std::string> const& bundlesPaths, plist::cache_t& cache);

namespace bundles
{
// Insert item_uuid into the “items” array of the menu addressed by menu_uuid
// inside info_plist’s mainMenu (bundle_uuid addresses the top-level items;
// any other uuid addresses mainMenu.submenus.<uuid>.items), placed directly
// after after_uuid, or appended when after_uuid is empty or absent. The entry
// is de-duplicated. Returns false without touching info_plist when either
// uuid is invalid or the addressed menu does not exist.
bool insert_uuid_into_main_menu (plist::dictionary_t& info_plist, std::string const& bundle_uuid, std::string const& menu_uuid, std::string const& item_uuid, std::string const& after_uuid = std::string());
}

#endif /* end of include guard: LOAD_H_C8BVI372 */
