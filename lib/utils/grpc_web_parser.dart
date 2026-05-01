import 'dart:convert';
import 'dart:typed_data';

class GrpcWebParser {
  static String? parseFullNameFromBase64(String base64Body){
    final bytes = base64Decode(base64Body);
    return _parseFullName(bytes);
  }

  static String? _parseFullName(Uint8List data) {
    int offset = 0;
    while (offset + 5 <= data.length) {
      final flags = data[offset] & 0xFF;
      final length = ((data[offset + 1] & 0xFF) << 24) |
      ((data[offset + 2] & 0xFF) << 16) |
      ((data[offset + 3] & 0xFF) << 8) |
      (data[offset + 4] & 0xFF);
      offset += 5;

      if (offset + length > data.length) {
        print('[gRPC] Frame out of bounds: offset=$offset length=$length total=${data.length}');
        break;
      }

      if (flags == 0x00 && length > 0) {
        final protoBytes = data.sublist(offset, offset + length);
        return _extractName(protoBytes, targetDepth: 2);
      }

      offset += length;
    }
    return null;
  }

  static String? _extractName(Uint8List bytes, {required int targetDepth}) {
    final fields = <int, String>{};
    _collectFields(bytes, currentDepth: 0, targetDepth: targetDepth, result: fields);

    final firstName = fields[2]?.trim();
    final lastName = fields[3]?.trim();
    if (firstName == null || lastName == null) return null;

    final initial = firstName.isNotEmpty ? '${firstName[0]}.' : '';
    return '$lastName $initial'.trim();
  }

  static void _collectFields(
      Uint8List bytes, {
        required int currentDepth,
        required int targetDepth,
        required Map<int, String> result,
      }) {
    int i = 0;
    while (i < bytes.length) {
      int tag = 0, shift = 0;
      while (i < bytes.length) {
        final b = bytes[i++] & 0xFF;
        tag |= (b & 0x7F) << shift;
        if (b & 0x80 == 0) break;
        shift += 7;
      }

      final fieldNumber = tag >> 3;
      final wireType = tag & 0x07;

      switch (wireType) {
        case 0:
          while (i < bytes.length && bytes[i] & 0x80 != 0) i++;
          if (i < bytes.length) i++;
          break;
        case 1:
          i += 8;
          break;
        case 5:
          i += 4;
          break;
        case 2:
          int len = 0;
          shift = 0;
          while (i < bytes.length) {
            final b = bytes[i++] & 0xFF;
            len |= (b & 0x7F) << shift;
            if (b & 0x80 == 0) break;
            shift += 7;
          }
          if (len < 0 || i + len > bytes.length) return;
          final fieldBytes = bytes.sublist(i, i + len);
          i += len;

          if (currentDepth == targetDepth) {
            try {
              final str = utf8.decode(fieldBytes);
              if (str.trim().isNotEmpty) result[fieldNumber] = str;
            } catch (_) {}
          } else {
            _collectFields(
              fieldBytes,
              currentDepth: currentDepth + 1,
              targetDepth: targetDepth,
              result: result,
            );
          }
          break;
        default:
          return;
      }
    }
  }
}