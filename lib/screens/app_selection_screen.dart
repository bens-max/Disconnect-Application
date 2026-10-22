import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import '../services/storage_service.dart';
import 'timer_screen.dart';
import 'schedule_screen.dart';

class AppSelectionScreen extends StatefulWidget {
  const AppSelectionScreen({super.key});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  final StorageService _storageService = StorageService();
  List<AppInfo> _installedApps = [];
  Set<String> _selectedPackages = {};
  bool _isLoading = true;
  String _searchQuery = '';
  final Map<String, Uint8List?> _appIcons = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: true,
      withIcon: false,
    );

    final selected = await _storageService.getBlockedApps();
    
    // Sort apps alphabetically
    apps.sort((a, b) => a.name.compareTo(b.name));

    setState(() {
      _installedApps = apps;
      _selectedPackages = selected.toSet();
      _isLoading = false;
    });

    _loadIconsInBackground(apps);
  }

  Future<void> _loadIconsInBackground(List<AppInfo> apps) async {
    for (var app in apps) {
      if (!mounted) break;
      final info = await InstalledApps.getAppInfo(app.packageName);
      if (info != null && info.icon != null && mounted) {
        setState(() {
          _appIcons[app.packageName] = info.icon;
        });
      }
    }
  }

  List<AppInfo> get _filteredApps {
    if (_searchQuery.isEmpty) return _installedApps;
    return _installedApps
        .where((app) =>
            app.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  void _toggleSelection(String packageName) {
    setState(() {
      if (_selectedPackages.contains(packageName)) {
        _selectedPackages.remove(packageName);
      } else {
        _selectedPackages.add(packageName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Apps to Block'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _filteredApps.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, indent: 80, color: Color(0xFF2C2C2C)),
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      final isSelected = _selectedPackages.contains(app.packageName);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _appIcons.containsKey(app.packageName) && _appIcons[app.packageName] != null
                              ? Image.memory(_appIcons[app.packageName]!, width: 42, height: 42)
                              : const Icon(Icons.android, size: 42),
                        ),
                        title: Text(
                          app.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          app.packageName,
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (_) => _toggleSelection(app.packageName),
                          activeColor: Theme.of(context).colorScheme.primary,
                        ),
                        onTap: () => _toggleSelection(app.packageName),
                      );

                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _storageService.saveBlockedApps(_selectedPackages.toList());
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const TimerScreen()),
                          );
                        },
                        icon: const Icon(Icons.timer_outlined),
                        label: Text(
                          _selectedPackages.isEmpty
                              ? 'Set a Whole-Device Timer'
                              : 'Set a One-Time Timer',
                        ),
                      ),
                    ),
                    if (_selectedPackages.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await _storageService.saveBlockedApps(_selectedPackages.toList());
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ScheduleScreen()),
                            );
                          },
                          icon: const Icon(Icons.schedule),
                          label: const Text('Set a Daily From / To Schedule'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

    );
  }
}
