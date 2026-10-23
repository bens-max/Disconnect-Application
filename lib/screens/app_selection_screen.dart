import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import '../services/storage_service.dart';
import 'timer_screen.dart';

class AppSelectionScreen extends StatefulWidget {
  final bool returnSelection;

  const AppSelectionScreen({super.key, this.returnSelection = false});

  @override
  State<AppSelectionScreen> createState() => _AppSelectionScreenState();
}

class _AppSelectionScreenState extends State<AppSelectionScreen> {
  final StorageService _storageService = StorageService();
  List<AppInfo> _installedApps = [];
  Set<String> _selectedPackages = {};
  bool _isLoading = true;
  String? _loadError;
  String _searchQuery = '';
  final Map<String, Uint8List?> _appIcons = {};
  static const _maxCachedIcons = 40;

  Color get _accent => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _appIcons.clear();
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: true,
        withIcon: false,
      );
      final selected = await _storageService.getBlockedApps();
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _installedApps = apps;
        _selectedPackages = selected.toSet();
        _isLoading = false;
        _loadError = null;
      });
      _loadIconsInBackground(apps.take(_maxCachedIcons).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load installed apps. Please try again.';
      });
    }
  }

  Future<void> _loadIconsInBackground(List<AppInfo> apps) async {
    for (var app in apps) {
      if (!mounted) break;
      try {
        final info = await InstalledApps.getAppInfo(app.packageName);
        if (info == null || !mounted || info.icon == null) {
          continue;
        }
        setState(() {
          _appIcons[app.packageName] = info.icon;
        });
      } catch (_) {
        continue;
      }
    }
  }

  List<AppInfo> get _filteredApps {
    if (_searchQuery.isEmpty) return _installedApps;
    return _installedApps
        .where(
          (app) => app.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
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

  Future<void> _confirmSelection() async {
    await _storageService.saveBlockedApps(_selectedPackages.toList());
    if (!mounted) return;
    if (widget.returnSelection) {
      Navigator.pop(context, true);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TimerScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select apps', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Choose what to disconnect',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accent.withValues(alpha: 0.18),
                  Theme.of(context).colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
            ),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Search installed apps',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(() => _searchQuery = ''),
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.touch_app_outlined, size: 18, color: _accent),
                    const SizedBox(width: 8),
                    Text(
                      _selectedPackages.isEmpty
                          ? 'Tap an app to add it to your focus list'
                          : '${_selectedPackages.length} app${_selectedPackages.length == 1 ? '' : 's'} selected',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    child: FilledButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      label: Text(_loadError!),
                    ),
                  )
                : _filteredApps.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 56,
                          color: _accent.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No apps found',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Try a different search term',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _filteredApps.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      indent: 80,
                      color: Color(0xFF2C2C2C),
                    ),
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      final isSelected = _selectedPackages.contains(
                        app.packageName,
                      );
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? _accent.withValues(alpha: 0.45)
                                : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _accent.withValues(alpha: 0.2)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child:
                                _appIcons.containsKey(app.packageName) &&
                                    _appIcons[app.packageName] != null
                                ? Image.memory(
                                    _appIcons[app.packageName]!,
                                    width: 42,
                                    height: 42,
                                  )
                                : const Icon(Icons.android, size: 42),
                          ),
                          title: Text(
                            app.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            app.packageName,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          trailing: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: isSelected
                                ? Icon(
                                    Icons.check_circle,
                                    key: const ValueKey('selected'),
                                    color: _accent,
                                  )
                                : const Icon(
                                    Icons.add_circle_outline,
                                    key: ValueKey('unselected'),
                                    color: Colors.grey,
                                  ),
                          ),
                          onTap: () => _toggleSelection(app.packageName),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmSelection,
              icon: const Icon(Icons.done),
              label: const Text('Done'),
            ),
          ),
        ),
      ),
    );
  }
}
