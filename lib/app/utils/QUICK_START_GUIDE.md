# Quick Start Guide - Accent-Insensitive Multi-Word Search

## 🚀 The Feature is Already Working!

The accent-insensitive, multi-word search is already integrated into your SearchOverlay. Just start typing in the search field!

## 📝 How It Works

### Example 1: Searching for Cities with Accents

**Before:** Typing "sao paulo" wouldn't find "São Paulo"  
**Now:** Typing "sao paulo" ✅ finds "São Paulo"

```
User types: "sao paulo"
Matches:
  ✅ São Paulo
  ✅ São Paulo, Brazil
  ✅ Trip to São Paulo
```

### Example 2: Multi-Word Search (Any Order)

**Before:** Words had to be in exact order  
**Now:** Words can be in any order

```
User types: "paulo sao"
Matches:
  ✅ São Paulo (words in any order!)
  
User types: "brazil rio"
Matches:
  ✅ Rio de Janeiro, Brazil
```

### Example 3: Search Across Multiple Fields

**Before:** Search only looked in one field at a time  
**Now:** All words must appear somewhere across all fields

```
User types: "beach rio"
Matches memory with:
  ✅ Title: "Beach Day" (contains "beach")
  ✅ Location: "Rio de Janeiro" (contains "rio")
```

### Example 4: Special Characters Ignored

```
User types: "laquila"
Matches:
  ✅ L'Aquila
  
User types: "cafe francais"
Matches:
  ✅ Café-Français
```

## 🧪 Test It Yourself

### Test 1: Accent Removal
1. Create a memory with location "São Paulo"
2. Search for "sao paulo" (without accents)
3. ✅ Memory should appear in results

### Test 2: Multi-Word (Any Order)
1. Create a memory with location "Rio de Janeiro, Brazil"
2. Search for "brazil rio" (reversed order)
3. ✅ Memory should appear in results

### Test 3: Multi-Field Search
1. Create a memory:
   - Title: "Beach Day"
   - Location: "Rio de Janeiro"
2. Search for "beach rio"
3. ✅ Memory should appear (words from different fields)

### Test 4: Hashtags and Mentions
1. Create a memory with hashtag "#Viagem" (Portuguese for trip)
2. Search for "viagem" (without accent)
3. ✅ Memory should appear in suggestions

## 💡 Pro Tips

### Tip 1: Search Multiple Words
Instead of searching for one word at a time, search for multiple words to narrow down results:
- "paris 2024" - finds Paris memories from 2024
- "beach sunset" - finds beach memories with sunset

### Tip 2: Words Can Be Partial
You don't need to type the full word:
- "uber" matches "Uberlândia"
- "pau" matches "São Paulo"

### Tip 3: Order Doesn't Matter
Type words in any order that's convenient:
- "paulo sao" = "sao paulo"
- "york new" = "new york"

## 🔧 For Developers

### Using SearchUtils in Your Code

```dart
import 'package:spacetime/app/utils/search_utils.dart';

// Example 1: Simple search
bool matches = SearchUtils.matchesSearch('São Paulo', 'sao paulo');
// Returns: true

// Example 2: Multi-field search
bool matches = SearchUtils.matchesSearchInAny('beach rio', [
  'Beach Day',           // Contains "beach"
  'Rio de Janeiro',      // Contains "rio"
  'Sunny weather',
]);
// Returns: true (all words found across fields)

// Example 3: Filter a list
final cities = ['São Paulo', 'Rio de Janeiro', 'Uberlândia'];
final filtered = SearchUtils.filterList(
  cities,
  'paulo',
  (city) => city,
);
// Returns: ['São Paulo']

// Example 4: Filter with multiple fields
final memories = [
  {'title': 'Beach Day', 'location': 'Rio de Janeiro'},
  {'title': 'City Tour', 'location': 'São Paulo'},
];
final filtered = SearchUtils.filterListMultiField(
  memories,
  'beach rio',
  (memory) => [memory['title'], memory['location']],
);
// Returns: [{'title': 'Beach Day', 'location': 'Rio de Janeiro'}]
```

## 📚 More Information

- **Full Documentation**: `lib/app/utils/SEARCH_IMPLEMENTATION.md`
- **Code Examples**: `lib/app/utils/search_utils_example.dart`
- **Tests**: `test/search_utils_test.dart`
- **Source Code**: `lib/app/utils/search_utils.dart`

## ❓ FAQ

**Q: Does it work with all languages?**  
A: Yes! It removes diacritics from all languages (Portuguese, Spanish, French, German, etc.)

**Q: What if I want exact matching?**  
A: The search is designed to be flexible. If you need exact matching, you can modify the `normalizeText()` function.

**Q: Does it affect performance?**  
A: No significant impact. Text normalization is fast and happens on-the-fly.

**Q: Can I search for special characters?**  
A: Special characters are removed during normalization, so searching for them won't work. This is by design to make search more flexible.

**Q: What about numbers?**  
A: Numbers are preserved and searchable (e.g., "2024" will match "2024").

## 🎉 Enjoy Your New Search Feature!

The search is now much more powerful and user-friendly. Users can type naturally without worrying about accents or word order!

