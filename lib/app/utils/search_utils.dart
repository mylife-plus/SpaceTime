import 'package:diacritic/diacritic.dart';

/// Search utility class for accent-insensitive and multi-word search
class SearchUtils {
  /// Normalizes text by:
  /// 1. Removing diacritics (accents)
  /// 2. Converting to lowercase
  /// 3. Removing apostrophes and special characters
  /// 4. Trimming whitespace
  ///
  /// Example:
  /// - "São Paulo" -> "sao paulo"
  /// - "Uberlândia" -> "uberlandia"
  /// - "L'Aquila" -> "laquila"
  static String normalizeText(String text) {
    if (text.isEmpty) return '';

    // Remove diacritics (accents)
    String normalized = removeDiacritics(text);

    // Convert to lowercase
    normalized = normalized.toLowerCase();

    // Replace apostrophes with empty string (L'Aquila -> LAquila)
    normalized = normalized.replaceAll(RegExp(r"['']"), '');

    // Replace other special characters with spaces (Café-Français -> Cafe Francais)
    normalized = normalized.replaceAll(RegExp(r"[\-_.,;:!?(){}[\]""]+"), ' ');

    // Replace multiple spaces with single space and trim
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return normalized;
  }

  /// Checks if a text matches a search query using multi-word, accent-insensitive matching.
  ///
  /// Rules:
  /// - All words in the query must appear somewhere in the text
  /// - Words can appear in any order
  /// - Matching is accent-insensitive
  /// - Apostrophes and special characters are ignored
  ///
  /// Example:
  /// - Query: "paulo sao" matches "São Paulo"
  /// - Query: "uber dia" matches "Uberlândia"
  /// - Query: "new york" matches "New York City"
  ///
  /// Parameters:
  /// - [text]: The text to search in
  /// - [query]: The search query
  ///
  /// Returns: true if all query words are found in the text
  static bool matchesSearch(String text, String query) {
    if (query.isEmpty) return true;
    if (text.isEmpty) return false;
    
    // Normalize both text and query
    final normalizedText = normalizeText(text);
    final normalizedQuery = normalizeText(query);
    
    // Split query into individual words
    final queryWords = normalizedQuery.split(' ').where((word) => word.isNotEmpty).toList();
    
    if (queryWords.isEmpty) return true;
    
    // Check if all query words appear in the text
    for (final word in queryWords) {
      if (!normalizedText.contains(word)) {
        return false;
      }
    }
    
    return true;
  }

  /// Checks if any of the provided texts match the search query.
  ///
  /// This is useful when searching across multiple fields (e.g., title, description, location).
  /// For multi-word queries, all words must appear across the combined fields.
  ///
  /// Example:
  /// ```dart
  /// final matches = SearchUtils.matchesSearchInAny(
  ///   'sao paulo',
  ///   ['São Paulo', 'Brazil', 'City'],
  /// );
  /// // Returns true because both "sao" and "paulo" are found in the first field
  ///
  /// final matches2 = SearchUtils.matchesSearchInAny(
  ///   'beach rio',
  ///   ['Beach Day', 'Rio de Janeiro'],
  /// );
  /// // Returns true because "beach" is in first field and "rio" is in second field
  /// ```
  ///
  /// Parameters:
  /// - [query]: The search query
  /// - [texts]: List of texts to search in
  ///
  /// Returns: true if all query words are found across the combined texts
  static bool matchesSearchInAny(String query, List<String?> texts) {
    if (query.isEmpty) return true;

    // Combine all non-null texts into a single string
    final combinedText = texts
        .where((text) => text != null && text.isNotEmpty)
        .join(' ');

    if (combinedText.isEmpty) return false;

    // Check if the query matches the combined text
    return matchesSearch(combinedText, query);
  }

  /// Filters a list of items based on a search query.
  ///
  /// Example:
  /// ```dart
  /// final cities = ['São Paulo', 'Rio de Janeiro', 'Uberlândia'];
  /// final filtered = SearchUtils.filterList(
  ///   cities,
  ///   'paulo',
  ///   (city) => city,
  /// );
  /// // Result: ['São Paulo']
  /// ```
  ///
  /// Parameters:
  /// - [items]: The list of items to filter
  /// - [query]: The search query
  /// - [textExtractor]: Function to extract searchable text from each item
  ///
  /// Returns: Filtered list of items
  static List<T> filterList<T>(
    List<T> items,
    String query,
    String Function(T item) textExtractor,
  ) {
    if (query.isEmpty) return items;
    
    return items.where((item) {
      final text = textExtractor(item);
      return matchesSearch(text, query);
    }).toList();
  }

  /// Filters a list of items based on a search query across multiple fields.
  ///
  /// Example:
  /// ```dart
  /// final memories = [
  ///   {'title': 'São Paulo Trip', 'location': 'Brazil'},
  ///   {'title': 'Paris Vacation', 'location': 'France'},
  /// ];
  /// final filtered = SearchUtils.filterListMultiField(
  ///   memories,
  ///   'paulo',
  ///   (memory) => [memory['title'], memory['location']],
  /// );
  /// ```
  ///
  /// Parameters:
  /// - [items]: The list of items to filter
  /// - [query]: The search query
  /// - [textsExtractor]: Function to extract multiple searchable texts from each item
  ///
  /// Returns: Filtered list of items
  static List<T> filterListMultiField<T>(
    List<T> items,
    String query,
    List<String?> Function(T item) textsExtractor,
  ) {
    if (query.isEmpty) return items;
    
    return items.where((item) {
      final texts = textsExtractor(item);
      return matchesSearchInAny(query, texts);
    }).toList();
  }
}

