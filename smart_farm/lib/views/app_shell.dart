import 'package:flutter/material.dart';

import '../state/farm_controller.dart';
import '../theme/app_tokens.dart';
import '../theme/farm_palette.dart';
import 'tabs/controls_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'widgets/gateway_sheet.dart';

/// The app frame: header, the two tabs, and navigation.
///
/// Navigation is a bottom bar on a phone and a rail once the window is wide
/// enough, because a dashboard on a wall-mounted tablet has completely
/// different space to work with than one held in a hand.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final FarmController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final PageController _pages = PageController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _pages.dispose();
    super.dispose();
  }

  /// Surfaces failed commands as snack bars.
  ///
  /// The controller queues messages rather than calling into the scaffold
  /// itself, so it stays free of any context. Draining happens after the frame
  /// because a snack bar cannot be shown while the tree is building.
  void _onControllerChanged() {
    String? message;
    while ((message = widget.controller.takeCommandError()) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message!)));
      });
    }
  }

  void _selectTab(int index) {
    if (index == widget.controller.tabIndex) return;
    widget.controller.selectTab(index);
    _pages.animateToPage(
      index,
      duration: AppTokens.slow,
      curve: AppTokens.curve,
    );
  }

  /// Keeps the visible page in step with the selected tab.
  ///
  /// The page view is driven imperatively, so anything that rebuilds or
  /// remounts it — a window resized across the navigation breakpoint, for
  /// instance — can leave it showing a different tab from the one the
  /// navigation highlights. Correcting it after the frame keeps the two from
  /// ever disagreeing.
  void _syncPageToSelection() {
    if (!mounted || !_pages.hasClients) return;
    final double page = _pages.page ?? _pages.initialPage.toDouble();
    if ((page - widget.controller.tabIndex).abs() < 0.01) return;
    _pages.jumpToPage(widget.controller.tabIndex);
  }

  Future<void> _openGatewaySheet() async {
    final GatewaySheetResult? result = await showGatewaySheet(
      context,
      controller: widget.controller,
    );
    if (!mounted || result == null) return;
    await widget.controller.useAddress(
      result.useDiscovery ? null : result.address,
    );
  }

  void _toggleTheme() {
    widget.controller.toggleTheme(Theme.of(context).brightness);
  }

  @override
  Widget build(BuildContext context) {
    final int index = widget.controller.tabIndex;

    return Scaffold(
      appBar: _FarmAppBar(
        online: widget.controller.isOnline,
        onToggleTheme: _toggleTheme,
        onOpenGateway: _openGatewaySheet,
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= AppTokens.railBreakpoint;
          final Widget pages = PageView(
            controller: _pages,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              DashboardTab(
                controller: widget.controller,
                onOpenControls: () => _selectTab(1),
              ),
              ControlsTab(
                controller: widget.controller,
                onOpenSettings: _openGatewaySheet,
              ),
            ],
          );

          // The rail lives in the same tree position at every width, only
          // collapsing to nothing when there is no room for it. Moving it would
          // remount the page view and silently reset it to the first tab.
          final Widget navigation = wide
              ? _NavigationRail(index: index, onSelect: _selectTab)
              : const SizedBox.shrink();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncPageToSelection();
          });

          return Column(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    navigation,
                    Expanded(child: pages),
                  ],
                ),
              ),
              if (!wide) _NavigationBar(index: index, onSelect: _selectTab),
            ],
          );
        },
      ),
    );
  }
}

/// Flat header: wordmark on the left, actions on the right.
class _FarmAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _FarmAppBar({
    required this.online,
    required this.onToggleTheme,
    required this.onOpenGateway,
  });

  final bool online;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenGateway;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FarmPalette palette = FarmPalette.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return AppBar(
      toolbarHeight: 60,
      titleSpacing: AppTokens.md,
      title: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[palette.soil, palette.rain],
              ),
            ),
            child: const Icon(
              Icons.eco_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppTokens.sm),
          // Flexible so the wordmark ellipsises rather than pushing the action
          // buttons off a narrow screen or a large text scale.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Smart Farm',
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  online ? 'Streaming live' : 'Link down',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: online ? palette.online : palette.danger,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        _HeaderAction(
          icon: Icons.dns_outlined,
          tooltip: 'Gateway address',
          onPressed: onOpenGateway,
        ),
        _HeaderAction(
          icon: dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          tooltip: dark ? 'Switch to light' : 'Switch to dark',
          onPressed: onToggleTheme,
        ),
        const SizedBox(width: AppTokens.sm),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: palette.hairline),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final FarmPalette palette = FarmPalette.of(context);

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: palette.inkSoft,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation, used on narrow windows.
class _NavigationBar extends StatelessWidget {
  const _NavigationBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // A hairline rather than a shadow keeps the flat treatment while still
      // separating the bar from the scrolling content behind it.
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: FarmPalette.of(context).hairline),
        ),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Controls',
          ),
        ],
      ),
    );
  }
}

/// Side navigation, used once the window is wide enough.
class _NavigationRail extends StatelessWidget {
  const _NavigationRail({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: FarmPalette.of(context).hairline),
        ),
      ),
      child: NavigationRail(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.9,
        destinations: const <NavigationRailDestination>[
          NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: Text('Dashboard'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: Text('Controls'),
          ),
        ],
      ),
    );
  }
}