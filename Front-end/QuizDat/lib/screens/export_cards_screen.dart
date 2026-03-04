import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Để dùng Clipboard
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

  // Cấu hình dấu phân cách (Mặc định giống Import)
  String _colSeparator = 'Tab';
  String _rowSeparator = 'New Line';

  @override
  void initState() {
    super.initState();
    _generateExportData();
  }

  // LOGIC ĐẢO NGƯỢC: Chuyển List thành String
  void _generateExportData() {
    if (widget.cards.isEmpty) {
      _outputController.text = "";
      return;
    }

    // Xác định ký tự phân cách cột
    String colChar = _colSeparator == 'Tab' ? '\t' : ',';
    // Xác định ký tự phân cách hàng
    String rowChar = _rowSeparator == 'New Line' ? '\n' : ';';

    // Nối dữ liệu
    String result = widget.cards
        .map((card) {
          return "${card.term}$colChar${card.definition}";
        })
        .join(rowChar);

    setState(() {
      _outputController.text = result;
    });
  }

  void _copyToClipboard() {
    if (_outputController.text.isEmpty) return;

    Clipboard.setData(ClipboardData(text: _outputController.text)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Đã sao chép vào bộ nhớ tạm!"),
          backgroundColor: Colors.green,
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
              "XUẤT DỮ LIỆU",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              widget.setName.toUpperCase(),
              style: const TextStyle(
                color: Colors.black38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _copyToClipboard,
            icon: const Icon(
              Icons.copy,
              size: 18,
              color: Color.fromARGB(255, 0, 0, 0),
            ),
            label: const Text(
              "SAO CHÉP",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 0, 0, 0),
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
              "Dữ liệu đã sẵn sàng để xuất. Bạn có thể dán vào Excel hoặc Word.",
              style: TextStyle(
                color: Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Textarea hiển thị kết quả (Chỉ cho phép đọc)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border.all(width: 2, color: Colors.black),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _outputController,
                maxLines: 15,
                readOnly: true, // Không cho sửa ở đây
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(12),
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
                  "KÝ TỰ PHÂN CÁCH CỘT",
                  _colSeparator,
                  ['Tab', 'Comma'],
                  (val) {
                    setState(() => _colSeparator = val!);
                    _generateExportData();
                  },
                ),
                const SizedBox(width: 40),
                _buildSeparatorOption(
                  "KÝ TỰ PHÂN CÁCH HÀNG",
                  _rowSeparator,
                  ['New Line', 'Semicolon'],
                  (val) {
                    setState(() => _rowSeparator = val!);
                    _generateExportData();
                  },
                ),
              ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Colors.black45,
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
                activeColor: const Color.fromARGB(255, 0, 0, 0),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                opt,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
