// ignore_for_file: file_names

import '../../../core/proxy/generated/CoreProxyClients.g.dart';
import '../../../core/proxy/generated/CoreProxyModels.g.dart' as core_proxy;
import '../../../data/preferences/UserPreferencesManager.dart';

/// Inherits only the selected chat's workspace while the native tab is selected.
Future<String?> sidebarNewChatWorkspaceId({
  required GeneratedCoreProxyClients clients,
  required List<core_proxy.ChatHistoryListItem> histories,
  required String? currentChatId,
}) async {
  final id = await UserPreferencesManager(
    clients: clients,
  ).loadDefaultWorkspaceId();
  if (id == null) return null;
  return (await clients.repositoryWorkspacePreferenceStore.getById(
    workspaceId: id,
  ))?.id;
}
