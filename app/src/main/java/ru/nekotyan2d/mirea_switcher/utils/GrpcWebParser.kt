package ru.nekotyan2d.mirea_switcher.utils

import android.util.Base64
import android.util.Log

object GrpcWebParser {

    fun parseFullNameFromBase64(base64Body: String): String? {
        val bytes = Base64.decode(base64Body, Base64.DEFAULT)
        return parseFullName(bytes)
    }

    private fun parseFullName(data: ByteArray): String? {
        var offset = 0
        while (offset + 5 <= data.size) {
            val flags  = data[offset].toInt() and 0xFF
            val length = ((data[offset + 1].toInt() and 0xFF) shl 24) or
                    ((data[offset + 2].toInt() and 0xFF) shl 16) or
                    ((data[offset + 3].toInt() and 0xFF) shl 8)  or
                    (data[offset + 4].toInt() and 0xFF)
            offset += 5

            if (offset + length > data.size) {
                Log.e("gRPC", "Frame out of bounds: offset=$offset length=$length total=${data.size}")
                break
            }

            if (flags == 0x00 && length > 0) {
                val protoBytes = data.copyOfRange(offset, offset + length)
                return extractName(protoBytes, targetDepth = 2)
            }

            offset += length
        }
        return null
    }

    private fun extractName(bytes: ByteArray, targetDepth: Int): String? {
        val fields = mutableMapOf<Int, String>()
        collectFields(bytes, currentDepth = 0, targetDepth, fields)

        val firstName  = fields[2]?.trim() ?: return null
        val lastName   = fields[3]?.trim() ?: return null

        val initials = buildString {
            append(firstName.firstOrNull() ?: "")
            append(".")
        }

        return "$lastName $initials".trim()
    }

    private fun collectFields(
        bytes: ByteArray,
        currentDepth: Int,
        targetDepth: Int,
        result: MutableMap<Int, String>
    ) {
        var i = 0
        while (i < bytes.size) {
            var tag = 0; var shift = 0
            while (i < bytes.size) {
                val b = bytes[i++].toInt() and 0xFF
                tag = tag or ((b and 0x7F) shl shift)
                if (b and 0x80 == 0) break
                shift += 7
            }

            val fieldNumber = tag ushr 3
            val wireType    = tag and 0x07

            when (wireType) {
                0 -> { while (i < bytes.size && bytes[i].toInt() and 0x80 != 0) i++; if (i < bytes.size) i++ }
                1 -> i += 8
                5 -> i += 4
                2 -> {
                    var len = 0; shift = 0
                    while (i < bytes.size) {
                        val b = bytes[i++].toInt() and 0xFF
                        len = len or ((b and 0x7F) shl shift)
                        if (b and 0x80 == 0) break
                        shift += 7
                    }
                    if (len < 0 || i + len > bytes.size) return
                    val fieldBytes = bytes.copyOfRange(i, i + len)
                    i += len

                    if (currentDepth == targetDepth) {
                        val str = runCatching { String(fieldBytes, Charsets.UTF_8) }.getOrNull()
                        if (str != null && str.isNotBlank()) result[fieldNumber] = str
                    } else {
                        collectFields(fieldBytes, currentDepth + 1, targetDepth, result)
                    }
                }
                else -> return
            }
        }
    }
}