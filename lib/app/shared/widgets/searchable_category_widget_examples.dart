import 'package:flutter/material.dart';
import 'package:spacetime/app/shared/widgets/searchable_category_widget.dart';
import 'package:spacetime/app/models/place_category_model.dart';

/// Examples of how to use the generic SearchableCategoryWidget
/// This file demonstrates different use cases and configurations

class SearchableCategoryWidgetExamples extends StatelessWidget {
  const SearchableCategoryWidgetExamples({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SearchableCategoryWidget Examples')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Example 1: Memory Creation Context
            _buildExampleSection(
              title: '1. Memory Creation Context',
              description: 'Used in memory creation with recent categories and full functionality',
              child: SearchableCategoryWidget(
                title: 'Place Categories',
                onCategorySelected: (category) {
                  // In real usage, this would call: memoryController.setCategory(categoryWithEmoji)
                  debugPrint('Memory: Selected ${category.emoji} ${category.name}');
                },
                saveToRecent: true, // Save to recent categories
                showActionButtons: true, // Show "See all" and "Add new" buttons
              ),
            ),

            const SizedBox(height: 32),

            // Example 2: Filter Popup Context
            _buildExampleSection(
              title: '2. Filter Popup Context',
              description: 'Used in filters with custom background and no action buttons',
              child: SearchableCategoryWidget(
                title: 'Search Places Categories',
                onCategorySelected: (category) {
                  // In real usage, this would call: filterController.addCategory(categoryWithEmoji)
                  debugPrint('Filter: Selected ${category.emoji} ${category.name}');
                },
                saveToRecent: true, // Show recent categories in filter context
                showActionButtons: false, // Hide "See all" and "Add new" buttons in filter context
                backgroundColor: Colors.grey[100], // Custom background
              ),
            ),

            const SizedBox(height: 32),

            // Example 3: Compact Version
            _buildExampleSection(
              title: '3. Compact Version',
              description: 'Minimal version with no action buttons and compact styling',
              child: SearchableCategoryWidget(
                title: 'Quick Category Select',
                onCategorySelected: (category) {
                  debugPrint('Compact: Selected ${category.emoji} ${category.name}');
                },
                saveToRecent: false,
                showActionButtons: false, // No "See all" and "Add new" buttons
                isCompact: true, // Smaller padding, transparent background
              ),
            ),

            const SizedBox(height: 32),

            // Example 4: Custom Icon and Styling
            _buildExampleSection(
              title: '4. Custom Icon and Styling',
              description: 'With custom icon and background color',
              child: SearchableCategoryWidget(
                title: 'Custom Category Picker',
                onCategorySelected: (category) {
                  debugPrint('Custom: Selected ${category.emoji} ${category.name}');
                },
                saveToRecent: true,
                showActionButtons: true,
                iconPath: 'assets/images/ic_location.png', // Custom icon
                backgroundColor: Colors.blue[50], // Custom background
              ),
            ),

            const SizedBox(height: 32),

            // Example 5: With Selected Category Display
            _buildExampleSection(
              title: '5. With Selected Category Display',
              description: 'Shows currently selected category',
              child: SearchableCategoryWidget(
                title: 'Places',
                selectedCategory: '🏠 Home', // Show selected category
                onCategorySelected: (category) {
                  debugPrint('Selected: ${category.emoji} ${category.name}');
                  // In real usage, you would update the selectedCategory value
                },
                saveToRecent: true,
                showActionButtons: true,
              ),
            ),

            const SizedBox(height: 32),

            // Code Examples Section
            _buildCodeExamplesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleSection({
    required String title,
    required String description,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildCodeExamplesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Code Examples',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        
        _buildCodeExample(
          title: 'Memory Creation Usage',
          code: '''
// In memory creation widget
SearchableCategoryWidget(
  selectedCategory: controller.selectedCategory.value,
  onCategorySelected: (category) {
    final categoryWithEmoji = category.emoji.isNotEmpty
        ? '\${category.emoji} \${category.name}'
        : category.name;
    controller.setCategory(categoryWithEmoji);
  },
),''',
        ),

        const SizedBox(height: 16),

        _buildCodeExample(
          title: 'Filter Popup Usage',
          code: '''
// In filter popup
SearchableCategoryWidget(
  title: 'Search Places Categories',
  onCategorySelected: (category) {
    final categoryWithEmoji = category.emoji.isNotEmpty
        ? '\${category.emoji} \${category.name}'
        : category.name;
    controller.addCategory(categoryWithEmoji);
  },
  saveToRecent: true, // Show recent categories in filter context
  showActionButtons: false, // Hide "See all" and "Add new" buttons in filter context
  backgroundColor: uiController.darkMode.value
      ? Colors.white.withValues(alpha: 0.2)
      : Colors.white,
),''',
        ),

        const SizedBox(height: 16),

        _buildCodeExample(
          title: 'Compact Usage',
          code: '''
// Compact version for tight spaces
SearchableCategoryWidget(
  title: 'Quick Select',
  onCategorySelected: (category) => handleSelection(category),
  showActionButtons: false,
  isCompact: true,
  saveToRecent: false,
),''',
        ),
      ],
    );
  }

  Widget _buildCodeExample({
    required String title,
    required String code,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}
