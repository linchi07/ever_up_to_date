import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:ever_up_to_date/ever_up_to_date.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EverUpToDate Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const UpdateDemoPage(),
    );
  }
}

class UpdateDemoPage extends StatefulWidget {
  const UpdateDemoPage({super.key});

  @override
  State<UpdateDemoPage> createState() => _UpdateDemoPageState();
}

class _UpdateDemoPageState extends State<UpdateDemoPage> {
  static const String DEMO_MANIFEST_URL = String.fromEnvironment(
    'EVERUP_MANIFEST_URL',
    defaultValue:
        'https://raw.githubusercontent.com/linchi07/ever_up_to_date/main/example/demo_appcast.json',
  );

  @override
  void initState() {
    super.initState();
    _initUpdater();
  }

  void _initUpdater() {
    EverUpToDate.instance.initialize(
      const UpdateOptions(
        manifestUrl: DEMO_MANIFEST_URL,
        channel: 'beta',
        preferredLocale: 'zh-CN',
        publicKeyEd25519: bool.hasEnvironment('EVERUP_PUBLIC_KEY')
            ? String.fromEnvironment('EVERUP_PUBLIC_KEY')
            : null,
      ),
    );
  }

  Future<void> _checkUpdate() async {
    await EverUpToDate.instance.checkForUpdate();
  }

  Future<void> _downloadUpdate() async {
    await EverUpToDate.instance.downloadUpdate();
  }

  Future<void> _installUpdate() async {
    // Check permission on Android if needed
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final canInstall = await EverUpToDate.instance
          .canRequestPackageInstalls();
      if (!canInstall) {
        await EverUpToDate.instance.openInstallPermissionSettings();
        return;
      }
    }

    await EverUpToDate.instance.installUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EverUpToDate Auto-Update Demo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ValueListenableBuilder<UpdateState>(
            valueListenable: EverUpToDate.instance.stateNotifier,
            builder: (context, state, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '当前状态: ${_describeState(state)}',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (state is UpdateDownloadingState) ...[
                    LinearProgressIndicator(value: state.progress),
                    const SizedBox(height: 8),
                    Text('${(state.progress * 100).toStringAsFixed(1)}%'),
                  ],
                  if (state is UpdateAvailableState) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '发现新版本: ${state.updateInfo.targetVersion}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('更新日志:\n${state.updateInfo.releaseNotes}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _downloadUpdate,
                      icon: const Icon(Icons.download),
                      label: const Text('下载更新'),
                    ),
                  ],
                  if (state is UpdateReadyToInstallState) ...[
                    ElevatedButton.icon(
                      onPressed: _installUpdate,
                      icon: const Icon(Icons.system_update_alt),
                      label: const Text('立即安装'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed:
                        state is UpdateCheckingState ||
                            state is UpdateDownloadingState ||
                            state is UpdateVerifyingState ||
                            state is UpdateInstallingState
                        ? null
                        : _checkUpdate,
                    child: const Text('检查更新 (Check For Updates)'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _describeState(UpdateState state) {
    if (state is UpdateIdleState) return '空闲 (Idle)';
    if (state is UpdateDeferredState) return '暂缓更新: ${state.reason}';
    if (state is UpdateInstalledState) return '已确认运行新版本: ${state.version}';
    if (state is UpdateCheckingState) return '正在检查新版本...';
    if (state is UpdateUpToDateState) return '已是最新版本 (Up to date)';
    if (state is UpdateAvailableState) return '有新版本可用';
    if (state is UpdateDownloadingState) return '正在下载更新包...';
    if (state is UpdateVerifyingState) return '正在校验文件哈希与签名...';
    if (state is UpdateReadyToInstallState) return '下载与校验完成，准备安装';
    if (state is UpdateInstallingState) return '正在启动安装流程...';
    if (state is UpdateErrorState) return '错误: ${state.message}';
    return state.toString();
  }
}
