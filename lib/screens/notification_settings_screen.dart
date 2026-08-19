import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fasting_provider.dart';
import '../services/notification_service.dart';
import '../models/fasting_zone.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _masterEnabled = true;
  List<String> _disabledMilestones = [];
  Map<String, int> _customMilestones = {};
  bool _reminderEnabled = false;
  int _reminderHour = 20;
  int _reminderMin = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await NotificationService.isEnabled();
    final disabled = await NotificationService.getDisabledMilestones();
    final custom = await NotificationService.getCustomMilestones();
    final rEnabled = await NotificationService.isReminderEnabled();
    final (rH, rM) = await NotificationService.getReminderTime();
    if (mounted) {
      setState(() {
        _masterEnabled = enabled;
        _disabledMilestones = disabled;
        _customMilestones = custom;
        _reminderEnabled = rEnabled;
        _reminderHour = rH;
        _reminderMin = rM;
      });
    }
  }

  Future<void> _toggleReminder(bool value) async {
    if (value) {
      await NotificationService.requestPermissions();
    }
    await NotificationService.setReminderEnabled(value);
    await _loadSettings();
  }

  Future<void> _pickReminderTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMin),
    );
    if (time != null) {
      await NotificationService.setReminderTime(time.hour, time.minute);
      await _loadSettings();
    }
  }

  Future<void> _toggleMaster(bool value) async {
    if (value) {
      await NotificationService.requestPermissions();
    }
    await NotificationService.setEnabled(value);
    await _loadSettings();
    _reschedule();
  }

  Future<void> _toggleMilestone(String name, bool value) async {
    await NotificationService.toggleMilestone(name, value);
    await _loadSettings();
    _reschedule();
  }

  Future<void> _addCustom() async {
    final nameController = TextEditingController();
    final hoursController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Custom Milestone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g. Water Break)'),
              textCapitalization: TextCapitalization.words,
            ),
            TextField(
              controller: hoursController,
              decoration: const InputDecoration(labelText: 'Hours into fast'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && int.tryParse(hoursController.text) != null) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      await NotificationService.addCustomMilestone(nameController.text, int.parse(hoursController.text));
      await _loadSettings();
      _reschedule();
    }
  }

  Future<void> _deleteCustom(String name) async {
    await NotificationService.deleteCustomMilestone(name);
    await _loadSettings();
    _reschedule();
  }

  void _reschedule() {
    final fp = context.read<FastingProvider>();
    if (_masterEnabled && fp.isFasting && fp.startTime != null) {
      NotificationService.scheduleMilestones(fp.startTime!, fp.protocol.hours);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('All Notifications'),
            subtitle: const Text('Enable or disable all fasting alerts'),
            value: _masterEnabled,
            onChanged: _toggleMaster,
          ),
          const Divider(),
          const _SectionHeader(title: 'DAILY REMINDER'),
          SwitchListTile(
            title: const Text('Start Fasting Reminder'),
            subtitle: const Text('Reminds you to start your fast every day if none is active'),
            value: _reminderEnabled,
            onChanged: _masterEnabled ? _toggleReminder : null,
          ),
          ListTile(
            enabled: _masterEnabled && _reminderEnabled,
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Reminder Time'),
            trailing: Text(
              '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMin.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _masterEnabled && _reminderEnabled ? null : Colors.grey,
                  ),
            ),
            onTap: _masterEnabled && _reminderEnabled ? _pickReminderTime : null,
          ),
          const Divider(),
          const _SectionHeader(title: 'STANDARD ZONES'),
          for (final zone in kFastingZones.skip(1))
            CheckboxListTile(
              enabled: _masterEnabled,
              secondary: Text(zone.emoji, style: const TextStyle(fontSize: 20)),
              title: Text(zone.name),
              subtitle: Text('At ${zone.fromHour}h'),
              value: !_disabledMilestones.contains(zone.name),
              onChanged: _masterEnabled ? (v) => _toggleMilestone(zone.name, v ?? true) : null,
            ),
          CheckboxListTile(
            enabled: _masterEnabled,
            secondary: const Icon(Icons.flag_rounded, color: Colors.green),
            title: const Text('Goal Reached'),
            subtitle: Text('At ${fp.protocol.hours}h'),
            value: !_disabledMilestones.contains('Goal Reached'),
            onChanged: _masterEnabled ? (v) => _toggleMilestone('Goal Reached', v ?? true) : null,
          ),
          const Divider(),
          _SectionHeader(
            title: 'CUSTOM MILESTONES',
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _masterEnabled ? _addCustom : null,
              color: scheme.primary,
            ),
          ),
          if (_customMilestones.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No custom milestones added yet.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          for (final entry in _customMilestones.entries)
            ListTile(
              enabled: _masterEnabled,
              leading: Checkbox(
                value: !_disabledMilestones.contains(entry.key),
                onChanged: _masterEnabled ? (v) => _toggleMilestone(entry.key, v ?? true) : null,
              ),
              title: Text(entry.key),
              subtitle: Text('At ${entry.value}h'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: _masterEnabled ? () => _deleteCustom(entry.key) : null,
              ),
            ),
          const Divider(),
          const _SectionHeader(title: 'SCHEDULED FOR CURRENT FAST'),
          if (!fp.isFasting)
            const ListTile(
              title: Text('No active fast'),
              subtitle: Text('Start a fast to see exact alert times.'),
            )
          else ...[
             for (final zone in kFastingZones.skip(1))
              if (!_disabledMilestones.contains(zone.name))
                _ScheduledTimeTile(
                  label: zone.name,
                  emoji: zone.emoji,
                  time: fp.startTime!.add(Duration(hours: zone.fromHour)),
                ),
             for (final entry in _customMilestones.entries)
              if (!_disabledMilestones.contains(entry.key))
                _ScheduledTimeTile(
                  label: entry.key,
                  emoji: '⭐',
                  time: fp.startTime!.add(Duration(hours: entry.value)),
                ),
            if (!_disabledMilestones.contains('Goal Reached'))
               _ScheduledTimeTile(
                  label: 'Goal Reached',
                  emoji: '🏁',
                  time: fp.startTime!.add(Duration(hours: fp.protocol.hours)),
                ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.primary),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ScheduledTimeTile extends StatelessWidget {
  final String label;
  final String emoji;
  final DateTime time;

  const _ScheduledTimeTile({
    required this.label,
    required this.emoji,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final isPast = time.isBefore(DateTime.now());
    return ListTile(
      dense: true,
      leading: Text(emoji, style: const TextStyle(fontSize: 18)),
      title: Text(label),
      trailing: Text(
        _formatTime(time),
        style: TextStyle(
          color: isPast ? Colors.grey : null,
          decoration: isPast ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final now = DateTime.now();
  final day = t.day == now.day ? 'Today' : (t.day == now.day + 1 ? 'Tomorrow' : '${t.day}.${t.month}');
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return '$day $hm';
}
