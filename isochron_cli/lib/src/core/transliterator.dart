class Transliterator {
  // A simple example mapping for Cyrillic to Latin.
  // You can expand this map for any language you need.
  static const Map<String, String> _map = {
    // Cyrillic (Mongolian/Russian specific examples)
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd',
    'е': 'ye', 'ё': 'yo', 'ж': 'j', 'з': 'z', 'и': 'i',
    'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
    'о': 'o', 'ө': 'u', 'п': 'p', 'р': 'r', 'с': 's',
    'т': 't', 'у': 'u', 'ү': 'u', 'ф': 'f', 'х': 'kh',
    'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch', 'ъ': '',
    'ы': 'y', 'ь': 'i', 'э': 'e', 'ю': 'yu', 'я': 'ya',
    // Uppercase
    'А': 'A', 'Б': 'B', 'В': 'V', 'Г': 'G', 'Д': 'D',
    'Е': 'Ye', 'Ё': 'Yo', 'Ж': 'J', 'З': 'Z', 'И': 'I',
    'Й': 'I', 'К': 'K', 'Л': 'L', 'М': 'M', 'Н': 'N',
    'О': 'O', 'Ө': 'U', 'П': 'P', 'Р': 'R', 'С': 'S',
    'Т': 'T', 'У': 'U', 'Ү': 'U', 'Ф': 'F', 'Х': 'Kh',
    'Ц': 'Ts', 'Ч': 'Ch', 'Ш': 'Sh', 'Щ': 'Shch', 'Ъ': '',
    'Ы': 'Y', 'Ь': 'I', 'Э': 'E', 'Ю': 'Yu', 'Я': 'Ya',
  };

  static String convert(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      // If char is in map, use replacement, otherwise keep original
      buffer.write(_map[char] ?? char);
    }
    return buffer.toString();
  }
}
