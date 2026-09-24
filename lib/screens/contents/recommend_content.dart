import 'package:aaplay/core/theme/app_animations.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aaplay/presentation/viewmodels/auth_viewmodel.dart';
import 'package:aaplay/presentation/viewmodels/recommend_viewmodel.dart';
import 'package:aaplay/presentation/layouts/work_layout_strategy.dart';
import 'package:aaplay/presentation/widgets/auth/login_dialog.dart';
import 'package:aaplay/widgets/work_grid/enhanced_work_grid_view.dart';
import 'package:aaplay/widgets/filter/filter_with_keyword.dart';

class RecommendContent extends StatefulWidget {
  const RecommendContent({super.key});

  @override
  State<RecommendContent> createState() => _RecommendContentState();
}

class _RecommendContentState extends State<RecommendContent>
    with AutomaticKeepAliveClientMixin {
  final _layoutStrategy = const WorkLayoutStrategy();
  final _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.minScrollExtent) {
      return;
    }
    context.read<RecommendViewModel>().closeFilterPanel();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecommendViewModel>().loadRecommendations();
    });
  }

  @override
  void dispose() {
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
      context.read<RecommendViewModel>().loadRecommendations(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        // Grid: only rebuilds when list data changes
        Selector<
            RecommendViewModel,
            ({
              List<Work> works,
              bool isLoading,
              String? error,
              bool isLoginError,
              int currentPage,
              int? totalPages
            })>(
          selector: (_, vm) => (
            works: vm.works,
            isLoading: vm.isLoading,
            error: vm.error,
            isLoginError: vm.isLoginError,
            currentPage: vm.currentPage,
            totalPages: vm.totalPages,
          ),
          builder: (context, data, child) {
            return EnhancedWorkGridView(
              works: data.works,
              isLoading: data.isLoading,
              error: data.error,
              isLoginError: data.isLoginError,
              onLogin: _promptLogin,
              currentPage: data.currentPage,
              totalPages: data.totalPages,
              onPageChanged: (page) =>
                  context.read<RecommendViewModel>().loadPage(page),
              onRefresh: () => context
                  .read<RecommendViewModel>()
                  .loadRecommendations(refresh: true),
              onRetry: () => context
                  .read<RecommendViewModel>()
                  .loadRecommendations(refresh: true),
              layoutStrategy: _layoutStrategy,
              scrollController: _scrollController,
            );
          },
        ),
        // Filter panel: only rebuilds when filter state changes
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child:
              Selector<RecommendViewModel, ({bool expanded, bool hasSubtitle})>(
            selector: (_, vm) => (
              expanded: vm.filterPanelExpanded,
              hasSubtitle: vm.hasSubtitle,
            ),
            builder: (context, data, child) {
              return AnimatedSlide(
                duration: AppAnimations.short,
                curve: AppAnimations.standard,
                offset: Offset(0, data.expanded ? 0 : -1),
                child: FilterWithKeyword(
                  hasSubtitle: data.hasSubtitle,
                  onSubtitleChanged: (_) =>
                      context.read<RecommendViewModel>().toggleSubtitleFilter(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
