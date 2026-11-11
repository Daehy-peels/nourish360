import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nourish360/features/profile/presentation/profile_setup_screen.dart';

import 'water_tracker_widget.dart';
import 'weekly_chart_widget.dart';
import 'calorie_tracker_widget.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'User';
    final displayName = email.split('@').first;

    final formattedName = displayName.isNotEmpty
        ? displayName[0].toUpperCase() + displayName.substring(1)
        : 'User';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF023E8A), Color(0xFF0077B6), Color(0xFF00B4D8)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, screenConstraints) {
              final isSmallScreen = screenConstraints.maxWidth < 360;

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isSmallScreen ? 12 : 20,
                  isSmallScreen ? 16 : 28,
                  isSmallScreen ? 12 : 20,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ==========================================
                        // RESPONSIVE FLOATING HEADER
                        // ==========================================
                        _buildHeader(context, formattedName, isSmallScreen),

                        const SizedBox(height: 20),

                        // ==========================================
                        // WATER TRACKER & HISTORY
                        // ==========================================
                        const WaterTrackerWidget(),

                        const SizedBox(height: 20),

                        // ==========================================
                        // WEEKLY ANALYTICS
                        // ==========================================
                        const WeeklyChartWidget(),

                        const SizedBox(height: 24),

                        // ==========================================
                        // CALORIE TRACKER
                        // ==========================================
                        const CalorieTrackerWidget(),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ==========================================
  // RESPONSIVE HEADER
  // ==========================================
  Widget _buildHeader(
    BuildContext context,
    String formattedName,
    bool isSmallScreen,
  ) {
    final avatarSize = isSmallScreen ? 40.0 : 44.0;
    final horizontalPadding = isSmallScreen ? 12.0 : 18.0;
    final buttonPadding = isSmallScreen ? 8.0 : 10.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: isSmallScreen ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                height: avatarSize,
                width: avatarSize,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF90E0EF), Color(0xFF00B4D8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF90E0EF).withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    formattedName.isNotEmpty
                        ? formattedName[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF03045E),
                    ),
                  ),
                ),
              ),

              SizedBox(width: isSmallScreen ? 8 : 12),

              // Greeting and username
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nourish360 Hub',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 12,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      formattedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 15 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(width: isSmallScreen ? 6 : 10),

              // Header action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeaderIconButton(
                    icon: Icons.settings_rounded,
                    tooltip: 'Health Setup',
                    padding: buttonPadding,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileSetupScreen(),
                        ),
                      );
                    },
                  ),

                  SizedBox(width: isSmallScreen ? 4 : 8),

                  _buildHeaderIconButton(
                    icon: Icons.logout_rounded,
                    tooltip: 'Sign Out',
                    padding: buttonPadding,
                    onTap: () async {
                      try {
                        await Supabase.instance.client.auth.signOut();
                      } catch (error) {
                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Sign out failed: $error'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // HEADER ICON BUTTON
  // ==========================================
  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required double padding,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
