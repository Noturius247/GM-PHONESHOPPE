import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// Generates and plays a high-frequency beep sound for scan feedback.
class BeepService {
  static AudioPlayer? _player;

  static AudioPlayer get _audioPlayer {
    _player ??= AudioPlayer();
    return _player!;
  }

  /// Play a short high-frequency beep (default 2500 Hz, 150ms).
  static Future<void> playBeep({
    int frequency = 2500,
    int durationMs = 150,
    double volume = 0.8,
  }) async {
    try {
      final wavBytes = _generateWav(frequency: frequency, durationMs: durationMs);
      await _audioPlayer.setVolume(volume);
      await _audioPlayer.play(BytesSource(wavBytes));
    } catch (_) {
      // Silently fail — beep is non-critical
    }
  }

  /// Generate a PCM WAV in memory with the given frequency and duration.
  static Uint8List _generateWav({
    required int frequency,
    required int durationMs,
    int sampleRate = 44100,
  }) {
    final numSamples = (sampleRate * durationMs / 1000).round();
    final dataSize = numSamples * 2; // 16-bit mono
    final fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize - 8, Endian.little);
    buffer.setUint8(8, 0x57);  // W
    buffer.setUint8(9, 0x41);  // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E

    // fmt sub-chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // (space)
    buffer.setUint32(16, 16, Endian.little); // sub-chunk size
    buffer.setUint16(20, 1, Endian.little);  // PCM format
    buffer.setUint16(22, 1, Endian.little);  // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    buffer.setUint16(32, 2, Endian.little);  // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample

    // data sub-chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);

    // Generate sine wave samples with fade-in/out to avoid clicks
    final fadeLength = (numSamples * 0.1).round();
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double amplitude = 16000;

      // Fade in
      if (i < fadeLength) {
        amplitude *= i / fadeLength;
      }
      // Fade out
      if (i > numSamples - fadeLength) {
        amplitude *= (numSamples - i) / fadeLength;
      }

      final sample = (sin(2 * pi * frequency * t) * amplitude).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  static void dispose() {
    _player?.dispose();
    _player = null;
  }
}
