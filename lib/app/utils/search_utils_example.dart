import 'package:flutter/material.dart';
import 'search_utils.dart';

/// Example usage of SearchUtils for accent-insensitive, multi-word search
/// 
/// This file demonstrates various use cases for the SearchUtils class.
/// You can use these examples as a reference for implementing search in your app.

// ============================================================================
// Example 1: Basic Text Normalization
// ============================================================================

void exampleNormalization() {
  // Remove accents and normalize text
  print(SearchUtils.normalizeText('São Paulo')); // Output: "sao paulo"
  print(SearchUtils.normalizeText('Uberlândia')); // Output: "uberlandia"
  print(SearchUtils.normalizeText("L'Aquila")); // Output: "laquila"
  print(SearchUtils.normalizeText('Café-Français')); // Output: "cafe francais"
}

// ============================================================================
// Example 2: Single-Word Search
// ============================================================================

void exampleSingleWordSearch() {
  final cities = [
    'São Paulo',
    'Rio de Janeiro',
    'Uberlândia',
    'Brasília',
    'Porto Alegre',
  ];

  // Search for "paulo" - matches "São Paulo"
  final result1 = cities.where((city) => SearchUtils.matchesSearch(city, 'paulo')).toList();
  print(result1); // Output: ['São Paulo']

  // Search for "uber" - matches "Uberlândia"
  final result2 = cities.where((city) => SearchUtils.matchesSearch(city, 'uber')).toList();
  print(result2); // Output: ['Uberlândia']

  // Search for "brasilia" - matches "Brasília" (accent-insensitive)
  final result3 = cities.where((city) => SearchUtils.matchesSearch(city, 'brasilia')).toList();
  print(result3); // Output: ['Brasília']
}

// ============================================================================
// Example 3: Multi-Word Search (Any Order)
// ============================================================================

void exampleMultiWordSearch() {
  final locations = [
    'São Paulo, Brazil',
    'New York City, USA',
    'Rio de Janeiro, Brazil',
    'Paris, France',
  ];

  // Search for "paulo sao" - matches "São Paulo, Brazil"
  final result1 = locations.where((loc) => SearchUtils.matchesSearch(loc, 'paulo sao')).toList();
  print(result1); // Output: ['São Paulo, Brazil']

  // Search for "brazil rio" - matches "Rio de Janeiro, Brazil"
  final result2 = locations.where((loc) => SearchUtils.matchesSearch(loc, 'brazil rio')).toList();
  print(result2); // Output: ['Rio de Janeiro, Brazil']

  // Search for "city york new" - matches "New York City, USA"
  final result3 = locations.where((loc) => SearchUtils.matchesSearch(loc, 'city york new')).toList();
  print(result3); // Output: ['New York City, USA']
}

// ============================================================================
// Example 4: Filtering a List with Single Field
// ============================================================================

void exampleFilterList() {
  final cities = ['São Paulo', 'Rio de Janeiro', 'Uberlândia', 'Brasília'];

  // Filter cities matching "paulo"
  final filtered = SearchUtils.filterList(
    cities,
    'paulo',
    (city) => city, // Extract the city name itself
  );

  print(filtered); // Output: ['São Paulo']
}

// ============================================================================
// Example 5: Filtering a List with Multiple Fields
// ============================================================================

void exampleFilterListMultiField() {
  final memories = [
    {'title': 'Trip to São Paulo', 'location': 'Brazil', 'description': 'Amazing city'},
    {'title': 'Paris Vacation', 'location': 'France', 'description': 'Beautiful architecture'},
    {'title': 'Beach Day', 'location': 'Rio de Janeiro', 'description': 'Sunny weather'},
  ];

  // Search for "paulo" - matches first memory (in title)
  final result1 = SearchUtils.filterListMultiField(
    memories,
    'paulo',
    (memory) => [
      memory['title'] as String?,
      memory['location'] as String?,
      memory['description'] as String?,
    ],
  );
  print(result1.length); // Output: 1

  // Search for "beach rio" - matches third memory (both words found)
  final result2 = SearchUtils.filterListMultiField(
    memories,
    'beach rio',
    (memory) => [
      memory['title'] as String?,
      memory['location'] as String?,
      memory['description'] as String?,
    ],
  );
  print(result2.length); // Output: 1
}

// ============================================================================
// Example 6: Using in a TextField with onChanged
// ============================================================================

class SearchExample extends StatefulWidget {
  const SearchExample({super.key});

  @override
  State<SearchExample> createState() => _SearchExampleState();
}

class _SearchExampleState extends State<SearchExample> {
  final List<String> allCities = [
    'São Paulo',
    'Rio de Janeiro',
    'Uberlândia',
    'Brasília',
    'Porto Alegre',
    'Belo Horizonte',
  ];

  List<String> filteredCities = [];
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    filteredCities = allCities;
  }

  void _onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
      filteredCities = SearchUtils.filterList(
        allCities,
        query,
        (city) => city,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('City Search')),
      body: Column(
        children: [
          // Search TextField
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search cities (e.g., "sao paulo", "uber")',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          // Results List
          Expanded(
            child: ListView.builder(
              itemCount: filteredCities.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(filteredCities[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

