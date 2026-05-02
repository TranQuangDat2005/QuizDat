import 'package:flutter/material.dart';

class ImportCardsScreen extends StatefulWidget {
  const ImportCardsScreen({super.key});

  @override
  State<ImportCardsScreen> createState() => _ImportCardsScreenState();
}

class _ImportCardsScreenState extends State<ImportCardsScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _customColCtrl = TextEditingController();
  final TextEditingController _customRowCtrl = TextEditingController();

  // 'Tab' | 'Phẩy' | 'Tùy chỉnh'
  String _colSeparator = 'Tab';
  // 'Dòng mới' | 'Chấm phẩy' | 'Tùy chỉnh'
  String _rowSeparator = 'Dòng mới';

  List<Map<String, String>> _previewCards = [];

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_parseData);
    _customColCtrl.addListener(_parseData);
    _customRowCtrl.addListener(_parseData);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _customColCtrl.dispose();
    _customRowCtrl.dispose();
    super.dispose();
  }

  String get _resolvedCol {
    switch (_colSeparator) {
      case 'Tab':
        return '\t';
      case 'Phẩy':
        return ',';
      default:
        return _customColCtrl.text;
    }
  }

  String get _resolvedRow {
    switch (_rowSeparator) {
      case 'Dòng mới':
        return '\n';
      case 'Chấm phẩy':
        return ';';
      default:
        return _customRowCtrl.text;
    }
  }

  void _parseData() {
    final text = _inputController.text;
    final col = _resolvedCol;
    final row = _resolvedRow;

    if (text.isEmpty || col.isEmpty || row.isEmpty) {
      setState(() => _previewCards = []);
      return;
    }

    final rows = text.split(row);
    final result = <Map<String, String>>[];
    for (final r in rows) {
      if (r.trim().isEmpty) continue;
      final parts = r.split(col);
      final term = parts.isNotEmpty ? parts[0].trim() : '';
      final def = parts.length > 1 ? parts[1].trim() : '';
      if (term.isNotEmpty || def.isNotEmpty) {
        result.add({'term': term, 'def': def});
      }
    }
    setState(() => _previewCards = result);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'NHẬP DỮ LIỆU',
          style: tt.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            fontFamilyFallback: ['Malgun Gothic', 'Roboto'], // Hỗ trợ tiếng Hàn
          ),
        ),
        actions: [
          TextButton(
            onPressed: _previewCards.isEmpty
                ? null
                : () => Navigator.pop(context, _previewCards),
            child: Text(
              'NHẬP (${_previewCards.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _previewCards.isEmpty
                    ? cs.onSurface.withOpacity(0.35)
                    : cs.primary,
                fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
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
              'Dán dữ liệu vào đây (từ Word, Excel, Google Docs…)',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.6),
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
              ),
            ),
            const SizedBox(height: 8),

            // ── Textarea nhập liệu ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outline, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _inputController,
                maxLines: 9,
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontFamilyFallback: const ['Malgun Gothic', 'Gulim', 'Roboto'], // Hỗ trợ gõ tiếng Hàn
                ),
                decoration: InputDecoration(
                  hintText:
                      'Từ 1\tĐịnh nghĩa 1\nTừ 2\tĐịnh nghĩa 2\n…',
                  hintStyle: TextStyle(
                    color: cs.onSurface.withOpacity(0.35),
                    fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
                  ),
                  contentPadding: const EdgeInsets.all(12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Cấu hình dấu phân cách ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSeparatorGroup(
                    label: 'Giữa thuật ngữ và định nghĩa',
                    value: _colSeparator,
                    options: const ['Tab', 'Phẩy', 'Tùy chỉnh'],
                    customCtrl: _customColCtrl,
                    customHint: 'VD: |',
                    onChanged: (v) {
                      setState(() => _colSeparator = v!);
                      _parseData();
                    },
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildSeparatorGroup(
                    label: 'Giữa các hàng',
                    value: _rowSeparator,
                    options: const ['Dòng mới', 'Chấm phẩy', 'Tùy chỉnh'],
                    customCtrl: _customRowCtrl,
                    customHint: 'VD: |',
                    onChanged: (v) {
                      setState(() => _rowSeparator = v!);
                      _parseData();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Xem trước ──────────────────────────────────────────────────
            Text(
              'XEM TRƯỚC (${_previewCards.length} THẺ)',
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: cs.onSurface,
                fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
              ),
            ),
            Divider(thickness: 2, color: cs.outline),
            if (_previewCards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Chưa có thẻ nào được nhận dạng',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.4),
                      fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _previewCards.length,
                itemBuilder: (context, i) {
                  final card = _previewCards[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                            color: cs.outline.withOpacity(0.3)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            card['term']!,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                              fontFamilyFallback: const ['Malgun Gothic', 'Gulim', 'Roboto'],
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_right_alt,
                            color: cs.onSurface.withOpacity(0.3)),
                        Expanded(
                          child: Text(
                            card['def']!,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontFamilyFallback: const ['Malgun Gothic', 'Gulim', 'Roboto'],
                            ),
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

  Widget _buildSeparatorGroup({
    required String label,
    required String value,
    required List<String> options,
    required TextEditingController customCtrl,
    required String customHint,
    required ValueChanged<String?> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCustom = value == 'Tùy chỉnh';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tt.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: cs.onSurface.withOpacity(0.5),
            fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
          ),
        ),
        const SizedBox(height: 4),
        ...options.map((opt) {
          final selected = value == opt;
          final isThisCustom = opt == 'Tùy chỉnh';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => onChanged(opt),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Radio<String>(
                      value: opt,
                      groupValue: value,
                      onChanged: onChanged,
                      activeColor: cs.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                    if (isThisCustom && selected)
                      Flexible(
                        child: Container(
                          width: 110,
                          height: 34,
                          margin: const EdgeInsets.only(right: 4),
                          child: TextField(
                            controller: customCtrl,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
                            ),
                            decoration: InputDecoration(
                              hintText: customHint,
                              hintStyle: TextStyle(
                                color: cs.onSurface.withOpacity(0.4),
                                fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest
                                  .withOpacity(0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: cs.primary, width: 1.5),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: cs.primary.withOpacity(0.5),
                                    width: 1.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: cs.primary, width: 2),
                              ),
                            ),
                            autofocus: true,
                          ),
                        ),
                      )
                    else
                      Text(
                        opt,
                        style: tt.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                          fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
                        ),
                      ),
                  ],
                ),
              ),
              if (isThisCustom && !selected)
                const SizedBox.shrink(),
            ],
          );
        }),
        if (isCustom)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 4),
            child: Text(
              customCtrl.text.isEmpty
                  ? 'Nhập ký tự phân cách bên cạnh'
                  : 'Sử dụng: "${customCtrl.text}"',
              style: tt.bodySmall?.copyWith(
                fontSize: 11,
                color: customCtrl.text.isEmpty
                    ? Colors.orange
                    : cs.primary,
                fontStyle: FontStyle.italic,
                fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
              ),
            ),
          ),
      ],
    );
  }
}
