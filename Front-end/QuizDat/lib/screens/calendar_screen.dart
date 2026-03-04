import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../models/calendar_event.dart';
import '../services/calendar_service.dart';
import 'dashboard.dart';
import 'folder_management.dart';
import '../widgets/app_sidebar.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final ValueNotifier<List<CalendarEvent>> _selectedEvents;
  final CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<CalendarEvent> _allEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _selectedEvents = ValueNotifier(_getEventsForDay(_selectedDay!));
    _loadEvents();
  }

  @override
  void dispose() {
    _selectedEvents.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final events = await CalendarService().fetchEvents();
      if (!mounted) return;
      setState(() {
        _allEvents = events;
        _isLoading = false;
        _selectedEvents.value = _getEventsForDay(_selectedDay!);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar("Lỗi: $e", Colors.red);
    }
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    return _allEvents.where((event) => isSameDay(event.date, day)).toList();
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
      _selectedEvents.value = _getEventsForDay(selectedDay);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  // --- DIALOG THÊM/SỬA SỰ KIỆN ---
  void _showEventDialog({CalendarEvent? event}) {
    final titleController = TextEditingController(text: event?.title ?? "");
    final descController = TextEditingController(
      text: event?.description ?? "",
    );
    CalendarType selectedType = event?.type ?? CalendarType.study;
    TimeOfDay selectedTime = event != null
        ? TimeOfDay.fromDateTime(event.date)
        : TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return Dialog(
            backgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: theme.dividerColor, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    event == null ? Icons.add_alarm : Icons.edit_calendar,
                    size: 60,
                    color: theme.iconTheme.color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    event == null ? "THÊM SỰ KIỆN" : "SỬA SỰ KIỆN",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleController,
                    cursorColor: theme.primaryColor,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      labelText: "Tiêu đề",
                      labelStyle: theme.textTheme.bodyMedium,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: theme.primaryColor, width: 2),
                      ),
                    ),
                  ),
                  TextField(
                    controller: descController,
                    cursorColor: theme.primaryColor,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      labelText: "Mô tả (không bắt buộc)",
                      labelStyle: theme.textTheme.bodyMedium,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: theme.primaryColor, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<CalendarType>(
                    value: selectedType,
                    style: theme.textTheme.bodyMedium,
                    dropdownColor: theme.cardColor,
                    items: CalendarType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              t.name.toUpperCase(),
                              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedType = val!),
                    decoration: InputDecoration(
                      labelText: "Loại sự kiện",
                      labelStyle: theme.textTheme.bodyMedium,
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Giờ: ${selectedTime.format(context)}",
                      style: theme.textTheme.bodyMedium,
                    ),
                    trailing: Icon(Icons.access_time, color: theme.iconTheme.color),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          "HỦY",
                          style: TextStyle(
                            color: theme.disabledColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryColor,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        onPressed: () async {
                          if (titleController.text.isEmpty) return;
                          final finalDate = DateTime(
                            _selectedDay!.year,
                            _selectedDay!.month,
                            _selectedDay!.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          );

                          if (event == null) {
                            await CalendarService().createEvent(
                              title: titleController.text,
                              description: descController.text,
                              date: finalDate,
                              type: selectedType.name,
                            );
                          } else {
                            await CalendarService().updateEvent(
                              calendarId: event.id,
                              title: titleController.text,
                              description: descController.text,
                              date: finalDate,
                              type: selectedType.name,
                              isDone: event.isDone,
                            );
                          }
                          Navigator.pop(context);
                          _loadEvents();
                        },
                        child: const Text("LƯU"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        iconTheme: theme.iconTheme,
        title: Text(
          "LỊCH HỌC TẬP",
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.iconTheme.color!),
              ),
              child: Icon(Icons.add, size: 20, color: theme.iconTheme.color),
            ),
            onPressed: () => _showEventDialog(),
          ),
        ],
      ),
      drawer: const AppSidebar(currentRoute: '/calendar'),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    border: Border.all(color: theme.dividerColor, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    onDaySelected: _onDaySelected,
                    eventLoader: _getEventsForDay,
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: theme.textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      leftChevronIcon: Icon(Icons.chevron_left, color: theme.iconTheme.color),
                      rightChevronIcon: Icon(Icons.chevron_right, color: theme.iconTheme.color),
                    ),
                    calendarStyle: CalendarStyle(
                      defaultTextStyle: theme.textTheme.bodyMedium!,
                      weekendTextStyle: TextStyle(color: isDark ? Colors.redAccent : Colors.red),
                      outsideTextStyle: TextStyle(color: theme.textTheme.bodyMedium?.color?.withOpacity(0.5)),
                      selectedDecoration: BoxDecoration(
                        color: isDark ? Colors.white : Colors.black,
                        shape: BoxShape.circle,
                      ),
                      selectedTextStyle: TextStyle(color: isDark ? Colors.black : Colors.white),
                      todayDecoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(color: theme.textTheme.bodyMedium?.color),
                      markerDecoration: BoxDecoration(
                        color: isDark ? Colors.purpleAccent : const Color.fromARGB(255, 121, 121, 121),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "SỰ KIỆN TRONG NGÀY",
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<List<CalendarEvent>>(
                    valueListenable: _selectedEvents,
                    builder: (context, value, _) {
                      if (value.isEmpty) {
                        return const Center(
                          child: Text(
                            "Trống",
                            style: TextStyle(color: Colors.black26),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: value.length,
                        itemBuilder: (context, index) {
                          final event = value[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              border: Border.all(color: theme.dividerColor),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: ListTile(
                              onTap: () => _showEventDialog(event: event),
                              leading: Checkbox(
                                value: event.isDone,
                                activeColor: theme.primaryColor,
                                checkColor: isDark ? Colors.black : Colors.white,
                                side: BorderSide(color: theme.unselectedWidgetColor),
                                onChanged: (val) async {
                                  setState(() => event.isDone = val!);
                                  await CalendarService().toggleEventStatus(
                                    calendarId: event.id,
                                    isDone: val!,
                                  );
                                },
                              ),
                              title: Text(
                                event.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: event.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: theme.textTheme.titleMedium?.color,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${DateFormat('HH:mm').format(event.date)} • ${event.typeName}",
                                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                                  ),
                                  if (event.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      event.description,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: theme.iconTheme.color,
                                ),
                                onPressed: () async {
                                  await CalendarService().deleteEvent(event.id);
                                  _loadEvents();
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
