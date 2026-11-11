import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// 1. MEAL MODEL
// ============================================================

class MealItem {
  final String id;
  final String mealType;
  final String foodName;
  final int calories;
  final DateTime createdAt;

  const MealItem({
    required this.id,
    required this.mealType,
    required this.foodName,
    required this.calories,
    required this.createdAt,
  });
}

// ============================================================
// 2. CALORIE STATE
// ============================================================

class CalorieState {
  final int currentCalories;
  final int dailyGoalCalories;
  final List<MealItem> todayMeals;
  final bool isLoading;

  const CalorieState({
    this.currentCalories = 0,
    this.dailyGoalCalories = 2000,
    this.todayMeals = const [],
    this.isLoading = false,
  });

  CalorieState copyWith({
    int? currentCalories,
    int? dailyGoalCalories,
    List<MealItem>? todayMeals,
    bool? isLoading,
  }) {
    return CalorieState(
      currentCalories: currentCalories ?? this.currentCalories,
      dailyGoalCalories: dailyGoalCalories ?? this.dailyGoalCalories,
      todayMeals: todayMeals ?? this.todayMeals,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  double get progress {
    if (dailyGoalCalories <= 0) return 0;
    return (currentCalories / dailyGoalCalories).clamp(0.0, 1.0);
  }

  int get remainingCalories =>
      (dailyGoalCalories - currentCalories).clamp(0, dailyGoalCalories);

  int get percentage {
    if (dailyGoalCalories <= 0) return 0;
    return ((currentCalories / dailyGoalCalories) * 100).round();
  }
}

// ============================================================
// 3. CALORIE NOTIFIER - SUPABASE
// ============================================================

class CalorieNotifier extends StateNotifier<CalorieState> {
  CalorieNotifier() : super(const CalorieState()) {
    loadTodayCalories();
  }

  final SupabaseClient _supabase = Supabase.instance.client;

  // Local midnight is converted to UTC before querying timestamptz.
  DateTime get _startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _startOfTomorrow =>
      DateTime(_startOfToday.year, _startOfToday.month, _startOfToday.day + 1);

  Future<void> loadTodayCalories() async {
    state = state.copyWith(isLoading: true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        state = state.copyWith(
          currentCalories: 0,
          todayMeals: [],
          isLoading: false,
        );
        return;
      }

      final profileRes = await _supabase
          .from('users_profile')
          .select('daily_calorie_goal')
          .eq('id', userId)
          .maybeSingle();

      var goal = 2000;
      final storedGoal = profileRes?['daily_calorie_goal'];
      if (storedGoal is num && storedGoal > 0) {
        goal = storedGoal.toInt();
      }

      final startUtc = _startOfToday.toUtc().toIso8601String();
      final endUtc = _startOfTomorrow.toUtc().toIso8601String();

      // These names match the actual meal_logs table.
      final logsRes = await _supabase
          .from('meal_logs')
          .select('id, meal_type, description, calories, logged_at')
          .eq('user_id', userId)
          .gte('logged_at', startUtc)
          .lt('logged_at', endUtc)
          .order('logged_at', ascending: false);

      var totalCalories = 0;
      final fetchedMeals = <MealItem>[];

      for (final log in logsRes) {
        final calories = (log['calories'] as num?)?.toInt() ?? 0;
        totalCalories += calories;

        final loggedAt = log['logged_at']?.toString();
        fetchedMeals.add(
          MealItem(
            id: log['id'].toString(),
            mealType: log['meal_type']?.toString() ?? 'Other',
            foodName: log['description']?.toString() ?? 'Unnamed meal',
            calories: calories,
            createdAt: loggedAt == null
                ? DateTime.now()
                : DateTime.parse(loggedAt).toLocal(),
          ),
        );
      }

      state = state.copyWith(
        dailyGoalCalories: goal,
        currentCalories: totalCalories,
        todayMeals: fetchedMeals,
        isLoading: false,
      );
    } catch (e, stackTrace) {
      debugPrint('Error loading calorie data: $e');
      debugPrintStack(stackTrace: stackTrace);
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> addMeal(String mealType, String foodName, int calories) async {
    final userId = _supabase.auth.currentUser?.id;
    final trimmedFoodName = foodName.trim();

    if (userId == null || trimmedFoodName.isEmpty || calories <= 0) {
      return false;
    }

    try {
      await _supabase.from('meal_logs').insert({
        'user_id': userId,
        'meal_type': mealType,
        'description': trimmedFoodName,
        'calories': calories,
        'logged_at': DateTime.now().toUtc().toIso8601String(),
      });

      await loadTodayCalories();
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error saving meal log: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> deleteMealLog(String mealId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase
          .from('meal_logs')
          .delete()
          .eq('id', mealId)
          .eq('user_id', userId);

      await loadTodayCalories();
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error deleting meal log: $e');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<bool> resetTodayMeals() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    state = state.copyWith(isLoading: true);

    try {
      final startUtc = _startOfToday.toUtc().toIso8601String();
      final endUtc = _startOfTomorrow.toUtc().toIso8601String();

      await _supabase
          .from('meal_logs')
          .delete()
          .eq('user_id', userId)
          .gte('logged_at', startUtc)
          .lt('logged_at', endUtc);

      state = state.copyWith(
        currentCalories: 0,
        todayMeals: [],
        isLoading: false,
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error resetting meal logs: $e');
      debugPrintStack(stackTrace: stackTrace);
      state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

final calorieProvider = StateNotifierProvider<CalorieNotifier, CalorieState>((
  ref,
) {
  return CalorieNotifier();
});

// ============================================================
// 4. CALORIE TRACKER WIDGET
// ============================================================

class CalorieTrackerWidget extends ConsumerWidget {
  const CalorieTrackerWidget({super.key});

  static const Color _aqua = Color(0xFF90E0EF);
  static const Color _gold = Color(0xFFFFB703);
  static const Color _deepBlue = Color(0xFF03045E);

  Future<void> _showAddMealDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddMealDialog(
        onSave: (mealType, foodName, calories) {
          return ref
              .read(calorieProvider.notifier)
              .addMeal(mealType, foodName, calories);
        },
      ),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meal added successfully!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF007F5F),
        ),
      );
    }
  }

  Future<void> _showResetConfirmation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF023E8A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        title: const Text(
          "Reset today's meals?",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently remove all meals logged today.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (shouldReset != true || !context.mounted) return;

    final success = await ref.read(calorieProvider.notifier).resetTodayMeals();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? "Today's meals have been cleared."
              : 'Could not reset meals. Please try again.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDeleteMeal(
    BuildContext context,
    WidgetRef ref,
    MealItem meal,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF023E8A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        title: const Text(
          'Delete meal?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove "${meal.foodName}" from today\'s meal history?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    final success = await ref
        .read(calorieProvider.notifier)
        .deleteMealLog(meal.id);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Meal deleted.' : 'Could not delete this meal.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _glassPanel({
    required Widget child,
    double radius = 26,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 1.1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'kcal',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _mealTypeIcon(String mealType) {
    final type = mealType.toLowerCase();
    final (icon, color) = switch (type) {
      'breakfast' => (Icons.wb_twilight_rounded, const Color(0xFFFFC857)),
      'lunch' => (Icons.wb_sunny_rounded, const Color(0xFFFFB703)),
      'dinner' => (Icons.nights_stay_rounded, const Color(0xFFB8C0FF)),
      'snack' => (Icons.cookie_rounded, const Color(0xFFFF9F9F)),
      _ => (Icons.restaurant_rounded, _aqua),
    };

    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }

  Widget _emptyMealsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: _aqua.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: _aqua,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No meals logged yet',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start tracking your nutrition by logging your first meal.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _mealHistoryItem(BuildContext context, WidgetRef ref, MealItem meal) {
    final formattedTime = DateFormat('h:mm a').format(meal.createdAt);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _mealTypeIcon(meal.mealType),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meal.foodName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    meal.mealType,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text(
                    '•',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  Text(
                    formattedTime,
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormat('#,###').format(meal.calories),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'kcal',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(width: 3),
        IconButton(
          tooltip: 'Delete meal',
          visualDensity: VisualDensity.compact,
          onPressed: () => _confirmDeleteMeal(context, ref, meal),
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white54,
            size: 19,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calorieState = ref.watch(calorieProvider);
    final numberFormat = NumberFormat('#,###');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // CALORIE OVERVIEW
        _glassPanel(
          radius: 28,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD166), Color(0xFFFF9F1C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      color: Color(0xFF713F12),
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calorie Tracker',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Your daily nutrition overview',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh calorie data',
                    onPressed: calorieState.isLoading
                        ? null
                        : () => ref
                              .read(calorieProvider.notifier)
                              .loadTodayCalories(),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white70,
                    ),
                  ),
                  IconButton(
                    tooltip: "Reset today's meals",
                    onPressed:
                        calorieState.todayMeals.isEmpty ||
                            calorieState.isLoading
                        ? null
                        : () => _showResetConfirmation(context, ref),
                    icon: const Icon(
                      Icons.restart_alt_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Center(
                child: SizedBox(
                  height: 184,
                  width: 184,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 184,
                        width: 184,
                        child: CircularProgressIndicator(
                          value: 1,
                          strokeWidth: 13,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 184,
                        width: 184,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                            begin: 0,
                            end: calorieState.progress,
                          ),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) =>
                              CircularProgressIndicator(
                                value: value,
                                strokeWidth: 13,
                                strokeCap: StrokeCap.round,
                                backgroundColor: Colors.transparent,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  _gold,
                                ),
                              ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: _gold,
                            size: 25,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            numberFormat.format(calorieState.currentCalories),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 29,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'of ${numberFormat.format(calorieState.dailyGoalCalories)} kcal',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            calorieState.currentCalories >=
                                    calorieState.dailyGoalCalories
                                ? 'Daily goal reached!'
                                : '${calorieState.percentage}% completed',
                            style: const TextStyle(
                              color: _aqua,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _summaryTile(
                      icon: Icons.flag_rounded,
                      label: 'DAILY GOAL',
                      value: numberFormat.format(
                        calorieState.dailyGoalCalories,
                      ),
                      color: _aqua,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryTile(
                      icon: Icons.track_changes_rounded,
                      label: 'REMAINING',
                      value: numberFormat.format(
                        calorieState.remainingCalories,
                      ),
                      color: const Color(0xFF9BF6FF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddMealDialog(context, ref),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text(
                    'Log Meal / Food',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _aqua,
                    foregroundColor: _deepBlue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              if (calorieState.isLoading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.white12,
                  color: _aqua,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),

        // TODAY'S MEAL HISTORY
        _glassPanel(
          radius: 26,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's Meals",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Your food diary for today',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _aqua.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _aqua.withValues(alpha: 0.18)),
                    ),
                    child: Text(
                      '${calorieState.todayMeals.length} entries',
                      style: const TextStyle(
                        color: _aqua,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (calorieState.isLoading && calorieState.todayMeals.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _aqua,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else if (calorieState.todayMeals.isEmpty)
                _emptyMealsState()
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: calorieState.todayMeals.length,
                  separatorBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  itemBuilder: (context, index) => _mealHistoryItem(
                    context,
                    ref,
                    calorieState.todayMeals[index],
                  ),
                ),
              if (calorieState.todayMeals.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.summarize_rounded,
                        color: _aqua,
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          'Total consumed today',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      Text(
                        '${numberFormat.format(calorieState.currentCalories)} kcal',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 5. ADD MEAL DIALOG
// The dialog owns its controllers and disposes them only when
// Flutter removes this widget from the widget tree.
// ============================================================

class _AddMealDialog extends StatefulWidget {
  const _AddMealDialog({required this.onSave});

  final Future<bool> Function(String mealType, String foodName, int calories)
  onSave;

  @override
  State<_AddMealDialog> createState() => _AddMealDialogState();
}

class _AddMealDialogState extends State<_AddMealDialog> {
  static const Color _aqua = Color(0xFF90E0EF);
  static const Color _gold = Color(0xFFFFB703);
  static const Color _deepBlue = Color(0xFF03045E);
  static const Color _dialogBlue = Color(0xFF023E8A);

  final _formKey = GlobalKey<FormState>();
  final _foodController = TextEditingController();
  final _calorieController = TextEditingController();

  String _selectedMealType = 'Breakfast';
  bool _isSaving = false;

  @override
  void dispose() {
    _foodController.dispose();
    _calorieController.dispose();
    super.dispose();
  }

  Future<void> _saveMeal() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    final calories = int.parse(_calorieController.text.trim());
    try {
      final success = await widget.onSave(
        _selectedMealType,
        _foodController.text.trim(),
        calories,
      );

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your meal. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong while saving your meal: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
        fontSize: 13,
      ),
      prefixIcon: Icon(icon, color: _aqua, size: 19),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      errorStyle: const TextStyle(color: Color(0xFFFFB4AB)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _aqua, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: _dialogBlue,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.restaurant_menu_rounded,
                          color: _gold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Log a Meal',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close dialog',
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your food and its calorie amount.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _fieldLabel('MEAL TYPE'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedMealType,
                        isExpanded: true,
                        dropdownColor: _dialogBlue,
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        items: const ['Breakfast', 'Lunch', 'Dinner', 'Snack']
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _selectedMealType = value);
                                }
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _fieldLabel('FOOD NAME'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _foodController,
                    enabled: !_isSaving,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      hint: 'e.g. Grilled chicken salad',
                      icon: Icons.fastfood_rounded,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a food name';
                      }
                      if (value.trim().length < 2) {
                        return 'Food name must be at least 2 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  _fieldLabel('CALORIES (KCAL)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _calorieController,
                    enabled: !_isSaving,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      hint: 'e.g. 450',
                      icon: Icons.local_fire_department_rounded,
                    ),
                    onFieldSubmitted: (_) => _saveMeal(),
                    validator: (value) {
                      final calories = int.tryParse(value?.trim() ?? '');
                      if (calories == null || calories <= 0) {
                        return 'Enter a calorie amount greater than 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveMeal,
                          icon: _isSaving
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _deepBlue,
                                  ),
                                )
                              : const Icon(Icons.add_rounded, size: 18),
                          label: Text(_isSaving ? 'Saving...' : 'Add Meal'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _aqua,
                            foregroundColor: _deepBlue,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                    ],
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
