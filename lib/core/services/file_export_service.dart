import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api/api_client.dart';

class FileExportService {
  static Future<void> downloadAndShare({
    required String endpoint,
    required String defaultFileName,
    Map<String, dynamic>? queryParameters,
  }) async {
    final bytes = await ApiClient().getBytes(endpoint, queryParameters: queryParameters);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$defaultFileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Exported report from InternHub',
    );
  }
}
