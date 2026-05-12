import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/accessibility_helper.dart';

class _RoleOption {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _RoleOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final AccessibilityHelper _accessibilityHelper = AccessibilityHelper();
  final _phoneController = TextEditingController();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _idFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  String _selectedRole = 'victim';
  bool _isOtpSent = false;
  bool _isLoading = false;
  bool _isCreateMode = false;
  String? _authErrorMessage;

  static const _roles = <_RoleOption>[
    _RoleOption(
      value: 'victim',
      label: 'Victim / Affected Person',
      icon: Icons.person_outline,
      color: Color(0xFFE53935),
    ),
    _RoleOption(
      value: 'volunteer',
      label: 'Volunteer',
      icon: Icons.groups_outlined,
      color: Color(0xFFFB8C00),
    ),
    _RoleOption(
      value: 'responder',
      label: 'Emergency Responder',
      icon: Icons.health_and_safety_outlined,
      color: Color(0xFF1E88E5),
    ),
    _RoleOption(
      value: 'coordinator',
      label: 'Coordinator (admin)',
      icon: Icons.admin_panel_settings_outlined,
      color: Color(0xFF00BFA5),
    ),
  ];

  @override
  void initState() {
    super.initState();
    for (final focusNode in [
      _phoneFocusNode,
      _idFocusNode,
      _passwordFocusNode,
      _confirmPasswordFocusNode,
    ]) {
      focusNode.addListener(() {
        if (!focusNode.hasFocus && mounted) {
          _formKey.currentState?.validate();
        }
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _phoneFocusNode.dispose();
    _idFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  void _openAccessibility() {
    final next = !_accessibilityHelper.enabled;
    _accessibilityHelper.setEnabled(next);
    if (mounted) {
      setState(() {});
    }
  }

  String _buildTempPhone() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'tmp$ts';
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      prefixIcon: Icon(icon),
    );
  }

  Widget _buildModeToggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const activeColor = Color(0xFF1E6FEF);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOption(_RoleOption role) {
    final selected = _selectedRole == role.value;
    final borderColor = selected ? role.color : Colors.grey[200]!;

    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: role.color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(role.icon, color: role.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                role.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? role.color : Colors.black87,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: role.color,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRoles = _isCreateMode
        ? _roles
            .where((role) =>
                role.value == 'volunteer' || role.value == 'responder')
            .toList()
        : _roles;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                child: Form(
                  key: _formKey,
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFCE8E6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.shield_outlined,
                              color: Color(0xFFE53935),
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'ReddiHelp',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE53935),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Jamaica Emergency Management',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          transitionBuilder: (child, animation) =>
                              SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.15),
                              end: Offset.zero,
                            ).animate(animation),
                            child: FadeTransition(
                                opacity: animation, child: child),
                          ),
                          child: _authErrorMessage == null
                              ? const SizedBox.shrink()
                              : Container(
                                  key: const ValueKey('auth-banner'),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border:
                                        Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Invalid credentials. Please try again.',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => setState(() {
                                          _authErrorMessage = null;
                                        }),
                                        icon: const Icon(Icons.close,
                                            color: Colors.red),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        if (!_isOtpSent)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F3F7),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                _buildModeToggleButton(
                                  label: 'Sign In',
                                  selected: !_isCreateMode,
                                  onTap: () => setState(() {
                                    _isCreateMode = false;
                                  }),
                                ),
                                _buildModeToggleButton(
                                  label: 'Create Account',
                                  selected: _isCreateMode,
                                  onTap: () => setState(() {
                                    _isCreateMode = true;
                                    if (_selectedRole != 'volunteer' &&
                                        _selectedRole != 'responder') {
                                      _selectedRole = 'volunteer';
                                    }
                                  }),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        if (!_isOtpSent) ...[
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'I am a...',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...visibleRoles.map(_buildRoleOption),
                          const SizedBox(height: 4),
                          if (_isCreateMode) ...[
                            TextFormField(
                              focusNode: _idFocusNode,
                              controller: _idController,
                              onChanged: (_) =>
                                  setState(() => _authErrorMessage = null),
                              decoration: _fieldDecoration(
                                label: 'Username *',
                                icon: Icons.person_outline,
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'This field is required'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              focusNode: _passwordFocusNode,
                              controller: _passwordController,
                              onChanged: (_) =>
                                  setState(() => _authErrorMessage = null),
                              decoration: _fieldDecoration(
                                label: 'Password *',
                                icon: Icons.lock_outline,
                              ),
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'This field is required';
                                }
                                if (value.trim().length < 8) {
                                  return 'Password must be at least 8 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              focusNode: _confirmPasswordFocusNode,
                              controller: _confirmPasswordController,
                              onChanged: (_) =>
                                  setState(() => _authErrorMessage = null),
                              decoration: _fieldDecoration(
                                label: 'Confirm Password *',
                                icon: Icons.lock_outline,
                              ),
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'This field is required';
                                }
                                if (value.trim() !=
                                    _passwordController.text.trim()) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ] else ...[
                            if (_selectedRole == 'victim')
                              TextFormField(
                                focusNode: _phoneFocusNode,
                                controller: _phoneController,
                                onChanged: (_) =>
                                    setState(() => _authErrorMessage = null),
                                decoration: _fieldDecoration(
                                  label: 'Phone Number',
                                  hint: '+1876...',
                                  icon: Icons.phone_outlined,
                                ),
                                keyboardType: TextInputType.phone,
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                        ? 'This field is required'
                                        : null,
                              )
                            else ...[
                              TextFormField(
                                focusNode: _idFocusNode,
                                controller: _idController,
                                onChanged: (_) =>
                                    setState(() => _authErrorMessage = null),
                                decoration: _fieldDecoration(
                                  label: 'Username',
                                  icon: Icons.person_outline,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'This field is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                focusNode: _passwordFocusNode,
                                controller: _passwordController,
                                onChanged: (_) =>
                                    setState(() => _authErrorMessage = null),
                                decoration: _fieldDecoration(
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                ),
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'This field is required';
                                  }
                                  if (value.trim().length < 8) {
                                    return 'Password must be at least 8 characters';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _authenticate,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE53935),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      _isCreateMode
                                          ? 'Create Account'
                                          : 'Continue',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                            ),
                          ),
                        ] else ...[
                          Text(
                            'Enter the 6-digit code sent to\n${_phoneController.text}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _otpController,
                            decoration: _fieldDecoration(
                              label: '6-digit OTP',
                              icon: Icons.lock_outline,
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : () => _verifyOtp(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE53935),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Text('Verify & Sign In',
                                      style: TextStyle(fontSize: 16)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isOtpSent = false;
                                _otpController.clear();
                              });
                            },
                            child: const Text('← Change number / role'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: IconButton(
                    icon: Icon(
                      Icons.wheelchair_pickup,
                      color: _accessibilityHelper.enabled
                          ? Colors.teal
                          : Colors.black87,
                    ),
                    onPressed: _openAccessibility,
                    tooltip: 'Accessibility',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _authenticate() async {
    setState(() => _authErrorMessage = null);
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (_isCreateMode) {
      await _createAccount();
    } else {
      if (_selectedRole == 'victim') {
        final phone = _phoneController.text.trim();
        setState(() => _isLoading = true);
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final ok = await auth.requestOtp(phone);
        setState(() => _isLoading = false);
        if (ok) {
          setState(() => _isOtpSent = true);
          _snack('OTP sent! Check your phone for the code');
        } else {
          _snack('Failed to send OTP', isError: true);
        }
      } else {
        final username = _idController.text.trim();
        final password = _passwordController.text.trim();
        setState(() => _isLoading = true);
        final auth = Provider.of<AuthProvider>(context, listen: false);
        // Previously used mockLogin which bypassed credential validation.
        final success =
            await auth.login(username, password, selectedRole: _selectedRole);
        setState(() => _isLoading = false);
        if (!success) {
          setState(() =>
              _authErrorMessage = 'Invalid credentials. Please try again.');
        }
      }
    }
  }

  Future<void> _createAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final username = _idController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final phone = _buildTempPhone();

    if (password != confirmPassword) {
      _snack('Passwords do not match', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    const selectedSkills = <String>[];

    final success = await auth.register(
      username,
      password,
      phone,
      _selectedRole,
      selectedSkills,
    );
    setState(() => _isLoading = false);

    if (!success) {
      _snack('Account creation failed', isError: true);
    }
  }

  Future<void> _verifyOtp(BuildContext context) async {
    final phone = _phoneController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _snack('Please enter a valid 6-digit OTP', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ok = await auth.verifyOtp(phone, otp, _selectedRole);
    setState(() => _isLoading = false);
    if (!ok) _snack('Invalid OTP', isError: true);
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }
}
