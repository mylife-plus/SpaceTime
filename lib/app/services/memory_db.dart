import 'dart:io';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static const _databaseName = 'memories.db';
  static const _databaseVersion =
      12; // Updated version for videos support

  // Memory table and columns
  static const tableMemories = 'memories';
  static const columnId = 'id';
  static const columnDate = 'date';
  static const columnTime = 'time';
  static const columnLocation = 'location';
  static const columnLocationCountry = 'location_country';
  static const columnLocationCity = 'location_city';
  static const columnLocationName = 'location_name';
  static const columnLocationAddress = 'location_address';
  static const columnLocationFlag = 'location_flag';
  static const columnLocationLatitude = 'location_latitude';
  static const columnLocationLongitude = 'location_longitude';
  static const columnCategory = 'category';
  static const columnDescription = 'description';
  static const columnImagePath = 'image_path'; // Deprecated - will be removed
  static const columnAudioPath = 'audio_path';
  static const columnTags = 'tags';
  static const columnMentions = 'mentions';
  static const columnCreatedAt = 'created_at';
  static const columnUpdatedAt = 'updated_at';

  // Images table and columns
  static const tableImages = 'memory_images';
  static const columnImageId = 'image_id';
  static const columnMemoryId = 'memory_id';
  static const columnImageData = 'image_data';
  static const columnImageOrder = 'image_order';
  static const columnImageCreatedAt = 'image_created_at';

  // Audio table and columns
  static const tableAudios = 'memory_audios';
  static const columnAudioId = 'audio_id';
  static const columnAudioMemoryId = 'audio_memory_id';
  static const columnAudioFilePath = 'audio_file_path';
  static const columnAudioDuration = 'audio_duration';
  static const columnAudioOrder = 'audio_order';
  static const columnAudioCreatedAt = 'audio_created_at';

  // Videos table and columns
  static const tableVideos = 'memory_videos';
  static const columnVideoId = 'video_id';
  static const columnVideoMemoryId = 'video_memory_id';
  static const columnVideoFilePath = 'video_file_path';
  static const columnVideoDuration = 'video_duration';
  static const columnVideoThumbnailPath = 'video_thumbnail_path';
  static const columnVideoOrder = 'video_order';
  static const columnVideoCreatedAt = 'video_created_at';

  // Tags table and columns
  static const tableTags = 'tags';
  static const columnTagName = 'name';
  static const columnTagCount = 'count';

  // Mentions table and columns
  static const tableMentions = 'mentions';
  static const columnMentionName = 'name';
  static const columnMentionCount = 'count';

  // Categories table and columns (legacy - will be deprecated)
  static const tableCategories = 'categories';
  static const columnCategoryName = 'name';
  static const columnCategoryCount = 'count';

  // Place Categories table and columns
  static const tablePlaceCategories = 'place_categories';
  static const columnPlaceCategoryId = 'place_category_id';
  static const columnPlaceCategoryName = 'place_category_name';
  static const columnPlaceCategoryEmoji = 'place_category_emoji';
  static const columnPlaceCategoryParentId = 'place_category_parent_id';
  static const columnPlaceCategoryOrder = 'place_category_order';
  static const columnPlaceCategoryIsCustom = 'place_category_is_custom';
  static const columnPlaceCategoryCreatedAt = 'place_category_created_at';
  static const columnPlaceCategoryUpdatedAt = 'place_category_updated_at';

  // Hashtag groups table and columns
  static const tableHashtagGroups = 'hashtag_groups';
  static const columnHashtagGroupId = 'hashtag_group_id';
  static const columnHashtagGroupName = 'hashtag_group_name';
  static const columnHashtagGroupParentId = 'hashtag_group_parent_id';
  static const columnHashtagGroupOrder = 'hashtag_group_order';
  static const columnHashtagGroupIsCustom = 'hashtag_group_is_custom';
  static const columnHashtagGroupCreatedAt = 'hashtag_group_created_at';
  static const columnHashtagGroupUpdatedAt = 'hashtag_group_updated_at';

  // Contact groups table and columns
  static const tableContactGroups = 'contact_groups';
  static const columnContactGroupId = 'contact_group_id';
  static const columnContactGroupName = 'contact_group_name';
  static const columnContactGroupParentId = 'contact_group_parent_id';
  static const columnContactGroupOrder = 'contact_group_order';
  static const columnContactGroupIsCustom = 'contact_group_is_custom';
  static const columnContactGroupCreatedAt = 'contact_group_created_at';
  static const columnContactGroupUpdatedAt = 'contact_group_updated_at';

  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  static bool _isInitializing = false;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    // Prevent concurrent initialization
    if (_isInitializing) {
      // Wait for initialization to complete
      while (_isInitializing) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      if (_database != null && _database!.isOpen) {
        return _database!;
      }
    }

    _isInitializing = true;
    try {
      _database = await _initDatabase();
      return _database!;
    } finally {
      _isInitializing = false;
    }
  }

  _initDatabase() async {
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, _databaseName);

      debugPrint('[DatabaseHelper] Initializing database at: $path');

      final db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      // Configure database settings after opening
      await _configureDatabaseSettings(db);

      return db;
    } catch (e) {
      debugPrint('[DatabaseHelper] Error initializing database: $e');

      // Try to recover by deleting corrupted database
      try {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        final path = join(documentsDirectory.path, _databaseName);
        final file = File(path);
        if (await file.exists()) {
          debugPrint('[DatabaseHelper] Attempting to delete corrupted database');
          await file.delete();
        }

        // Try to initialize again
        final db = await openDatabase(
          path,
          version: _databaseVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );

        // Configure database settings after recovery
        await _configureDatabaseSettings(db);
        debugPrint('[DatabaseHelper] Database recovered and opened successfully');

        return db;
      } catch (recoveryError) {
        debugPrint('[DatabaseHelper] Failed to recover database: $recoveryError');
        rethrow;
      }
    }
  }

  /// Configure database settings after opening
  Future<void> _configureDatabaseSettings(Database db) async {
    try {
      debugPrint('[DatabaseHelper] Configuring database settings...');

      // Skip WAL mode for now due to Android compatibility issues
      // Just verify the database is accessible
      await db.rawQuery('SELECT 1');
      debugPrint('[DatabaseHelper] Database accessibility verified');

      debugPrint('[DatabaseHelper] Database configuration completed');
    } catch (e) {
      debugPrint('[DatabaseHelper] Warning: Database configuration failed: $e');
      // Continue without these optimizations if they fail
    }
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableMemories (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnDate TEXT NOT NULL,
        $columnTime TEXT NOT NULL,
        $columnLocation TEXT,
        $columnLocationCountry TEXT,
        $columnLocationCity TEXT,
        $columnLocationName TEXT,
        $columnLocationAddress TEXT,
        $columnLocationFlag TEXT,
        $columnLocationLatitude REAL,
        $columnLocationLongitude REAL,
        $columnCategory TEXT,
        $columnDescription TEXT,
        $columnImagePath TEXT,
        $columnAudioPath TEXT,
        $columnTags TEXT,
        $columnMentions TEXT,
        $columnCreatedAt TEXT NOT NULL,
        $columnUpdatedAt TEXT
      )
    ''');

    // Create images table
    await db.execute('''
      CREATE TABLE $tableImages (
        $columnImageId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnMemoryId INTEGER NOT NULL,
        $columnImageData TEXT NOT NULL,
        $columnImageOrder INTEGER DEFAULT 0,
        $columnImageCreatedAt TEXT NOT NULL,
        FOREIGN KEY ($columnMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
      )
    ''');

    // Create audio table
    await db.execute('''
      CREATE TABLE $tableAudios (
        $columnAudioId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnAudioMemoryId INTEGER NOT NULL,
        $columnAudioFilePath TEXT NOT NULL,
        $columnAudioDuration TEXT NOT NULL,
        $columnAudioOrder INTEGER DEFAULT 0,
        $columnAudioCreatedAt TEXT NOT NULL,
        FOREIGN KEY ($columnAudioMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
      )
    ''');

    // Create videos table
    await db.execute('''
      CREATE TABLE $tableVideos (
        $columnVideoId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnVideoMemoryId INTEGER NOT NULL,
        $columnVideoFilePath TEXT NOT NULL,
        $columnVideoDuration TEXT,
        $columnVideoThumbnailPath TEXT,
        $columnVideoOrder INTEGER DEFAULT 0,
        $columnVideoCreatedAt TEXT NOT NULL,
        FOREIGN KEY ($columnVideoMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTags (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnTagName TEXT UNIQUE NOT NULL,
        $columnTagCount INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableMentions (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnMentionName TEXT UNIQUE NOT NULL,
        $columnMentionCount INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableCategories (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnCategoryName TEXT UNIQUE NOT NULL,
        $columnCategoryCount INTEGER DEFAULT 1
      )
    ''');

    // Create place categories table
    await db.execute('''
      CREATE TABLE $tablePlaceCategories (
        $columnPlaceCategoryId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnPlaceCategoryName TEXT NOT NULL,
        $columnPlaceCategoryEmoji TEXT NOT NULL,
        $columnPlaceCategoryParentId INTEGER,
        $columnPlaceCategoryOrder INTEGER DEFAULT 0,
        $columnPlaceCategoryIsCustom INTEGER DEFAULT 0,
        $columnPlaceCategoryCreatedAt TEXT NOT NULL,
        $columnPlaceCategoryUpdatedAt TEXT NOT NULL,
        FOREIGN KEY ($columnPlaceCategoryParentId) REFERENCES $tablePlaceCategories ($columnPlaceCategoryId) ON DELETE CASCADE
      )
    ''');

    // Create hashtag groups table
    await db.execute('''
      CREATE TABLE $tableHashtagGroups (
        $columnHashtagGroupId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnHashtagGroupName TEXT NOT NULL,
        $columnHashtagGroupParentId INTEGER,
        $columnHashtagGroupOrder INTEGER DEFAULT 0,
        $columnHashtagGroupIsCustom INTEGER DEFAULT 0,
        $columnHashtagGroupCreatedAt TEXT NOT NULL,
        $columnHashtagGroupUpdatedAt TEXT NOT NULL,
        FOREIGN KEY ($columnHashtagGroupParentId) REFERENCES $tableHashtagGroups ($columnHashtagGroupId) ON DELETE CASCADE
      )
    ''');

    // Create contact groups table
    await db.execute('''
      CREATE TABLE $tableContactGroups (
        $columnContactGroupId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnContactGroupName TEXT NOT NULL,
        $columnContactGroupParentId INTEGER,
        $columnContactGroupOrder INTEGER DEFAULT 0,
        $columnContactGroupIsCustom INTEGER DEFAULT 0,
        $columnContactGroupCreatedAt TEXT NOT NULL,
        $columnContactGroupUpdatedAt TEXT NOT NULL,
        FOREIGN KEY ($columnContactGroupParentId) REFERENCES $tableContactGroups ($columnContactGroupId) ON DELETE CASCADE
      )
    ''');

    // Insert predefined categories
    await _insertPredefinedCategories(db);

    // Insert predefined place categories
    await _insertPredefinedPlaceCategories(db);

    // Note: Hashtag groups and contact groups are no longer pre-populated
    // Users will create their own groups as needed
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE $tableTags (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnTagName TEXT UNIQUE NOT NULL,
          $columnTagCount INTEGER DEFAULT 1
        )
      ''');

      await db.execute('''
        CREATE TABLE $tableMentions (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnMentionName TEXT UNIQUE NOT NULL,
          $columnMentionCount INTEGER DEFAULT 1
        )
      ''');
    }

    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE $tableMemories ADD COLUMN $columnUpdatedAt TEXT
      ''');
    }

    if (oldVersion < 4) {
      // The audio_path column already exists, but we'll use it to store multiple audio paths
      // separated by '|' character, similar to how image_path works
      // No schema change needed, just documentation that audio_path can contain multiple paths
    }

    if (oldVersion < 5) {
      // Add categories table
      await db.execute('''
        CREATE TABLE $tableCategories (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnCategoryName TEXT UNIQUE NOT NULL,
          $columnCategoryCount INTEGER DEFAULT 1
        )
      ''');

      // Insert predefined categories
      await _insertPredefinedCategories(db);
    }

    if (oldVersion < 6) {
      // Add images table
      await db.execute('''
        CREATE TABLE $tableImages (
          $columnImageId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnMemoryId INTEGER NOT NULL,
          $columnImageData TEXT NOT NULL,
          $columnImageOrder INTEGER DEFAULT 0,
          $columnImageCreatedAt TEXT NOT NULL,
          FOREIGN KEY ($columnMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
        )
      ''');

      // Migrate existing image data from memories table to images table
      await _migrateExistingImages(db);
    }

    if (oldVersion < 7) {
      // Add audio table
      await db.execute('''
        CREATE TABLE $tableAudios (
          $columnAudioId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnAudioMemoryId INTEGER NOT NULL,
          $columnAudioFilePath TEXT NOT NULL,
          $columnAudioDuration TEXT NOT NULL,
          $columnAudioOrder INTEGER DEFAULT 0,
          $columnAudioCreatedAt TEXT NOT NULL,
          FOREIGN KEY ($columnAudioMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
        )
      ''');

      // Migrate existing audio data from memories table to audio table
      await _migrateExistingAudios(db);
    }

    if (oldVersion < 8) {
      // Add place categories table
      await db.execute('''
        CREATE TABLE $tablePlaceCategories (
          $columnPlaceCategoryId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnPlaceCategoryName TEXT NOT NULL,
          $columnPlaceCategoryEmoji TEXT NOT NULL,
          $columnPlaceCategoryParentId INTEGER,
          $columnPlaceCategoryOrder INTEGER DEFAULT 0,
          $columnPlaceCategoryIsCustom INTEGER DEFAULT 0,
          $columnPlaceCategoryCreatedAt TEXT NOT NULL,
          $columnPlaceCategoryUpdatedAt TEXT NOT NULL,
          FOREIGN KEY ($columnPlaceCategoryParentId) REFERENCES $tablePlaceCategories ($columnPlaceCategoryId) ON DELETE CASCADE
        )
      ''');

      // Insert predefined place categories
      await _insertPredefinedPlaceCategories(db);
    }

    if (oldVersion < 9) {
      // Add enhanced location columns to memories table
      await db.execute(
        'ALTER TABLE $tableMemories ADD COLUMN $columnLocationCountry TEXT',
      );
      await db.execute(
        'ALTER TABLE $tableMemories ADD COLUMN $columnLocationCity TEXT',
      );
      await db.execute(
        'ALTER TABLE $tableMemories ADD COLUMN $columnLocationName TEXT',
      );
      await db.execute(
        'ALTER TABLE $tableMemories ADD COLUMN $columnLocationAddress TEXT',
      );
      await db.execute(
        'ALTER TABLE $tableMemories ADD COLUMN $columnLocationFlag TEXT',
      );
      await db.execute(
        'ALTER TABLE $tableMemories ADD COLUMN $columnLocationLatitude REAL',
      );
      await db.execute(
        'ALTER TABLE $tableMemories ADD COLUMN $columnLocationLongitude REAL',
      );

      debugPrint('✅ Enhanced location columns added to memories table');
    }

    if (oldVersion < 10) {
      // Add hashtag groups table
      await db.execute('''
        CREATE TABLE $tableHashtagGroups (
          $columnHashtagGroupId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnHashtagGroupName TEXT NOT NULL,
          $columnHashtagGroupParentId INTEGER,
          $columnHashtagGroupOrder INTEGER DEFAULT 0,
          $columnHashtagGroupIsCustom INTEGER DEFAULT 0,
          $columnHashtagGroupCreatedAt TEXT NOT NULL,
          $columnHashtagGroupUpdatedAt TEXT NOT NULL,
          FOREIGN KEY ($columnHashtagGroupParentId) REFERENCES $tableHashtagGroups ($columnHashtagGroupId) ON DELETE CASCADE
        )
      ''');

      // Note: Hashtag groups are no longer pre-populated
      // Users will create their own groups as needed

      debugPrint('✅ Hashtag groups table created');
    }

    if (oldVersion < 11) {
      // Add contact groups table
      await db.execute('''
        CREATE TABLE $tableContactGroups (
          $columnContactGroupId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnContactGroupName TEXT NOT NULL,
          $columnContactGroupParentId INTEGER,
          $columnContactGroupOrder INTEGER DEFAULT 0,
          $columnContactGroupIsCustom INTEGER DEFAULT 0,
          $columnContactGroupCreatedAt TEXT NOT NULL,
          $columnContactGroupUpdatedAt TEXT NOT NULL,
          FOREIGN KEY ($columnContactGroupParentId) REFERENCES $tableContactGroups ($columnContactGroupId) ON DELETE CASCADE
        )
      ''');

      // Note: Contact groups are no longer pre-populated
      // Users will create their own groups as needed

      debugPrint('✅ Contact groups table created');
    }

    if (oldVersion < 12) {
      // Add videos table
      await db.execute('''
        CREATE TABLE $tableVideos (
          $columnVideoId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnVideoMemoryId INTEGER NOT NULL,
          $columnVideoFilePath TEXT NOT NULL,
          $columnVideoDuration TEXT,
          $columnVideoThumbnailPath TEXT,
          $columnVideoOrder INTEGER DEFAULT 0,
          $columnVideoCreatedAt TEXT NOT NULL,
          FOREIGN KEY ($columnVideoMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
        )
      ''');

      debugPrint('✅ Videos table created');
    }
  }

  // Migrate existing image data from memories table to images table
  Future<void> _migrateExistingImages(Database db) async {
    try {
      // Get all memories with image data
      final memories = await db.query(
        tableMemories,
        where: '$columnImagePath IS NOT NULL AND $columnImagePath != ""',
      );

      for (final memory in memories) {
        final memoryId = memory[columnId] as int;
        final imagePathString = memory[columnImagePath] as String?;

        if (imagePathString != null && imagePathString.isNotEmpty) {
          // Split multiple images (if stored with | separator)
          final imageDataList =
              imagePathString
                  .split('|')
                  .where((img) => img.isNotEmpty)
                  .toList();

          // Insert each image into the images table
          for (int i = 0; i < imageDataList.length; i++) {
            await db.insert(tableImages, {
              columnMemoryId: memoryId,
              columnImageData: imageDataList[i],
              columnImageOrder: i,
              columnImageCreatedAt: DateTime.now().toIso8601String(),
            });
          }
        }
      }

      debugPrint(
        'Migrated images for ${memories.length} memories to separate table',
      );
    } catch (e) {
      debugPrint('Error migrating existing images: $e');
    }
  }

  // Migrate existing audio data from memories table to audio table
  Future<void> _migrateExistingAudios(Database db) async {
    try {
      // Get all memories with audio data
      final memories = await db.query(
        tableMemories,
        where: '$columnAudioPath IS NOT NULL AND $columnAudioPath != ""',
      );

      for (final memory in memories) {
        final memoryId = memory[columnId] as int;
        final audioPathString = memory[columnAudioPath] as String?;

        if (audioPathString != null && audioPathString.isNotEmpty) {
          // Split multiple audio files (if stored with | separator)
          final audioPathList =
              audioPathString
                  .split('|')
                  .where((path) => path.isNotEmpty)
                  .toList();

          // Insert each audio into the audio table
          for (int i = 0; i < audioPathList.length; i++) {
            // Extract duration from filename or use default
            String duration = '0:00';
            // Try to extract duration from path if it contains duration info
            // For now, use default duration

            await db.insert(tableAudios, {
              columnAudioMemoryId: memoryId,
              columnAudioFilePath: audioPathList[i],
              columnAudioDuration: duration,
              columnAudioOrder: i,
              columnAudioCreatedAt: DateTime.now().toIso8601String(),
            });
          }
        }
      }

      debugPrint(
        'Migrated audio files for ${memories.length} memories to separate table',
      );
    } catch (e) {
      debugPrint('Error migrating existing audio files: $e');
    }
  }

  // Memory operations
  Future<int> insertMemory(Map<String, dynamic> row) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        Database db = await instance.database;

        // Verify database is still open and accessible
        if (!db.isOpen) {
          debugPrint('[DatabaseHelper] Database is closed, reinitializing...');
          _database = null;
          db = await instance.database;
        }

        // Use transaction for better reliability
        return await db.transaction((txn) async {
          debugPrint('[DatabaseHelper] Inserting memory with transaction');
          return await txn.insert(tableMemories, row);
        });

      } catch (e) {
        retryCount++;
        debugPrint('[DatabaseHelper] Error inserting memory (attempt $retryCount/$maxRetries): $e');

        if (retryCount >= maxRetries) {
          debugPrint('[DatabaseHelper] Max retries reached, failing memory insertion');
          rethrow;
        }

        // Reset database connection for retry
        _database = null;
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }

    throw Exception('Failed to insert memory after $maxRetries attempts');
  }

  /// Insert complete memory with images, audio, and videos in a single transaction
  Future<int> insertCompleteMemory({
    required Map<String, dynamic> memoryData,
    List<String>? imageDataList,
    List<Map<String, dynamic>>? audioDataList,
    List<Map<String, dynamic>>? videoDataList,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        Database db = await instance.database;

        // Verify database is still open and accessible
        if (!db.isOpen) {
          debugPrint('[DatabaseHelper] Database is closed during complete memory insert, reinitializing...');
          _database = null;
          db = await instance.database;
        }

        return await db.transaction((txn) async {
          debugPrint('[DatabaseHelper] Starting complete memory insertion transaction');

          // Insert main memory record
          final memoryId = await txn.insert(tableMemories, memoryData);
          debugPrint('[DatabaseHelper] Inserted memory with ID: $memoryId');

          // Insert images if any
          if (imageDataList != null && imageDataList.isNotEmpty) {
            for (int i = 0; i < imageDataList.length; i++) {
              await txn.insert(tableImages, {
                columnMemoryId: memoryId,
                columnImageData: imageDataList[i],
                columnImageOrder: i,
                columnImageCreatedAt: DateTime.now().toIso8601String(),
              });
            }
            debugPrint('[DatabaseHelper] Inserted ${imageDataList.length} images');
          }

          // Insert audio files if any
          if (audioDataList != null && audioDataList.isNotEmpty) {
            for (int i = 0; i < audioDataList.length; i++) {
              final audioData = audioDataList[i];
              await txn.insert(tableAudios, {
                columnAudioMemoryId: memoryId,
                columnAudioFilePath: audioData['path'],
                columnAudioDuration: audioData['duration'],
                columnAudioOrder: i,
                columnAudioCreatedAt: DateTime.now().toIso8601String(),
              });
            }
            debugPrint('[DatabaseHelper] Inserted ${audioDataList.length} audio files');
          }

          // Insert video files if any
          if (videoDataList != null && videoDataList.isNotEmpty) {
            for (int i = 0; i < videoDataList.length; i++) {
              final videoData = videoDataList[i];
              await txn.insert(tableVideos, {
                columnVideoMemoryId: memoryId,
                columnVideoFilePath: videoData['path'],
                columnVideoDuration: videoData['duration'],
                columnVideoThumbnailPath: videoData['thumbnail'],
                columnVideoOrder: i,
                columnVideoCreatedAt: DateTime.now().toIso8601String(),
              });
            }
            debugPrint('[DatabaseHelper] Inserted ${videoDataList.length} video files');
          }

          debugPrint('[DatabaseHelper] Complete memory insertion transaction completed successfully');
          return memoryId;
        });

      } catch (e) {
        retryCount++;
        debugPrint('[DatabaseHelper] Error in complete memory insertion (attempt $retryCount/$maxRetries): $e');

        if (retryCount >= maxRetries) {
          debugPrint('[DatabaseHelper] Max retries reached, failing complete memory insertion');
          rethrow;
        }

        // Reset database connection and wait before retry
        _database = null;
        await Future.delayed(Duration(milliseconds: 1000 * retryCount));
      }
    }

    throw Exception('Failed to insert complete memory after $maxRetries attempts');
  }

  Future<List<Map<String, dynamic>>> queryAllMemories() async {
    Database db = await instance.database;
    return await db.query(tableMemories, orderBy: '$columnCreatedAt DESC');
  }

  Future<List<Map<String, dynamic>>> getMemoriesByDate(DateTime date) async {
    Database db = await instance.database;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return await db.query(
      tableMemories,
      where: '$columnDate = ?',
      whereArgs: [dateStr],
      orderBy: '$columnCreatedAt DESC',
    );
  }

  Future<Map<String, dynamic>?> queryMemory(int id) async {
    Database db = await instance.database;
    var result = await db.query(
      tableMemories,
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> updateMemory(Map<String, dynamic> row) async {
    Database db = await instance.database;
    int id = row[columnId];
    row[columnUpdatedAt] = DateTime.now().toIso8601String();
    return await db.update(
      tableMemories,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteMemory(int id) async {
    Database db = await instance.database;
    // Images will be automatically deleted due to CASCADE constraint
    return await db.delete(
      tableMemories,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  // Image operations
  Future<int> insertMemoryImage(
    int memoryId,
    String imageData,
    int order,
  ) async {
    Database db = await instance.database;
    return await db.insert(tableImages, {
      columnMemoryId: memoryId,
      columnImageData: imageData,
      columnImageOrder: order,
      columnImageCreatedAt: DateTime.now().toIso8601String(),
    });
  }

  Future<List<String>> getMemoryImages(int memoryId) async {
    Database db = await instance.database;
    final result = await db.query(
      tableImages,
      columns: [columnImageData],
      where: '$columnMemoryId = ?',
      whereArgs: [memoryId],
      orderBy: '$columnImageOrder ASC',
    );
    return result.map((row) => row[columnImageData] as String).toList();
  }

  Future<int> deleteMemoryImages(int memoryId) async {
    Database db = await instance.database;
    return await db.delete(
      tableImages,
      where: '$columnMemoryId = ?',
      whereArgs: [memoryId],
    );
  }

  // Delete a specific image by its order in a memory
  Future<int> deleteMemoryImageByOrder(int memoryId, int imageOrder) async {
    Database db = await instance.database;
    return await db.delete(
      tableImages,
      where: '$columnMemoryId = ? AND $columnImageOrder = ?',
      whereArgs: [memoryId, imageOrder],
    );
  }

  // Get image details with order for a specific memory
  Future<List<Map<String, dynamic>>> getMemoryImagesWithOrder(
    int memoryId,
  ) async {
    Database db = await instance.database;
    final result = await db.query(
      tableImages,
      columns: [columnImageId, columnImageData, columnImageOrder],
      where: '$columnMemoryId = ?',
      whereArgs: [memoryId],
      orderBy: '$columnImageOrder ASC',
    );
    return result;
  }

  // Audio operations
  Future<int> insertMemoryAudio(
    int memoryId,
    String audioPath,
    String duration,
    int order,
  ) async {
    Database db = await instance.database;
    return await db.insert(tableAudios, {
      columnAudioMemoryId: memoryId,
      columnAudioFilePath: audioPath,
      columnAudioDuration: duration,
      columnAudioOrder: order,
      columnAudioCreatedAt: DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getMemoryAudios(int memoryId) async {
    Database db = await instance.database;
    final result = await db.query(
      tableAudios,
      columns: [columnAudioFilePath, columnAudioDuration],
      where: '$columnAudioMemoryId = ?',
      whereArgs: [memoryId],
      orderBy: '$columnAudioOrder ASC',
    );
    return result;
  }

  Future<int> deleteMemoryAudios(int memoryId) async {
    Database db = await instance.database;
    return await db.delete(
      tableAudios,
      where: '$columnAudioMemoryId = ?',
      whereArgs: [memoryId],
    );
  }

  // Delete a specific audio by its order in a memory
  Future<int> deleteMemoryAudioByOrder(int memoryId, int audioOrder) async {
    Database db = await instance.database;
    return await db.delete(
      tableAudios,
      where: '$columnAudioMemoryId = ? AND $columnAudioOrder = ?',
      whereArgs: [memoryId, audioOrder],
    );
  }

  // Get audio details with order for a specific memory
  Future<List<Map<String, dynamic>>> getMemoryAudiosWithOrder(
    int memoryId,
  ) async {
    Database db = await instance.database;
    final result = await db.query(
      tableAudios,
      columns: [
        columnAudioId,
        columnAudioFilePath,
        columnAudioDuration,
        columnAudioOrder,
      ],
      where: '$columnAudioMemoryId = ?',
      whereArgs: [memoryId],
      orderBy: '$columnAudioOrder ASC',
    );
    return result;
  }

  // Video operations
  Future<int> insertMemoryVideo(
    int memoryId,
    String videoPath,
    String? duration,
    String? thumbnailPath,
    int order,
  ) async {
    Database db = await instance.database;
    return await db.insert(tableVideos, {
      columnVideoMemoryId: memoryId,
      columnVideoFilePath: videoPath,
      columnVideoDuration: duration,
      columnVideoThumbnailPath: thumbnailPath,
      columnVideoOrder: order,
      columnVideoCreatedAt: DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getMemoryVideos(int memoryId) async {
    Database db = await instance.database;
    final result = await db.query(
      tableVideos,
      columns: [
        columnVideoFilePath,
        columnVideoDuration,
        columnVideoThumbnailPath,
      ],
      where: '$columnVideoMemoryId = ?',
      whereArgs: [memoryId],
      orderBy: '$columnVideoOrder ASC',
    );
    debugPrint('🎥 getMemoryVideos for memory $memoryId: Found ${result.length} videos');
    if (result.isNotEmpty) {
      debugPrint('🎥 Video data: $result');
    }
    return result;
  }

  Future<int> deleteMemoryVideos(int memoryId) async {
    Database db = await instance.database;
    return await db.delete(
      tableVideos,
      where: '$columnVideoMemoryId = ?',
      whereArgs: [memoryId],
    );
  }

  // Delete a specific video by its order in a memory
  Future<int> deleteMemoryVideoByOrder(int memoryId, int videoOrder) async {
    Database db = await instance.database;
    return await db.delete(
      tableVideos,
      where: '$columnVideoMemoryId = ? AND $columnVideoOrder = ?',
      whereArgs: [memoryId, videoOrder],
    );
  }

  // Get video details with order for a specific memory
  Future<List<Map<String, dynamic>>> getMemoryVideosWithOrder(
    int memoryId,
  ) async {
    Database db = await instance.database;
    final result = await db.query(
      tableVideos,
      columns: [
        columnVideoId,
        columnVideoFilePath,
        columnVideoDuration,
        columnVideoThumbnailPath,
        columnVideoOrder,
      ],
      where: '$columnVideoMemoryId = ?',
      whereArgs: [memoryId],
      orderBy: '$columnVideoOrder ASC',
    );
    return result;
  }

  // Tag operations
  Future<int> insertTag(String tag) async {
    Database db = await instance.database;
    try {
      return await db.insert(tableTags, {
        columnTagName: tag.toLowerCase(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } catch (e) {
      await db.rawUpdate(
        'UPDATE $tableTags SET $columnTagCount = $columnTagCount + 1 WHERE $columnTagName = ?',
        [tag.toLowerCase()],
      );
      return 1;
    }
  }

  Future<List<String>> getPopularTags({int limit = 10}) async {
    Database db = await instance.database;
    final result = await db.query(
      tableTags,
      columns: [columnTagName],
      orderBy: '$columnTagCount DESC',
      limit: limit,
    );
    return result.map((e) => e[columnTagName] as String).toList();
  }

  // Mention operations
  Future<int> insertMention(String mention) async {
    Database db = await instance.database;
    try {
      return await db.insert(tableMentions, {
        columnMentionName: mention.toLowerCase(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } catch (e) {
      await db.rawUpdate(
        'UPDATE $tableMentions SET $columnMentionCount = $columnMentionCount + 1 WHERE $columnMentionName = ?',
        [mention.toLowerCase()],
      );
      return 1;
    }
  }

  Future<List<String>> getPopularMentions({int limit = 10}) async {
    Database db = await instance.database;
    final result = await db.query(
      tableMentions,
      columns: [columnMentionName],
      orderBy: '$columnMentionCount DESC',
      limit: limit,
    );
    return result.map((e) => e[columnMentionName] as String).toList();
  }

  // Search operations
  Future<List<Map<String, dynamic>>> searchMemories(String query) async {
    Database db = await instance.database;
    return await db.query(
      tableMemories,
      where:
          '$columnDescription LIKE ? OR $columnTags LIKE ? OR $columnMentions LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: '$columnCreatedAt DESC',
    );
  }

  // Helper method to get audio paths from a memory record
  List<String> getAudioPathsFromMemory(Map<String, dynamic> memory) {
    final audioPathString = memory[columnAudioPath] as String?;
    if (audioPathString == null || audioPathString.isEmpty) {
      return [];
    }
    return audioPathString.split('|').where((path) => path.isNotEmpty).toList();
  }

  // Helper method to get base64 images from a memory record
  List<String> getBase64ImagesFromMemory(Map<String, dynamic> memory) {
    final imageBase64String = memory[columnImagePath] as String?;
    if (imageBase64String == null || imageBase64String.isEmpty) {
      return [];
    }
    return imageBase64String
        .split('|')
        .where((base64) => base64.isNotEmpty)
        .toList();
  }

  // Helper method to get image paths from a memory record (deprecated - now using base64)
  List<String> getImagePathsFromMemory(Map<String, dynamic> memory) {
    final imagePathString = memory[columnImagePath] as String?;
    if (imagePathString == null || imagePathString.isEmpty) {
      return [];
    }
    return imagePathString.split('|').where((path) => path.isNotEmpty).toList();
  }

  // Category operations
  Future<void> _insertPredefinedCategories(Database db) async {
    final predefinedCategories = [
      'Restaurant',
      'Cafe',
      'Park',
      'Beach',
      'Museum',
      'Shopping Mall',
      'Hotel',
      'Airport',
      'Hospital',
      'School',
      'Office',
      'Home',
      'Gym',
      'Library',
      'Theater',
      'Stadium',
      'Church',
      'Temple',
      'Mosque',
      'Market',
      'Gas Station',
      'Bank',
      'Pharmacy',
      'Supermarket',
      'Bakery',
      'Bar',
      'Club',
      'Spa',
      'Salon',
      'Workshop',
    ];

    for (String category in predefinedCategories) {
      try {
        await db.insert(tableCategories, {
          columnCategoryName: category.toLowerCase(),
          columnCategoryCount: 1,
        });
      } catch (e) {
        // Category might already exist, ignore error
      }
    }
  }

  Future<int> insertCategory(String categoryName) async {
    Database db = await instance.database;
    try {
      return await db.insert(tableCategories, {
        columnCategoryName: categoryName.toLowerCase(),
        columnCategoryCount: 1,
      });
    } catch (e) {
      // Category already exists, increment count
      await db.rawUpdate(
        '''
        UPDATE $tableCategories
        SET $columnCategoryCount = $columnCategoryCount + 1
        WHERE $columnCategoryName = ?
      ''',
        [categoryName.toLowerCase()],
      );
      return 0;
    }
  }

  Future<List<String>> getPopularCategories({int limit = 50}) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableCategories,
      orderBy: '$columnCategoryCount DESC, $columnCategoryName ASC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => maps[i][columnCategoryName]);
  }

  Future<List<String>> searchCategories(String query, {int limit = 20}) async {
    Database db = await instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableCategories,
      where: '$columnCategoryName LIKE ?',
      whereArgs: ['%${query.toLowerCase()}%'],
      orderBy: '$columnCategoryCount DESC, $columnCategoryName ASC',
      limit: limit,
    );
    return List.generate(maps.length, (i) => maps[i][columnCategoryName]);
  }

  // Place Categories operations
  Future<void> _insertPredefinedPlaceCategories(Database db) async {
    debugPrint(
      '[DatabaseHelper][_insertPredefinedPlaceCategories] Starting to insert predefined place categories',
    );

    // Import the place categories JSON
    final placeCategoriesJson = {
      "Accommodation": [
        {"name": "Home", "emoji": "🏠"},
        {"name": "Hotel", "emoji": "🏨"},
        {"name": "Motel", "emoji": "🏩"},
        {"name": "Hostel", "emoji": "🛏️"},
        {"name": "Bed and Breakfast", "emoji": "🥞"},
        {"name": "Vacation Rental", "emoji": "🏡"},
        {"name": "Campground", "emoji": "🏕️"},
        {"name": "Resort", "emoji": "🏖️"},
        {"name": "Guest House", "emoji": "🏘️"},
      ],
      "Food and Drink": [
        {"name": "Restaurant", "emoji": "🍽️"},
        {"name": "Cafe", "emoji": "☕️"},
        {"name": "Bar/Pub", "emoji": "🍻"},
        {"name": "Fast Food", "emoji": "🍔"},
        {"name": "Bakery", "emoji": "🥖"},
        {"name": "Food Court", "emoji": "🥡"},
        {"name": "Ice Cream Shop", "emoji": "🍨"},
        {"name": "Coffee Shop", "emoji": "🫘"},
      ],
      "Retail and Shopping": [
        {"name": "Supermarket", "emoji": "🛒"},
        {"name": "Convenience Store", "emoji": "🏪"},
        {"name": "Department Store", "emoji": "🛍️"},
        {"name": "Shopping Mall", "emoji": "🏬"},
        {"name": "Pharmacy", "emoji": "💊"},
        {"name": "Market", "emoji": "🧺"},
        {"name": "Jewelry Store", "emoji": "💍"},
        {"name": "Florist", "emoji": "🌷"},
      ],
      "Health and Medical": [
        {"name": "Hospital", "emoji": "🏥"},
        {"name": "Clinic", "emoji": "🩺"},
        {"name": "Pharmacy", "emoji": "⚕️"},
        {"name": "Dentist", "emoji": "🦷"},
        {"name": "Veterinary Clinic", "emoji": "🐾"},
      ],
      "Education": [
        {"name": "School", "emoji": "🏫"},
        {"name": "University", "emoji": "🧑‍🎓"},
        {"name": "College", "emoji": "🎓"},
        {"name": "Kindergarten", "emoji": "🧒"},
        {"name": "Library", "emoji": "📚"},
      ],
      "Transportation": [
        {"name": "Airport", "emoji": "✈️"},
        {"name": "Train Station", "emoji": "🚆"},
        {"name": "Bus Station", "emoji": "🚍"},
        {"name": "Subway/Metro Station", "emoji": "🚇"},
        {"name": "Taxi Stand", "emoji": "🚖"},
        {"name": "Parking Lot/Garage", "emoji": "🅿️"},
        {"name": "Bicycle Rental", "emoji": "🚲"},
        {"name": "Car Rental", "emoji": "🚗"},
        {"name": "Ferry Terminal", "emoji": "⛴️"},
        {"name": "Charging Station", "emoji": "🔋"},
      ],
      "Financial Service": [
        {"name": "Bank", "emoji": "🏦"},
        {"name": "ATM", "emoji": "🏧"},
        {"name": "Currency Exchange", "emoji": "💱"},
        {"name": "Insurance Agency", "emoji": "📑"},
      ],
      "Entertainment and Recreation": [
        {"name": "Movie Theater", "emoji": "🎬"},
        {"name": "Amusement Park", "emoji": "🎡"},
        {"name": "Zoo", "emoji": "🐘"},
        {"name": "Aquarium", "emoji": "🐠"},
        {"name": "Bowling Alley", "emoji": "🎳"},
        {"name": "Arcade", "emoji": "🕹️"},
        {"name": "Nightclub", "emoji": "💃"},
        {"name": "Casino", "emoji": "♦️"},
        {"name": "Concert Venue", "emoji": "🎤"},
        {"name": "Theater", "emoji": "🎭"},
      ],
      "Cultural and Historical": [
        {"name": "Museum", "emoji": "🏛️"},
        {"name": "Art Gallery", "emoji": "🖼️"},
        {"name": "Historical Site", "emoji": "📜"},
        {"name": "Monument", "emoji": "🗿"},
        {"name": "Archaeological Site", "emoji": "⚒️"},
        {"name": "Castle", "emoji": "🏰"},
        {"name": "Cultural Center", "emoji": "🎎"},
        {"name": "Memorial", "emoji": "🪦"},
      ],
      "Sport and Fitness": [
        {"name": "Gyms/Fitness Center", "emoji": "🏋️"},
        {"name": "Sports Field", "emoji": "⚽️"},
        {"name": "Stadium", "emoji": "🏟️"},
        {"name": "Swimming Pool", "emoji": "🏊"},
        {"name": "Golf Course", "emoji": "⛳️"},
        {"name": "Tennis Court", "emoji": "🎾"},
        {"name": "Skate Park", "emoji": "🛹"},
        {"name": "Yoga Studio", "emoji": "🧘"},
      ],
      "Parks and Nature": [
        {"name": "Park", "emoji": "🌳"},
        {"name": "Nature Reserve", "emoji": "🌲"},
        {"name": "Beach", "emoji": "🏖️"},
        {"name": "Forest", "emoji": "🌴"},
        {"name": "Coast", "emoji": "🌊"},
        {"name": "Botanical Garden", "emoji": "🌺"},
        {"name": "Picnic Area", "emoji": "🧺"},
        {"name": "Playground", "emoji": "🛝"},
        {"name": "Scenic Lookout", "emoji": "🌄"},
      ],
      "Religious Site": [
        {"name": "Church", "emoji": "⛪️"},
        {"name": "Mosque", "emoji": "🕌"},
        {"name": "Temple", "emoji": "🛕"},
        {"name": "Synagogue", "emoji": "🕍"},
        {"name": "Shrine", "emoji": "🎐"},
        {"name": "Monastery", "emoji": "🏯"},
        {"name": "Cemetery", "emoji": "🪦"},
      ],
      "Government and Public Service": [
        {"name": "Post Office", "emoji": "📮"},
        {"name": "Police Station", "emoji": "👮"},
        {"name": "Fire Station", "emoji": "🚒"},
        {"name": "Courthouse", "emoji": "⚖️"},
        {"name": "City Hall", "emoji": "🏛️"},
        {"name": "Embassy/Consulate", "emoji": "🛂"},
        {"name": "Public Library", "emoji": "📖"},
        {"name": "Community Center", "emoji": "🏘️"},
      ],
      "Business and Professional Service": [
        {"name": "Office", "emoji": "🏢"},
        {"name": "Co-working Space", "emoji": "👩‍💻"},
        {"name": "Conference Center", "emoji": "🎤"},
        {"name": "Law Firm", "emoji": "⚖️"},
        {"name": "Accounting Firm", "emoji": "🧾"},
        {"name": "Repair Shop", "emoji": "🔧"},
      ],
      "Beauty and Personal Care": [
        {"name": "Hair Salon", "emoji": "💇"},
        {"name": "Barbershop", "emoji": "💈"},
        {"name": "Spa", "emoji": "💆"},
        {"name": "Nail Salon", "emoji": "💅"},
        {"name": "Tattoo Parlor", "emoji": "🎨"},
      ],
    };

    final currentTime = DateTime.now().toIso8601String();
    int order = 0;

    for (final categoryEntry in placeCategoriesJson.entries) {
      final categoryName = categoryEntry.key;
      final subcategories = categoryEntry.value as List;

      try {
        // Insert main category
        final parentId = await db.insert(tablePlaceCategories, {
          columnPlaceCategoryName: categoryName,
          columnPlaceCategoryEmoji: '📍', // Default emoji for main categories
          columnPlaceCategoryParentId: null,
          columnPlaceCategoryOrder: order++,
          columnPlaceCategoryIsCustom: 0,
          columnPlaceCategoryCreatedAt: currentTime,
          columnPlaceCategoryUpdatedAt: currentTime,
        });

        debugPrint(
          '[DatabaseHelper][_insertPredefinedPlaceCategories] Inserted main category: $categoryName with ID: $parentId',
        );

        // Insert subcategories
        int subOrder = 0;
        for (final subcategory in subcategories) {
          try {
            await db.insert(tablePlaceCategories, {
              columnPlaceCategoryName: subcategory['name'],
              columnPlaceCategoryEmoji: subcategory['emoji'],
              columnPlaceCategoryParentId: parentId,
              columnPlaceCategoryOrder: subOrder++,
              columnPlaceCategoryIsCustom: 0,
              columnPlaceCategoryCreatedAt: currentTime,
              columnPlaceCategoryUpdatedAt: currentTime,
            });
          } catch (e) {
            debugPrint(
              '[DatabaseHelper][_insertPredefinedPlaceCategories] Error inserting subcategory ${subcategory['name']}: $e',
            );
          }
        }
      } catch (e) {
        debugPrint(
          '[DatabaseHelper][_insertPredefinedPlaceCategories] Error inserting main category $categoryName: $e',
        );
      }
    }

    debugPrint(
      '[DatabaseHelper][_insertPredefinedPlaceCategories] Completed inserting predefined place categories',
    );
  }

  /// Get all main place categories (parent categories)
  Future<List<Map<String, dynamic>>> getMainPlaceCategories() async {
    debugPrint(
      '[DatabaseHelper][getMainPlaceCategories] Fetching main categories',
    );
    final db = await database;
    final result = await db.query(
      tablePlaceCategories,
      where: '$columnPlaceCategoryParentId IS NULL',
      orderBy: '$columnPlaceCategoryOrder ASC, $columnPlaceCategoryName ASC',
    );
    debugPrint(
      '[DatabaseHelper][getMainPlaceCategories] Found ${result.length} main categories',
    );

    // Log first few for debugging
    for (int i = 0; i < math.min(3, result.length); i++) {
      debugPrint(
        '[DatabaseHelper][getMainPlaceCategories] Main category $i: ${result[i]}',
      );
    }

    return result;
  }

  /// Get subcategories for a specific parent category
  Future<List<Map<String, dynamic>>> getSubPlaceCategories(int parentId) async {
    final db = await database;
    return await db.query(
      tablePlaceCategories,
      where: '$columnPlaceCategoryParentId = ?',
      whereArgs: [parentId],
      orderBy: '$columnPlaceCategoryOrder ASC, $columnPlaceCategoryName ASC',
    );
  }

  /// Get all place categories (hierarchical structure)
  Future<List<Map<String, dynamic>>> getAllPlaceCategoriesHierarchical() async {
    debugPrint(
      '[DatabaseHelper][getAllPlaceCategoriesHierarchical] Starting hierarchical fetch',
    );

    // Get main categories
    final mainCategories = await getMainPlaceCategories();
    debugPrint(
      '[DatabaseHelper][getAllPlaceCategoriesHierarchical] Found ${mainCategories.length} main categories',
    );

    // For each main category, get its subcategories
    for (final mainCategory in mainCategories) {
      final categoryId = mainCategory[columnPlaceCategoryId];
      debugPrint(
        '[DatabaseHelper][getAllPlaceCategoriesHierarchical] Processing category ID: $categoryId, Name: ${mainCategory[columnPlaceCategoryName]}',
      );

      final subcategories = await getSubPlaceCategories(categoryId);
      debugPrint(
        '[DatabaseHelper][getAllPlaceCategoriesHierarchical] Found ${subcategories.length} subcategories for category: ${mainCategory[columnPlaceCategoryName]}',
      );

      mainCategory['subcategories'] = subcategories;
    }

    debugPrint(
      '[DatabaseHelper][getAllPlaceCategoriesHierarchical] Returning ${mainCategories.length} main categories with subcategories',
    );
    return mainCategories;
  }

  /// Search place categories by name
  Future<List<Map<String, dynamic>>> searchPlaceCategories(
    String query, {
    int limit = 20,
  }) async {
    final db = await database;
    return await db.query(
      tablePlaceCategories,
      where: '$columnPlaceCategoryName LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: '$columnPlaceCategoryOrder ASC, $columnPlaceCategoryName ASC',
      limit: limit,
    );
  }

  /// Add a new custom place category
  Future<int> addCustomPlaceCategory({
    required String name,
    required String emoji,
    int? parentId,
    int order = 0,
  }) async {
    final db = await database;
    final currentTime = DateTime.now().toIso8601String();

    debugPrint(
      '[DatabaseHelper][addCustomPlaceCategory] Adding custom category: $name with emoji: $emoji',
    );

    return await db.insert(tablePlaceCategories, {
      columnPlaceCategoryName: name,
      columnPlaceCategoryEmoji: emoji,
      columnPlaceCategoryParentId: parentId,
      columnPlaceCategoryOrder: order,
      columnPlaceCategoryIsCustom: 1,
      columnPlaceCategoryCreatedAt: currentTime,
      columnPlaceCategoryUpdatedAt: currentTime,
    });
  }

  /// Update an existing place category
  Future<int> updatePlaceCategory({
    required int categoryId,
    String? name,
    String? emoji,
    int? order,
  }) async {
    final db = await database;
    final currentTime = DateTime.now().toIso8601String();

    final updateData = <String, dynamic>{
      columnPlaceCategoryUpdatedAt: currentTime,
    };

    if (name != null) updateData[columnPlaceCategoryName] = name;
    if (emoji != null) updateData[columnPlaceCategoryEmoji] = emoji;
    if (order != null) updateData[columnPlaceCategoryOrder] = order;

    debugPrint(
      '[DatabaseHelper][updatePlaceCategory] Updating category ID: $categoryId with data: $updateData',
    );

    return await db.update(
      tablePlaceCategories,
      updateData,
      where: '$columnPlaceCategoryId = ?',
      whereArgs: [categoryId],
    );
  }

  /// Delete a place category (custom categories and predefined subcategories can be deleted)
  Future<int> deletePlaceCategory(int categoryId) async {
    final db = await database;

    debugPrint(
      '[DatabaseHelper][deletePlaceCategory] Deleting category ID: $categoryId',
    );

    // First, check if this is a main category with subcategories
    final subcategoriesCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tablePlaceCategories WHERE $columnPlaceCategoryParentId = ?',
      [categoryId],
    );
    final hasSubcategories = (subcategoriesCount.first['count'] as int) > 0;

    if (hasSubcategories) {
      debugPrint(
        '[DatabaseHelper][deletePlaceCategory] Cannot delete category with subcategories',
      );
      return 0; // Cannot delete main categories that have subcategories
    }

    // Allow deletion of:
    // 1. Custom categories (both main and sub)
    // 2. Predefined subcategories (but not predefined main categories)
    return await db.delete(
      tablePlaceCategories,
      where:
          '$columnPlaceCategoryId = ? AND ($columnPlaceCategoryIsCustom = 1 OR $columnPlaceCategoryParentId IS NOT NULL)',
      whereArgs: [categoryId],
    );
  }

  /// Check if place categories are already initialized
  Future<bool> arePlaceCategoriesInitialized() async {
    final db = await database;
    final result = await db.query(
      tablePlaceCategories,
      where: '$columnPlaceCategoryIsCustom = 0',
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Format category as it's stored in memories (emoji + space + name)
  String _formatCategoryForMemory(String emoji, String name) {
    return '$emoji $name';
  }

  /// Check if any memories exist with a specific category (using formatted string)
  Future<int> getMemoryCountForCategory(String categoryName) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableMemories WHERE $columnCategory = ?',
      [categoryName],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Check if any memories exist with a specific category by emoji and name
  Future<int> getMemoryCountForCategoryByEmojiAndName(
    String emoji,
    String name,
  ) async {
    final formattedCategory = _formatCategoryForMemory(emoji, name);
    return await getMemoryCountForCategory(formattedCategory);
  }

  /// Get all memories that use a specific category
  Future<List<Map<String, dynamic>>> getMemoriesForCategory(
    String categoryName,
  ) async {
    final db = await database;
    return await db.query(
      tableMemories,
      where: '$columnCategory = ?',
      whereArgs: [categoryName],
      orderBy: '$columnDate DESC, $columnTime DESC',
    );
  }

  /// Get all memories that use a specific category by emoji and name
  Future<List<Map<String, dynamic>>> getMemoriesForCategoryByEmojiAndName(
    String emoji,
    String name,
  ) async {
    final formattedCategory = _formatCategoryForMemory(emoji, name);
    return await getMemoriesForCategory(formattedCategory);
  }

  /// Update category name in all memories that use the old category name
  Future<int> updateMemoryCategoryName(
    String oldCategoryName,
    String newCategoryName,
  ) async {
    final db = await database;
    final currentTime = DateTime.now().toIso8601String();

    debugPrint(
      '[DatabaseHelper][updateMemoryCategoryName] Updating memories from "$oldCategoryName" to "$newCategoryName"',
    );

    final rowsAffected = await db.update(
      tableMemories,
      {columnCategory: newCategoryName, columnUpdatedAt: currentTime},
      where: '$columnCategory = ?',
      whereArgs: [oldCategoryName],
    );

    debugPrint(
      '[DatabaseHelper][updateMemoryCategoryName] Updated $rowsAffected memories',
    );
    return rowsAffected;
  }

  /// Update category in all memories when emoji or name changes
  Future<int> updateMemoryCategoryByEmojiAndName(
    String oldEmoji,
    String oldName,
    String newEmoji,
    String newName,
  ) async {
    final oldFormattedCategory = _formatCategoryForMemory(oldEmoji, oldName);
    final newFormattedCategory = _formatCategoryForMemory(newEmoji, newName);

    debugPrint(
      '[DatabaseHelper][updateMemoryCategoryByEmojiAndName] Updating memories from "$oldFormattedCategory" to "$newFormattedCategory"',
    );

    return await updateMemoryCategoryName(
      oldFormattedCategory,
      newFormattedCategory,
    );
  }

  /// Check if a category can be safely deleted (no memories using it)
  Future<bool> canDeleteCategory(String categoryName) async {
    final memoryCount = await getMemoryCountForCategory(categoryName);
    return memoryCount == 0;
  }

  /// Check if a category can be safely deleted by emoji and name (no memories using it)
  Future<bool> canDeleteCategoryByEmojiAndName(
    String emoji,
    String name,
  ) async {
    final memoryCount = await getMemoryCountForCategoryByEmojiAndName(
      emoji,
      name,
    );
    return memoryCount == 0;
  }

  /// Check if any memories exist with a specific hashtag group name
  Future<int> getMemoryCountForHashtagGroup(String groupName) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableMemories WHERE $columnTags LIKE ?',
      ['%$groupName%'],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Check if any memories exist with a specific contact group name
  Future<int> getMemoryCountForContactGroup(String groupName) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableMemories WHERE $columnMentions LIKE ?',
      ['%$groupName%'],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Check if a hashtag group can be safely deleted (no memories using it)
  Future<bool> canDeleteHashtagGroup(String groupName) async {
    final memoryCount = await getMemoryCountForHashtagGroup(groupName);
    return memoryCount == 0;
  }

  /// Check if a contact group can be safely deleted (no memories using it)
  Future<bool> canDeleteContactGroup(String groupName) async {
    final memoryCount = await getMemoryCountForContactGroup(groupName);
    return memoryCount == 0;
  }

  /// Initialize place categories if not already done (for app launch)
  Future<void> initializePlaceCategoriesIfNeeded() async {
    debugPrint(
      '[DatabaseHelper][initializePlaceCategoriesIfNeeded] Checking if place categories need initialization',
    );

    final isInitialized = await arePlaceCategoriesInitialized();

    if (!isInitialized) {
      debugPrint(
        '[DatabaseHelper][initializePlaceCategoriesIfNeeded] Place categories not initialized, adding them now',
      );
      final db = await database;
      await _insertPredefinedPlaceCategories(db);
    } else {
      debugPrint(
        '[DatabaseHelper][initializePlaceCategoriesIfNeeded] Place categories already initialized',
      );
    }
  }

  /// TEMPORARY: Clear all data from the database (for testing purposes)
  Future<void> clearAllData() async {
    try {
      debugPrint('[DatabaseHelper][clearAllData] Starting database cleanup...');
      final db = await database;

      // Clear all tables in reverse order of dependencies
      await db.delete(tableAudios);
      await db.delete(tableImages);
      await db.delete(tableMemories);
      await db.delete(tableTags);
      await db.delete(tableMentions);
      await db.delete(tableCategories);
      await db.delete(tablePlaceCategories);

      debugPrint('[DatabaseHelper][clearAllData] ✅ All tables cleared');

      // Reinitialize predefined data
      await _insertPredefinedCategories(db);
      await _insertPredefinedPlaceCategories(db);

      debugPrint('[DatabaseHelper][clearAllData] ✅ Predefined data reinserted');
    } catch (e) {
      debugPrint('[DatabaseHelper][clearAllData] ❌ Error clearing database: $e');
      rethrow;
    }
  }

  // Get all memories with their images from separate table
  Future<List<Map<String, dynamic>>> getAllMemoriesWithDetails() async {
    final db = await database;

    try {
      // First, get all memories (without image data to avoid CursorWindow issues)
      final memories = await db.query(
        tableMemories,
        columns: [
          columnId, columnDate, columnTime, columnLocation, columnCategory,
          columnDescription, columnAudioPath, columnTags, columnMentions,
          columnCreatedAt, columnUpdatedAt,
          // Enhanced location fields
          columnLocationCountry, columnLocationCity, columnLocationName,
          columnLocationAddress, columnLocationFlag, columnLocationLatitude,
          columnLocationLongitude,
        ],
        orderBy: '$columnCreatedAt DESC',
      );

      debugPrint('Loaded ${memories.length} memories from database');

      // Then, get images for each memory from the images table
      final List<Map<String, dynamic>> memoriesWithImages = [];

      for (final memory in memories) {
        final memoryId = memory[columnId] as int;

        // Get images for this memory
        final images = await getMemoryImages(memoryId);

        // Get audio files for this memory
        final audios = await getMemoryAudios(memoryId);

        // Get video files for this memory
        final videos = await getMemoryVideos(memoryId);

        // Create memory object with images, audios, and videos
        final memoryWithMedia = Map<String, dynamic>.from(memory);
        memoryWithMedia['images'] = images; // Store as separate field
        memoryWithMedia['audios'] = audios; // Store audio data
        memoryWithMedia['videos'] = videos; // Store video data

        // For backward compatibility, also store in image_path field
        if (images.isNotEmpty) {
          memoryWithMedia[columnImagePath] = images.join('|');
        }

        // For backward compatibility, also store in audio_path field
        if (audios.isNotEmpty) {
          final audioPaths =
              audios
                  .map((audio) => audio[columnAudioFilePath] as String)
                  .toList();
          memoryWithMedia[columnAudioPath] = audioPaths.join('|');
        }

        memoriesWithImages.add(memoryWithMedia);
      }

      debugPrint(
        'Successfully loaded ${memoriesWithImages.length} memories with images',
      );
      return memoriesWithImages;
    } catch (e) {
      debugPrint('Error loading memories with images: $e');
      return [];
    }
  }

  /// Reset database connection (useful for recovery)
  Future<void> resetDatabaseConnection() async {
    try {
      if (_database != null && _database!.isOpen) {
        debugPrint('[DatabaseHelper] Closing existing database connection');
        await _database!.close();
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] Error closing database: $e');
    } finally {
      _database = null;
      _isInitializing = false;
    }

    // Reinitialize
    debugPrint('[DatabaseHelper] Reinitializing database connection');
    await database;
  }

  /// Check if database is healthy and accessible
  Future<bool> isDatabaseHealthy() async {
    try {
      final db = await database;
      if (!db.isOpen) return false;

      // Try a simple query to test database accessibility
      await db.rawQuery('SELECT 1');
      return true;
    } catch (e) {
      debugPrint('[DatabaseHelper] Database health check failed: $e');
      return false;
    }
  }

  // ==================== HASHTAG GROUPS METHODS ====================

  // Note: _insertPredefinedHashtagGroups method removed
  // Hashtag groups are no longer pre-populated - users create their own groups

  /// Insert a new hashtag group
  Future<int> insertHashtagGroup(Map<String, dynamic> group) async {
    final db = await database;
    return await db.insert(tableHashtagGroups, group);
  }

  /// Update a hashtag group
  Future<int> updateHashtagGroup(int groupId, Map<String, dynamic> updates) async {
    try {
      debugPrint('[DatabaseHelper][updateHashtagGroup] ===== DATABASE UPDATE STARTED =====');
      debugPrint('[DatabaseHelper][updateHashtagGroup] Input parameters:');
      debugPrint('  - Group ID: $groupId (type: ${groupId.runtimeType})');
      debugPrint('  - Updates: $updates');
      debugPrint('  - Table: $tableHashtagGroups');
      debugPrint('  - Where clause: $columnHashtagGroupId = ?');
      debugPrint('  - Where args: [$groupId]');

      final db = await database;
      debugPrint('[DatabaseHelper][updateHashtagGroup] Database instance obtained');

      // First, let's check if the record exists
      final existingRecords = await db.query(
        tableHashtagGroups,
        where: '$columnHashtagGroupId = ?',
        whereArgs: [groupId],
      );

      debugPrint('[DatabaseHelper][updateHashtagGroup] Existing records found: ${existingRecords.length}');
      if (existingRecords.isNotEmpty) {
        debugPrint('[DatabaseHelper][updateHashtagGroup] Current record: ${existingRecords.first}');
      } else {
        debugPrint('[DatabaseHelper][updateHashtagGroup] ❌ NO RECORD FOUND with ID $groupId');
      }

      debugPrint('[DatabaseHelper][updateHashtagGroup] 🔄 Executing update...');
      final result = await db.update(
        tableHashtagGroups,
        updates,
        where: '$columnHashtagGroupId = ?',
        whereArgs: [groupId],
      );

      debugPrint('[DatabaseHelper][updateHashtagGroup] Update result: $result rows affected');

      // Verify the update
      if (result > 0) {
        final updatedRecords = await db.query(
          tableHashtagGroups,
          where: '$columnHashtagGroupId = ?',
          whereArgs: [groupId],
        );
        debugPrint('[DatabaseHelper][updateHashtagGroup] ✅ Updated record: ${updatedRecords.first}');
      }

      return result;
    } catch (e) {
      debugPrint('[DatabaseHelper][updateHashtagGroup] ❌ EXCEPTION: $e');
      debugPrint('[DatabaseHelper][updateHashtagGroup] Exception type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Delete a hashtag group
  Future<int> deleteHashtagGroup(int groupId) async {
    final db = await database;

    // First, check if this is a main group with subgroups
    final subgroupsCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableHashtagGroups WHERE $columnHashtagGroupParentId = ?',
      [groupId],
    );
    final hasSubgroups = (subgroupsCount.first['count'] as int) > 0;

    if (hasSubgroups) {
      debugPrint(
        '[DatabaseHelper][deleteHashtagGroup] Cannot delete group with subgroups',
      );
      return 0; // Cannot delete main groups that have subgroups
    }

    // Allow deletion of all groups since there are no predefined groups when app is installed
    return await db.delete(
      tableHashtagGroups,
      where: '$columnHashtagGroupId = ?',
      whereArgs: [groupId],
    );
  }

  /// Get all hashtag groups
  Future<List<Map<String, dynamic>>> getAllHashtagGroups() async {
    final db = await database;
    return await db.query(
      tableHashtagGroups,
      orderBy: '$columnHashtagGroupOrder ASC',
    );
  }

  /// Get main hashtag groups only (no parent)
  Future<List<Map<String, dynamic>>> getMainHashtagGroups() async {
    final db = await database;
    return await db.query(
      tableHashtagGroups,
      where: '$columnHashtagGroupParentId IS NULL',
      orderBy: '$columnHashtagGroupOrder ASC',
    );
  }

  /// Get subgroups for a specific main group
  Future<List<Map<String, dynamic>>> getSubHashtagGroups(int mainGroupId) async {
    final db = await database;
    return await db.query(
      tableHashtagGroups,
      where: '$columnHashtagGroupParentId = ?',
      whereArgs: [mainGroupId],
      orderBy: '$columnHashtagGroupOrder ASC',
    );
  }

  /// Get a specific hashtag group by ID
  Future<Map<String, dynamic>?> getHashtagGroupById(int groupId) async {
    final db = await database;
    final results = await db.query(
      tableHashtagGroups,
      where: '$columnHashtagGroupId = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Check if hashtag groups are already initialized
  Future<bool> areHashtagGroupsInitialized() async {
    // Since there are no predefined groups, always return true to skip initialization
    return true;
  }

  /// Initialize hashtag groups if not already done (for app launch)
  Future<void> initializeHashtagGroupsIfNeeded() async {
    debugPrint(
      '[DatabaseHelper][initializeHashtagGroupsIfNeeded] Hashtag groups initialization skipped - no predefined groups',
    );
    // Note: No longer initializing predefined hashtag groups
    // Users will create their own groups as needed
  }

  // ==================== CONTACT GROUPS METHODS ====================

  // Note: _insertPredefinedContactGroups method removed
  // Contact groups are no longer pre-populated - users create their own groups

  /// Insert a new contact group
  Future<int> insertContactGroup(Map<String, dynamic> group) async {
    final db = await database;
    return await db.insert(tableContactGroups, group);
  }

  /// Update a contact group
  Future<int> updateContactGroup(int groupId, Map<String, dynamic> updates) async {
    try {
      debugPrint('[DatabaseHelper][updateContactGroup] ===== DATABASE UPDATE STARTED =====');
      debugPrint('[DatabaseHelper][updateContactGroup] Input parameters:');
      debugPrint('  - Group ID: $groupId (type: ${groupId.runtimeType})');
      debugPrint('  - Updates: $updates');
      debugPrint('  - Table: $tableContactGroups');
      debugPrint('  - Where clause: $columnContactGroupId = ?');
      debugPrint('  - Where args: [$groupId]');

      final db = await database;
      debugPrint('[DatabaseHelper][updateContactGroup] Database instance obtained');

      // First, let's check if the record exists
      final existingRecords = await db.query(
        tableContactGroups,
        where: '$columnContactGroupId = ?',
        whereArgs: [groupId],
      );

      debugPrint('[DatabaseHelper][updateContactGroup] Existing records found: ${existingRecords.length}');
      if (existingRecords.isNotEmpty) {
        debugPrint('[DatabaseHelper][updateContactGroup] Current record: ${existingRecords.first}');
      } else {
        debugPrint('[DatabaseHelper][updateContactGroup] ❌ NO RECORD FOUND with ID $groupId');
      }

      debugPrint('[DatabaseHelper][updateContactGroup] 🔄 Executing update...');
      final result = await db.update(
        tableContactGroups,
        updates,
        where: '$columnContactGroupId = ?',
        whereArgs: [groupId],
      );

      debugPrint('[DatabaseHelper][updateContactGroup] Update result: $result rows affected');

      // Verify the update
      if (result > 0) {
        final updatedRecords = await db.query(
          tableContactGroups,
          where: '$columnContactGroupId = ?',
          whereArgs: [groupId],
        );
        debugPrint('[DatabaseHelper][updateContactGroup] ✅ Updated record: ${updatedRecords.first}');
      }

      return result;
    } catch (e) {
      debugPrint('[DatabaseHelper][updateContactGroup] ❌ EXCEPTION: $e');
      debugPrint('[DatabaseHelper][updateContactGroup] Exception type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Delete a contact group (only custom groups and subgroups)
  Future<int> deleteContactGroup(int groupId) async {
    final db = await database;

    // First, check if this is a main group with subgroups
    final subgroupsCount = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableContactGroups WHERE $columnContactGroupParentId = ?',
      [groupId],
    );
    final hasSubgroups = (subgroupsCount.first['count'] as int) > 0;

    if (hasSubgroups) {
      debugPrint(
        '[DatabaseHelper][deleteContactGroup] Cannot delete group with subgroups',
      );
      return 0; // Cannot delete main groups that have subgroups
    }

    // Allow deletion of all groups since there are no predefined groups when app is installed
    return await db.delete(
      tableContactGroups,
      where: '$columnContactGroupId = ?',
      whereArgs: [groupId],
    );
  }

  /// Get all contact groups
  Future<List<Map<String, dynamic>>> getAllContactGroups() async {
    final db = await database;
    return await db.query(
      tableContactGroups,
      orderBy: '$columnContactGroupOrder ASC',
    );
  }

  /// Get main contact groups only (no parent)
  Future<List<Map<String, dynamic>>> getMainContactGroups() async {
    final db = await database;
    return await db.query(
      tableContactGroups,
      where: '$columnContactGroupParentId IS NULL',
      orderBy: '$columnContactGroupOrder ASC',
    );
  }

  /// Get subgroups for a specific main group
  Future<List<Map<String, dynamic>>> getSubContactGroups(int mainGroupId) async {
    final db = await database;
    return await db.query(
      tableContactGroups,
      where: '$columnContactGroupParentId = ?',
      whereArgs: [mainGroupId],
      orderBy: '$columnContactGroupOrder ASC',
    );
  }

  /// Get a specific contact group by ID
  Future<Map<String, dynamic>?> getContactGroupById(int groupId) async {
    final db = await database;
    final results = await db.query(
      tableContactGroups,
      where: '$columnContactGroupId = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Check if contact groups are already initialized
  Future<bool> areContactGroupsInitialized() async {
    // Since there are no predefined groups, always return true to skip initialization
    return true;
  }

  /// Initialize contact groups if not already done (for app launch)
  Future<void> initializeContactGroupsIfNeeded() async {
    debugPrint(
      '[DatabaseHelper][initializeContactGroupsIfNeeded] Contact groups initialization skipped - no predefined groups',
    );
    // Note: No longer initializing predefined contact groups
    // Users will create their own groups as needed
  }
}
