import 'package:flutter_test/flutter_test.dart';
import 'package:spacetime/app/utils/search_utils.dart';

void main() {
  group('SearchUtils - Text Normalization', () {
    test('removes accents from text', () {
      expect(SearchUtils.normalizeText('São Paulo'), 'sao paulo');
      expect(SearchUtils.normalizeText('Uberlândia'), 'uberlandia');
      expect(SearchUtils.normalizeText('Brasília'), 'brasilia');
      expect(SearchUtils.normalizeText('Café'), 'cafe');
    });

    test('converts to lowercase', () {
      expect(SearchUtils.normalizeText('NEW YORK'), 'new york');
      expect(SearchUtils.normalizeText('Paris'), 'paris');
    });

    test('removes apostrophes and special characters', () {
      expect(SearchUtils.normalizeText("L'Aquila"), 'laquila');
      expect(SearchUtils.normalizeText('Café-Français'), 'cafe francais');
      expect(SearchUtils.normalizeText('Hello, World!'), 'hello world');
    });

    test('normalizes whitespace', () {
      expect(SearchUtils.normalizeText('  multiple   spaces  '), 'multiple spaces');
      expect(SearchUtils.normalizeText('tab\tseparated'), 'tab separated');
    });
  });

  group('SearchUtils - Single Word Search', () {
    test('matches single word with accents', () {
      expect(SearchUtils.matchesSearch('São Paulo', 'paulo'), true);
      expect(SearchUtils.matchesSearch('São Paulo', 'sao'), true);
      expect(SearchUtils.matchesSearch('Uberlândia', 'uber'), true);
      expect(SearchUtils.matchesSearch('Brasília', 'brasilia'), true);
    });

    test('does not match when word is not present', () {
      expect(SearchUtils.matchesSearch('São Paulo', 'rio'), false);
      expect(SearchUtils.matchesSearch('Paris', 'london'), false);
    });

    test('handles empty query', () {
      expect(SearchUtils.matchesSearch('São Paulo', ''), true);
    });

    test('handles empty text', () {
      expect(SearchUtils.matchesSearch('', 'paulo'), false);
    });
  });

  group('SearchUtils - Multi-Word Search', () {
    test('matches all words in any order', () {
      expect(SearchUtils.matchesSearch('São Paulo, Brazil', 'paulo sao'), true);
      expect(SearchUtils.matchesSearch('São Paulo, Brazil', 'brazil paulo'), true);
      expect(SearchUtils.matchesSearch('New York City', 'city york new'), true);
    });

    test('requires all words to match', () {
      expect(SearchUtils.matchesSearch('São Paulo', 'paulo rio'), false);
      expect(SearchUtils.matchesSearch('Paris, France', 'paris london'), false);
    });

    test('matches partial words', () {
      expect(SearchUtils.matchesSearch('Uberlândia', 'uber dia'), true);
      expect(SearchUtils.matchesSearch('São Paulo', 'pau'), true);
    });
  });

  group('SearchUtils - Multi-Field Search', () {
    test('matches in any field', () {
      expect(
        SearchUtils.matchesSearchInAny('paulo', ['São Paulo', 'Brazil', 'City']),
        true,
      );
      expect(
        SearchUtils.matchesSearchInAny('brazil', ['São Paulo', 'Brazil', 'City']),
        true,
      );
    });

    test('does not match when not in any field', () {
      expect(
        SearchUtils.matchesSearchInAny('london', ['São Paulo', 'Brazil', 'City']),
        false,
      );
    });

    test('handles null values in fields', () {
      expect(
        SearchUtils.matchesSearchInAny('paulo', ['São Paulo', null, 'City']),
        true,
      );
      expect(
        SearchUtils.matchesSearchInAny('london', [null, null, 'City']),
        false,
      );
    });
  });

  group('SearchUtils - Filter List', () {
    final cities = ['São Paulo', 'Rio de Janeiro', 'Uberlândia', 'Brasília'];

    test('filters list with single field', () {
      final result = SearchUtils.filterList(cities, 'paulo', (city) => city);
      expect(result, ['São Paulo']);
    });

    test('filters list with multi-word query', () {
      final result = SearchUtils.filterList(cities, 'rio janeiro', (city) => city);
      expect(result, ['Rio de Janeiro']);
    });

    test('returns all items when query is empty', () {
      final result = SearchUtils.filterList(cities, '', (city) => city);
      expect(result, cities);
    });

    test('returns empty list when no matches', () {
      final result = SearchUtils.filterList(cities, 'london', (city) => city);
      expect(result, []);
    });
  });

  group('SearchUtils - Filter List Multi-Field', () {
    final memories = [
      {'title': 'Trip to São Paulo', 'location': 'Brazil'},
      {'title': 'Paris Vacation', 'location': 'France'},
      {'title': 'Beach Day', 'location': 'Rio de Janeiro'},
    ];

    test('filters by title', () {
      final result = SearchUtils.filterListMultiField(
        memories,
        'paulo',
        (m) => [m['title'], m['location']],
      );
      expect(result.length, 1);
      expect(result[0]['title'], 'Trip to São Paulo');
    });

    test('filters by location', () {
      final result = SearchUtils.filterListMultiField(
        memories,
        'france',
        (m) => [m['title'], m['location']],
      );
      expect(result.length, 1);
      expect(result[0]['title'], 'Paris Vacation');
    });

    test('filters with multi-word query', () {
      final result = SearchUtils.filterListMultiField(
        memories,
        'beach rio',
        (m) => [m['title'], m['location']],
      );
      expect(result.length, 1);
      expect(result[0]['title'], 'Beach Day');
    });
  });
}

