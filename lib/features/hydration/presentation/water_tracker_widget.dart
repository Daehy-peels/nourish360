import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ==========================================
// 1. WATER LOG MODEL & STATE (Riverpod)
// ==========================================

class WaterLogItem {
  final String id;
  final int amountMl;
  final DateTime createdAt;

  WaterLogItem({
    required this.id,
    required this.amountMl,
    required this.createdAt,
  });
}

class WaterState {
  final int currentAmountMl;
  final int dailyGoalMl;
  final List<WaterLogItem> todayLogs;
  final bool isLoading;

  WaterState({
    this.currentAmountMl = 0,
    this.dailyGoalMl = 2000,
    this.todayLogs = const [],
    this.isLoading = false,
  });

  WaterState copyWith({
    int? currentAmountMl,
    int? dailyGoalMl,
    List<WaterLogItem>? todayLogs,
    bool? isLoading,
  }) {
    return WaterState(
      currentAmountMl: currentAmountMl ?? this.currentAmountMl,
      dailyGoalMl: dailyGoalMl ?? this.dailyGoalMl,
      todayLogs: todayLogs ?? this.todayLogs,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  double get progress => (currentAmountMl / dailyGoalMl).clamp(0.0, 1.0);
}

class WaterNotifier extends StateNotifier<WaterState> {
  WaterNotifier() : super(WaterState()) {
    loadTodayHydration();
  }

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> loadTodayHydration() async {
    state = state.copyWith(isLoading: true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      // 1. Fetch user's personalized daily water goal
      final profileRes = await _supabase
          .from('users_profile')
          .select('daily_water_goal_ml')
          .eq('id', userId)
          .maybeSingle();

      int goal = 2000;
      if (profileRes != null && profileRes['daily_water_goal_ml'] != null) {
        goal = (profileRes['daily_water_goal_ml'] as num).toInt();
      }

      // 2. Fetch today's detailed water logs sorted newest first
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final logsRes = await _supabase
          .from('water_logs')
          .select('id, amount_ml, created_at')
          .eq('user_id', userId)
          .gte('created_at', '${todayStr}T00:00:00')
          .order('created_at', ascending: false);

      int totalConsumed = 0;
      final List<WaterLogItem> fetchedLogs = [];

      for (var log in (logsRes as List)) {
        final amount = (log['amount_ml'] as num).toInt();
        totalConsumed += amount;
        fetchedLogs.add(
          WaterLogItem(
            id: log['id'].toString(),
            amountMl: amount,
            createdAt: DateTime.parse(log['created_at'].toString()),
          ),
        );
      }

      state = state.copyWith(
        dailyGoalMl: goal,
        currentAmountMl: totalConsumed,
        todayLogs: fetchedLogs,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error loading water data: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> addWater(int amountMl) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('water_logs').insert({
        'user_id': userId,
        'amount_ml': amountMl,
        'created_at': DateTime.now().toIso8601String(),
      });
      // Re-fetch to get complete database timestamp & generated ID
      await loadTodayHydration();
    } catch (e) {
      debugPrint('Error saving water log: $e');
    }
  }

  Future<void> deleteWaterLog(String logId) async {
    try {
      await _supabase.from('water_logs').delete().eq('id', logId);
      await loadTodayHydration();
    } catch (e) {
      debugPrint('Error deleting water log: $e');
    }
  }

  Future<void> resetTodayWater() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    state = state.copyWith(isLoading: true);
    try {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);

      await _supabase
          .from('water_logs')
          .delete()
          .eq('user_id', userId)
          .gte('created_at', '${todayStr}T00:00:00');

      state = state.copyWith(
        currentAmountMl: 0,
        todayLogs: [],
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error resetting water logs: $e');
      state = state.copyWith(isLoading: false);
    }
  }
}

final waterProvider = StateNotifierProvider<WaterNotifier, WaterState>((ref) {
  return WaterNotifier();
});

// ==========================================
// 2. GLASSMORPHISM WATER TRACKER WIDGET
// ==========================================


class WaterTrackerWidget extends ConsumerWidget {
  const WaterTrackerWidget({super.key});

  static const Color _aqua = Color(0xFF90E0EF);
  static const Color _navy = Color(0xFF023E8A);

  BoxDecoration _glassDecoration({
    double opacity = 0.12,
    double radius = 26,
  }) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.20),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Future<void> _showCustomAddSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();

    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final formKey = GlobalKey<FormState>();

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            decoration: const BoxDecoration(
              color: Color(0xFF064477),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(30),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Icon(
                          Icons.water_drop_rounded,
                          color: _aqua,
                          size: 26,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Add water intake',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the amount of water you just drank.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. 330',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        suffixText: 'ml',
                        suffixStyle: const TextStyle(
                          color: _aqua,
                          fontWeight: FontWeight.bold,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.09),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: _aqua,
                            width: 1.5,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final parsed = int.tryParse(value?.trim() ?? '');

                        if (parsed == null || parsed <= 0) {
                          return 'Please enter a valid amount greater than 0.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(
                              sheetContext,
                              int.parse(controller.text.trim()),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _aqua,
                          foregroundColor: _navy,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Add water',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    controller.dispose();

    if (amount != null) {
      ref.read(waterProvider.notifier).addWater(amount);
    }
  }

  Future<void> _showResetConfirmation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF064477),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            "Reset today's intake?",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'This will permanently remove all water logs recorded today.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B6B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      ref.read(waterProvider.notifier).resetTodayWater();
    }
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    WaterLogItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF064477),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Delete water log?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            "Remove the ${item.amountMl} ml entry from today's history?",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: _aqua),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF8585)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      ref.read(waterProvider.notifier).deleteWaterLog(item.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waterState = ref.watch(waterProvider);

    final progress = waterState.dailyGoalMl > 0
        ? (waterState.currentAmountMl / waterState.dailyGoalMl)
            .clamp(0.0, 1.0)
        : 0.0;

    final remaining = (waterState.dailyGoalMl -
            waterState.currentAmountMl)
        .clamp(0, waterState.dailyGoalMl);

    final percentage = waterState.dailyGoalMl > 0
        ? (waterState.currentAmountMl /
                waterState.dailyGoalMl *
                100)
            .round()
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ==========================================
        // MAIN HYDRATION CARD
        // ==========================================
        Container(
          padding: const EdgeInsets.all(22),
          decoration: _glassDecoration(
            opacity: 0.14,
            radius: 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _aqua.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.water_drop_rounded,
                      color: _aqua,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hydration',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Stay refreshed throughout the day',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: waterState.isLoading
                        ? null
                        : () => _showResetConfirmation(context, ref),
                    tooltip: "Reset today's intake",
                    icon: Icon(
                      Icons.restart_alt_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                      size: 22,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Progress indicator
              Center(
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 184,
                        height: 184,
                        child: CircularProgressIndicator(
                          value: 1,
                          strokeWidth: 13,
                          strokeCap: StrokeCap.round,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.13),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 184,
                        height: 184,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: progress,
                          ),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return CircularProgressIndicator(
                              value: value,
                              strokeWidth: 13,
                              strokeCap: StrokeCap.round,
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(
                                _aqua,
                              ),
                            );
                          },
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.water_drop_rounded,
                            color: _aqua,
                            size: 25,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            NumberFormat('#,###').format(
                              waterState.currentAmountMl,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'of ${NumberFormat('#,###').format(waterState.dailyGoalMl)} ml',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Progress summary
              Row(
                children: [
                  Expanded(
                    child: _buildStat(
                      label: 'COMPLETED',
                      value: '$percentage%',
                      icon: Icons.check_circle_outline_rounded,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 42,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  Expanded(
                    child: _buildStat(
                      label: 'REMAINING',
                      value: '${NumberFormat('#,###').format(remaining)} ml',
                      icon: Icons.flag_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // Quick add heading
              Row(
                children: [
                  const Text(
                    'Quick add',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Log your water intake',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Quick add buttons
              Row(
                children: [
                  Expanded(
                    child: _buildQuickAddButton(
                      label: '250 ml',
                      icon: Icons.local_drink_rounded,
                      onTap: () => ref
                          .read(waterProvider.notifier)
                          .addWater(250),
                      enabled: !waterState.isLoading,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _buildQuickAddButton(
                      label: '500 ml',
                      icon: Icons.water_drop_rounded,
                      onTap: () => ref
                          .read(waterProvider.notifier)
                          .addWater(500),
                      enabled: !waterState.isLoading,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _buildQuickAddButton(
                      label: 'Custom',
                      icon: Icons.add_rounded,
                      onTap: () => _showCustomAddSheet(context, ref),
                      enabled: !waterState.isLoading,
                    ),
                  ),
                ],
              ),

              if (waterState.isLoading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  backgroundColor: Colors.white12,
                  color: _aqua,
                  minHeight: 3,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ==========================================
        // TODAY'S WATER HISTORY
        // ==========================================
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _glassDecoration(
            opacity: 0.10,
            radius: 26,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: _aqua,
                    size: 21,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      "Today's activity",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${waterState.todayLogs.length} entries',
                      style: const TextStyle(
                        color: _aqua,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (waterState.isLoading &&
                  waterState.todayLogs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _aqua,
                      strokeWidth: 2,
                    ),
                  ),
                )
              else if (waterState.todayLogs.isEmpty)
                _buildEmptyHistory()
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: waterState.todayLogs.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 18,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  itemBuilder: (context, index) {
                    final item = waterState.todayLogs[index];

                    final formattedTime = DateFormat('h:mm a')
                        .format(item.createdAt);

                    return Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _aqua.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.water_drop_rounded,
                            color: _aqua,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '+${NumberFormat('#,###').format(item.amountMl)} ml',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formattedTime,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete entry',
                          onPressed: waterState.isLoading
                              ? null
                              : () => _showDeleteConfirmation(
                                    context,
                                    ref,
                                    item,
                                  ),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.55),
                            size: 20,
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStat({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Icon(
            icon,
            color: _aqua,
            size: 18,
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAddButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 13,
            horizontal: 4,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: const Color(0xFF0077B6),
                size: 19,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0077B6),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHistory() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.water_drop_outlined,
                color: Colors.white.withValues(alpha: 0.55),
                size: 27,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No water logged yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Your water entries will appear here.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
