# Accent-Insensitive Multi-Word Search Implementation

This document describes the implementation of accent-insensitive, multi-word search functionality in the SpaceTime app.

## Overview

The search feature supports:
- **Accent-insensitive matching**: "Sao Paulo" matches "São Paulo", "Uberlandia" matches "Uberlândia"
- **Multi-word search**: "paulo sao" matches "São Paulo" (words can be in any order)
- **Special character removal**: Apostrophes, punctuation, and special characters are ignored
- **All words must match**: Every word in the query must appear somewhere in the text

## Implementation Structure

### 1. Search Utility Class (`lib/app/utils/search_utils.dart`)

The `SearchUtils` class provides static methods for text normalization and search matching.

#### Key Methods:

**`normalizeText(String text)`**
- Removes diacritics (accents) using the `diacritic` package
- Converts to lowercase
- Removes apostrophes and special characters
- Normalizes whitespace

**`matchesSearch(String text, String query)`**
- Checks if all query words appear in the text
- Words can appear in any order
- Uses normalized text for comparison

**`matchesSearchInAny(String query, List<String?> texts)`**
- Checks if query matches any of the provided texts
- Useful for searching across multiple fields

**`filterList<T>(...)`**
- Filters a list based on a single field

**`filterListMultiField<T>(...)`**
- Filters a list based on multiple fields

### 2. Integration with AddMemoriesController

The search functionality is integrated into the `AddMemoriesController` in two places:

#### A. Search Suggestions (`generateSearchSuggestions`)

When the user types in the search field, suggestions are generated using accent-insensitive matching:

```dart
// Normalize the query
final normalizedQuery = SearchUtils.normalizeText(query);

// Match against memory fields
bool matchesDescription = SearchUtils.matchesSearch(text, query);
bool matchesLocation = SearchUtils.matchesSearchInAny(query, [
  locationCity,
  locationCountry,
  location,
]);
```

#### B. Memory Filtering (`matchesSearchQuery`)

When filtering memories, the search uses multi-field matching:

```dart
bool matchesSearchQuery(String query) {
  if (query.isEmpty) return true;

  return SearchUtils.matchesSearchInAny(query, [
    text,
    location,
    date,
    category,
    tags,
    mentions,
  ]);
}
```

## Examples

### Example 1: Basic Search
```dart
// Query: "sao paulo"
// Matches: "São Paulo", "São Paulo, Brazil"
// Does not match: "Rio de Janeiro"
```

### Example 2: Multi-Word Search (Any Order)
```dart
// Query: "paulo sao"
// Matches: "São Paulo" (words in any order)

// Query: "brazil rio"
// Matches: "Rio de Janeiro, Brazil"
```

### Example 3: Accent-Insensitive
```dart
// Query: "uberlandia"
// Matches: "Uberlândia"

// Query: "brasilia"
// Matches: "Brasília"
```

### Example 4: Special Characters Ignored
```dart
// Query: "laquila"
// Matches: "L'Aquila"

// Query: "cafe francais"
// Matches: "Café-Français"
```

## Dependencies

The implementation uses the `diacritic` package for removing accents:

```yaml
dependencies:
  diacritic: ^0.1.5
```

This package is already included in the project's `pubspec.yaml`.

## Testing

To test the search functionality:

1. **Test accent removal**:
   - Search for "sao paulo" → should find "São Paulo"
   - Search for "uberlandia" → should find "Uberlândia"

2. **Test multi-word search**:
   - Search for "paulo sao" → should find "São Paulo"
   - Search for "brazil rio" → should find "Rio de Janeiro, Brazil"

3. **Test special characters**:
   - Search for "laquila" → should find "L'Aquila"

4. **Test hashtags and mentions**:
   - Search for "#travel" → should find memories with #travel tag
   - Search for "@john" → should find memories mentioning @john

## Code Location

- **Search Utility**: `lib/app/utils/search_utils.dart`
- **Example Usage**: `lib/app/utils/search_utils_example.dart`
- **Controller Integration**: `lib/app/modules/add_memories/controllers/add_memories_controller.dart`
  - Line ~672: `generateSearchSuggestions` method
  - Line ~2113: `matchesSearchQuery` method
- **UI**: `lib/app/modules/add_memories/views/mini_widgets/search_overly.dart`

## Performance Considerations

- Text normalization is performed on-the-fly during search
- For large datasets, consider caching normalized text
- The current implementation is optimized for real-time search as the user types

## Future Enhancements

Possible improvements:
- Cache normalized text for better performance
- Add fuzzy matching (e.g., "paulo" matches "paulos")
- Add search result highlighting
- Add search history
- Add search filters (date range, category, etc.)

