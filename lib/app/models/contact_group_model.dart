class ContactGroup {
  final int? id;
  final String name;
  final int? parentId;
  final int order;
  final bool isCustom;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ContactGroup>? subgroups;

  ContactGroup({
    this.id,
    required this.name,
    this.parentId,
    this.order = 0,
    this.isCustom = false,
    required this.createdAt,
    required this.updatedAt,
    this.subgroups,
  });

  /// Create ContactGroup from database map
  factory ContactGroup.fromMap(Map<String, dynamic> map) {
    return ContactGroup(
      id: map['contact_group_id'] as int?,
      name: map['contact_group_name'] as String,
      parentId: map['contact_group_parent_id'] as int?,
      order: map['contact_group_order'] as int? ?? 0,
      isCustom: (map['contact_group_is_custom'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['contact_group_created_at'] as String),
      updatedAt: DateTime.parse(map['contact_group_updated_at'] as String),
      subgroups: null, // Will be populated separately if needed
    );
  }

  /// Convert ContactGroup to database map
  Map<String, dynamic> toMap() {
    return {
      'contact_group_id': id,
      'contact_group_name': name,
      'contact_group_parent_id': parentId,
      'contact_group_order': order,
      'contact_group_is_custom': isCustom ? 1 : 0,
      'contact_group_created_at': createdAt.toIso8601String(),
      'contact_group_updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  ContactGroup copyWith({
    int? id,
    String? name,
    int? parentId,
    int? order,
    bool? isCustom,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ContactGroup>? subgroups,
  }) {
    return ContactGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      order: order ?? this.order,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      subgroups: subgroups ?? this.subgroups,
    );
  }

  /// Create a copy with updated timestamp
  ContactGroup copyWithUpdatedTimestamp() {
    return copyWith(updatedAt: DateTime.now());
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
      'order': order,
      'isCustom': isCustom,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'subgroups': subgroups?.map((e) => e.toJson()).toList(),
    };
  }

  /// Create from JSON
  factory ContactGroup.fromJson(Map<String, dynamic> json) {
    return ContactGroup(
      id: json['id'] as int?,
      name: json['name'] as String,
      parentId: json['parentId'] as int?,
      order: json['order'] as int? ?? 0,
      isCustom: json['isCustom'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      subgroups: json['subgroups'] != null
          ? (json['subgroups'] as List)
              .map((e) => ContactGroup.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  /// Check if this is a main group (has no parent)
  bool get isMainGroup => parentId == null;

  /// Check if this is a subgroup (has a parent)
  bool get isSubgroup => parentId != null;

  /// Check if this group has subgroups
  bool get hasSubgroups => subgroups != null && subgroups!.isNotEmpty;

  @override
  String toString() {
    return 'ContactGroup{id: $id, name: $name, parentId: $parentId, order: $order, isCustom: $isCustom}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContactGroup &&
        other.id == id &&
        other.name == name &&
        other.parentId == parentId &&
        other.order == order &&
        other.isCustom == isCustom;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        parentId.hashCode ^
        order.hashCode ^
        isCustom.hashCode;
  }
}

/// Helper class for contact group operations
class ContactGroupHelper {
  /// Convert list of database maps to list of ContactGroup objects
  static List<ContactGroup> fromMapList(List<Map<String, dynamic>> maps) {
    return maps.map((map) => ContactGroup.fromMap(map)).toList();
  }

  /// Build hierarchical structure from flat list
  static List<ContactGroup> buildHierarchy(List<ContactGroup> flatList) {
    final Map<int, ContactGroup> groupMap = {};
    final List<ContactGroup> mainGroups = [];

    // First pass: create map and identify main groups
    for (final group in flatList) {
      groupMap[group.id!] = group.copyWith(subgroups: []);
      if (group.isMainGroup) {
        mainGroups.add(groupMap[group.id!]!);
      }
    }

    // Second pass: build parent-child relationships
    for (final group in flatList) {
      if (group.isSubgroup && group.parentId != null) {
        final parent = groupMap[group.parentId!];
        if (parent != null) {
          parent.subgroups!.add(groupMap[group.id!]!);
        }
      }
    }

    // Sort main groups and their subgroups by order
    mainGroups.sort((a, b) => a.order.compareTo(b.order));
    for (final mainGroup in mainGroups) {
      if (mainGroup.subgroups != null) {
        mainGroup.subgroups!.sort((a, b) => a.order.compareTo(b.order));
      }
    }

    return mainGroups;
  }

  /// Flatten hierarchical structure to flat list
  static List<ContactGroup> flattenHierarchy(List<ContactGroup> hierarchical) {
    final List<ContactGroup> flatList = [];

    void addGroupAndSubgroups(ContactGroup group) {
      flatList.add(group);
      if (group.subgroups != null) {
        for (final subgroup in group.subgroups!) {
          addGroupAndSubgroups(subgroup);
        }
      }
    }

    for (final group in hierarchical) {
      addGroupAndSubgroups(group);
    }

    return flatList;
  }

  /// Get all subgroups for a main group
  static List<ContactGroup> getSubgroups(ContactGroup mainGroup) {
    return mainGroup.subgroups ?? [];
  }

  /// Find group by ID in hierarchical structure
  static ContactGroup? findById(List<ContactGroup> groups, int id) {
    for (final group in groups) {
      if (group.id == id) return group;
      if (group.subgroups != null) {
        final found = findById(group.subgroups!, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Get all main groups from hierarchical structure
  static List<ContactGroup> getMainGroups(List<ContactGroup> groups) {
    return groups.where((group) => group.isMainGroup).toList();
  }

  /// Get total count of groups (including subgroups)
  static int getTotalCount(List<ContactGroup> groups) {
    int count = 0;
    for (final group in groups) {
      count++;
      if (group.subgroups != null) {
        count += getTotalCount(group.subgroups!);
      }
    }
    return count;
  }
}
