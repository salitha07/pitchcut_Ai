
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _qualityKey = 'pitchcut_video_quality';
  static const String _formatKey = 'pitchcut_video_format';
  static const String _autoSaveKey = 'pitchcut_auto_save';

  String _videoQuality = '1080p';
  String _videoFormat = 'MP4';
  String _appVersion = 'Loading...';
  bool _autoSave = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();

    if (!mounted) return;

    setState(() {
      _videoQuality = prefs.getString(_qualityKey) ?? '1080p';
      _videoFormat = prefs.getString(_formatKey) ?? 'MP4';
      _autoSave = prefs.getBool(_autoSaveKey) ?? true;
      _appVersion = packageInfo.version;
      _loading = false;
    });
  }

  Future<void> _saveQuality(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_qualityKey, value);

    if (!mounted) return;

    setState(() => _videoQuality = value);
    _showMessage('Video quality saved');
  }

  Future<void> _saveFormat(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_formatKey, value);

    if (!mounted) return;

    setState(() => _videoFormat = value);
    _showMessage('Video format saved');
  }

  Future<void> _saveAutoSave(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSaveKey, value);

    if (!mounted) return;

    setState(() => _autoSave = value);
    _showMessage(value ? 'Auto-save enabled' : 'Auto-save disabled');
  }

  Future<void> _changeTheme(
    BuildContext context,
    ThemeMode mode,
  ) async {
    await AppThemeController.instance.setThemeMode(mode);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${mode == ThemeMode.dark ? 'Dark' : 'Light'} mode enabled',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 21),
          const SizedBox(width: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text(
                    'Customize your PitchCut AI experience.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  _sectionTitle(
                    context,
                    'Appearance',
                    Icons.palette_outlined,
                  ),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: RadioGroup<ThemeMode>(
                        groupValue: AppThemeController.instance.themeMode,
                        onChanged: (value) {
                          if (value != null) {
                            _changeTheme(context, value);
                          }
                        },
                        child: Column(
                          children: [
                            RadioListTile<ThemeMode>(
                              value: ThemeMode.dark,
                              title: const Text('Dark Mode'),
                              subtitle: const Text(
                                'Use the dark appearance',
                              ),
                              secondary: const Icon(
                                Icons.dark_mode_outlined,
                              ),
                            ),
                            const Divider(height: 1),
                            RadioListTile<ThemeMode>(
                              value: ThemeMode.light,
                              title: const Text('Light Mode'),
                              subtitle: const Text(
                                'Use the light appearance',
                              ),
                              secondary: const Icon(
                                Icons.light_mode_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  _sectionTitle(
                    context,
                    'Video & Editing',
                    Icons.video_settings_outlined,
                  ),

                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.high_quality_outlined),
                          title: const Text('Video Quality'),
                          subtitle: const Text(
                            'Choose your export resolution',
                          ),
                          trailing: DropdownButton<String>(
                            value: _videoQuality,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(
                                value: '720p',
                                child: Text('720p'),
                              ),
                              DropdownMenuItem(
                                value: '1080p',
                                child: Text('1080p'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _saveQuality(value);
                              }
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.video_file_outlined),
                          title: const Text('Video Format'),
                          subtitle: const Text(
                            'Choose your preferred video format',
                          ),
                          trailing: DropdownButton<String>(
                            value: _videoFormat,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(
                                value: 'MP4',
                                child: Text('MP4'),
                              ),
                              DropdownMenuItem(
                                value: 'MOV',
                                child: Text('MOV'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _saveFormat(value);
                              }
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.save_outlined),
                          title: const Text('Auto-save'),
                          subtitle: const Text(
                            'Automatically save editing changes',
                          ),
                          value: _autoSave,
                          onChanged: _saveAutoSave,
                        ),
                      ],
                    ),
                  ),

                  _sectionTitle(
                    context,
                    'Presentation Analysis',
                    Icons.analytics_outlined,
                  ),

                  Card(
                    child: _settingsTile(
                      icon: Icons.record_voice_over_outlined,
                      title: 'Speaking Analysis',
                      subtitle: 'Presentation performance analysis',
                      onTap: () {
                        context.push('/analysis');
                      },
                    ),
                  ),

                  _sectionTitle(
                    context,
                    'About',
                    Icons.info_outline_rounded,
                  ),

                  Card(
                    child: Column(
                      children: [
                        _settingsTile(
                          icon: Icons.smart_display_outlined,
                          title: 'PitchCut AI',
                          subtitle:
                              'Intelligent Presentation Video Editor and Speaking Coach',
                        ),
                        const Divider(height: 1),
                        _settingsTile(
                          icon: Icons.code_rounded,
                          title: 'App Version',
                          subtitle: 'Version $_appVersion',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Center(
                    child: Text(
                      'Made with PitchCut AI',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
