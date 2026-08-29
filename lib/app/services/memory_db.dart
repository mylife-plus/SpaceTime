import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:spacetime/app/constants/place_categories_data.dart';

/// One gallery/file item recorded for GPS-upload dedupe (asset id and/or capture time).
class ImportedGalleryAssetRecord {
  const ImportedGalleryAssetRecord({
    this.assetId,
    required this.mediaCreatedAt,
  });

  final String? assetId;
  final DateTime mediaCreatedAt;
}

class DatabaseHelper {
  static const _databaseName = 'memories.db';
  static const _databaseVersion =
      19; // indexes for memory/images/audios/videos to keep large libraries fast

  static const tableImportedGalleryAssets = 'imported_gallery_assets';
  static const columnGalleryAssetRowId = 'row_id';
  static const columnGalleryAssetId = 'asset_id';
  static const columnGalleryAssetMediaCreatedAt = 'media_created_at';
  static const columnGalleryAssetMemoryId = 'memory_id';

  /// Legacy migrated rows — datetime dedupe ignores this sentinel.
  static const importedGalleryMediaCreatedAtUnknownSentinel =
      '1970-01-01T00:00:00.000Z';

  static int mediaCreatedAtDedupeKey(DateTime dt) =>
      dt.toUtc().millisecondsSinceEpoch ~/ 1000;

  /// Stored on [tableTrackImportLog] rows — filters past uploads by screen.
  static const String trackImportSourceGpxKmz = 'gpx_kmz';
  static const String trackImportSourceMediaGps = 'media_gps';

  static const columnTrackImportFingerprint = 'track_import_fingerprint';
  static const tableTrackImportLog = 'track_import_log';
  static const tableTrackImportLogItems = 'track_import_log_items';
  static const columnTrackLogId = 'track_log_id';
  static const columnTrackLogItemId = 'track_log_item_id';
  static const columnTrackLogItemLogId = 'track_log_item_log_id';
  static const columnTrackLogItemWhen = 'item_when';
  static const columnTrackLogItemLat = 'item_lat';
  static const columnTrackLogItemLng = 'item_lng';
  static const columnTrackLogItemLocation = 'item_location';
  static const columnTrackLogItemMemoryId = 'item_memory_id';
  static const columnTrackLogFileName = 'file_name';
  static const columnTrackLogNewCount = 'new_count';
  static const columnTrackLogDupCount = 'dup_count';
  static const columnTrackLogIgnoredCount = 'ignored_count';
  static const columnTrackLogRawCount = 'raw_count';
  static const columnTrackLogCreatedAt = 'created_at';
  static const columnTrackLogImportSource = 'import_source';

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

  /// True while [memories.db] is being replaced on disk (backup restore).
  /// [database] waits so concurrent readers don't hit a closed handle.
  static bool _databaseReplacementInProgress = false;
  static const Duration _replacementWaitTimeout = Duration(minutes: 2);

  Future<Database> get database async {
    final deadline = DateTime.now().add(_replacementWaitTimeout);
    while (_databaseReplacementInProgress) {
      if (DateTime.now().isAfter(deadline)) {
        debugPrint(
          '[DatabaseHelper] database replacement wait timed out — proceeding',
        );
        break;
      }
      await Future.delayed(const Duration(milliseconds: 25));
    }

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

      await _ensureTrackImportLogItemsMemoryIdColumn(db);

      debugPrint('[DatabaseHelper] Database configuration completed');
    } catch (e) {
      debugPrint('[DatabaseHelper] Warning: Database configuration failed: $e');
      // Continue without these optimizations if they fail
    }
  }

  /// Some installs reached schema v15 without running migration 15; add column if missing.
  Future<void> _ensureTrackImportLogItemsMemoryIdColumn(Database db) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($tableTrackImportLogItems)');
      if (info.isEmpty) return;
      final has = info.any((row) => row['name'] == columnTrackLogItemMemoryId);
      if (has) return;
      await db.execute('''
        ALTER TABLE $tableTrackImportLogItems
        ADD COLUMN $columnTrackLogItemMemoryId INTEGER
      ''');
      debugPrint(
        '[DatabaseHelper] Added $columnTrackLogItemMemoryId to $tableTrackImportLogItems',
      );
    } catch (e) {
      debugPrint('[DatabaseHelper] _ensureTrackImportLogItemsMemoryIdColumn: $e');
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
        $columnUpdatedAt TEXT,
        $columnTrackImportFingerprint TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTrackImportLog (
        $columnTrackLogId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnTrackLogFileName TEXT NOT NULL,
        $columnTrackLogRawCount INTEGER NOT NULL DEFAULT 0,
        $columnTrackLogIgnoredCount INTEGER NOT NULL DEFAULT 0,
        $columnTrackLogDupCount INTEGER NOT NULL DEFAULT 0,
        $columnTrackLogNewCount INTEGER NOT NULL DEFAULT 0,
        $columnTrackLogCreatedAt TEXT NOT NULL,
        $columnTrackLogImportSource TEXT NOT NULL DEFAULT '$trackImportSourceGpxKmz'
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTrackImportLogItems (
        $columnTrackLogItemId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnTrackLogItemLogId INTEGER NOT NULL,
        $columnTrackLogItemWhen TEXT NOT NULL,
        $columnTrackLogItemLat REAL NOT NULL,
        $columnTrackLogItemLng REAL NOT NULL,
        $columnTrackLogItemLocation TEXT,
        $columnTrackLogItemMemoryId INTEGER,
        FOREIGN KEY ($columnTrackLogItemLogId) REFERENCES $tableTrackImportLog ($columnTrackLogId) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableImportedGalleryAssets (
        $columnGalleryAssetRowId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnGalleryAssetId TEXT,
        $columnGalleryAssetMediaCreatedAt TEXT NOT NULL,
        $columnGalleryAssetMemoryId INTEGER NOT NULL,
        FOREIGN KEY ($columnGalleryAssetMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_imported_gallery_asset_id
      ON $tableImportedGalleryAssets($columnGalleryAssetId)
      WHERE $columnGalleryAssetId IS NOT NULL AND $columnGalleryAssetId != ''
    ''');
    await db.execute('''
      CREATE INDEX idx_imported_gallery_media_created_at
      ON $tableImportedGalleryAssets($columnGalleryAssetMediaCreatedAt)
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

    await _createMemoryScaleIndexes(db);

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

    if (oldVersion < 13) {
      await db.execute('''
        ALTER TABLE $tableMemories ADD COLUMN $columnTrackImportFingerprint TEXT
      ''');
      await db.execute('''
        CREATE TABLE $tableTrackImportLog (
          $columnTrackLogId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnTrackLogFileName TEXT NOT NULL,
          $columnTrackLogRawCount INTEGER NOT NULL DEFAULT 0,
          $columnTrackLogIgnoredCount INTEGER NOT NULL DEFAULT 0,
          $columnTrackLogDupCount INTEGER NOT NULL DEFAULT 0,
          $columnTrackLogNewCount INTEGER NOT NULL DEFAULT 0,
          $columnTrackLogCreatedAt TEXT NOT NULL,
          $columnTrackLogImportSource TEXT NOT NULL DEFAULT '$trackImportSourceGpxKmz'
        )
      ''');
      debugPrint('✅ track_import_fingerprint + track_import_log');
    }

    if (oldVersion < 14) {
      await db.execute('''
        CREATE TABLE $tableTrackImportLogItems (
          $columnTrackLogItemId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnTrackLogItemLogId INTEGER NOT NULL,
          $columnTrackLogItemWhen TEXT NOT NULL,
          $columnTrackLogItemLat REAL NOT NULL,
          $columnTrackLogItemLng REAL NOT NULL,
          $columnTrackLogItemLocation TEXT,
          FOREIGN KEY ($columnTrackLogItemLogId) REFERENCES $tableTrackImportLog ($columnTrackLogId) ON DELETE CASCADE
        )
      ''');
      debugPrint('✅ track_import_log_items');
    }

    if (oldVersion < 15) {
      await db.execute('''
        ALTER TABLE $tableTrackImportLogItems
        ADD COLUMN $columnTrackLogItemMemoryId INTEGER
      ''');
      debugPrint('✅ track_import_log_items.item_memory_id');
    }

    if (oldVersion < 16) {
      await db.execute('''
        ALTER TABLE $tableTrackImportLog ADD COLUMN $columnTrackLogImportSource TEXT NOT NULL DEFAULT '$trackImportSourceGpxKmz'
      ''');
      await db.rawUpdate(
        '''
        UPDATE $tableTrackImportLog
        SET $columnTrackLogImportSource = ?
        WHERE $columnTrackLogFileName LIKE ?
        ''',
        [trackImportSourceMediaGps, r'Media GPS %'],
      );
      debugPrint('✅ track_import_log.import_source');
    }

    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableImportedGalleryAssets (
          $columnGalleryAssetId TEXT PRIMARY KEY,
          $columnGalleryAssetMemoryId INTEGER NOT NULL,
          FOREIGN KEY ($columnGalleryAssetMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
        )
      ''');
      debugPrint('✅ imported_gallery_assets');
    }

    if (oldVersion < 18) {
      await db.execute('''
        CREATE TABLE imported_gallery_assets_v18 (
          $columnGalleryAssetRowId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnGalleryAssetId TEXT,
          $columnGalleryAssetMediaCreatedAt TEXT NOT NULL,
          $columnGalleryAssetMemoryId INTEGER NOT NULL,
          FOREIGN KEY ($columnGalleryAssetMemoryId) REFERENCES $tableMemories ($columnId) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        INSERT INTO imported_gallery_assets_v18 (
          $columnGalleryAssetId,
          $columnGalleryAssetMediaCreatedAt,
          $columnGalleryAssetMemoryId
        )
        SELECT
          $columnGalleryAssetId,
          '$importedGalleryMediaCreatedAtUnknownSentinel',
          $columnGalleryAssetMemoryId
        FROM $tableImportedGalleryAssets
      ''');
      await db.execute('DROP TABLE $tableImportedGalleryAssets');
      await db.execute(
        'ALTER TABLE imported_gallery_assets_v18 RENAME TO $tableImportedGalleryAssets',
      );
      await db.execute('''
        CREATE UNIQUE INDEX idx_imported_gallery_asset_id
        ON $tableImportedGalleryAssets($columnGalleryAssetId)
        WHERE $columnGalleryAssetId IS NOT NULL AND $columnGalleryAssetId != ''
      ''');
      await db.execute('''
        CREATE INDEX idx_imported_gallery_media_created_at
        ON $tableImportedGalleryAssets($columnGalleryAssetMediaCreatedAt)
      ''');
      debugPrint('✅ imported_gallery_assets.media_created_at');
    }

    if (oldVersion < 19) {
      // getAllMemoriesWithDetails() (ORDER BY created_at DESC + a batch
      // load of ALL rows from images/audios/videos, ORDER BY memory_id) and
      // the per-memory media lookups (WHERE memory_id = ?) both did full
      // table scans + temp-sort on these tables with no supporting index.
      // Harmless at 10-20 memories, but a real cost at ~20,000.
      await _createMemoryScaleIndexes(db);
      debugPrint('✅ memory/images/audios/videos indexes for scale');
    }
  }

  /// Indexes backing [getAllMemoriesWithDetails]'s ORDER BY + the
  /// per-memory `WHERE memory_id = ?` media lookups. IF NOT EXISTS so this
  /// is safe to call from both a fresh [_onCreate] and the v19 migration.
  Future<void> _createMemoryScaleIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_memories_created_at
      ON $tableMemories($columnCreatedAt)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_images_memory_id_order
      ON $tableImages($columnMemoryId, $columnImageOrder)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_audios_memory_id_order
      ON $tableAudios($columnAudioMemoryId, $columnAudioOrder)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_videos_memory_id_order
      ON $tableVideos($columnVideoMemoryId, $columnVideoOrder)
    ''');
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

  /// Rows used for KMZ/GPX import duplicate detection.
  Future<List<Map<String, dynamic>>> queryMemoriesTrackImportDedupeRows() async {
    final db = await database;
    return db.query(
      tableMemories,
      columns: [
        columnDate,
        columnTime,
        columnLocationLatitude,
        columnLocationLongitude,
        columnTrackImportFingerprint,
      ],
    );
  }

  /// Gallery-import memories (for merging new clusters into existing ones).
  Future<Set<String>> queryImportedGalleryAssetIds() async {
    final db = await database;
    final rows = await db.query(
      tableImportedGalleryAssets,
      columns: [columnGalleryAssetId],
    );
    return rows
        .map((r) => r[columnGalleryAssetId] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Set<int>> queryImportedGalleryMediaCreatedAtKeys() async {
    final db = await database;
    final rows = await db.query(
      tableImportedGalleryAssets,
      columns: [columnGalleryAssetMediaCreatedAt],
    );
    final out = <int>{};
    for (final r in rows) {
      final raw = r[columnGalleryAssetMediaCreatedAt] as String?;
      if (raw == null ||
          raw.isEmpty ||
          raw == importedGalleryMediaCreatedAtUnknownSentinel) {
        continue;
      }
      final dt = DateTime.tryParse(raw);
      if (dt != null) out.add(mediaCreatedAtDedupeKey(dt));
    }
    return out;
  }

  Future<void> recordImportedGalleryAssets(
    int memoryId,
    Iterable<ImportedGalleryAssetRecord> records,
  ) async {
    final db = await database;
    await _insertImportedGalleryAssetRecords(db, memoryId, records);
  }

  /// Replaces gallery image/video dedupe rows for [memoryId] only — other
  /// memories' dedupe entries are never touched.
  Future<void> replaceImportedGalleryDedupeForMemory(
    int memoryId,
    Iterable<ImportedGalleryAssetRecord> records,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await purgeImportedGalleryDedupeForMemory(txn, memoryId);
      await _insertImportedGalleryAssetRecords(txn, memoryId, records);
    });
  }

  Future<void> _insertImportedGalleryAssetRecords(
    DatabaseExecutor db,
    int memoryId,
    Iterable<ImportedGalleryAssetRecord> records,
  ) async {
    final batch = db.batch();
    var count = 0;
    for (final record in records) {
      final id = record.assetId?.trim();
      batch.insert(
        tableImportedGalleryAssets,
        {
          columnGalleryAssetId:
              (id != null && id.isNotEmpty) ? id : null,
          columnGalleryAssetMediaCreatedAt:
              record.mediaCreatedAt.toUtc().toIso8601String(),
          columnGalleryAssetMemoryId: memoryId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      count++;
    }
    if (count == 0) return;
    await batch.commit(noResult: true);
  }

  /// Removes gallery image/video dedupe rows for [memoryId] only.
  Future<int> purgeImportedGalleryDedupeForMemory(
    DatabaseExecutor db,
    int memoryId,
  ) async {
    return db.delete(
      tableImportedGalleryAssets,
      where: '$columnGalleryAssetMemoryId = ?',
      whereArgs: [memoryId],
    );
  }

  Future<List<Map<String, dynamic>>> queryMemoriesGalleryMergeCandidates() async {
    final db = await database;
    return db.query(
      tableMemories,
      columns: [
        columnId,
        columnCreatedAt,
        columnLocationLatitude,
        columnLocationLongitude,
        columnTrackImportFingerprint,
      ],
      where: '$columnTrackImportFingerprint LIKE ?',
      whereArgs: const ['gallery:%'],
    );
  }

  Future<int> maxImageOrderForMemory(int memoryId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT IFNULL(MAX($columnImageOrder), -1) AS m FROM $tableImages WHERE $columnMemoryId = ?',
      [memoryId],
    );
    if (r.isEmpty) return -1;
    return (r.first['m'] as num?)?.toInt() ?? -1;
  }

  Future<int> maxVideoOrderForMemory(int memoryId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT IFNULL(MAX($columnVideoOrder), -1) AS m FROM $tableVideos WHERE $columnVideoMemoryId = ?',
      [memoryId],
    );
    if (r.isEmpty) return -1;
    return (r.first['m'] as num?)?.toInt() ?? -1;
  }

  Future<int> maxAudioOrderForMemory(int memoryId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT IFNULL(MAX($columnAudioOrder), -1) AS m FROM $tableAudios WHERE $columnAudioMemoryId = ?',
      [memoryId],
    );
    if (r.isEmpty) return -1;
    return (r.first['m'] as num?)?.toInt() ?? -1;
  }

  Future<int> touchMemoryUpdatedAt(int memoryId) async {
    final db = await database;
    return db.update(
      tableMemories,
      {columnUpdatedAt: DateTime.now().toIso8601String()},
      where: '$columnId = ?',
      whereArgs: [memoryId],
    );
  }

  Future<int> insertTrackImportLog({
    required String fileName,
    required int rawCount,
    required int ignoredCount,
    required int dupCount,
    required int newCount,
    String importSource = trackImportSourceGpxKmz,
  }) async {
    final db = await database;
    return db.insert(tableTrackImportLog, {
      columnTrackLogFileName: fileName,
      columnTrackLogRawCount: rawCount,
      columnTrackLogIgnoredCount: ignoredCount,
      columnTrackLogDupCount: dupCount,
      columnTrackLogNewCount: newCount,
      columnTrackLogCreatedAt: DateTime.now().toIso8601String(),
      columnTrackLogImportSource: importSource,
    });
  }

  Future<void> insertTrackImportLogItems({
    required int logId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final it in items) {
      final mid = it[columnTrackLogItemMemoryId];
      final row = <String, dynamic>{
        columnTrackLogItemLogId: logId,
        columnTrackLogItemWhen: (it[columnTrackLogItemWhen] ?? '').toString(),
        columnTrackLogItemLat: (it[columnTrackLogItemLat] as num?)?.toDouble() ?? 0.0,
        columnTrackLogItemLng: (it[columnTrackLogItemLng] as num?)?.toDouble() ?? 0.0,
        columnTrackLogItemLocation: (it[columnTrackLogItemLocation] ?? '').toString(),
      };
      if (mid is int) {
        row[columnTrackLogItemMemoryId] = mid;
      } else if (mid is num) {
        row[columnTrackLogItemMemoryId] = mid.toInt();
      }
      batch.insert(tableTrackImportLogItems, row);
    }
    await batch.commit(noResult: true);
  }

  Future<int> countTrackImportLogs({String? importSource}) async {
    final db = await database;
    if (importSource == null || importSource.isEmpty) {
      final r = await db.rawQuery(
        'SELECT COUNT(*) as c FROM $tableTrackImportLog',
      );
      return Sqflite.firstIntValue(r) ?? 0;
    }
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $tableTrackImportLog WHERE $columnTrackLogImportSource = ?',
      [importSource],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Map<String, dynamic>>> queryTrackImportLogs({
    String? importSource,
  }) async {
    final db = await database;
    if (importSource == null || importSource.isEmpty) {
      return db.query(
        tableTrackImportLog,
        orderBy: '$columnTrackLogCreatedAt DESC',
      );
    }
    return db.query(
      tableTrackImportLog,
      where: '$columnTrackLogImportSource = ?',
      whereArgs: [importSource],
      orderBy: '$columnTrackLogCreatedAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> queryTrackImportLogItems(int logId) async {
    final db = await database;
    return db.query(
      tableTrackImportLogItems,
      where: '$columnTrackLogItemLogId = ?',
      whereArgs: [logId],
      orderBy: '$columnTrackLogItemWhen DESC',
    );
  }

  Future<int> deleteTrackImportLog(int logId) async {
    final db = await database;
    return db.delete(
      tableTrackImportLog,
      where: '$columnTrackLogId = ?',
      whereArgs: [logId],
    );
  }

  /// Removes past-upload rows for [memoryId] and deletes the parent log when no
  /// memories from that upload remain.
  Future<void> purgeTrackImportLogEntriesForMemory(
    DatabaseExecutor db,
    int memoryId,
  ) async {
    final affected = await db.query(
      tableTrackImportLogItems,
      columns: [columnTrackLogItemLogId],
      where: '$columnTrackLogItemMemoryId = ?',
      whereArgs: [memoryId],
    );
    final logIds = <int>{};
    for (final row in affected) {
      final v = row[columnTrackLogItemLogId];
      if (v is int) {
        logIds.add(v);
      } else if (v is num) {
        logIds.add(v.toInt());
      }
    }
    if (logIds.isEmpty) return;

    await db.delete(
      tableTrackImportLogItems,
      where: '$columnTrackLogItemMemoryId = ?',
      whereArgs: [memoryId],
    );

    for (final logId in logIds) {
      await _deleteTrackImportLogIfNoMemoriesRemain(db, logId);
    }
  }

  Future<void> _deleteTrackImportLogIfNoMemoriesRemain(
    DatabaseExecutor db,
    int logId,
  ) async {
    final items = await db.query(
      tableTrackImportLogItems,
      columns: [columnTrackLogItemMemoryId],
      where: '$columnTrackLogItemLogId = ?',
      whereArgs: [logId],
    );
    if (items.isEmpty) {
      await db.delete(
        tableTrackImportLog,
        where: '$columnTrackLogId = ?',
        whereArgs: [logId],
      );
      return;
    }

    for (final item in items) {
      final mid = item[columnTrackLogItemMemoryId];
      if (mid == null) continue;
      final memId = mid is int ? mid : (mid as num).toInt();
      final mem = await db.query(
        tableMemories,
        columns: [columnId],
        where: '$columnId = ?',
        whereArgs: [memId],
        limit: 1,
      );
      if (mem.isNotEmpty) return;
    }

    await db.delete(
      tableTrackImportLog,
      where: '$columnTrackLogId = ?',
      whereArgs: [logId],
    );
  }

  Future<void> deleteTrackImportLogAndMemories(int logId) async {
    final db = await database;
    final items = await db.query(
      tableTrackImportLogItems,
      columns: [columnTrackLogItemMemoryId],
      where: '$columnTrackLogItemLogId = ?',
      whereArgs: [logId],
    );
    final memoryIds = <int>{};
    for (final row in items) {
      final v = row[columnTrackLogItemMemoryId];
      if (v is int) {
        memoryIds.add(v);
      } else if (v is num) {
        memoryIds.add(v.toInt());
      }
    }

    for (final id in memoryIds) {
      await deleteMemory(id);
    }

    // Drop leftover log rows even when legacy items had no memory_id.
    await db.delete(
      tableTrackImportLogItems,
      where: '$columnTrackLogItemLogId = ?',
      whereArgs: [logId],
    );
    await db.delete(
      tableTrackImportLog,
      where: '$columnTrackLogId = ?',
      whereArgs: [logId],
    );

    await purgeOrphanedImportedGalleryDedupe();
  }

  /// Gallery dedupe rows whose memory was removed without a full [deleteMemory] pass.
  Future<void> purgeOrphanedImportedGalleryDedupe() async {
    final db = await database;
    await db.rawDelete('''
      DELETE FROM $tableImportedGalleryAssets
      WHERE $columnGalleryAssetMemoryId NOT IN (
        SELECT $columnId FROM $tableMemories
      )
    ''');
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
    List<int>? imageOrders,
    List<int>? videoOrders,
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
                columnImageOrder: (imageOrders != null && i < imageOrders.length) ? imageOrders[i] : i,
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
                columnVideoOrder: (videoOrders != null && i < videoOrders.length) ? videoOrders[i] : i,
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

  static bool _storedValueLooksLikeFilesystemMediaRef(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t.startsWith('data:')) return false;
    if (t.startsWith('/') ||
        t.startsWith('memory_images/') ||
        t.startsWith('memory_videos/') ||
        t.startsWith('memory_audios/') ||
        t.startsWith('audio_files/') ||
        t.startsWith('imported_media/') ||
        t.startsWith('temp_draft_')) {
      return true;
    }
    if (t.contains(r'\')) return true;
    return false;
  }

  Future<String> _absolutePathUnderDocuments(String stored) async {
    if (stored.startsWith('/')) return stored;
    final appDir = await getApplicationDocumentsDirectory();
    return join(appDir.path, stored);
  }

  Future<void> _tryDeleteFilePath(String path) async {
    if (path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[DatabaseHelper] file delete skipped: $path ($e)');
    }
  }

  /// Public helper for edit flows that drop media refs without erase-all.
  Future<void> deleteStoredMediaFileIfPresent(String storedValue) async {
    if (storedValue.isEmpty) return;
    if (!_storedValueLooksLikeFilesystemMediaRef(storedValue) &&
        !storedValue.startsWith('memory_audios/') &&
        !storedValue.startsWith('/') &&
        !storedValue.contains('.mp4') &&
        !storedValue.contains('.mov') &&
        !storedValue.contains('.m4a') &&
        !storedValue.contains('.jpg') &&
        !storedValue.contains('.jpeg') &&
        !storedValue.contains('.png') &&
        !storedValue.contains('.webp')) {
      return;
    }
    await _tryDeleteFilePath(await _absolutePathUnderDocuments(storedValue));
  }

  /// Known on-disk media folders under Documents (not offline tiles / mbtiles).
  static const List<String> memoryMediaDirectoryNames = [
    'memory_images',
    'memory_videos',
    'memory_audios',
    'audio_files',
    'temp_draft_images',
    'temp_draft_audio',
    'temp_draft_videos',
    'imported_media',
    'backups',
  ];

  /// Folders under Library/Caches (or temp) that are safe to wipe on erase-all.
  static const List<String> memoryCacheDirectoryNames = [
    'media_gps_file_staging',
    'mapbox_tiles',
  ];

  Future<int> _directorySizeBytes(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _deleteDirectoryFully(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
    } catch (e) {
      debugPrint(
        '[DatabaseHelper] full delete failed ${dir.path}: $e — wiping contents',
      );
      await _wipeDirectoryContents(dir);
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _wipeDirectoryContents(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      final children = await dir.list(followLinks: false).toList();
      for (final entity in children) {
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          debugPrint(
            '[DatabaseHelper] wipe skipped ${entity.path}: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] wipe dir failed ${dir.path}: $e');
    }
  }

  /// Map assets that must survive erase-all (MBTiles + style JSON).
  static const String offlineTilesDirectoryName = 'offline_tiles';

  /// Style filenames that must never be deleted during memory wipe.
  static const List<String> preservedMapStyleFileNames = [
    'custom-style.json',
    'style.json',
  ];

  /// True for Application Support / Documents children that must survive erase-all.
  bool _isPreservedMapStorageName(String name) {
    // offline_tiles holds tiles.mbtiles AND custom-style.json.
    return name == offlineTilesDirectoryName;
  }

  bool _isPreservedMapStyleFile(String path) {
    final name = basename(path).toLowerCase();
    return preservedMapStyleFileNames.any((f) => f.toLowerCase() == name);
  }

  /// Deletes all memory media / temp / non-map caches.
  /// Preserves `offline_tiles` (MBTiles + map style JSON). Does not touch
  /// SharedPreferences.
  Future<void> purgeAllMemoryMediaFromDisk() async {
    Future<void> logSize(String label, Directory dir) async {
      final bytes = await _directorySizeBytes(dir);
      if (bytes <= 0) return;
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      debugPrint('[DatabaseHelper] disk before wipe: $label = ${mb}MB');
    }

    final appDir = await getApplicationDocumentsDirectory();
    await logSize('Documents', appDir);

    for (final name in memoryMediaDirectoryNames) {
      if (_isPreservedMapStorageName(name)) continue;
      await _deleteDirectoryFully(Directory(join(appDir.path, name)));
    }

    // Loose media files that may sit at Documents root (legacy absolute copies).
    // Never delete map style JSON or the offline_tiles folder.
    try {
      await for (final entity in appDir.list(followLinks: false)) {
        final name = basename(entity.path);
        if (_isPreservedMapStorageName(name)) continue;
        if (entity is File && _isPreservedMapStyleFile(entity.path)) continue;
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        const mediaExts = [
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.heic',
          '.mp4',
          '.mov',
          '.m4v',
          '.m4a',
          '.aac',
          '.mp3',
          '.wav',
          '.caf',
        ];
        if (mediaExts.any(lower.endsWith)) {
          await _tryDeleteFilePath(entity.path);
        }
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] documents root media scan: $e');
    }

    // Temp: edit sessions, video thumbs, backup zips, GPS staging.
    // Skip style JSON / offline_tiles if they ever land here.
    try {
      final tmp = await getTemporaryDirectory();
      await logSize('tmp', tmp);
      await _wipeDirectoryContentsPreservingMapAssets(tmp);
    } catch (e) {
      debugPrint('[DatabaseHelper] temp wipe skipped: $e');
    }

    // Cache: wipe known folders + leftovers. Preserve map style if present.
    try {
      final cache = await getApplicationCacheDirectory();
      await logSize('cache', cache);
      for (final name in memoryCacheDirectoryNames) {
        await _deleteDirectoryFully(Directory(join(cache.path, name)));
      }
      await for (final entity in cache.list(followLinks: false)) {
        final name = basename(entity.path);
        if (name.startsWith('.')) continue;
        if (_isPreservedMapStorageName(name)) continue;
        if (entity is File && _isPreservedMapStyleFile(entity.path)) continue;
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          debugPrint('[DatabaseHelper] cache wipe skipped $name: $e');
        }
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] cache wipe skipped: $e');
    }

    // Application Support: keep offline_tiles (MBTiles + custom-style.json).
    try {
      final support = await getApplicationSupportDirectory();
      await logSize('support', support);
      await for (final entity in support.list(followLinks: false)) {
        final name = basename(entity.path);
        if (_isPreservedMapStorageName(name)) {
          debugPrint(
            '[DatabaseHelper] preserving map assets: ${entity.path}',
          );
          continue;
        }
        if (entity is File && _isPreservedMapStyleFile(entity.path)) {
          debugPrint(
            '[DatabaseHelper] preserving map style file: ${entity.path}',
          );
          continue;
        }
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          debugPrint('[DatabaseHelper] support wipe skipped $name: $e');
        }
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] support wipe skipped: $e');
    }

    debugPrint(
      '[DatabaseHelper] purgeAllMemoryMediaFromDisk finished '
      '(offline_tiles + style JSON preserved)',
    );
  }

  /// Wipe dir contents but keep offline_tiles / style JSON.
  Future<void> _wipeDirectoryContentsPreservingMapAssets(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      final children = await dir.list(followLinks: false).toList();
      for (final entity in children) {
        final name = basename(entity.path);
        if (_isPreservedMapStorageName(name)) continue;
        if (entity is File && _isPreservedMapStyleFile(entity.path)) continue;
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          debugPrint(
            '[DatabaseHelper] wipe skipped ${entity.path}: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] wipe dir failed ${dir.path}: $e');
    }
  }

  /// Deletes media files on disk for this memory (paths in images/videos/audios tables).
  Future<void> purgeMemoryMediaFilesFromDisk(int memoryId) async {
    final db = await instance.database;

    final imgRows = await db.query(
      tableImages,
      columns: [columnImageData],
      where: '$columnMemoryId = ?',
      whereArgs: [memoryId],
    );
    for (final r in imgRows) {
      final data = (r[columnImageData] ?? '').toString();
      if (_storedValueLooksLikeFilesystemMediaRef(data)) {
        await _tryDeleteFilePath(await _absolutePathUnderDocuments(data));
      }
    }

    final audRows = await db.query(
      tableAudios,
      columns: [columnAudioFilePath],
      where: '$columnAudioMemoryId = ?',
      whereArgs: [memoryId],
    );
    for (final r in audRows) {
      final p = (r[columnAudioFilePath] ?? '').toString();
      if (p.isNotEmpty) {
        await _tryDeleteFilePath(await _absolutePathUnderDocuments(p));
      }
    }

    final vidRows = await db.query(
      tableVideos,
      columns: [columnVideoFilePath, columnVideoThumbnailPath],
      where: '$columnVideoMemoryId = ?',
      whereArgs: [memoryId],
    );
    for (final r in vidRows) {
      final vp = (r[columnVideoFilePath] ?? '').toString();
      final tp = (r[columnVideoThumbnailPath] ?? '').toString();
      if (vp.isNotEmpty) {
        await _tryDeleteFilePath(await _absolutePathUnderDocuments(vp));
      }
      if (tp.isNotEmpty) {
        await _tryDeleteFilePath(await _absolutePathUnderDocuments(tp));
      }
    }
  }

  Future<int> deleteMemory(int id) async {
    // Purge files while DB rows still exist (works with or without FK cascade).
    await purgeMemoryMediaFilesFromDisk(id);

    final Database db = await instance.database;
    return db.transaction((txn) async {
      await purgeImportedGalleryDedupeForMemory(txn, id);
      await purgeTrackImportLogEntriesForMemory(txn, id);
      await txn.delete(
        tableImages,
        where: '$columnMemoryId = ?',
        whereArgs: [id],
      );
      await txn.delete(
        tableAudios,
        where: '$columnAudioMemoryId = ?',
        whereArgs: [id],
      );
      await txn.delete(
        tableVideos,
        where: '$columnVideoMemoryId = ?',
        whereArgs: [id],
      );
      return txn.delete(
        tableMemories,
        where: '$columnId = ?',
        whereArgs: [id],
      );
    });
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

    const placeCategoriesJson = kPlaceCategoriesSeed;

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
    int? parentId,
  }) async {
    final db = await database;
    final currentTime = DateTime.now().toIso8601String();

    final updateData = <String, dynamic>{
      columnPlaceCategoryUpdatedAt: currentTime,
    };

    if (name != null) updateData[columnPlaceCategoryName] = name;
    if (emoji != null) updateData[columnPlaceCategoryEmoji] = emoji;
    if (order != null) updateData[columnPlaceCategoryOrder] = order;
    if (parentId != null) updateData[columnPlaceCategoryParentId] = parentId;

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

  /// Clear all memories and memory-attached media/log rows only.
  /// Also wipes on-disk media / temp / non-map caches, then VACUUMs SQLite so
  /// iOS/Android Settings reflect reclaimed space. Offline MBTiles are kept.
  Future<void> clearAllMemories() async {
    try {
      debugPrint('[DatabaseHelper][clearAllMemories] Starting memories cleanup...');

      // Log DB size before (base64-era rows can leave a multi-GB file).
      try {
        final docs = await getApplicationDocumentsDirectory();
        final dbFile = File(join(docs.path, _databaseName));
        if (await dbFile.exists()) {
          final mb =
              ((await dbFile.length()) / (1024 * 1024)).toStringAsFixed(1);
          debugPrint('[DatabaseHelper][clearAllMemories] DB size before: ${mb}MB');
        }
      } catch (_) {}

      // Files first — catches orphans from edit-remove and erase-all.
      await purgeAllMemoryMediaFromDisk();

      final db = await database;
      await db.transaction((txn) async {
        await txn.delete(tableTrackImportLogItems);
        await txn.delete(tableImportedGalleryAssets);
        await txn.delete(tableVideos);
        await txn.delete(tableAudios);
        await txn.delete(tableImages);
        await txn.delete(tableMemories);
        await txn.delete(tableTrackImportLog);
      });

      // Reclaim disk: DELETE alone does not shrink the SQLite file.
      try {
        await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (e) {
        debugPrint('[DatabaseHelper][clearAllMemories] wal_checkpoint: $e');
      }
      try {
        await db.execute('VACUUM');
        debugPrint('[DatabaseHelper][clearAllMemories] ✅ VACUUM complete');
      } catch (e) {
        debugPrint('[DatabaseHelper][clearAllMemories] VACUUM failed: $e');
      }

      try {
        final docs = await getApplicationDocumentsDirectory();
        final dbFile = File(join(docs.path, _databaseName));
        if (await dbFile.exists()) {
          final mb =
              ((await dbFile.length()) / (1024 * 1024)).toStringAsFixed(1);
          debugPrint('[DatabaseHelper][clearAllMemories] DB size after: ${mb}MB');
        }
      } catch (_) {}

      debugPrint('[DatabaseHelper][clearAllMemories] ✅ All memories cleared');
    } catch (e) {
      debugPrint('[DatabaseHelper][clearAllMemories] ❌ Error clearing memories: $e');
      rethrow;
    }
  }

  /// Attaches images/audios/videos lists to a memory row map.
  Map<String, dynamic> _memoryRowWithMedia(
    Map<String, dynamic> memory, {
    required List<String> images,
    required List<Map<String, dynamic>> imagesWithOrder,
    required List<Map<String, dynamic>> audios,
    required List<Map<String, dynamic>> videos,
    required List<Map<String, dynamic>> videosWithOrder,
  }) {
    final memoryWithMedia = Map<String, dynamic>.from(memory);
    memoryWithMedia['images'] = images;
    memoryWithMedia['audios'] = audios;
    memoryWithMedia['videos'] = videos;
    memoryWithMedia['imageOrders'] =
        imagesWithOrder.map((r) => r[columnImageOrder] as int? ?? 0).toList();
    memoryWithMedia['videoOrders'] =
        videosWithOrder.map((r) => r[columnVideoOrder] as int? ?? 0).toList();

    if (images.isNotEmpty) {
      memoryWithMedia[columnImagePath] = images.join('|');
    }
    if (audios.isNotEmpty) {
      final audioPaths =
          audios.map((audio) => audio[columnAudioFilePath] as String).toList();
      memoryWithMedia[columnAudioPath] = audioPaths.join('|');
    }
    return memoryWithMedia;
  }

  Future<_MemoryMediaBatch> _loadAllMemoryMediaBatch(Database db) async {
    final imageRows = await db.query(
      tableImages,
      columns: [columnMemoryId, columnImageData, columnImageOrder, columnImageId],
      orderBy: '$columnMemoryId ASC, $columnImageOrder ASC',
    );
    final imagesByMemory = <int, List<String>>{};
    final imagesWithOrderByMemory = <int, List<Map<String, dynamic>>>{};
    for (final row in imageRows) {
      final memoryId = row[columnMemoryId] as int;
      imagesByMemory.putIfAbsent(memoryId, () => []).add(
        row[columnImageData] as String,
      );
      imagesWithOrderByMemory.putIfAbsent(memoryId, () => []).add(row);
    }

    final audioRows = await db.query(
      tableAudios,
      columns: [
        columnAudioMemoryId,
        columnAudioFilePath,
        columnAudioDuration,
        columnAudioOrder,
        columnAudioId,
      ],
      orderBy: '$columnAudioMemoryId ASC, $columnAudioOrder ASC',
    );
    final audiosByMemory = <int, List<Map<String, dynamic>>>{};
    for (final row in audioRows) {
      final memoryId = row[columnAudioMemoryId] as int;
      audiosByMemory.putIfAbsent(memoryId, () => []).add(row);
    }

    final videoRows = await db.query(
      tableVideos,
      columns: [
        columnVideoMemoryId,
        columnVideoFilePath,
        columnVideoDuration,
        columnVideoThumbnailPath,
        columnVideoOrder,
        columnVideoId,
      ],
      orderBy: '$columnVideoMemoryId ASC, $columnVideoOrder ASC',
    );
    final videosByMemory = <int, List<Map<String, dynamic>>>{};
    final videosWithOrderByMemory = <int, List<Map<String, dynamic>>>{};
    for (final row in videoRows) {
      final memoryId = row[columnVideoMemoryId] as int;
      videosByMemory.putIfAbsent(memoryId, () => []).add(row);
      videosWithOrderByMemory.putIfAbsent(memoryId, () => []).add(row);
    }

    return _MemoryMediaBatch(
      imagesByMemory: imagesByMemory,
      imagesWithOrderByMemory: imagesWithOrderByMemory,
      audiosByMemory: audiosByMemory,
      videosByMemory: videosByMemory,
      videosWithOrderByMemory: videosWithOrderByMemory,
    );
  }

  /// One memory with media — avoids reloading the full library after a single save.
  Future<Map<String, dynamic>?> getMemoryWithDetails(int memoryId) async {
    final db = await database;
    try {
      final rows = await db.query(
        tableMemories,
        columns: [
          columnId, columnDate, columnTime, columnLocation, columnCategory,
          columnDescription, columnAudioPath, columnTags, columnMentions,
          columnCreatedAt, columnUpdatedAt,
          columnLocationCountry, columnLocationCity, columnLocationName,
          columnLocationAddress, columnLocationFlag, columnLocationLatitude,
          columnLocationLongitude,
        ],
        where: '$columnId = ?',
        whereArgs: [memoryId],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final images = await getMemoryImages(memoryId);
      final imagesWithOrder = await getMemoryImagesWithOrder(memoryId);
      final audios = await getMemoryAudios(memoryId);
      final videos = await getMemoryVideos(memoryId);
      final videosWithOrder = await getMemoryVideosWithOrder(memoryId);

      return _memoryRowWithMedia(
        rows.first,
        images: images,
        imagesWithOrder: imagesWithOrder,
        audios: audios,
        videos: videos,
        videosWithOrder: videosWithOrder,
      );
    } catch (e) {
      debugPrint('[DatabaseHelper] getMemoryWithDetails($memoryId): $e');
      return null;
    }
  }

  // Get all memories with their images from separate table
  Future<List<Map<String, dynamic>>> getAllMemoriesWithDetails() async {
    final db = await database;

    try {
      final memories = await db.query(
        tableMemories,
        columns: [
          columnId, columnDate, columnTime, columnLocation, columnCategory,
          columnDescription, columnAudioPath, columnTags, columnMentions,
          columnCreatedAt, columnUpdatedAt,
          columnLocationCountry, columnLocationCity, columnLocationName,
          columnLocationAddress, columnLocationFlag, columnLocationLatitude,
          columnLocationLongitude,
        ],
        orderBy: '$columnCreatedAt DESC',
      );

      debugPrint('Loaded ${memories.length} memories from database');

      final mediaBatch = await _loadAllMemoryMediaBatch(db);
      final List<Map<String, dynamic>> memoriesWithImages = [];

      for (final memory in memories) {
        final memoryId = memory[columnId] as int;
        memoriesWithImages.add(
          _memoryRowWithMedia(
            memory,
            images: mediaBatch.imagesByMemory[memoryId] ?? const [],
            imagesWithOrder:
                mediaBatch.imagesWithOrderByMemory[memoryId] ?? const [],
            audios: mediaBatch.audiosByMemory[memoryId] ?? const [],
            videos: mediaBatch.videosByMemory[memoryId] ?? const [],
            videosWithOrder:
                mediaBatch.videosWithOrderByMemory[memoryId] ?? const [],
          ),
        );
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

  /// Close DB without reopening — use before replacing [memories.db] on disk (e.g. restore).
  Future<void> closeDatabaseOnly() async {
    _databaseReplacementInProgress = true;
    try {
      if (_database != null && _database!.isOpen) {
        debugPrint('[DatabaseHelper] Closing database (no reopen)');
        await _database!.close();
      }
    } catch (e) {
      debugPrint('[DatabaseHelper] Error closing database: $e');
    } finally {
      _database = null;
      _isInitializing = false;
    }
  }

  /// Merge WAL pages into the main DB file so a plain file copy is complete
  /// (safe for backup zip / cross-device restore).
  Future<void> flushWalForBackupSnapshot() async {
    try {
      final db = await database;
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (e) {
      debugPrint('[DatabaseHelper] flushWalForBackupSnapshot (non-fatal): $e');
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
    _databaseReplacementInProgress = false;
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

class _MemoryMediaBatch {
  const _MemoryMediaBatch({
    required this.imagesByMemory,
    required this.imagesWithOrderByMemory,
    required this.audiosByMemory,
    required this.videosByMemory,
    required this.videosWithOrderByMemory,
  });

  final Map<int, List<String>> imagesByMemory;
  final Map<int, List<Map<String, dynamic>>> imagesWithOrderByMemory;
  final Map<int, List<Map<String, dynamic>>> audiosByMemory;
  final Map<int, List<Map<String, dynamic>>> videosByMemory;
  final Map<int, List<Map<String, dynamic>>> videosWithOrderByMemory;
}
