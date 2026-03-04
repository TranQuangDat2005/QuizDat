import 'package:flutter/material.dart';

class ImportCardsScreen extends StatefulWidget {
  const ImportCardsScreen({super.key});

  @override
  State<ImportCardsScreen> createState() => _ImportCardsScreenState();
}

class _ImportCardsScreenState extends State<ImportCardsScreen> {
  final TextEditingController _inputController = TextEditingController();

  // Cấu hình dấu phân cách
  String _colSeparator = 'Tab';
  String _rowSeparator = 'New Line';
  final String _customColChar = '';
  final String _customRowChar = '';

  List<Map<String, String>> _previewCards = [];

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_parseData);
  }

  void _parseData() {
    String text = _inputController.text;
    if (text.isEmpty) {
      setState(() => _previewCards = []);
      return;
    }

    // Xác định ký tự phân cách hàng
    String rowPattern = _rowSeparator == 'New Line'
        ? '\n'
        : (_rowSeparator == 'Semicolon' ? ';' : _customRowChar);
    // Xác định ký tự phân cách cột
    String colPattern = _colSeparator == 'Tab'
        ? '\t'
        : (_colSeparator == 'Comma' ? ',' : _customColChar);

    if (rowPattern.isEmpty || colPattern.isEmpty) return;

    List<String> rows = text.split(rowPattern);
    List<Map<String, String>> result = [];

    for (var row in rows) {
      if (row.trim().isEmpty) continue;
      List<String> parts = row.split(colPattern);
      String term = parts.isNotEmpty ? parts[0].trim() : "";
      String def = parts.length > 1 ? parts[1].trim() : "";
      if (term.isNotEmpty || def.isNotEmpty) {
        result.add({'term': term, 'def': def});
      }
    }

    setState(() => _previewCards = result);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "NHẬP DỮ LIỆU",
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _previewCards.isEmpty
                ? null
                : () => Navigator.pop(context, _previewCards),
            child: Text(
              "NHẬP (${_previewCards.length})",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _previewCards.isEmpty
                    ? colorScheme.onSurface.withOpacity(0.38)
                    : colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Dán dữ liệu của bạn vào đây (từ Word, Excel, Google Docs...)",
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Textarea nhập liệu
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.outline,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _inputController,
                maxLines: 10,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: "Từ 1\tĐịnh nghĩa 1\nTừ 2\tĐịnh nghĩa 2...",
                  hintStyle: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Cấu hình dấu phân cách
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSeparatorOption(
                  "GIỮA THUẬT NGỮ & ĐỊNH NGHĨA",
                  _colSeparator,
                  ['Tab', 'Comma'],
                  (val) {
                    setState(() => _colSeparator = val!);
                    _parseData();
                  },
                ),
                const SizedBox(width: 40),
                _buildSeparatorOption(
                  "GIỮA CÁC THẺ",
                  _rowSeparator,
                  ['New Line', 'Semicolon'],
                  (val) {
                    setState(() => _rowSeparator = val!);
                    _parseData();
                  },
                ),
              ],
            ),

            const SizedBox(height: 32),
            Text(
              "XEM TRƯỚC (${_previewCards.length} THẺ)",
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: colorScheme.onSurface,
              ),
            ),
            Divider(thickness: 2, color: colorScheme.outline),

            // Bảng xem trước
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _previewCards.length,
              itemBuilder: (context, index) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outline.withOpacity(0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _previewCards[index]['term']!,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_right_alt,
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                      Expanded(
                        child: Text(
                          _previewCards[index]['def']!,
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeparatorOption(
    String title,
    String currentVal,
    List<String> options,
    Function(String?) onChanged,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        ...options.map(
          (opt) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Radio<String>(
                value: opt,
                groupValue: currentVal,
                onChanged: onChanged,
                activeColor: colorScheme.primary,
                visualDensity: VisualDensity.compact,
              ),
              Text(
                opt,
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
