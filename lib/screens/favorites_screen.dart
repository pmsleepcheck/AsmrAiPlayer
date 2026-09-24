import 'package:aaplay/common/constants/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aaplay/widgets/sidebar/sidebar_menu.dart';
import 'package:aaplay/presentation/viewmodels/auth_viewmodel.dart';
import 'package:aaplay/presentation/viewmodels/favorites_viewmodel.dart';
import 'package:aaplay/presentation/layouts/work_layout_strategy.dart';
import 'package:aaplay/presentation/widgets/auth/login_dialog.dart';
import 'package:aaplay/widgets/work_grid/enhanced_work_grid_view.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _layoutStrategy = const WorkLayoutStrategy();
  final _scrollController = ScrollController();
  late FavoritesViewModel _viewModel;
  bool _initialized = false;

  /// 桌面平台（win/mac/linux）没有系统返回手势/按键，且本页自带 drawer
  /// 会把 AppBar 自动 leading 抢成汉堡按钮 —— 桌面显式换成返回箭头。
  /// 移动端保持 `null`：框架按 drawer 推断出汉堡 + 系统返回兜底。
  /// 用 `defaultTargetPlatform`（可测试覆盖）而非 `dart:io Platform`。
  bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final authViewModel = Provider.of<AuthViewModel>(context, listen: false);
      _viewModel = FavoritesViewModel(authViewModel);
      _viewModel.loadFavorites();
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _promptLogin() async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => const LoginDialog(),
    );
    if (!mounted) return;
    if (context.read<AuthViewModel>().isLoggedIn) {
      _viewModel.loadFavorites();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(Strings.favorites),
          leading: _isDesktopPlatform
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: Strings.back,
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
        ),
        drawer: const SidebarMenu(),
        body: Consumer<FavoritesViewModel>(
          builder: (context, viewModel, child) {
            return Column(
              children: [
                Expanded(
                  child: EnhancedWorkGridView(
                    works: viewModel.works,
                    isLoading: viewModel.isLoading,
                    error: viewModel.error,
                    isLoginError: viewModel.isLoginError,
                    onLogin: _promptLogin,
                    onRetry: () => viewModel.loadFavorites(),
                    layoutStrategy: _layoutStrategy,
                    scrollController: _scrollController,
                    currentPage: viewModel.currentPage,
                    // 未知总页数按 1 兜底：与迁移前 PaginationControls 的显示一致。
                    totalPages: viewModel.totalPages ?? 1,
                    onPageChanged: viewModel.loadPage,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
