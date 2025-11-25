# Label Styling Documentation

## Overview
This document describes the consistent label styling implementation across all add/edit popups in the SpaceTime app for hashtags, mentions, contacts, places, categories, and subcategories.

## Standard Label Styling

### Label Style Specification
All labels above input fields and dropdowns follow this consistent styling:

```dart
Text(
  'Label Text',
  style: GoogleFonts.kumbhSans(
    fontSize: 15,
    color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
  ),
)
```

### Label Layout Structure
Labels are wrapped in an `Align` widget with left alignment and bottom padding:

```dart
Align(
  alignment: Alignment.centerLeft,
  child: Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 4),
    child: Text(
      'Label Text',
      style: GoogleFonts.kumbhSans(
        fontSize: 15,
        color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
      ),
    ),
  ),
),
```

**Note:** Some labels use `padding: const EdgeInsets.only(bottom: 4)` without left padding when they don't need left offset.

## Popup-Specific Label Implementations

### 1. AddEditGroupPopup
**File:** `lib/app/shared/widgets/add_edit_group_popup.dart`

**Purpose:** Add/edit hashtag groups, contact groups, and their subgroups

**Labels Implemented:**
- **Name Label** (Line 174-187):
  - For main groups: "Hashtag Group" or "Contact Group"
  - For subgroups: "Hashtag" or "Contact"
  - Positioned above the name input field

**Parent Group Display:**
- Shows parent group name with folder emoji when editing/adding subgroups (Line 155-169)
- Format: `📁 {parentGroupName}`
- Font size: 14
- Color: `uiController.darkMode.value ? Colors.white : Colors.black`

---

### 2. AddEditGroupPopupNew
**File:** `lib/app/shared/widgets/add_edit_group_pop_new.dart`

**Purpose:** Unified popup for adding/editing place categories, hashtag groups, and contact groups with parent dropdown support

**Labels Implemented:**

#### A. Category/Group Dropdown Label (Line 1604-1617)
- **Label Text:** Dynamic based on mode
  - Place mode: "Place Category"
  - Hashtag mode: "Hashtag Group"
  - Contact mode: "Contact Group"
- **Visibility:** Shows when `fromMemoryView` or `isMainCategory` or editing existing items
- **Positioned:** Above category/group dropdown

#### B. New Category/Group Name Label (Line 1730-1743)
- **Label Text:** "{Category/Group} Name"
- **Visibility:** Shows when "Add New Category/Group" is selected from dropdown
- **Positioned:** Above the new category/group name input field

#### C. Subcategory/Item Name Label (Line 1894-1917)
- **Label Text:** Dynamic based on mode
  - Place mode: "Place Name" or "Place"
  - Hashtag mode: "Hashtag"
  - Contact mode: "Contact"
- **Visibility:** Shows in Memory View mode or when editing subcategories
- **Positioned:** Above the item name input field

---

### 3. AddPlaceCategoryPopup
**File:** `lib/app/shared/widgets/add_place_category_popup.dart`

**Purpose:** Add/edit place categories and places

**Labels Implemented:**

#### A. Place Category Label (Line 772-784)
- **Label Text:** "Place Category"
- **Visibility:** Shows when `fromMemoryView` or `isMainCategory` or editing existing category
- **Positioned:** Above category dropdown

#### B. Category Name Label (Line 863-876)
- **Label Text:** "Category Name"
- **Visibility:** Shows when "Add New Category" is selected from dropdown
- **Positioned:** Above the new category name input field

#### C. Place Name Label (Line 1030-1053)
- **Label Text:** "Place Name"
- **Visibility:** Shows in Memory View mode or when editing subcategories
- **Positioned:** Above the place name input field with emoji picker

---

### 4. AddPlaceCategoryPopupForCategoryPicker
**File:** `lib/app/shared/widgets/add_place_category_popup.dart`

**Purpose:** Add/edit place categories and places from category picker widget

**Labels Implemented:**

#### A. Category Name Label (Line 2025-2038)
- **Label Text:** "Category Name"
- **Visibility:** Shows when "Add New Category" is selected from dropdown (first instance)
- **Positioned:** Above the new category name input field

#### B. Category Name Label (Line 2155-2168)
- **Label Text:** "Category Name"
- **Visibility:** Shows when "Add New Category" is selected from dropdown (second instance in different mode)
- **Positioned:** Above the new category name input field

#### C. Place Name Label (Line 2204-2220)
- **Label Text:** "Place Name"
- **Visibility:** Shows when adding subcategories or in Memory View mode or editing subcategories
- **Positioned:** Above the place name input field with emoji picker

---

### 5. TagMentionBottomSheet (_AddGroupPopupDialog)
**File:** `lib/app/modules/memories/views/mini_widgets/mention_bottom_sheet_widget.dart`

**Purpose:** Add hashtags/mentions from memory description field

**Labels Implemented:**

#### A. Group Dropdown Label (Line 1296-1310)
- **Label Text:** "Hashtag Group" or "Contact Group"
- **Positioned:** Above the group dropdown
- **Font Weight:** `FontWeight.w500` (slightly bolder than other labels)
- **Color:** `uiController.darkMode.value ? Colors.white : Colors.black`

#### B. New Group Name Label (Line 1387-1400)
- **Label Text:** "Hashtag Group Name" or "Contact Group Name"
- **Visibility:** Shows when "Add New Group" is selected from dropdown
- **Positioned:** Above the new group name input field
- **Color:** `uiController.darkMode.value ? Colors.white70 : Colors.grey[700]`

#### C. Subcategory Name Label (Line 1440-1454)
- **Label Text:** "Hashtag" or "Contact"
- **Positioned:** Above the hashtag/contact name input field
- **Font Weight:** `FontWeight.w500`
- **Color:** `uiController.darkMode.value ? Colors.white : Colors.black`

---

## Summary Table

| Popup | File | Labels Count | Label Types |
|-------|------|--------------|-------------|
| AddEditGroupPopup | add_edit_group_popup.dart | 1 | Name label |
| AddEditGroupPopupNew | add_edit_group_pop_new.dart | 3 | Category/Group, New Name, Item Name |
| AddPlaceCategoryPopup | add_place_category_popup.dart | 3 | Category, Category Name, Place Name |
| AddPlaceCategoryPopupForCategoryPicker | add_place_category_popup.dart | 3 | Category Name (2x), Place Name |
| TagMentionBottomSheet | mention_bottom_sheet_widget.dart | 3 | Group, New Group Name, Item Name |

**Total Labels Implemented:** 13 labels across 5 popup types

---

## Design Consistency Notes

1. **Font Size:** All labels use `fontSize: 15`
2. **Font Family:** All labels use `GoogleFonts.kumbhSans`
3. **Color Scheme:** 
   - Most labels: `darkMode ? Colors.white70 : Colors.grey[700]`
   - Some labels in TagMentionBottomSheet: `darkMode ? Colors.white : Colors.black` with `FontWeight.w500`
4. **Padding:** Bottom padding of 4px is standard
5. **Alignment:** All labels are left-aligned using `Alignment.centerLeft`
6. **Spacing:** Labels are placed directly above their corresponding input fields/dropdowns

---

## Usage Guidelines

When adding new input fields or dropdowns to any popup:

1. Add a label above the input field/dropdown
2. Use the standard label styling from this document
3. Ensure the label text clearly describes the field purpose
4. Maintain consistent spacing (4px bottom padding)
5. Use appropriate color based on dark mode state
6. Keep font size at 15 for consistency

---

## Views Using These Popups

### HashtagGroupsView
**File:** `lib/app/modules/hashtag_groups/views/hashtag_groups_view.dart`

**Popups Used:**
- `AddEditGroupPopup` - For editing hashtag groups and subgroups (lines 589, 895, 2070)
- `AddEditGroupPopupNew` - For editing from filter mode with parent dropdown (line 1838)

### ContactGroupsView
**File:** `lib/app/modules/contact_groups/views/contact_groups_view.dart`

**Popups Used:**
- `AddEditGroupPopup` - For editing contact groups and subgroups (lines 587, 905, 2117)
- `AddEditGroupPopupNew` - For editing from filter mode with parent dropdown (line 1885)

### CategoryPickerWidget
**File:** `lib/app/modules/memories/views/mini_widgets/category_picker_widget.dart`

**Popups Used:**
- `AddPlaceCategoryPopupForCategoryPicker` - For adding/editing place categories and subcategories (lines 593, 628, 1176)
- `AddPlaceCategoryPopup` - For editing subcategories with parent dropdown (line 715)

### MemoryView (via Memory Description Field)
**File:** `lib/app/modules/memories/views/mini_widgets/memory_description_field_widget.dart`

**Popups Used:**
- `TagMentionBottomSheet` - For adding hashtags and mentions from description field

---

**Last Updated:** 2025-11-25
**Maintained By:** SpaceTime Development Team

