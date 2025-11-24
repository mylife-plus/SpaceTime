import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../services/memory_db.dart';

class DebugDatabaseViewer extends StatelessWidget {
  const DebugDatabaseViewer({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Get.forceAppUpdate(),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getAllMemoriesWithDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No memories found'));
          }

          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final memory = snapshot.data![index];
              return Card(
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ID: ${memory['id']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Date: ${memory['date']}'),
                      Text('Time: ${memory['time']}'),
                      Text('Location: ${memory['location']}'),
                      Text('Description: ${memory['description']}'),
                      if (memory['tags'] != null)
                        Text('Tags: ${memory['tags']}'),
                      Text('Created: ${memory['created_at']}'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.content_copy),
        onPressed: () async {
          final memories =
              await DatabaseHelper.instance.getAllMemoriesWithDetails();
          final text = memories.map((m) => m.toString()).join('\n\n');
          await Clipboard.setData(ClipboardData(text: text));
          Get.snackbar('Copied!', 'Database contents copied to clipboard',         duration: const Duration(seconds: 2));
        },
      ),
    );
  }
}
