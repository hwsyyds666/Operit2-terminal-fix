// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:operit_folder_access/operit_folder_access.dart';

import '../../../../core/bridge/ProxyCoreRuntimeBridge.dart';
import '../../../../core/proxy/generated/CoreProxyClients.g.dart';
import '../../../../core/proxy/generated/CoreProxyModels.g.dart' as core;
import '../../../../data/preferences/UserPreferencesManager.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../common/components/M3LoadingIndicator.dart';
import '../../../theme/OperitGlassSurface.dart';
import '../components/SettingsControlStyles.dart';
import 'TerminalProfilesSettings.dart';

class WorkspaceSettingsPanel extends StatefulWidget {
  const WorkspaceSettingsPanel({super.key, GeneratedCoreProxyClients? clients})
    : clients =
          clients ?? const GeneratedCoreProxyClients(ProxyCoreRuntimeBridge());

  final GeneratedCoreProxyClients clients;

  @override
  State<WorkspaceSettingsPanel> createState() => _WorkspaceSettingsPanelState();
}

class _WorkspaceSettingsPanelState extends State<WorkspaceSettingsPanel> {
  Future<_WorkspaceSettingsData>? _future;
  final Set<String> _selectedWorkspaceNames = <String>{};
  bool _deleteInProgress = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_WorkspaceSettingsData> _load() async {
    final summary = await widget.clients.application
        .workspaceService()
        .workspaceManagementSummary();

    return _WorkspaceSettingsData(
      unboundWorkspaces: summary.unboundWorkspaces
          .map(
            (workspace) => _UnboundWorkspaceInfo(
              name: workspace.name,
              fullPath: workspace.fullPath,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.settingsWorkspaceConfirmDeleteTitle),
          content: Text(
            l10n.settingsWorkspaceDeleteConfirmation(
              _selectedWorkspaceNames.length,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _deleteInProgress
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: _deleteInProgress
                  ? null
                  : () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _deleteSelectedWorkspaces();
  }

  Future<void> _deleteSelectedWorkspaces() async {
    final l10n = AppLocalizations.of(context)!;
    final targets = Set<String>.from(_selectedWorkspaceNames);
    setState(() => _deleteInProgress = true);
    try {
      await widget.clients.application
          .workspaceService()
          .deleteUnboundWorkspaces(workspaceNames: targets.toList());
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedWorkspaceNames.clear();
        _future = _load();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsWorkspaceDeleteFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _deleteInProgress = false);
      }
    }
  }

  void _selectAll(List<_UnboundWorkspaceInfo> workspaces) {
    setState(() {
      _selectedWorkspaceNames
        ..clear()
        ..addAll(workspaces.map((workspace) => workspace.name));
    });
  }

  void _clearSelected() {
    setState(() => _selectedWorkspaceNames.clear());
  }

  void _setWorkspaceSelected(String workspaceName, bool selected) {
    if (_deleteInProgress) {
      return;
    }
    setState(() {
      if (selected) {
        _selectedWorkspaceNames.add(workspaceName);
      } else {
        _selectedWorkspaceNames.remove(workspaceName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<_WorkspaceSettingsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          Error.throwWithStackTrace(snapshot.error!, snapshot.stackTrace!);
        }
        final data = snapshot.data;
        if (data == null) {
          return const M3LoadingPane();
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: <Widget>[
            _WorkspaceManagementCard(
              clients: widget.clients,
              onChanged: () => setState(() => _future = _load()),
            ),
            TerminalProfilesSettings(clients: widget.clients),
            _UnboundWorkspaceCard(
              workspaces: data.unboundWorkspaces,
              selectedWorkspaceNames: _selectedWorkspaceNames,
              deleteInProgress: _deleteInProgress,
              onSelectAll: () => _selectAll(data.unboundWorkspaces),
              onClearSelected: _clearSelected,
              onSelectionChange: _setWorkspaceSelected,
              onDeleteSelected: _confirmDeleteSelected,
            ),
          ],
        );
      },
    );
    return content;
  }
}

class _WorkspaceManagementCard extends StatefulWidget {
  const _WorkspaceManagementCard({
    required this.clients,
    required this.onChanged,
  });
  final GeneratedCoreProxyClients clients;
  final VoidCallback onChanged;

  @override
  State<_WorkspaceManagementCard> createState() =>
      _WorkspaceManagementCardState();
}

class _WorkspaceManagementCardState extends State<_WorkspaceManagementCard> {
  bool busy = false;
  String? defaultId;
  List<core.Workspace> workspaces = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await widget.clients.repositoryWorkspacePreferenceStore
        .getAll();
    final selected = await UserPreferencesManager(
      clients: widget.clients,
    ).loadDefaultWorkspaceId();
    if (!mounted) return;
    setState(() {
      workspaces = items;
      defaultId = items.any((item) => item.id == selected) ? selected : null;
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      await _reload();
      if (mounted) widget.onChanged();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> _nameDialog(String title, [String initial = '']) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<core.WorkspaceFolder?> _pickFolder() async {
    final source = await OperitFolderAccess.pickWorkspaceDirectory();
    if (source == null) return null;
    final path = await widget.clients.servicesFileSelectionService
        .mountDirectory(
          sourceJson: jsonEncode({
            'namespace': source.namespace,
            'backend': source.backend,
            'root': source.root,
            'name': source.name,
          }),
        );
    final node = await widget.clients.serverCoreNodeRouter.localNodeId();
    return core.WorkspaceFolder(
      name: source.name,
      path: '$node://${path.replaceFirst(RegExp(r"^/+"), "")}',
    );
  }

  Future<void> _create(bool internal) async {
    final name = await _nameDialog('新建工作区');
    if (name == null) return;
    await _run(() async {
      core.WorkspaceFolder? folder;
      if (internal) {
        final id = 'workspace-${DateTime.now().microsecondsSinceEpoch}';
        final path = await widget.clients.chatRuntimeHolderMain
            .createAndGetDefaultWorkspace(chatId: id, projectType: 'blank');
        folder = core.WorkspaceFolder(name: name, path: path);
      } else {
        folder = await _pickFolder();
      }
      if (folder == null) return;
      await widget.clients.repositoryWorkspacePreferenceStore.create(
        name: name,
        folders: [folder],
      );
    });
  }

  Future<void> _save(
    core.Workspace workspace, {
    String? name,
    List<core.WorkspaceFolder>? folders,
  }) async {
    await widget.clients.repositoryWorkspacePreferenceStore.upsert(
      workspace: core.Workspace(
        id: workspace.id,
        name: name ?? workspace.name,
        folders: folders ?? workspace.folders,
        createdAt: workspace.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: '工作区',
    children: [
      DropdownButtonFormField<String>(
        initialValue: defaultId ?? '',
        decoration: const InputDecoration(labelText: '新建聊天的默认工作区'),
        items: [
          const DropdownMenuItem(value: '', child: Text('普通聊天')),
          for (final workspace in workspaces)
            DropdownMenuItem(value: workspace.id, child: Text(workspace.name)),
        ],
        onChanged: busy
            ? null
            : (value) => _run(
                () => UserPreferencesManager(
                  clients: widget.clients,
                ).saveDefaultWorkspaceId(value),
              ),
      ),
      for (final workspace in workspaces)
        ExpansionTile(
          key: ValueKey(workspace.id),
          title: Text(workspace.name),
          subtitle: Text(
            workspace.folders.first.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            for (var index = 0; index < workspace.folders.length; index++)
              ListTile(
                title: Text(workspace.folders[index].name),
                subtitle: SelectableText(workspace.folders[index].path),
                leading: Icon(index == 0 ? Icons.star : Icons.folder_outlined),
                trailing: Wrap(
                  children: [
                    if (index != 0)
                      IconButton(
                        tooltip: '设为主目录',
                        icon: const Icon(Icons.star_outline),
                        onPressed: busy
                            ? null
                            : () => _run(() async {
                                final folders = [...workspace.folders];
                                folders.insert(0, folders.removeAt(index));
                                await _save(workspace, folders: folders);
                              }),
                      ),
                    if (workspace.folders.length > 1)
                      IconButton(
                        tooltip: '移除目录',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: busy
                            ? null
                            : () => _run(() async {
                                final folders = [...workspace.folders]
                                  ..removeAt(index);
                                await _save(workspace, folders: folders);
                              }),
                      ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                          final folder = await _pickFolder();
                          if (folder == null) return;
                          if (workspace.folders.any(
                            (item) =>
                                item.path == folder.path ||
                                item.name == folder.name,
                          )) {
                            throw StateError('该目录或目录名已存在');
                          }
                          await _save(
                            workspace,
                            folders: [...workspace.folders, folder],
                          );
                        }),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('添加目录'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final name = await _nameDialog(
                            '重命名工作区',
                            workspace.name,
                          );
                          if (name != null)
                            await _run(() => _save(workspace, name: name));
                        },
                  child: const Text('重命名'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('移除工作区'),
                              content: const Text(
                                '移除工作区登记，目录和文件会保留。请先将关联的聊天移走。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('移除'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true)
                            await _run(() async {
                              await widget.clients.application
                                  .workspaceService()
                                  .removeWorkspaceRecord(
                                    workspaceId: workspace.id,
                                  );
                              if (defaultId == workspace.id) {
                                await UserPreferencesManager(
                                  clients: widget.clients,
                                ).saveDefaultWorkspaceId(null);
                              }
                            });
                        },
                  child: const Text('移除'),
                ),
              ],
            ),
          ],
        ),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: busy ? null : () => _create(false),
            icon: const Icon(Icons.folder_open),
            label: const Text('添加共享目录'),
          ),
          TextButton.icon(
            onPressed: busy ? null : () => _create(true),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('创建内部工作区'),
          ),
        ],
      ),
    ],
  );
}

class _WorkspaceSettingsData {
  const _WorkspaceSettingsData({required this.unboundWorkspaces});

  final List<_UnboundWorkspaceInfo> unboundWorkspaces;
}

class _UnboundWorkspaceInfo {
  const _UnboundWorkspaceInfo({required this.name, required this.fullPath});

  final String name;
  final String fullPath;
}

class _UnboundWorkspaceCard extends StatelessWidget {
  const _UnboundWorkspaceCard({
    required this.workspaces,
    required this.selectedWorkspaceNames,
    required this.deleteInProgress,
    required this.onSelectAll,
    required this.onClearSelected,
    required this.onSelectionChange,
    required this.onDeleteSelected,
  });

  final List<_UnboundWorkspaceInfo> workspaces;
  final Set<String> selectedWorkspaceNames;
  final bool deleteInProgress;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelected;
  final void Function(String workspaceName, bool selected) onSelectionChange;
  final VoidCallback onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: l10n.settingsWorkspaceUnboundTitle,
      children: <Widget>[
        _BodyText(l10n.settingsWorkspaceUnboundSubtitle),
        if (workspaces.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.settingsWorkspaceNoUnbound,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.settingsWorkspaceSelectedCount(
                    selectedWorkspaceNames.length,
                    workspaces.length,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: deleteInProgress ? null : onSelectAll,
                child: Text(l10n.settingsWorkspaceSelectAllCurrentList),
              ),
              TextButton(
                onPressed: selectedWorkspaceNames.isEmpty || deleteInProgress
                    ? null
                    : onClearSelected,
                child: Text(l10n.settingsWorkspaceClearAll),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.30,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: workspaces.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: colorScheme.surface.withValues(alpha: 0.75),
                  ),
                  itemBuilder: (context, index) {
                    final workspace = workspaces[index];
                    return _UnboundWorkspaceRow(
                      workspaceInfo: workspace,
                      selected: selectedWorkspaceNames.contains(workspace.name),
                      deleteInProgress: deleteInProgress,
                      onSelectionChange: (selected) =>
                          onSelectionChange(workspace.name, selected),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: selectedWorkspaceNames.isEmpty || deleteInProgress
                ? null
                : onDeleteSelected,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            icon: deleteInProgress
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onError,
                    ),
                  )
                : const Icon(Icons.delete_outline),
            label: Text(
              l10n.settingsWorkspaceDeleteSelected(
                selectedWorkspaceNames.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UnboundWorkspaceRow extends StatelessWidget {
  const _UnboundWorkspaceRow({
    required this.workspaceInfo,
    required this.selected,
    required this.deleteInProgress,
    required this.onSelectionChange,
  });

  final _UnboundWorkspaceInfo workspaceInfo;
  final bool selected;
  final bool deleteInProgress;
  final ValueChanged<bool> onSelectionChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: deleteInProgress ? null : () => onSelectionChange(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Checkbox(
              value: selected,
              onChanged: deleteInProgress
                  ? null
                  : (value) => onSelectionChange(value == true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    workspaceInfo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.settingsWorkspaceNotUsedByAnyChat,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    workspaceInfo.fullPath,
                    softWrap: true,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.folder_outlined, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OperitGlassSurface(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: radius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.18),
        ),
        material: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: SettingsControlStyles.sectionTitleTextStyle(context),
              ),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
