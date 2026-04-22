#!/usr/bin/env python3
"""Patch en/es/fr/de.json templates for remaining l10n keys + helpers."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LANGS = ("en", "es", "fr", "de")

# English templates ($1, $2, …). Also fixes previously broken JSON values.
PATCH_EN: dict[str, str] = {
    # helpers
    "l10n_word_memory": "memory",
    "l10n_word_memories": "memories",
    "l10n_label_hashtag": "Hashtag",
    "l10n_label_contact": "Contact",
    "l10n_label_mention": "Mention",
    "l10n_lc_hashtag": "hashtag",
    "l10n_lc_contact": "contact",
    "l10n_please_select_group_h": "Please select a Hashtag Group",
    "l10n_please_select_group_c": "Please select a Contact Group",
    "l10n_please_select_or_add_h": "Please select a Hashtag Group or add a new Hashtag Group",
    "l10n_please_select_or_add_c": "Please select a Contact Group or add a new Contact Group",
    "l10n_enter_new_group_name_h": "Please enter a new Hashtag Group name",
    "l10n_enter_new_group_name_c": "Please enter a new Contact Group name",
    "l10n_please_enter_name_h": "Please enter a hashtag name",
    "l10n_please_enter_name_m": "Please enter a mention name",
    "l10n_failed_update_h": "Failed to update hashtag",
    "l10n_failed_update_c": "Failed to update contact",
    "l10n_loading_groups_h": "Loading Hashtag Groups...",
    "l10n_loading_groups_c": "Loading Contact Groups...",
    "l10n_add_new_group_h": "+ Add New Hashtag Group",
    "l10n_add_new_group_c": "+ Add New Contact Group",
    "l10n_group_label_h": "Hashtag Group",
    "l10n_group_label_c": "Contact Group",
    "l10n_group_name_label_h": "Hashtag Group Name",
    "l10n_group_name_label_c": "Contact Group Name",
    "l10n_hint_new_group_h": "Enter new Hashtag Group name",
    "l10n_hint_new_group_c": "Enter new Contact Group name",
    "l10n_subcategory_label_h": "Hashtag",
    "l10n_subcategory_label_c": "Contact",
    "l10n_fail_add_h": "Failed to add Hashtag",
    "l10n_fail_add_c": "Failed to add Contact",
    "l10n_fail_add_h_full": "Failed to add Hashtag Group and Hashtag",
    "l10n_fail_add_c_full": "Failed to add Contact Group and Contact",
    "l10n_title_edit_h": "edit Hashtag",
    "l10n_title_edit_m": "edit Mention",
    "l10n_title_new_h": "new Hashtag",
    "l10n_title_new_m": "new Mention",
    # memory debug dialog
    "text_id_memory": "ID: $1",
    "text_date_memory": "📅 Date: $1",
    "text_time_memory": "Time: $1",
    "text_location_memory": "📍 Location: $1",
    "text_category_memory": "🏷️ Category: $1",
    "text_description_memory": "📝 Description: $1",
    "text_tags_memory": "Tags: $1",
    "text_mentions_memory": "Mentions: $1",
    "text_created_memory": "📅 Created: $1",
    "text_updated_memory": "Updated: $1",
    "text_memory": "#$1",
    # dynamic templates (remaining inventory)
    "hinttext_widget_hint": "$1",
    "text_activefiltercount_filter_activefiltercount_1": "$1 filter$2 applied",
    "text_controller_filteredmemories_length_results": "($1 results)",
    "text_currentindex_1_of_totalcount": "$1 of $2",
    "text_widget_time": " $1",
    "text_getdayordate_widget_date_widget_year": "$1 ",
    "text_widget_time_substring_3": " $1",
    "text_search_controller_searchquery_value": "Search: \"$1\"",
    "text_controller_filteredmemories_length_results_2": "($1 results)",
    "text_date_year": "$1 $2",
    "text_are_you_sure_you_want_to_delete_contactgroup_name": "Are you sure you want to delete \"$1\"?",
    "text_the_contact_groupname_cannot_be_deleted_because_it": "The contact \"$1\" cannot be deleted because it is being used by $2 $3.",
    "text_selectedcontactgroups_where_g_g_issubgroup_length_s": "$1 selected",
    "text_span_maincontactgroup_subgroups_length_0": " ($1)",
    "text_span_selectedsubgroupscount": "$1",
    "text_span_maincontactgroup_subgroups_length_0_2": "/$1)",
    "text_are_you_sure_you_want_to_delete_hashtaggroup_name": "Are you sure you want to delete \"$1\"?",
    "text_the_hashtag_group_groupname_cannot_be_deleted_becau": "The hashtag group \"$1\" cannot be deleted because it is being used by $2 $3.",
    "text_selectedhashtaggroups_where_g_g_issubgroup_length_s": "$1 selected",
    "text_span_mainhashtaggroup_subgroups_length_0": " ($1)",
    "text_span_selectedsubgroupscount_2": "$1",
    "text_span_mainhashtaggroup_subgroups_length_0_2": "/$1)",
    "text_location_city_location_city_isnotempty_location_sta": "$1$2$3",
    "subtitle_literal_location_city_location_city_isnotempty": "$1$2$3",
    "text_cluster_memories_memories_length": "Cluster Memories ($1)",
    "text_all_memories_length_memories": "All $1 Memories",
    "text_yearmemories_length_from_year": "$1 from $2",
    "text_region_formatregionname_currentregion": "Region: $1",
    "text_formattilecount_totaltiles_50k": "$1 / 50K",
    "text_overallprogress_100_tostringasfixed_1": "$1%",
    "text_currentdownloadprogress_100_tostringasfixed_0": "$1%",
    "text_service_totaltilesdownloaded_value_tiles": "$1 tiles",
    "text_service_downloadprogress_value_100_tostringasfixed": "$1%",
    "text_region_service_currentdownloadregion_value": "Region: $1",
    "text_progress_service_downloadprogress_value_100_tostrin": "Progress: $1%",
    "text_tiles_downloaded_service_totaltilesdownloaded_value": "Tiles Downloaded: $1",
    "text_queue_service_downloadqueue_length_regions": "Queue: $1 regions",
    "text_quota_currenttiles_quota_maxtiles_tiles_quota_usage": "$1 / $2 tiles ($3%)",
    "text_geocoding_service_activerequests_value": "Geocoding ($1)",
    "text_service_processingprogress_value_100_tostringasfixe": "$1%",
    "text_progress_service_processingprogress_value_100_tostr": "Progress: $1%",
    "text_status_service_processingstatus_value": "Status: $1",
    "text_processed_memories_service_processedmemories_length": "Processed Memories: $1",
    "text_generated_clusters_service_processedclusters_length": "Generated Clusters: $1",
    "text_generated_arrows_service_processedarrows_length": "Generated Arrows: $1",
    "text_status_progress_100_tostringasfixed_1_status_status": "$1% - $2",
    "text_memories_status_memoriescount": "Memories: $1",
    "text_clusters_status_clusterscount": "Clusters: $1",
    "text_arrows_status_arrowscount": "Arrows: $1",
    "text_error_snapshot_error": "Error: $1",
    "text_error_snapshot_error_2": "Error: $1",
    "text_entry_key": "$1:",
    "text_entry_value": "$1",
    "text_total_memories_allmemories_length": "Total Memories: $1",
    "text_images_base64_base64images_length_image_s": "🖼️ Images (Base64): $1 image(s)",
    "text_image_index_1_base64_length_characters_base64_lengt": "Image $1: $2 characters ($3 KB)",
    "text_audio_files_audiopaths_length_file_s": "🎵 Audio Files: $1 file(s)",
    "text_audio_index_1_filename": "Audio $1: $2",
    "text_cannot_delete_categorytype": "Cannot Delete $1",
    "text_the_categorytype_categoryname_cannot_be_deleted_bec": "The $1 \"$2\" cannot be deleted because it is being used by $3 $4.",
    "text_to_delete_this_categorytype_first_change_the_place": "To delete this $1, first change the Place of all memories that use it, or delete those memories.",
    "dialog_content_fixed_totalfixed_place_inconsistencies_n": "Fixed $1 Place inconsistencies.\n\nMemories and Place picker now show the correct updated Place names.",
    "dialog_content_an_error_occurred_while_fixing_place_inco": "An error occurred while fixing Place inconsistencies:\n\n$1",
    "text_span_maincategory_subcategories_length_0": " ($1)",
    "text_span_selectedsubcategoriescount": "$1",
    "text_span_maincategory_subcategories_length_0_2": "/$1)",
    "text_in_getparentcategoryname_category_parentid": "in $1",
    "text_current_mode_offlinemodereason": "Current mode: $1",
    "text_location": "$1, $2",
    "title_text_flag_country_name": "$1 $2",
    "text_prefixchar_trimmedsearchtext": "$1$2",
    "text_prefixchar_item": "$1$2",
    "hinttext_prefixchar_name": "$1 Name",
    "subtitle_literal_displaynameforlanguagecode_controller_s": "($1)",
    "subtitle_literal_controller_maincolor_value_capitalizefi": "($1)",
    "text_select_getcategorylabeltext": "Select $1",
    "text_add_new_isplacemode_category_group": "+ Add New $1",
    "text_category_name": "$1",
    "hinttext_isplacemode_category_group_name": "$1 Name",
    "text_category_name_2": "$1",
    "text_widget_parentgroupname": "📁 $1",
    "text_category_name_3": "$1",
    "text_category_name_5": "$1",
    "text_category_emoji_category_name": "$1 $2",
    "text_offlineservice_stylepackprogress_value_100_tostring": "$1%",
    "text_offlineservice_downloadedtilecount_value_tiles": "$1 tiles",
    "text_offlineservice_downloadedtilecount_value_tiles_down": "$1 tiles downloaded",
    "dialog_content_moved_to_location": "Moved to $1",
    "text_no_widget_istagmode": "No $1 groups available",
    "text_loading_widget_istagmode": "Loading $1 Groups...",
    "text_add_new_widget_istagmode": "+ Add New $1 Group",
    "text_select_prefixchar_widget_istagmode": "select $1 $2 Group",
    "text_widget_istagmode": "$1 Group",
    "text_widget_istagmode_2": "$1",
    "dialog_content_please_enter_a_widget_istagmode": "Please enter a $1 name",
    "dialog_content_failed_to_update_widget_istagmode": "Failed to update $1",
    "dialog_content_failed_to_add_widget_istagmode": "Failed to add $1",
    "dialog_content_please_select_a_widget_istagmode": "Please select a $1 Group",
    "dialog_content_please_select_a_widget_istagmode_2": "Please select a $1 Group or add a new $2 Group",
    "snackbar_widget_please_select_a_widget_istagmode": "Please select a $1 Group",
    "snackbar_widget_please_select_a_widget_istagmode_2": "Please select a $1 Group or add a new $2 Group",
    "snackbar_widget_please_select_a_widget_istagmode_3": "Please select a $1 Group",
    "snackbar_widget_please_select_a_widget_istagmode_4": "Please select a $1 Group or add a new $2 Group",
}


def translate_batch(texts: list[str], target: str) -> list[str]:
    from deep_translator import GoogleTranslator

    tr = GoogleTranslator(source="en", target=target)
    out: list[str] = []
    batch = 40
    for i in range(0, len(texts), batch):
        chunk = texts[i : i + batch]
        try:
            got = tr.translate_batch(chunk)
        except Exception:
            got = list(chunk)
        if not got or len(got) != len(chunk):
            got = list(chunk)
        out.extend(got)
        time.sleep(0.25)
    return out


def main() -> int:
    changed_keys = list(PATCH_EN.keys())
    base_en = PATCH_EN.copy()

    for lang in LANGS:
        p = REPO / "assets" / "l10n" / f"{lang}.json"
        data = json.loads(p.read_text(encoding="utf-8"))
        if lang == "en":
            for k, v in base_en.items():
                data[k] = v
        else:
            values = [base_en[k] for k in changed_keys]
            translated = translate_batch(values, lang)
            for k, t in zip(changed_keys, translated):
                data[k] = t or base_en[k]
        p.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(lang, "patched", len(changed_keys), "keys")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ImportError:
        print("pip install deep-translator", file=sys.stderr)
        raise SystemExit(1)
