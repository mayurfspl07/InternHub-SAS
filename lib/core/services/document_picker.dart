import 'dart:io';
import 'package:file_picker/file_picker.dart';

/// A file the user picked for upload.
class PickedDocument {
  final File file;
  final String name;
  final int sizeBytes;

  const PickedDocument({required this.file, required this.name, required this.sizeBytes});

  String get sizeLabel => sizeBytes >= 1024 * 1024
      ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
}

/// Thrown with a message that can be shown to the user as-is.
class DocumentPickException implements Exception {
  final String message;
  const DocumentPickException(this.message);

  @override
  String toString() => message;
}

/// Documents and images accepted for leave notes, assignment briefs, submissions and task files.
const kDocumentExtensions = ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg'];

/// Opens the system file picker. Returns null when the user cancels; throws [DocumentPickException]
/// when the file is too large or of a type that isn't allowed.
Future<PickedDocument?> pickDocument({
  List<String> allowedExtensions = kDocumentExtensions,
  int maxMb = 10,
}) async {
  final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: allowedExtensions);
  final picked = result?.files.single;
  if (picked == null || picked.path == null) return null;

  final ext = picked.name.contains('.') ? picked.name.split('.').last.toLowerCase() : '';
  if (!allowedExtensions.contains(ext)) {
    throw DocumentPickException('Choose a ${allowedExtensions.map((e) => e.toUpperCase()).join(', ')} file.');
  }
  if (picked.size > maxMb * 1024 * 1024) {
    throw DocumentPickException('That file is larger than $maxMb MB. Choose a smaller one.');
  }
  return PickedDocument(file: File(picked.path!), name: picked.name, sizeBytes: picked.size);
}
