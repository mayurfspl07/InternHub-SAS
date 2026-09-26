import '../../core/api/api_client.dart';
import 'models/blog_models.dart';

class BlogRepository {
  static final BlogRepository _instance = BlogRepository._internal();
  factory BlogRepository() => _instance;
  BlogRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/blogs?page&per_page=12&tag&search (published)
  Future<BlogListResponse> getPublishedBlogs({
    int page = 1,
    int perPage = 12,
    String? tag,
    String? search,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };

    if (tag != null && tag.isNotEmpty && tag.toLowerCase() != 'all') {
      params['tag'] = tag.toLowerCase().trim();
    }

    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }

    final res = await _client.get('/api/blogs', queryParameters: params);
    return BlogListResponse.fromJson(res);
  }

  /// GET /api/blogs/admin/all?page&per_page=12&search
  Future<BlogListResponse> getAdminAllBlogs({
    int page = 1,
    int perPage = 12,
    String? search,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
    };

    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }

    final res = await _client.get('/api/blogs/admin/all', queryParameters: params);
    return BlogListResponse.fromJson(res);
  }

  /// GET /api/blogs/{slug}
  Future<BlogPost> getBlogBySlug(String slug) async {
    final encodedSlug = Uri.encodeComponent(slug.trim());
    final res = await _client.get('/api/blogs/$encodedSlug');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return BlogPost.fromJson(data);
    }
    throw Exception('Failed to load blog post');
  }

  /// POST /api/blogs
  Future<BlogPost> createBlog({
    required String title,
    required String content,
    String? slug,
    String? excerpt,
    String? coverImageUrl,
    List<String> tags = const [],
    String status = 'published',
  }) async {
    final cleanContent = sanitizeBlogHtml(content);
    final cleanExcerpt = excerpt != null && excerpt.isNotEmpty ? sanitizeBlogHtml(excerpt) : null;
    final finalSlug = slug != null && slug.trim().isNotEmpty ? slug.trim() : generateBlogSlug(title);

    final payload = <String, dynamic>{
      'title': title.trim(),
      'slug': finalSlug,
      'content': cleanContent,
      'tags': tags,
      'status': status.trim().toLowerCase(),
    };
    if (cleanExcerpt != null) payload['excerpt'] = cleanExcerpt;
    if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty) {
      payload['cover_image_url'] = coverImageUrl.trim();
    }

    final res = await _client.post('/api/blogs', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return BlogPost.fromJson(data);
    }
    throw Exception('Failed to create blog post');
  }

  /// PUT /api/blogs/{id}
  Future<BlogPost> updateBlog(
    int id, {
    required String title,
    required String content,
    String? slug,
    String? excerpt,
    String? coverImageUrl,
    List<String> tags = const [],
    String status = 'published',
  }) async {
    final cleanContent = sanitizeBlogHtml(content);
    final cleanExcerpt = excerpt != null && excerpt.isNotEmpty ? sanitizeBlogHtml(excerpt) : null;
    final finalSlug = slug != null && slug.trim().isNotEmpty ? slug.trim() : generateBlogSlug(title);

    final payload = <String, dynamic>{
      'title': title.trim(),
      'slug': finalSlug,
      'content': cleanContent,
      'tags': tags,
      'status': status.trim().toLowerCase(),
    };
    if (cleanExcerpt != null) payload['excerpt'] = cleanExcerpt;
    if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty) {
      payload['cover_image_url'] = coverImageUrl.trim();
    }

    final res = await _client.put('/api/blogs/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return BlogPost.fromJson(data);
    }
    throw Exception('Failed to update blog post #$id');
  }

  /// DELETE /api/blogs/{id} (Soft-delete to Recycle Bin)
  Future<bool> deleteBlog(int id) async {
    final res = await _client.delete('/api/blogs/$id');
    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true;
    }
    return true;
  }
}
