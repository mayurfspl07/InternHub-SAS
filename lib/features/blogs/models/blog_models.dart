import 'dart:math';
import 'package:intl/intl.dart';
import '../../../shared/models/user_model.dart';

class BlogPost {
  final int id;
  final String title;
  final String slug;
  final String? excerpt;
  final String? content; // HTML
  final String? coverImageUrl;
  final List<String> tags;
  final String status; // "draft" | "published" | string
  final int authorId;
  final String authorName;
  final String? publishedAt;
  final String createdAt;
  final String updatedAt;

  const BlogPost({
    required this.id,
    required this.title,
    required this.slug,
    this.excerpt,
    this.content,
    this.coverImageUrl,
    this.tags = const [],
    this.status = 'published',
    required this.authorId,
    required this.authorName,
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDraft => status.toLowerCase().trim() == 'draft';
  bool get isPublished => status.toLowerCase().trim() == 'published';

  String get primaryTag => tags.isNotEmpty ? tags.first : 'ARTICLE';

  factory BlogPost.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    List<String> parseTags(dynamic t) {
      if (t == null) return [];
      if (t is List) {
        return t.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (t is String) {
        return t.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    return BlogPost(
      id: toInt(json['id']),
      title: json['title']?.toString() ?? 'Untitled',
      slug: json['slug']?.toString() ?? '',
      excerpt: json['excerpt']?.toString(),
      content: json['content']?.toString(),
      coverImageUrl: json['cover_image_url']?.toString() ?? json['cover_image']?.toString(),
      tags: parseTags(json['tags']),
      status: json['status']?.toString().toLowerCase().trim() ?? 'published',
      authorId: toInt(json['author_id'] ?? json['author']?['id']),
      authorName: json['author_name']?.toString() ?? json['author']?['name']?.toString() ?? 'InternHub Team',
      publishedAt: json['published_at']?.toString(),
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'slug': slug,
      if (excerpt != null) 'excerpt': excerpt,
      if (content != null) 'content': content,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
      'tags': tags,
      'status': status,
      'author_id': authorId,
      'author_name': authorName,
      if (publishedAt != null) 'published_at': publishedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class BlogListResponse {
  final List<BlogPost> items;
  final int total;
  final int page;
  final int perPage;

  const BlogListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });

  int get totalPages => perPage > 0 ? max(1, (total / perPage).ceil()) : 1;

  factory BlogListResponse.fromJson(dynamic raw) {
    int toInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    List rawItems = [];
    int total = 0;
    int page = 1;
    int perPage = 12;

    if (raw is List) {
      rawItems = raw;
      total = raw.length;
    } else if (raw is Map<String, dynamic>) {
      if (raw['items'] is List) {
        rawItems = raw['items'];
      } else if (raw['blogs'] is List) {
        rawItems = raw['blogs'];
      } else if (raw['data'] is List) {
        rawItems = raw['data'];
      }
      total = toInt(raw['total'] ?? raw['total_count'] ?? raw['total_items'], rawItems.length);
      page = toInt(raw['page'] ?? raw['current_page'], 1);
      perPage = toInt(raw['per_page'] ?? raw['page_size'] ?? raw['perPage'], 12);
    }

    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map((m) => BlogPost.fromJson(m))
        .toList();

    return BlogListResponse(
      items: items,
      total: total,
      page: page,
      perPage: perPage,
    );
  }
}

// Fixed popular tag pills from web
const List<String> popularTags = [
  'All',
  'Product',
  'Guide',
  'Engineering',
  'Design',
  'News',
  'Finance',
  'Web3',
];

// Permissions: role is admin OR superadmin
bool canManageBlogs(UserModel user) {
  return user.role == UserRole.admin || user.role == UserRole.superadmin;
}

// Helpers
String calculateReadingTime(String? text) {
  if (text == null || text.trim().isEmpty) return '3 min read';
  // Strip HTML tags for word count
  final cleanText = text.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
  final words = cleanText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (words == 0) return '3 min read';
  final minutes = max(1, (words / 180).ceil());
  return '$minutes min read';
}

String formatShortDate(String? dateTimeStr) {
  if (dateTimeStr == null || dateTimeStr.isEmpty) return '';
  final dt = DateTime.tryParse(dateTimeStr);
  if (dt == null) return dateTimeStr;
  return DateFormat('MMM d, yyyy').format(dt.toLocal());
}

String formatFullDate(String? dateTimeStr) {
  if (dateTimeStr == null || dateTimeStr.isEmpty) return '';
  final dt = DateTime.tryParse(dateTimeStr);
  if (dt == null) return dateTimeStr;
  return DateFormat('MMMM d, yyyy').format(dt.toLocal());
}

String getInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'U';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length > 1) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return trimmed.substring(0, min(2, trimmed.length)).toUpperCase();
}

// Slug auto-generation from title
String generateBlogSlug(String title) {
  var s = title.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'[^\w\s-]'), '');
  s = s.replaceAll(RegExp(r'\s+'), '-');
  s = s.replaceAll(RegExp(r'-+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  return s;
}

// HTML Sanitization on write (strips dangerous tags & scripts)
String sanitizeBlogHtml(String? html) {
  if (html == null) return '';
  var clean = html;

  // Remove script, iframe, object, embed, style, link, form, input tags and their contents
  clean = clean.replaceAll(RegExp(r'<(script|iframe|object|embed|style|link|form)[^>]*>[\s\S]*?<\/\1>', caseSensitive: false), '');
  clean = clean.replaceAll(RegExp(r'<(script|iframe|object|embed|style|link|form|input)[^>]*\/?>', caseSensitive: false), '');

  // Strip event handlers like onclick, onload, onerror, onmouseover, etc.
  clean = clean.replaceAll(RegExp(r"""\son\w+\s*=\s*["'].*?["']""", caseSensitive: false), '');
  clean = clean.replaceAll(RegExp(r'\son\w+\s*=\s*[^ >]+', caseSensitive: false), '');

  // Strip javascript: URLs in href or src
  clean = clean.replaceAll(RegExp(r"""(href|src)\s*=\s*["']\s*javascript:[^"']*?["']""", caseSensitive: false), r'$1="#"');

  return clean.trim();
}
