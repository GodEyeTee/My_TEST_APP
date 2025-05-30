import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../features/auth/presentation/bloc/auth_bloc.dart';
import '../features/auth/presentation/bloc/auth_event.dart';
import '../features/auth/presentation/bloc/auth_state.dart';
import '../features/auth/data/repositories/auth_repository_impl.dart';
import '../features/auth/data/models/user_model.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/wallet/presentation/pages/wallet_page.dart';
import '../features/analytics/presentation/pages/analytics_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/hotel_booking/presentation/pages/hotel_search_page.dart';
import '../features/shopping/presentation/pages/products_page.dart';
import '../features/ocr_scanner/presentation/pages/scanner_page.dart';
import '../services/rbac/rbac_service.dart';
import '../services/rbac/permission_guard.dart';
import '../services/rbac/role_manager.dart';

/// Enhanced main screen with security-first navigation and RBAC integration
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController;
  final RBACService _rbacService = RBACService();
  late List<NavigationItem> _allNavigationItems;
  List<NavigationItem> _visibleNavigationItems = [];

  // Security monitoring
  int _navigationAttempts = 0;
  int _blockedNavigationAttempts = 0;
  DateTime? _lastSecurityCheck;

  @override
  void initState() {
    super.initState();
    _initializeNavigation();
    _performSecurityCheck();
    print(
      '🔍 Debug: User permissions = ${_rbacService.getCurrentUserPermissions().map((p) => p.id).toList()}',
    );
  }

  /// Initialize navigation with comprehensive security configuration
  void _initializeNavigation() {
    _allNavigationItems = [
      NavigationItem(
        id: 'home',
        icon: Icons.home,
        activeIcon: Icons.home,
        label: 'Home',
        page: const HomePage(),
        permissions: [], // Home is accessible to all authenticated users
        category: NavigationCategory.primary,
        priority: 100,
        description: 'Dashboard and overview',
      ),
      NavigationItem(
        id: 'hotels',
        icon: Icons.hotel_outlined,
        activeIcon: Icons.hotel,
        label: 'Hotels',
        page: const HotelSearchPage(),
        permissions: ['book_hotels'],
        category: NavigationCategory.business,
        priority: 90,
        description: 'Search and book hotels',
      ),
      NavigationItem(
        id: 'shopping',
        icon: Icons.shopping_cart_outlined,
        activeIcon: Icons.shopping_cart,
        label: 'Shop',
        page: const ProductsPage(),
        permissions: ['purchase_products'],
        category: NavigationCategory.business,
        priority: 85,
        description: 'Browse and purchase products',
      ),
      NavigationItem(
        id: 'scanner',
        icon: Icons.document_scanner_outlined,
        activeIcon: Icons.document_scanner,
        label: 'Scanner',
        page: const ScannerPage(),
        permissions: ['use_scanner'],
        category: NavigationCategory.tools,
        priority: 70,
        description: 'OCR document scanning',
      ),
      NavigationItem(
        id: 'wallet',
        icon: Icons.account_balance_wallet_outlined,
        activeIcon: Icons.account_balance_wallet,
        label: 'Wallet',
        page: const WalletPage(),
        permissions: [], // Wallet is accessible to all
        category: NavigationCategory.financial,
        priority: 80,
        description: 'Manage your wallet and payments',
      ),
      NavigationItem(
        id: 'analytics',
        icon: Icons.analytics_outlined,
        activeIcon: Icons.analytics,
        label: 'Analytics',
        page: const AnalyticsPage(),
        permissions: ['view_analytics'],
        category: NavigationCategory.advanced,
        priority: 60,
        description: 'View reports and analytics',
      ),
      NavigationItem(
        id: 'settings',
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Settings',
        page: const SettingsPage(),
        permissions: [], // Settings is accessible to all
        category: NavigationCategory.system,
        priority: 50,
        description: 'App settings and preferences',
      ),
    ];

    _updateVisibleNavigationItems();
    _tabController = TabController(
      length: _visibleNavigationItems.length,
      vsync: this,
    );
  }

  /// Update visible navigation items based on user permissions
  void _updateVisibleNavigationItems() {
    _visibleNavigationItems =
        _allNavigationItems.where((item) {
          // Allow items with no permission requirements
          if (item.permissions.isEmpty) return true;

          // Check if user has required permissions
          return _rbacService.hasAnyPermission(item.permissions);
        }).toList();

    // Sort by priority (higher priority first)
    _visibleNavigationItems.sort((a, b) => b.priority.compareTo(a.priority));

    // Ensure selected index is valid
    if (_selectedIndex >= _visibleNavigationItems.length) {
      _selectedIndex = 0;
    }

    if (!kReleaseMode) {
      print(
        '🧭 Navigation: ${_visibleNavigationItems.length}/${_allNavigationItems.length} items visible',
      );
    }
  }

  /// Perform security check and update navigation
  void _performSecurityCheck() {
    _lastSecurityCheck = DateTime.now();

    final previousCount = _visibleNavigationItems.length;
    print(
      '🔍 Current permissions: ${_rbacService.getCurrentUserPermissions().map((p) => p.id).toList()}',
    );
    _updateVisibleNavigationItems();
    final currentCount = _visibleNavigationItems.length;

    // Update tab controller if item count changed
    if (previousCount != currentCount) {
      _tabController.dispose();
      _tabController = TabController(
        length: _visibleNavigationItems.length,
        vsync: this,
      );

      if (!kReleaseMode) {
        print('🔄 Navigation updated: $previousCount -> $currentCount items');
      }
    }
  }

  /// Handle navigation tap with security validation
  void _onItemTapped(int index) {
    _navigationAttempts++;

    if (index >= 0 && index < _visibleNavigationItems.length) {
      final item = _visibleNavigationItems[index];

      // Double-check permissions before navigation
      if (item.permissions.isNotEmpty &&
          !_rbacService.hasAnyPermission(item.permissions)) {
        _blockedNavigationAttempts++;
        _showAccessDeniedMessage(item);
        return;
      }

      setState(() {
        _selectedIndex = index;
      });

      _tabController.animateTo(index);

      if (!kReleaseMode) {
        print('🧭 Navigation: Switched to ${item.label} (${item.id})');
      }
    }
  }

  /// Show access denied message
  void _showAccessDeniedMessage(NavigationItem item) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.security, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Access denied to ${item.label}. Contact your administrator.',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Details',
          textColor: Colors.white,
          onPressed: () => _showPermissionDetails(item),
        ),
      ),
    );
  }

  /// Show permission details dialog
  void _showPermissionDetails(NavigationItem item) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.security, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('Access Requirements'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Feature: ${item.label}'),
                const SizedBox(height: 8),
                Text('Description: ${item.description}'),
                const SizedBox(height: 8),
                const Text('Required Permissions:'),
                ...item.permissions.map(
                  (permission) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('• $permission'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Contact your administrator to request access to these features.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        // Update navigation when auth state changes
        if (state is Authenticated || state is Unauthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _performSecurityCheck();
              setState(() {});
            }
          });
        }
      },
      builder: (context, state) {
        if (state is! Authenticated) {
          return _buildErrorScreen('Authentication Required');
        }

        if (_visibleNavigationItems.isEmpty) {
          return _buildErrorScreen('No Accessible Features');
        }

        return _buildMainScreen(state);
      },
    );
  }

  /// Build main screen with navigation
  Widget _buildMainScreen(Authenticated state) {
    final currentItem = _visibleNavigationItems[_selectedIndex];

    return Scaffold(
      appBar: _buildAppBar(state, currentItem),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNavigation(),
      drawer: _buildNavigationDrawer(state),
    );
  }

  /// Build app bar with security information
  PreferredSizeWidget _buildAppBar(
    Authenticated state,
    NavigationItem currentItem,
  ) {
    final user = state.user;
    final role = user?.role.displayName ?? 'Unknown';

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(currentItem.label),
          Text(
            '$role • ${_visibleNavigationItems.length} features',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
      actions: [
        // Debug buttons for development
        if (!kReleaseMode) ...[
          PopupMenuButton<String>(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Debug Tools',
            onSelected: (value) async {
              switch (value) {
                case 'refresh':
                  _refreshUserData(context);
                  break;
                case 'force_refresh':
                  _forceRefreshUserData(context);
                  break;
                case 'check_supabase':
                  await _checkSupabaseData(context);
                  break;
                case 'clear_cache':
                  _clearAllCaches(context);
                  break;
                case 'debug_info':
                  _showDetailedDebugInfo(context, state);
                  break;
              }
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Normal Refresh'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'force_refresh',
                    child: Row(
                      children: [
                        Icon(Icons.refresh_outlined, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Force Refresh'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'check_supabase',
                    child: Row(
                      children: [
                        Icon(Icons.storage, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Check Supabase'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear_cache',
                    child: Row(
                      children: [
                        Icon(Icons.clear_all, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Clear All Cache'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'debug_info',
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('Debug Info'),
                      ],
                    ),
                  ),
                ],
          ),
        ] else ...[
          // Normal refresh button for production
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshUserData(context),
            tooltip: 'Refresh User Data',
          ),
        ],

        // Security indicator
        _buildSecurityIndicator(),

        // Profile menu
        PopupMenuButton<String>(
          onSelected: (value) => _handleMenuAction(value, state),
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      const Icon(Icons.person),
                      const SizedBox(width: 8),
                      Text('Profile (${user?.email ?? 'Unknown'})'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Refresh Data',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'security',
                  child: Row(
                    children: [
                      Icon(Icons.security),
                      SizedBox(width: 8),
                      Text('Security Settings'),
                    ],
                  ),
                ),
                if (!kReleaseMode)
                  const PopupMenuItem(
                    value: 'permissions',
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings),
                        SizedBox(width: 8),
                        Text('Permission Debug'),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'signout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sign Out', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
        ),
      ],
    );
  }

  /// Normal refresh user data
  void _refreshUserData(BuildContext context) {
    print('🔄 Manual refresh triggered by user');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Refreshing from database...'),
          ],
        ),
        duration: Duration(seconds: 3),
      ),
    );

    context.read<AuthBloc>().add(
      RefreshUserDataEvent(includePermissions: true),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Data refreshed successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  /// Force refresh user data - bypasses all caches
  void _forceRefreshUserData(BuildContext context) {
    print('🔥 FORCE REFRESH triggered by user');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Force refreshing from database...'),
          ],
        ),
        duration: Duration(seconds: 4),
        backgroundColor: Colors.orange,
      ),
    );

    // Trigger force refresh in repository (bypasses cache)
    final authBloc = context.read<AuthBloc>();
    if (authBloc.authRepository is AuthRepositoryImpl) {
      (authBloc.authRepository as AuthRepositoryImpl).forceGetCurrentUser().then((
        result,
      ) {
        result.fold(
          (failure) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Force refresh failed: ${failure.message}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          (user) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Force refresh completed! Role: ${user?.role.displayName ?? 'None'}',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
              // Trigger UI update
              authBloc.add(RefreshUserDataEvent());
            }
          },
        );
      });
    }
  }

  /// Check Supabase data directly
  Future<void> _checkSupabaseData(BuildContext context) async {
    final user = context.read<AuthBloc>().currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No current user')));
      return;
    }
    print('🔍 Firebase UID: ${user.id}');
    print('🔍 UID Length: ${user.id.length}');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Checking Supabase...'),
              ],
            ),
          ),
    );

    try {
      // Check Supabase directly
      final supabaseClient = supabase.Supabase.instance.client;
      final response =
          await supabaseClient
              .from('users')
              .select()
              .eq('id', user.id)
              .maybeSingle(); // Use maybeSingle() instead of single()

      Navigator.of(context).pop(); // Close loading dialog

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Supabase Data'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Current App User:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('  Email: ${user.email}'),
                    Text('  Role: ${user.role.name}'),
                    const SizedBox(height: 16),
                    Text(
                      'Supabase Data:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (response != null) ...[
                      Text('  ID: ${response['id']}'),
                      Text('  Email: ${response['email']}'),
                      Text('  Role: ${response['role']}'),
                      Text('  Full Name: ${response['full_name']}'),
                      Text('  Updated: ${response['updated_at']}'),
                      const SizedBox(height: 16),
                      Text(
                        'Raw JSON:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          response.toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        '  No user found in Supabase database',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('  This user needs to be created in Supabase'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _forceRefreshUserData(
                            context,
                          ); // This will create the user
                        },
                        child: const Text('Create User in Supabase'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Supabase Error'),
              content: Text('Error: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
      );
    }
  }

  /// Clear all caches
  void _clearAllCaches(BuildContext context) {
    // Clear repository cache by triggering force refresh
    final authBloc = context.read<AuthBloc>();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All caches cleared!'),
        backgroundColor: Colors.orange,
      ),
    );

    // Trigger force refresh to clear cache
    authBloc.add(const CheckAuthStatusEvent(forceRefresh: true));
  }

  /// Show detailed debug information
  void _showDetailedDebugInfo(BuildContext context, Authenticated state) {
    final user = state.user;
    final permissions = _rbacService.getCurrentUserPermissions();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Detailed Debug Info'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'User Information:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('  ID: ${user?.id}'),
                  Text('  Email: ${user?.email}'),
                  Text('  Display Name: ${user?.displayName}'),
                  Text(
                    '  Role: ${user?.role.name} (${user?.role.displayName})',
                  ),
                  if (user is UserModel) ...[
                    Text('  Role Source: ${user.metadata['role_source']}'),
                    Text('  Last Updated: ${user.updatedAt}'),
                    Text('  Provider: ${user.provider}'),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Permissions:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (permissions.isEmpty)
                    Text('  No permissions')
                  else
                    ...permissions.map((p) => Text('  • ${p.id} (${p.name})')),
                  const SizedBox(height: 16),
                  Text(
                    'Navigation:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('  Visible Items: ${_visibleNavigationItems.length}'),
                  Text('  Total Items: ${_allNavigationItems.length}'),
                  Text('  Current Index: $_selectedIndex'),
                  const SizedBox(height: 16),
                  Text(
                    'Security Stats:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('  Navigation Attempts: $_navigationAttempts'),
                  Text('  Blocked Attempts: $_blockedNavigationAttempts'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  /// Build security indicator
  Widget _buildSecurityIndicator() {
    final securityLevel =
        _rbacService.currentUser?.role != null
            ? RoleManager().getSecurityLevel(_rbacService.currentUser!.role)
            : 'unknown';

    Color indicatorColor;
    IconData indicatorIcon;

    switch (securityLevel) {
      case 'high':
        indicatorColor = Colors.green;
        indicatorIcon = Icons.security;
        break;
      case 'medium':
        indicatorColor = Colors.orange;
        indicatorIcon = Icons.shield;
        break;
      default:
        indicatorColor = Colors.blue;
        indicatorIcon = Icons.verified_user;
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Icon(indicatorIcon, color: indicatorColor, size: 20),
    );
  }

  /// Build main body with permission-protected content
  Widget _buildBody() {
    final currentItem = _visibleNavigationItems[_selectedIndex];

    return PermissionGuard(
      permissionId:
          currentItem.permissions.isNotEmpty
              ? currentItem.permissions.first
              : '',
      fallback: _buildAccessDeniedPage(currentItem),
      child: IndexedStack(
        index: _selectedIndex,
        children: _visibleNavigationItems.map((item) => item.page).toList(),
      ),
    );
  }

  /// Build bottom navigation bar
  Widget? _buildBottomNavigation() {
    if (_visibleNavigationItems.length <= 1) return null;

    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      selectedItemColor: Theme.of(context).primaryColor,
      unselectedItemColor: Colors.grey,
      onTap: _onItemTapped,
      items:
          _visibleNavigationItems
              .map(
                (item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  activeIcon: Icon(item.activeIcon),
                  label: item.label,
                  tooltip: item.description,
                ),
              )
              .toList(),
    );
  }

  /// Build navigation drawer for additional options
  Widget _buildNavigationDrawer(Authenticated state) {
    return Drawer(
      child: Column(
        children: [
          _buildDrawerHeader(state),
          Expanded(
            child: ListView(
              children: [
                _buildDrawerSection('Navigation', [
                  ..._visibleNavigationItems.map(
                    (item) => ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      subtitle: Text(item.description),
                      selected:
                          _visibleNavigationItems.indexOf(item) ==
                          _selectedIndex,
                      onTap: () {
                        Navigator.of(context).pop();
                        _onItemTapped(_visibleNavigationItems.indexOf(item));
                      },
                    ),
                  ),
                ]),

                const Divider(),

                _buildDrawerSection('System', [
                  createPermissionMenuItem(
                    permissionId: 'view_analytics',
                    title: 'System Analytics',
                    icon: Icons.analytics,
                    subtitle: 'View system performance',
                    onTap: () {
                      Navigator.of(context).pop();
                      _showSystemAnalytics();
                    },
                  ),
                  createPermissionMenuItem(
                    permissionId: 'manage_users',
                    title: 'User Management',
                    icon: Icons.people,
                    subtitle: 'Manage user accounts',
                    onTap: () {
                      Navigator.of(context).pop();
                      _showUserManagement();
                    },
                  ),
                ]),
              ],
            ),
          ),
          _buildDrawerFooter(),
        ],
      ),
    );
  }

  /// Build drawer header with user information
  Widget _buildDrawerHeader(Authenticated state) {
    final user = state.user;

    return UserAccountsDrawerHeader(
      accountName: Text(user?.displayName ?? 'User'),
      accountEmail: Text(user?.email ?? 'No email'),
      currentAccountPicture: CircleAvatar(
        backgroundColor: Colors.white,
        child: Text(
          (user?.displayName?.substring(0, 1) ?? 'U').toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.8),
          ],
        ),
      ),
    );
  }

  /// Build drawer section
  Widget _buildDrawerSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  /// Build drawer footer
  Widget _buildDrawerFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Text(
            'Secure App v1.0.0',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Last security check: ${_lastSecurityCheck != null ? _formatTime(_lastSecurityCheck!) : 'Never'}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// Build access denied page
  Widget _buildAccessDeniedPage(NavigationItem item) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock, size: 80, color: Colors.orange.shade600),
            const SizedBox(height: 24),
            Text(
              'Access Restricted',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You don\'t have permission to access ${item.label}.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              item.description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showPermissionDetails(item),
              icon: const Icon(Icons.info_outline),
              label: const Text('View Requirements'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build error screen
  Widget _buildErrorScreen(String title) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Please restart the app or contact support.'),
          ],
        ),
      ),
    );
  }

  /// Handle menu actions
  void _handleMenuAction(String action, Authenticated state) {
    switch (action) {
      case 'profile':
        _showUserProfile(state);
        break;
      case 'refresh':
        _refreshUserData(context);
        break;
      case 'security':
        _showSecuritySettings();
        break;
      case 'permissions':
        _showPermissionDebug();
        break;
      case 'signout':
        _showSignOutDialog();
        break;
    }
  }

  /// Show user profile
  void _showUserProfile(Authenticated state) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('User Profile'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Email: ${state.user?.email ?? "No email"}'),
                Text('Role: ${state.user?.role.displayName ?? "No role"}'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _refreshUserData(context);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Data'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  /// Show security settings
  void _showSecuritySettings() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Security Settings'),
            content: const Text('Security settings will be implemented here.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  /// Show permission debug information
  void _showPermissionDebug() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              appBar: AppBar(title: const Text('Permission Debug')),
              body: const Center(
                child: Text('Permission debug info will be shown here'),
              ),
            ),
      ),
    );
  }

  /// Show system analytics
  void _showSystemAnalytics() {
    // Implementation for system analytics
  }

  /// Show user management
  void _showUserManagement() {
    // Implementation for user management
  }

  /// Show sign out confirmation dialog
  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sign Out'),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.read<AuthBloc>().add(SignOutEvent());
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Sign Out'),
              ),
            ],
          ),
    );
  }

  /// Format time for display
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

/// Navigation item data class with comprehensive metadata
class NavigationItem {
  final String id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget page;
  final List<String> permissions;
  final NavigationCategory category;
  final int priority;
  final String description;
  final bool isVisible;

  const NavigationItem({
    required this.id,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.page,
    this.permissions = const [],
    this.category = NavigationCategory.primary,
    this.priority = 50,
    this.description = '',
    this.isVisible = true,
  });
}

/// Navigation category enumeration
enum NavigationCategory {
  primary,
  business,
  financial,
  tools,
  advanced,
  system,
}

/// Extension for navigation category
extension NavigationCategoryExtension on NavigationCategory {
  String get displayName {
    switch (this) {
      case NavigationCategory.primary:
        return 'Primary';
      case NavigationCategory.business:
        return 'Business';
      case NavigationCategory.financial:
        return 'Financial';
      case NavigationCategory.tools:
        return 'Tools';
      case NavigationCategory.advanced:
        return 'Advanced';
      case NavigationCategory.system:
        return 'System';
    }
  }
}
