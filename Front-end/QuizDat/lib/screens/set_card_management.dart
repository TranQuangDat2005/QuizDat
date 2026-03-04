import 'package:flutter/material.dart';
import '../models/set_card.dart';
import '../models/card.dart';
import '../services/card_service.dart';
import 'import_cards_screen.dart';

class CardEditorItem {
  final String cardId;
  final String state;
  final TextEditingController termCtrl;
  final TextEditingController defCtrl;

  CardEditorItem({
    required this.cardId,
    required String term,
    required String def,
    required this.state,
  }) : termCtrl = TextEditingController(text: term),
       defCtrl = TextEditingController(text: def);

  void dispose() {
    termCtrl.dispose();
    defCtrl.dispose();
  }
}

class SetCardManagement extends StatefulWidget {
  final SetCard setCard;
  const SetCardManagement({super.key, required this.setCard});

  @override
  State<SetCardManagement> createState() => _SetCardManagementState();
}

class _SetCardManagementState extends State<SetCardManagement> {
  final CardService _cardService = CardService();
  final List<CardEditorItem> _items = [];
  List<VocabCard> _originalCards = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    for (var item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final cards = await _cardService.fetchCardsBySetId(widget.setCard.setId);
      if (!mounted) return;
      setState(() {
        _originalCards = List.from(cards);
        for (var card in cards) {
          _items.add(
            CardEditorItem(
              cardId: card.cardId,
              term: card.term,
              def: card.definition,
              state: card.state,
            ),
          );
        }
        if (_items.isEmpty) _addEmptyInitialCards();
        _isLoading = false;
      });
    } catch (e) {
      _notify("Lỗi tải dữ liệu", Colors.red);
    }
  }

  void _addEmptyInitialCards() {
    for (int i = 0; i < 2; i++) {
      _items.add(
        CardEditorItem(cardId: '', term: '', def: '', state: 'learning'),
      );
    }
  }

  void _showImportDialog() async {
    final List<Map<String, String>>? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ImportCardsScreen(),
        fullscreenDialog: true,
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        if (_items.length == 2 &&
            _items[0].termCtrl.text.isEmpty &&
            _items[0].defCtrl.text.isEmpty) {
          _items.clear();
        }

        for (var data in result) {
          _items.add(
            CardEditorItem(
              cardId: '',
              term: data['term']!,
              def: data['def']!,
              state: 'learning',
            ),
          );
        }
      });
      _notify("Đã nhập thành công ${result.length} thẻ", Colors.green);
    }
  }

  // ==========================================
  // LOGIC LƯU THAY ĐỔI (ĐÃ SỬA SANG BULK)
  // ==========================================
  Future<void> _handleSave() async {
    if (!_validate()) return;
    setState(() => _isSaving = true);

    try {
      // 1. Lấy danh sách các thẻ có nội dung
      final activeItems = _items
          .where(
            (it) => it.termCtrl.text.isNotEmpty || it.defCtrl.text.isNotEmpty,
          )
          .toList();

      final activeIds = activeItems
          .map((e) => e.cardId)
          .where((id) => id.isNotEmpty)
          .toSet();

      // 2. Gom danh sách ID cần XÓA (Thẻ cũ không còn xuất hiện)
      final idsToDelete = _originalCards
          .where((orig) => !activeIds.contains(orig.cardId))
          .map((c) => c.cardId)
          .toList();

      // 3. Gom danh sách thẻ cần CẬP NHẬT (Đã có ID)
      final updateData = activeItems
          .where((it) => it.cardId.isNotEmpty)
          .map(
            (it) => {
              "cardId": it.cardId,
              "term": it.termCtrl.text.trim(),
              "definition": it.defCtrl.text.trim(),
              "state": it.state,
            },
          )
          .toList();

      // 4. Gom danh sách thẻ MỚI (Chưa có ID)
      final newData = activeItems
          .where((it) => it.cardId.isEmpty)
          .map(
            (it) => {
              "term": it.termCtrl.text.trim(),
              "definition": it.defCtrl.text.trim(),
            },
          )
          .toList();

      // --- THỰC THI GỌI API HÀNG LOẠT ---
      // Chỉ tốn tối đa 3 requests tổng cộng
      if (idsToDelete.isNotEmpty) {
        await _cardService.deleteCardsBulk(cardIds: idsToDelete);
      }

      if (updateData.isNotEmpty) {
        await _cardService.updateCardsBulk(updates: updateData);
      }

      if (newData.isNotEmpty) {
        await _cardService.createCardsBulk(
          cards: newData,
          setId: widget.setCard.setId,
        );
      }

      if (mounted) {
        _notify("Đã lưu thành công", Colors.green);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _notify("Lỗi khi lưu thay đổi: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _validate() {
    final filled = _items
        .where(
          (it) =>
              it.termCtrl.text.trim().isNotEmpty ||
              it.defCtrl.text.trim().isNotEmpty,
        )
        .toList();
    if (filled.length < 2) {
      _notify("Cần ít nhất 2 thẻ dữ liệu", Colors.red);
      return false;
    }
    return true;
  }

  void _confirmDeleteCard(int index) {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Gỡ thẻ này?",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Nội dung thẻ sẽ bị xóa vĩnh viễn sau khi bạn nhấn LƯU.",
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Hủy", style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() => _items.removeAt(index).dispose());
                Navigator.pop(ctx);
              },
              child: const Text("Gỡ"),
            ),
          ],
        );
      },
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.cardColor,
          title: Text(
            "Xóa toàn bộ thẻ?",
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Tất cả nội dung sẽ bị xóa sạch. Bạn có chắc chắn không?",
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Hủy", style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  for (var it in _items) {
                    it.dispose();
                  }
                  _items.clear();
                  _addEmptyInitialCards();
                });
                Navigator.pop(ctx);
              },
              child: const Text("Xóa hết"),
            ),
          ],
        );
      },
    );
  }

  void _notify(String m, Color c) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.setCard.name.toUpperCase(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blue,
                    ),
                  )
                : const Icon(Icons.check, color: Colors.blue, size: 28),
            onPressed: _isSaving ? null : _handleSave,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : Column(
              children: [
                _buildControlBar(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 10, bottom: 20),
                    itemCount: _items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _items.length) return _buildAddBtn();
                      return _buildCardItem(index, _items[index]);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildControlBar() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(width: 1, color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          TextButton.icon(
            icon: Icon(Icons.add_box_outlined, color: theme.iconTheme.color),
            label: Text(
              "IMPORT",
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            onPressed: _showImportDialog,
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.swap_horiz, color: theme.iconTheme.color),
            onPressed: () {
              setState(() {
                for (var it in _items) {
                  final t = it.termCtrl.text;
                  it.termCtrl.text = it.defCtrl.text;
                  it.defCtrl.text = t;
                }
              });
              _notify("Đã đảo mặt tất cả thẻ", theme.textTheme.bodyMedium?.color ?? Colors.black);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
            onPressed: _confirmClearAll,
          ),
        ],
      ),
    );
  }

  Widget _buildCardItem(int index, CardEditorItem item) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(width: 2, color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            offset: const Offset(4, 4),
            color: theme.shadowColor.withOpacity(0.5),
          )
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text(
                  "${index + 1}",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _confirmDeleteCard(index),
                  child: const Text(
                    "GỠ THẺ",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 2, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInput("THUẬT NGỮ", item.termCtrl),
                const SizedBox(height: 16),
                _buildInput("ĐỊNH NGHĨA", item.defCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl) {
    final theme = Theme.of(context);
    return TextField(
      controller: ctrl,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(width: 1.5, color: theme.dividerColor),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(width: 2.5, color: theme.primaryColor),
        ),
      ),
    );
  }

  Widget _buildAddBtn() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(width: 2, color: theme.dividerColor),
            foregroundColor: theme.textTheme.bodyMedium?.color,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          icon: Icon(Icons.add, color: theme.iconTheme.color),
          label: Text(
            "THÊM THẺ MỚI",
            style: TextStyle(fontWeight: FontWeight.w900, color: theme.textTheme.bodyMedium?.color),
          ),
          onPressed: () => setState(
            () => _items.add(
              CardEditorItem(cardId: '', term: '', def: '', state: 'learning'),
            ),
          ),
        ),
      ),
    );
  }
}
