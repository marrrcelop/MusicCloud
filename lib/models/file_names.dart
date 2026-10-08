final RegExp _knownExtension = RegExp(
  r'\.(mp3|flac|wav|m4a|aac|ogg|oga|opus|wma|aiff|aif|weba|jpe?g|png|webp|gif|bmp)$',
  caseSensitive: false,
);

/// Quita la extensión conocida de un nombre de archivo:
/// "01 - Airbag.mp3" -> "01 - Airbag".
/// Solo quita extensiones de audio e imagen, para no cortar títulos como "Mr. Brightside".
String baseName(String fileName) => fileName.replaceFirst(_knownExtension, '');