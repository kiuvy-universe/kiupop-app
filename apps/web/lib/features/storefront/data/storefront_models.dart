import 'package:flutter/material.dart';

/// Mirrors components/schemas/StorefrontView (draft preview or published store).
class StorefrontView {
  const StorefrontView({
    required this.store,
    required this.theme,
    required this.products,
    required this.delivery,
    required this.contact,
    required this.payments,
    required this.share,
  });

  factory StorefrontView.fromJson(Map<String, dynamic> j) => StorefrontView(
    store: StoreInfo.fromJson(j['store'] as Map<String, dynamic>),
    theme: StoreTheme.fromJson(j['theme'] as Map<String, dynamic>),
    products: [
      for (final p in j['products'] as List)
        StoreProduct.fromJson(p as Map<String, dynamic>),
    ],
    delivery: Delivery.fromJson(j['delivery'] as Map<String, dynamic>),
    contact: Contact.fromJson(j['contact'] as Map<String, dynamic>),
    payments: Payments.fromJson(j['payments'] as Map<String, dynamic>),
    share: Share.fromJson(j['share'] as Map<String, dynamic>),
  );

  final StoreInfo store;
  final StoreTheme theme;
  final List<StoreProduct> products;
  final Delivery delivery;
  final Contact contact;
  final Payments payments;
  final Share share;

  bool get isDraft => store.status == 'draft';
}

class StoreInfo {
  const StoreInfo({
    required this.slug,
    required this.name,
    required this.tagline,
    required this.description,
    required this.category,
    required this.status,
    this.coverUrl,
  });

  factory StoreInfo.fromJson(Map<String, dynamic> j) => StoreInfo(
    slug: j['slug'] as String? ?? '',
    name: j['name'] as String,
    tagline: j['tagline'] as String? ?? '',
    description: j['description'] as String? ?? '',
    category: j['category'] as String? ?? '',
    status: j['status'] as String? ?? 'published',
    coverUrl: j['cover_url'] as String?,
  );

  final String slug, name, tagline, description, category, status;
  final String? coverUrl;
}

class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.imageUrl,
    required this.featured,
  });

  factory StoreProduct.fromJson(Map<String, dynamic> j) => StoreProduct(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String? ?? '',
    priceMinor: j['price_minor'] as int,
    imageUrl: j['image_url'] as String?,
    featured: j['featured'] as bool? ?? false,
  );

  final String id, name, description;
  final int priceMinor;
  final String? imageUrl;
  final bool featured;
}

class Delivery {
  const Delivery({required this.modes, required this.zones});
  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
    modes: (j['modes'] as List? ?? const []).cast<String>(),
    zones: (j['zones'] as List? ?? const []).cast<String>(),
  );
  final List<String> modes, zones;
}

class Contact {
  const Contact({required this.whatsappUrl, required this.instagram});
  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
    whatsappUrl: j['whatsapp_url'] as String? ?? '',
    instagram: j['instagram'] as String? ?? '',
  );
  final String whatsappUrl, instagram;
}

class Payments {
  const Payments({
    required this.checkout,
    required this.realPaymentsEnabled,
    required this.methodsToCoordinate,
  });
  factory Payments.fromJson(Map<String, dynamic> j) => Payments(
    checkout: j['checkout'] as String? ?? 'none',
    realPaymentsEnabled: j['real_payments_enabled'] as bool? ?? false,
    methodsToCoordinate: (j['methods_to_coordinate'] as List? ?? const [])
        .cast<String>(),
  );
  final String checkout;
  final bool realPaymentsEnabled;
  final List<String> methodsToCoordinate;
  bool get testCheckout => checkout == 'test';
}

class Share {
  const Share({required this.url, required this.title, required this.text});
  factory Share.fromJson(Map<String, dynamic> j) => Share(
    url: j['url'] as String? ?? '',
    title: j['title'] as String? ?? '',
    text: j['text'] as String? ?? '',
  );
  final String url, title, text;
}

/// Validated design tokens (the server already enforced ranges and WCAG contrast).
class StoreTheme {
  const StoreTheme({
    required this.template,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.accent,
    required this.typographyStyle,
    required this.headingWeight,
    required this.scale,
    required this.radius,
    required this.compact,
    required this.cardStyle,
    required this.pillButtons,
    required this.heroImage,
    required this.sections,
  });

  factory StoreTheme.fromJson(Map<String, dynamic> j) {
    final c = j['colors'] as Map<String, dynamic>;
    final t = j['typography'] as Map<String, dynamic>;
    return StoreTheme(
      template: j['template'] as String,
      primary: _hex(c['primary']),
      onPrimary: _hex(c['on_primary']),
      secondary: _hex(c['secondary']),
      background: _hex(c['background']),
      surface: _hex(c['surface']),
      text: _hex(c['text']),
      muted: _hex(c['muted']),
      accent: _hex(c['accent']),
      typographyStyle: t['style'] as String? ?? 'modern',
      headingWeight: (t['heading_weight'] as num?)?.toInt() ?? 800,
      scale: (t['scale'] as num?)?.toDouble() ?? 1,
      radius: (j['radius'] as num?)?.toDouble() ?? 20,
      compact: j['spacing'] == 'compact',
      cardStyle: j['card_style'] as String? ?? 'soft',
      pillButtons: j['button_style'] != 'rounded',
      heroImage: (j['hero'] as Map<String, dynamic>?)?['style'] == 'image',
      sections: (j['sections'] as List? ?? const ['hero', 'catalog'])
          .cast<String>(),
    );
  }

  static Color _hex(Object? v) {
    final s = (v as String? ?? '#FFFFFF').replaceFirst('#', '');
    return Color(int.parse('FF$s', radix: 16));
  }

  final String template;
  final Color primary, onPrimary, secondary, background, surface, text, muted;
  final Color accent;
  final String typographyStyle;
  final int headingWeight;
  final double scale, radius;
  final bool compact, pillButtons, heroImage;
  final String cardStyle;
  final List<String> sections;

  FontWeight get headingFontWeight =>
      FontWeight.values[(headingWeight ~/ 100 - 1).clamp(0, 8)];
}
