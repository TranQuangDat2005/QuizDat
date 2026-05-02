import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/card.dart';

class ExportCardsScreen extends StatefulWidget {
  final List<VocabCard> cards;
  final String setName;

  const ExportCardsScreen({
    super.key,
    required this.cards,
    required this.setName,
  });

  @override
  State<ExportCardsScreen> createState() => _ExportCardsScreenState();
}

class _ExportCardsScreenState extends State<ExportCardsScreen> {
  final TextEditingController _outputController = TextEditingController();
  final TextEditingController _customColCtrl = TextEditingController();
  final TextEditingController _customRowCtrl = TextEditingController();

  // 'Tab' | 'Phẩy' | 'Tùy chỉnh'
  String _colSeparator = 'Tab';
  // 'Dòng mới' | 'Chấm phẩy' | 'Tùy chỉnh'
  String _rowSeparator = 'Dòng mới';

  @override
  void initState() {
    super.initState();
    _customColCtrl.addListener(_generate);
    _customRowCtrl.addListener(_generate);
    _generate();
  }

  @override
  void dispose() {
    _outputController.dispose();
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

  void _generate() {
    final col = _resolvedCol;
    final row = _resolvedRow;
    if (col.isEmpty || row.isEmpty || widget.cards.isEmpty) {
      setState(() => _outputController.text = '');
      return;
    }
    final result = widget.cards
        .map((c) => '${c.term}$col${c.definition}')
        .join(row);
    setState(() => _outputController.text = result);
  }

  void _copyToClipboard() {
    if (_outputController.text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _outputController.text)).then((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã sao chép vào bộ nhớ tạm!',
              style: TextStyle(fontFamilyFallback: ['Malgun Gothic', 'Roboto'])),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'XUẤT DỮ LIỆU',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
              ),
            ),
            Text(
              widget.setName.toUpperCase(),
              style: const TextStyle(
                color: Colors.black38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _outputController.text.isEmpty ? null : _copyToClipboard,
            icon: Icon(
              Icons.copy,
              size: 18,
              color: _outputController.text.isEmpty
                  ? Colors.black26
                  : const Color.fromARGB(255, 0, 0, 0),
            ),
            label: Text(
              'SAO CHÉP',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _outputController.text.isEmpty
                    ? Colors.black26
                    : const Color.fromARGB(255, 0, 0, 0),
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
            const Text(
              'Dữ liệu sẵn sàng để xuất. Bạn có thể dán vào Excel hoặc Word.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
              ),
            ),
            const SizedBox(height: 10),

            // ── Cấu hình dấu phân cách ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSeparatorGroup(
                    label: 'KÝ TỰ PHÂN CÁCH CỘT',
                    value: _colSeparator,
                    options: const ['Tab', 'Phẩy', 'Tùy chỉnh'],
                    customCtrl: _customColCtrl,
                    customHint: 'VD: |',
                    onChanged: (v) {
                      setState(() => _colSeparator = v!);
                      _generate();
                    },
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _buildSeparatorGroup(
                    label: 'KÝ TỰ PHÂN CÁCH HÀNG',
                    value: _rowSeparator,
                    options: const ['Dòng mới', 'Chấm phẩy', 'Tùy chỉnh'],
                    customCtrl: _customRowCtrl,
                    customHint: 'VD: |',
                    onChanged: (v) {
                      setState(() => _rowSeparator = v!);
                      _generate();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Textarea xuất (cho phép copy, không edit) ──────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border.all(width: 2, color: Colors.black),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _outputController,
                maxLines: 14,
                readOnly: true,
                style: const TextStyle(
                  color: Colors.black87,
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['Malgun Gothic', 'Gulim', 'Roboto'],
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(12),
                  border: InputBorder.none,
                  hintText: _resolvedCol.isEmpty || _resolvedRow.isEmpty
                      ? 'Nhập ký tự tùy chỉnh phía trên để tạo dữ liệu…'
                      : 'Không có thẻ nào',
                  hintStyle: const TextStyle(
                    color: Colors.black38,
                    fontStyle: FontStyle.italic,
                    fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.info_outline, size: 13, color: Colors.black45),
                const SizedBox(width: 4),
                Text(
                  '${widget.cards.length} thẻ · chỉ đọc, dùng SAO CHÉP để lấy',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                    fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
                  ),
                ),
              ],
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
    final isCustom = value == 'Tùy chỉnh';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.black45,
            fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
          ),
        ),
        const SizedBox(height: 4),
        ...options.map((opt) {
          final selected = value == opt;
          final isThisCustom = opt == 'Tùy chỉnh';
          return InkWell(
            onTap: () => onChanged(opt),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<String>(
                  value: opt,
                  groupValue: value,
                  onChanged: onChanged,
                  activeColor: const Color.fromARGB(255, 0, 0, 0),
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
                        style: const TextStyle(
                          color: Colors.black,
                          fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
                        ),
                        decoration: InputDecoration(
                          hintText: customHint,
                          hintStyle: const TextStyle(
                            color: Colors.black38,
                            fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          filled: true,
                          fillColor: Colors.grey[200],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Colors.black, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Colors.black45, width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Colors.black, width: 2),
                          ),
                        ),
                        autofocus: true,
                      ),
                    ),
                  )
                else
                  Text(
                    opt,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      fontFamilyFallback: ['Malgun Gothic', 'Roboto'],
                    ),
                  ),
              ],
            ),
          );
        }),
        if (isCustom)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
            child: Text(
              customCtrl.text.isEmpty
                  ? 'Nhập ký tự phân cách bên cạnh'
                  : 'Đang dùng: "${customCtrl.text}"',
              style: TextStyle(
                fontSize: 11,
                color: customCtrl.text.isEmpty ? Colors.orange : Colors.black,
                fontStyle: FontStyle.italic,
                fontFamilyFallback: const ['Malgun Gothic', 'Roboto'],
              ),
            ),
          ),
      ],
    );
  }
}
