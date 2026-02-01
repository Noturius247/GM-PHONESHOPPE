// Stub implementation for non-web platforms
void downloadCsvFile(String content, String fileName) {
  // No-op on mobile platforms
  throw UnsupportedError('CSV download is only supported on web');
}
