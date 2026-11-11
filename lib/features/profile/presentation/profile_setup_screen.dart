import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Refreshes the calorie tracker after a profile goal has been saved.
import '../../hydration/presentation/calorie_tracker_widget.dart';

// ============================================================
// 1. PROFILE MODEL & CALCULATION
// ============================================================

enum ActivityLevel {
  sedentary(1.2, 'Sedentary', 'Little or no exercise', Icons.weekend_rounded),
  light(
    1.375,
    'Light',
    'Light exercise 1–3 days/week',
    Icons.directions_walk_rounded,
  ),
  moderate(
    1.55,
    'Moderate',
    'Moderate exercise 3–5 days/week',
    Icons.directions_run_rounded,
  ),
  active(
    1.725,
    'Active',
    'Hard exercise 6–7 days/week',
    Icons.fitness_center_rounded,
  );

  final double multiplier;
  final String label;
  final String description;
  final IconData icon;

  const ActivityLevel(this.multiplier, this.label, this.description, this.icon);

  static ActivityLevel fromDatabase(Object? value) {
    return ActivityLevel.values.firstWhere(
      (level) => level.name == value?.toString(),
      orElse: () => ActivityLevel.moderate,
    );
  }
}

enum BiologicalSex {
  male('Male', 'male'),
  female('Female', 'female');

  final String label;
  final String databaseValue;
  const BiologicalSex(this.label, this.databaseValue);

  static BiologicalSex fromDatabase(Object? value) {
    return BiologicalSex.values.firstWhere(
      (sex) => sex.databaseValue == value?.toString().toLowerCase(),
      orElse: () => BiologicalSex.male,
    );
  }
}

class ProfileState {
  final double? heightCm;
  final double? weightKg;
  final int age;
  final ActivityLevel activityLevel;
  final BiologicalSex sex;
  final double? bmi;
  final String bmiFeedback;
  final int waterGoalMl;
  final int calorieGoal;
  final bool isLoading;
  final bool isSaved;
  final bool hasLoaded;

  const ProfileState({
    this.heightCm,
    this.weightKg,
    this.age = 25,
    this.activityLevel = ActivityLevel.moderate,
    this.sex = BiologicalSex.male,
    this.bmi,
    this.bmiFeedback = 'Enter your details to calculate your daily goals.',
    this.waterGoalMl = 2000,
    this.calorieGoal = 2000,
    this.isLoading = false,
    this.isSaved = false,
    this.hasLoaded = false,
  });

  ProfileState copyWith({
    double? heightCm,
    double? weightKg,
    int? age,
    ActivityLevel? activityLevel,
    BiologicalSex? sex,
    double? bmi,
    String? bmiFeedback,
    int? waterGoalMl,
    int? calorieGoal,
    bool? isLoading,
    bool? isSaved,
    bool? hasLoaded,
    bool clearMetrics = false,
    bool clearHeight = false,
    bool clearWeight = false,
  }) {
    return ProfileState(
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
      age: age ?? this.age,
      activityLevel: activityLevel ?? this.activityLevel,
      sex: sex ?? this.sex,
      bmi: clearMetrics ? null : (bmi ?? this.bmi),
      bmiFeedback: bmiFeedback ?? this.bmiFeedback,
      waterGoalMl: waterGoalMl ?? this.waterGoalMl,
      calorieGoal: calorieGoal ?? this.calorieGoal,
      isLoading: isLoading ?? this.isLoading,
      isSaved: isSaved ?? this.isSaved,
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(const ProfileState());

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> loadExistingProfile() async {
    state = state.copyWith(isLoading: true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        state = state.copyWith(isLoading: false, hasLoaded: true);
        return;
      }

      final data = await _supabase
          .from('users_profile')
          .select(
            'height, weight, age, activity_level, sex, daily_water_goal_ml, daily_calorie_goal',
          )
          .eq('id', userId)
          .maybeSingle();

      if (data == null) {
        state = state.copyWith(isLoading: false, hasLoaded: true);
        return;
      }

      final height = (data['height'] as num?)?.toDouble();
      final weight = (data['weight'] as num?)?.toDouble();
      final age = (data['age'] as num?)?.toInt() ?? state.age;
      final activity = ActivityLevel.fromDatabase(data['activity_level']);
      final sex = BiologicalSex.fromDatabase(data['sex']);

      if (height != null && weight != null && height > 0 && weight > 0) {
        _calculateMetrics(
          height,
          weight,
          age,
          activity,
          sex,
          isLoading: false,
          hasLoaded: true,
        );
      } else {
        state = state.copyWith(
          heightCm: height,
          weightKg: weight,
          age: age,
          activityLevel: activity,
          sex: sex,
          waterGoalMl: (data['daily_water_goal_ml'] as num?)?.toInt() ?? 2000,
          calorieGoal: (data['daily_calorie_goal'] as num?)?.toInt() ?? 2000,
          isLoading: false,
          hasLoaded: true,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading health profile: $e');
      debugPrintStack(stackTrace: stackTrace);
      state = state.copyWith(isLoading: false, hasLoaded: true);
    }
  }

  void updateInputs({
    String? heightStr,
    String? weightStr,
    int? age,
    ActivityLevel? activity,
    BiologicalSex? sex,
  }) {
    final height = heightStr != null
        ? (heightStr.trim().isEmpty ? null : double.tryParse(heightStr.trim()))
        : state.heightCm;
    final weight = weightStr != null
        ? (weightStr.trim().isEmpty ? null : double.tryParse(weightStr.trim()))
        : state.weightKg;
    final updatedAge = age ?? state.age;
    final updatedActivity = activity ?? state.activityLevel;
    final updatedSex = sex ?? state.sex;

    if (height != null &&
        weight != null &&
        height > 0 &&
        weight > 0 &&
        updatedAge > 0) {
      _calculateMetrics(
        height,
        weight,
        updatedAge,
        updatedActivity,
        updatedSex,
      );
    } else {
      state = state.copyWith(
        heightCm: height,
        weightKg: weight,
        clearHeight: height == null,
        clearWeight: weight == null,
        age: updatedAge,
        activityLevel: updatedActivity,
        sex: updatedSex,
        bmiFeedback: 'Enter valid height and weight to calculate your goals.',
        waterGoalMl: 2000,
        calorieGoal: 2000,
        clearMetrics: true,
        isSaved: false,
      );
    }
  }

  void _calculateMetrics(
    double heightCm,
    double weightKg,
    int age,
    ActivityLevel activity,
    BiologicalSex sex, {
    bool isLoading = false,
    bool hasLoaded = false,
  }) {
    final heightM = heightCm / 100;
    final calculatedBmi = weightKg / (heightM * heightM);

    final String feedback;
    if (calculatedBmi < 18.5) {
      feedback =
          'Your BMI is below the usual adult range. Consider discussing your nutrition needs with a health professional.';
    } else if (calculatedBmi < 25) {
      feedback =
          'Your BMI is within the usual adult range. Keep building balanced, sustainable habits.';
    } else if (calculatedBmi < 30) {
      feedback =
          'Your BMI is above the usual adult range. A health professional can help interpret it in context.';
    } else {
      feedback =
          'Your BMI is in a higher range. BMI is only a screening measure, so consider professional guidance.';
    }

    final water = (weightKg * 35).round().clamp(1500, 4500);

    // Mifflin–St Jeor estimated resting energy expenditure (kcal/day).
    // Male: +5; Female: -161. This is an estimate, not a medical prescription.
    final sexConstant = sex == BiologicalSex.male ? 5 : -161;
    final bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * age) + sexConstant;
    final calories = (bmr * activity.multiplier).round().clamp(1200, 4500);

    state = state.copyWith(
      heightCm: heightCm,
      weightKg: weightKg,
      age: age,
      activityLevel: activity,
      sex: sex,
      bmi: double.parse(calculatedBmi.toStringAsFixed(1)),
      bmiFeedback: feedback,
      waterGoalMl: water,
      calorieGoal: calories,
      isLoading: isLoading,
      hasLoaded: hasLoaded,
      isSaved: false,
    );
  }

  Future<bool> saveProfile() async {
    final height = state.heightCm;
    final weight = state.weightKg;
    if (height == null ||
        weight == null ||
        height <= 0 ||
        weight <= 0 ||
        state.age < 13 ||
        state.age > 110) {
      return false;
    }

    state = state.copyWith(isLoading: true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('No authenticated user found.');

      await _supabase.from('users_profile').upsert({
        'id': userId,
        'height': height,
        'weight': weight,
        'age': state.age,
        'activity_level': state.activityLevel.name,
        'sex': state.sex.databaseValue,
        'daily_water_goal_ml': state.waterGoalMl,
        'daily_calorie_goal': state.calorieGoal,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      state = state.copyWith(isLoading: false, isSaved: true);
      return true;
    } catch (e, stackTrace) {
      debugPrint('SUPABASE PROFILE UPSERT ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);
      state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>((
  ref,
) {
  return ProfileNotifier();
});

// ============================================================
// 2. PROFILE SETUP SCREEN
// ============================================================

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  static const _aqua = Color(0xFF90E0EF);
  static const _deepBlue = Color(0xFF03045E);
  static const _blue = Color(0xFF0077B6);
  static const _gold = Color(0xFFFFD166);

  final _formKey = GlobalKey<FormState>();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _ageController = TextEditingController(text: '25');
  bool _controllersPopulated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(profileProvider.notifier).loadExistingProfile();
      if (!mounted) return;
      _populateControllers(ref.read(profileProvider));
    });
  }

  void _populateControllers(ProfileState profile) {
    if (_controllersPopulated || !profile.hasLoaded) return;
    _heightController.text = profile.heightCm == null
        ? ''
        : _formatNumber(profile.heightCm!);
    _weightController.text = profile.weightKg == null
        ? ''
        : _formatNumber(profile.weightKg!);
    _ageController.text = profile.age.toString();
    _controllersPopulated = true;
  }

  String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _updateMetrics() {
    ref
        .read(profileProvider.notifier)
        .updateInputs(
          heightStr: _heightController.text,
          weightStr: _weightController.text,
          age: int.tryParse(_ageController.text),
        );
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    _updateMetrics();
    final success = await ref.read(profileProvider.notifier).saveProfile();
    if (!mounted) return;

    if (success) {
      // The calorie tracker reads its goal from users_profile. Refresh it now
      // so an already-mounted tracker immediately receives the new goal.
      await ref.read(calorieProvider.notifier).loadTodayCalories();
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Health profile saved. Your calorie and water goals are synchronized!'
              : 'Could not save your profile. Check your details and try again.',
        ),
        backgroundColor: success ? const Color(0xFF007F5F) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    _populateControllers(profile);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Health & Goals',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_deepBlue, Color(0xFF0077B6), Color(0xFF00B4D8)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _glassCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildIntro(profile),
                        const SizedBox(height: 25),
                        _sectionTitle(
                          'PERSONAL DETAILS',
                          Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            Expanded(
                              child: _numberField(
                                controller: _heightController,
                                label: 'Height',
                                suffix: 'cm',
                                icon: Icons.height_rounded,
                                onChanged: (_) => _updateMetrics(),
                                validator: (value) {
                                  final number = double.tryParse(
                                    value?.trim() ?? '',
                                  );
                                  if (number == null ||
                                      number < 100 ||
                                      number > 250) {
                                    return 'Enter 100–250 cm';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _numberField(
                                controller: _weightController,
                                label: 'Weight',
                                suffix: 'kg',
                                icon: Icons.monitor_weight_outlined,
                                onChanged: (_) => _updateMetrics(),
                                validator: (value) {
                                  final number = double.tryParse(
                                    value?.trim() ?? '',
                                  );
                                  if (number == null ||
                                      number < 25 ||
                                      number > 350) {
                                    return 'Enter 25–350 kg';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        _numberField(
                          controller: _ageController,
                          label: 'Age',
                          suffix: 'years',
                          icon: Icons.cake_outlined,
                          onChanged: (_) => _updateMetrics(),
                          validator: (value) {
                            final age = int.tryParse(value?.trim() ?? '');
                            if (age == null || age < 13 || age > 110) {
                              return 'Enter an age between 13 and 110';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 23),
                        _sectionTitle(
                          'CALCULATION SETTINGS',
                          Icons.tune_rounded,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Sex used for the Mifflin–St Jeor equation',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: BiologicalSex.values.map((sex) {
                            final selected = profile.sex == sex;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: sex == BiologicalSex.male ? 8 : 0,
                                ),
                                child: _selectionCard(
                                  selected: selected,
                                  icon: sex == BiologicalSex.male
                                      ? Icons.male_rounded
                                      : Icons.female_rounded,
                                  title: sex.label,
                                  onTap: () => ref
                                      .read(profileProvider.notifier)
                                      .updateInputs(sex: sex),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Daily activity level',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 9),
                        ...ActivityLevel.values.map((level) {
                          final selected = profile.activityLevel == level;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _activityOption(level, selected),
                          );
                        }),
                        const SizedBox(height: 18),
                        _sectionTitle(
                          'YOUR DAILY TARGETS',
                          Icons.insights_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildMetrics(profile),
                        const SizedBox(height: 13),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _aqua.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _aqua.withValues(alpha: .2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.lightbulb_outline_rounded,
                                color: _aqua,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  profile.bmiFeedback,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Calorie target is an estimate based on the Mifflin–St Jeor equation and your selected activity level. BMI and calorie estimates are not medical advice.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .55),
                            fontSize: 10,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: profile.isLoading ? null : _onSave,
                            icon: profile.isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _deepBlue,
                                    ),
                                  )
                                : const Icon(Icons.cloud_done_rounded),
                            label: Text(
                              profile.isLoading
                                  ? 'Saving profile...'
                                  : 'Save & Sync Goals',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _blue,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        if (profile.isSaved) ...[
                          const SizedBox(height: 10),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF9BF6C8),
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Your profile is saved',
                                style: TextStyle(
                                  color: Color(0xFF9BF6C8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildIntro(ProfileState profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: _aqua.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.favorite_rounded, color: _aqua, size: 25),
        ),
        const SizedBox(height: 15),
        const Text(
          'Build your health profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.bold,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Add your details to calculate personalized daily water and calorie targets.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .75),
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: _aqua, size: 17),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required IconData icon,
    required ValueChanged<String> onChanged,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: .7),
          fontSize: 12,
        ),
        suffixStyle: TextStyle(
          color: Colors.white.withValues(alpha: .65),
          fontSize: 11,
        ),
        prefixIcon: Icon(icon, color: _aqua, size: 19),
        filled: true,
        fillColor: Colors.white.withValues(alpha: .075),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 15,
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFC4C4), fontSize: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .17)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .17)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _aqua, width: 1.4),
        ),
      ),
    );
  }

  Widget _selectionCard({
    required bool selected,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: .19)
              : Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? _aqua : Colors.white.withValues(alpha: .16),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? _aqua : Colors.white70, size: 19),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityOption(ActivityLevel level, bool selected) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () =>
          ref.read(profileProvider.notifier).updateInputs(activity: level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _aqua.withValues(alpha: .14)
              : Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? _aqua.withValues(alpha: .75)
                : Colors.white.withValues(alpha: .13),
          ),
        ),
        child: Row(
          children: [
            Icon(
              level.icon,
              color: selected ? _aqua : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    level.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    level.description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .62),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: _aqua, size: 19),
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(ProfileState profile) {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            'BMI',
            profile.bmi?.toStringAsFixed(1) ?? '--',
            'index',
            Icons.monitor_heart_outlined,
            Colors.white,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _metricCard(
            'WATER',
            '${profile.waterGoalMl}',
            'ml / day',
            Icons.water_drop_rounded,
            _aqua,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _metricCard(
            'CALORIES',
            '${profile.calorieGoal}',
            'kcal / day',
            Icons.local_fire_department_rounded,
            _gold,
          ),
        ),
      ],
    );
  }

  Widget _metricCard(
    String label,
    String value,
    String unit,
    IconData icon,
    Color accent,
  ) {
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .13)),
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 19),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .62),
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .52),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
