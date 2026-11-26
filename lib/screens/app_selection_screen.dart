import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import '../services/storage_service.dart';
import '../services/native_service.dart';
import 'timer_screen.dart';

enum _AppCategoryFilter {
  all,
  social,
  entertainment,
  games,
  browser,
  communication,
  everythingExceptEssentials,
  installed,
}

class AppSelectionScreen extends StatefulWidget {
  final bool returnSelection;
  final bool permittedSelection;

  const AppSelectionScreen({
    super.key,
    this.returnSelection = false,
    this.permittedSelection = false,
  });

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
  bool _showSystemApps = false;
  bool _isSaving = false;
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();
  _AppCategoryFilter _categoryFilter = _AppCategoryFilter.all;
  final Map<String, Uint8List?> _appIcons = {};
  static List<AppInfo>? _appCache;
  static List<AppInfo>? _permittedAppCache;
  static DateTime? _appCacheTime;
  static final Map<String, Uint8List?> _iconCache = {};
  static const _maxCachedIcons = 60;
  static const _appCacheLifetime = Duration(seconds: 30);
  static Future<List<AppInfo>>? _appLoadFuture;
  static Future<List<AppInfo>>? _permittedAppLoadFuture;
  static const _socialPackages = [
    'facebook',
    'instagram',
    'twitter',
    'snapchat',
    'tiktok',
    'reddit',
    'discord',
    'linkedin',
    'telegram',
    'whatsapp',
    'signal',
    'threads',
  ];
  static const _entertainmentPackages = [
    'youtube',
    'netflix',
    'spotify',
    'primevideo',
    'disney',
    'twitch',
    'pinterest',
    'podcast',
    'music',
    'gallery',
    'photos',
  ];
  static const _browserPackages = [
    'chrome',
    'chromium',
    'firefox',
    'opera',
    'edge',
    'brave',
    'sbrowser',
    'browser',
    'duckduckgo',
  ];
  static const _communicationPackages = [
    'messenger',
    'messages',
    'sms',
    'mms',
    'mail',
    'email',
    'gmail',
    'phone',
    'dialer',
    'contacts',
    'meet',
    'zoom',
    'skype',
    'teams',
  ];
  static const _essentialPackages = [
    'launcher',
    'android.settings',
    'packageinstaller',
    'dialer',
    'contacts',
    'messages',
    'sms',
    'mms',
    'calendar',
    'clock',
    'calculator',
    'files',
    'documents',
    'settings',
    'phone',
  ];

  Color get _accent => Theme.of(context).colorScheme.primary;

  @override
  void initState() {
    super.initState();
    _restorePickerPreferences();
    final cache = widget.permittedSelection ? _permittedAppCache : _appCache;
    if (cache != null) {
      _installedApps = cache;
      _appIcons.addAll({
        for (final app in cache)
          if (_iconCache.containsKey(app.packageName))
            app.packageName: _iconCache[app.packageName],
      });
      _isLoading = false;
    }
    _loadData();
  }

  Future<void> _restorePickerPreferences() async {
    final prefs = await _storageService.getAppPickerPreferences();
    if (!mounted) return;
    setState(() {
      _showSystemApps = prefs.showSystemApps;
      _categoryFilter = _AppCategoryFilter.values.firstWhere(
        (filter) => filter.name == prefs.category,
        orElse: () => _AppCategoryFilter.all,
      );
    });
  }

  Future<void> _savePickerPreferences() async {
    await _storageService.saveAppPickerPreferences(
      showSystemApps: _showSystemApps,
      category: _categoryFilter.name,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (_appCache == null) {
      setState(() => _isLoading = true);
    }
    try {
      final cacheIsFresh =
          _appCacheTime != null &&
          DateTime.now().difference(_appCacheTime!) < _appCacheLifetime;
      final appsFuture = widget.permittedSelection
          ? (forceRefresh
                ? (_permittedAppLoadFuture ??= _loadPermittedApps())
                : (_permittedAppLoadFuture ??= _loadPermittedApps()))
          : (!forceRefresh && cacheIsFresh
                ? Future<List<AppInfo>>.value(_appCache!)
                : (_appLoadFuture ??= _loadApps()));
      final selectedFuture = widget.permittedSelection
          ? _storageService.getPermittedApps()
          : _storageService.getBlockedApps();
      final results = await Future.wait<Object>([appsFuture, selectedFuture]);
      final apps = results[0] as List<AppInfo>;
      final selected = results[1] as List<String>;
      if (!mounted) return;
      setState(() {
        if (widget.permittedSelection) {
          _permittedAppCache = apps;
        } else {
          _appCache = apps;
        }
        _installedApps = apps;
        final installedPackageNames = apps
            .map((app) => app.packageName)
            .toSet();
        _selectedPackages = selected
            .where(installedPackageNames.contains)
            .toSet();
        _isLoading = false;
        _loadError = null;
      });
      if (_selectedPackages.length != selected.length) {
        if (widget.permittedSelection) {
          await _storageService.savePermittedApps(_selectedPackages.toList());
          await NativeService.savePermittedApps(_selectedPackages.toList());
        } else {
          await _storageService.saveBlockedApps(_selectedPackages.toList());
        }
      }
      _loadIconsInBackground(apps.take(_maxCachedIcons).toList());
    } catch (_) {
      _appLoadFuture = null;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = _appCache == null
            ? 'Could not load installed apps. Please try again.'
            : null;
      });
    }
  }

  static Future<List<AppInfo>> _loadApps() async {
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        withIcon: false,
        excludeNonLaunchableApps: false,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _appCache = apps;
      _appCacheTime = DateTime.now();
      return apps;
    } finally {
      _appLoadFuture = null;
    }
  }

  static Future<List<AppInfo>> _loadPermittedApps() async {
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: false,
        withIcon: false,
      );
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _permittedAppCache = apps;
      return apps;
    } finally {
      _permittedAppLoadFuture = null;
    }
  }

  Future<void> _loadIconsInBackground(List<AppInfo> apps) async {
    final missingApps = apps
        .where((app) => !_iconCache.containsKey(app.packageName))
        .toList();
    for (var start = 0; start < missingApps.length; start += 12) {
      if (!mounted) return;
      final batch = missingApps.skip(start).take(12);
      final results = await Future.wait(
        batch.map((app) async {
          try {
            final info = await InstalledApps.getAppInfo(app.packageName);
            return MapEntry(app.packageName, info?.icon);
          } catch (_) {
            return MapEntry<String, Uint8List?>(app.packageName, null);
          }
        }),
      );
      for (final result in results) {
        _iconCache[result.key] = result.value;
        if (_iconCache.length > _maxCachedIcons) {
          _iconCache.remove(_iconCache.keys.first);
        }
      }
      if (mounted) {
        setState(() {
          for (final result in results) {
            _appIcons[result.key] = result.value;
          }
        });
      }
    }
    if (mounted) {
      setState(() {
        for (final app in apps) {
          final icon = _iconCache[app.packageName];
          if (icon != null) {
            _appIcons[app.packageName] = icon;
          }
        }
      });
    }
  }

  List<AppInfo> get _filteredApps {
    final query = _searchQuery.toLowerCase();
    return _installedApps.where((app) {
      if (!_showSystemApps && app.isSystemApp) return false;
      if (query.isNotEmpty &&
          !app.name.toLowerCase().contains(query) &&
          !app.packageName.toLowerCase().contains(query)) {
        return false;
      }
      return _matchesCategory(app);
    }).toList();
  }

  bool _matchesCategory(AppInfo app) {
    switch (_categoryFilter) {
      case _AppCategoryFilter.all:
        return true;
      case _AppCategoryFilter.social:
        return app.category == AppCategory.social ||
            _matchesPackage(app, _socialPackages);
      case _AppCategoryFilter.entertainment:
        return app.category == AppCategory.audio ||
            app.category == AppCategory.video ||
            app.category == AppCategory.image ||
            app.category == AppCategory.news ||
            _matchesPackage(app, _entertainmentPackages);
      case _AppCategoryFilter.games:
        return app.category == AppCategory.game ||
            app.packageName.contains('game') ||
            app.name.toLowerCase().contains('game');
      case _AppCategoryFilter.browser:
        return _matchesPackage(app, _browserPackages);
      case _AppCategoryFilter.communication:
        return _matchesPackage(app, _communicationPackages);
      case _AppCategoryFilter.everythingExceptEssentials:
        return !app.isSystemApp && !_matchesPackage(app, _essentialPackages);
      case _AppCategoryFilter.installed:
        return !app.isSystemApp;
    }
  }

  bool _matchesPackage(AppInfo app, List<String> packages) {
    final packageName = app.packageName.toLowerCase();
    final name = app.name.toLowerCase();
    return packages.any((item) {
      final packageMatch =
          packageName == item ||
          packageName.startsWith('$item.') ||
          packageName.endsWith('.$item');
      final normalizedName = name.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normalizedItem = item.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final nameMatch =
          normalizedName == normalizedItem ||
          normalizedName.startsWith(normalizedItem);
      return packageMatch || nameMatch;
    });
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

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter apps',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show system apps'),
                      value: _showSystemApps,
                      onChanged: (value) {
                        setSheetState(() {});
                        setState(() {
                          _showSystemApps = value;
                          if (!value &&
                              _categoryFilter ==
                                  _AppCategoryFilter
                                      .everythingExceptEssentials) {
                            _categoryFilter = _AppCategoryFilter.all;
                          }
                        });
                        _savePickerPreferences();
                      },
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final filter in _AppCategoryFilter.values)
                          ChoiceChip(
                            label: Text(_filterLabel(filter)),
                            selected: _categoryFilter == filter,
                            onSelected: (_) {
                              setSheetState(() {});
                              setState(() => _categoryFilter = filter);
                              _savePickerPreferences();
                              Navigator.pop(sheetContext);
                            },
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _filterLabel(_AppCategoryFilter filter) {
    switch (filter) {
      case _AppCategoryFilter.all:
        return 'All';
      case _AppCategoryFilter.social:
        return 'Social';
      case _AppCategoryFilter.entertainment:
        return 'Entertainment';
      case _AppCategoryFilter.games:
        return 'Games';
      case _AppCategoryFilter.browser:
        return 'Browser';
      case _AppCategoryFilter.communication:
        return 'Communication';
      case _AppCategoryFilter.everythingExceptEssentials:
        return 'Everything except essentials';
      case _AppCategoryFilter.installed:
        return 'Installed apps';
    }
  }

  Future<void> _confirmSelection() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final packageNames = _selectedPackages.toList();
    try {
      if (widget.permittedSelection) {
        await _storageService.savePermittedApps(packageNames);
        final savedNative = await NativeService.savePermittedApps(packageNames);
        if (!savedNative) {
          throw Exception('Could not save permitted apps');
        }
      } else {
        await _storageService.saveBlockedApps(packageNames);
        final savedNative = await NativeService.saveBlockedApps(packageNames);
        if (!savedNative) {
          throw Exception('Could not save blocked apps');
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save app selection. Please try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
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
        actions: [
          IconButton(
            tooltip: 'Refresh installed apps',
            onPressed: _isLoading ? null : () => _loadData(forceRefresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.permittedSelection ? 'Permitted apps' : 'Select apps',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              widget.permittedSelection
                  ? 'Keep launchers and communications accessible'
                  : 'Choose what to disconnect',
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
                  controller: _searchController,
                  onChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 180),
                      () {
                        if (!mounted) return;
                        setState(() => _searchQuery = value);
                      },
                    );
                  },
                  decoration: InputDecoration(
                    hintText: 'Search installed apps',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchDebounce?.cancel();
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('All apps'),
                        selected: _categoryFilter == _AppCategoryFilter.all,
                        onSelected: (_) {
                          setState(
                            () => _categoryFilter = _AppCategoryFilter.all,
                          );
                          _savePickerPreferences();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _openFilterSheet,
                      icon: const Icon(Icons.tune, size: 18),
                      label: Text(_filterLabel(_categoryFilter)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _selectedPackages.addAll(
                          _filteredApps.map((app) => app.packageName),
                        );
                      }),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Select visible'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _selectedPackages.isEmpty
                          ? null
                          : () {
                              final removed = Set<String>.from(
                                _selectedPackages,
                              );
                              setState(() => _selectedPackages.clear());
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Cleared app selection'),
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () => setState(
                                      () => _selectedPackages.addAll(removed),
                                    ),
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.remove_done, size: 18),
                      label: const Text('Clear'),
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
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _filteredApps.length,
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      final isSelected = _selectedPackages.contains(
                        app.packageName,
                      );
                      return RepaintBoundary(
                        child: Container(
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
                          child: Semantics(
                            button: true,
                            selected: isSelected,
                            label:
                                '${app.name}${isSelected ? ', selected' : ', not selected'}',
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${app.isSystemApp ? 'System app' : 'Installed app'}'
                                ' • ${app.category.name}'
                                '${app.isLaunchableApp ? ' • Launchable' : ' • Not launchable'}',
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
                          ),
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
              onPressed: _isSaving ? null : _confirmSelection,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done),
              label: Text(
                widget.permittedSelection
                    ? 'Keep ${_selectedPackages.length} permitted app${_selectedPackages.length == 1 ? '' : 's'}'
                    : 'Block ${_selectedPackages.length} app${_selectedPackages.length == 1 ? '' : 's'}',
              ),
            ),
          ),
        ),
      ),
    );
  }
}