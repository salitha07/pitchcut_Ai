import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../data/auth_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthRepository _authRepository = AuthRepository();

  bool _isLoggingOut = false;

  User? get _user => _authRepository.currentUser;

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
          'Are you sure you want to logout from your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout != true || !mounted) return;

    setState(() => _isLoggingOut = true);

    try {
      await _authRepository.logout();

      if (!mounted) return;
      context.go('/login');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Logout failed. Please try again.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFFB69CFF), size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    final displayName = user?.displayName?.trim();
    final name = displayName == null || displayName.isEmpty
        ? 'User'
        : displayName;

    final email = user?.email ?? 'No email available';

    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A2C),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF38BDF8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          email,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF087F5B)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 15,
                                color: Color(0xFF4ADE80),
                              ),
                              SizedBox(width: 7),
                              Text(
                                'Active Account',
                                style: TextStyle(
                                  color: Color(0xFF4ADE80),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Account information
                  _sectionTitle('Account Information'),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A2C),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      children: [
                        _infoTile(
                          icon: Icons.person_outline_rounded,
                          title: 'Full Name',
                          value: name,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _infoTile(
                          icon: Icons.email_outlined,
                          title: 'Email Address',
                          value: email,
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _infoTile(
                          icon: Icons.security_rounded,
                          title: 'Authentication',
                          value: 'Firebase Email & Password',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // App information
                  _sectionTitle('Application'),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A2C),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.movie_creation_outlined,
                            color: Color(0xFFB69CFF),
                          ),
                          title: const Text('PitchCut AI'),
                          subtitle: const Text('AI Video Editing Application'),
                          trailing: const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF4ADE80),
                            size: 20,
                          ),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        const ListTile(
                          leading: Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFF38BDF8),
                          ),
                          title: Text('Application Version'),
                          subtitle: Text('Version 1.0.0'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Settings
                  _sectionTitle('Settings'),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A2C),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.settings_outlined,
                        color: Color(0xFFB69CFF),
                      ),
                      title: const Text('Settings'),
                      subtitle: const Text('Appearance and app preferences'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/settings'),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Logout
                  _sectionTitle('Account Actions'),

                  OutlinedButton.icon(
                    onPressed: _isLoggingOut ? null : _logout,
                    icon: _isLoggingOut
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: Text(_isLoggingOut ? 'Logging out...' : 'Logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B6B),
                      side: const BorderSide(color: Color(0x66FF6B6B)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  const Center(
                    child: Text(
                      'Made with care • PitchCut AI',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
