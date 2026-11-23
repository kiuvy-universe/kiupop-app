/// Mirrors packages/api_contracts/openapi.yaml (Store, StorePublic, StoreCreated).
class AdminStore {
  const AdminStore({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.whatsapp,
  });

  factory AdminStore.fromJson(Map<String, dynamic> j) => AdminStore(
    id: j['id'] as String,
    slug: j['slug'] as String,
    name: j['name'] as String,
    description: j['description'] as String,
    whatsapp: j['whatsapp'] as String,
  );

  final String id;
  final String slug;
  final String name;
  final String description;
  final String whatsapp;
}

class PublicStore {
  const PublicStore({
    required this.slug,
    required this.name,
    required this.description,
  });

  factory PublicStore.fromJson(Map<String, dynamic> j) => PublicStore(
    slug: j['slug'] as String,
    name: j['name'] as String,
    description: j['description'] as String,
  );

  final String slug;
  final String name;
  final String description;
}

/// Result of creating a store. [adminToken] is shown once and never again.
class CreatedStore {
  const CreatedStore({
    required this.store,
    required this.adminToken,
    required this.aiEnabled,
  });

  factory CreatedStore.fromJson(Map<String, dynamic> j) => CreatedStore(
    store: AdminStore.fromJson(j['store'] as Map<String, dynamic>),
    adminToken: j['admin_token'] as String,
    aiEnabled: (j['features'] as Map<String, dynamic>)['ai'] as bool,
  );

  final AdminStore store;
  final String adminToken;
  final bool aiEnabled;
}

class CurrentStore {
  const CurrentStore({required this.store, required this.aiEnabled});

  factory CurrentStore.fromJson(Map<String, dynamic> j) => CurrentStore(
    store: AdminStore.fromJson(j['store'] as Map<String, dynamic>),
    aiEnabled: (j['features'] as Map<String, dynamic>)['ai'] as bool,
  );

  final AdminStore store;
  final bool aiEnabled;
}
