import 'dart:ui';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ==========================================
// 1. WEEKLY CHART STATE & NOTIFIER
// ==========================================

class DailyHydrationData {
  final String dayLabel; // e.g. "Mon", "Tue"
  final int totalMl;

  DailyHydrationData({required this.dayLabel, required this.totalMl});
}

class WeeklyChartState {
  final List<DailyHydrationData> weeklyData;
  final int dailyGoalMl;
  final bool isLoading;

  WeeklyChartState({
    this.weeklyData = const [],
    this.dailyGoalMl = 2000,
    this.isLoading = false,
  });

  WeeklyChartState copyWith({
    List<DailyHydrationData>? weeklyData,
    int? dailyGoalMl,
    bool? isLoading,
  }) {
    return WeeklyChartState(
      weeklyData: weeklyData ?? this.weeklyData,
      dailyGoalMl: dailyGoalMl ?? this.dailyGoalMl,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class WeeklyChartNotifier extends StateNotifier<WeeklyChartState> {
  WeeklyChartNotifier() : super(WeeklyChartState()) {
    fetchWeeklyData();
  }

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> fetchWeeklyData() async {
    state = state.copyWith(isLoading: true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        state = state.copyWith(isLoading: false);
        return;
      }

      // 1. Fetch user's daily water target goal
      final profileRes = await _supabase
          .from('users_profile')
          .select('daily_water_goal_ml')
          .eq('id', userId)
          .maybeSingle();

      int goal = 2000;
      if (profileRes != null && profileRes['daily_water_goal_ml'] != null) {
        goal = (profileRes['daily_water_goal_ml'] as num).toInt();
      }

      // 2. Compute date range for past 7 days (including today)
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 6));
      final startDateStr = DateTime(
        sevenDaysAgo.year,
        sevenDaysAgo.month,
        sevenDaysAgo.day,
      ).toIso8601String();

      final logsRes = await _supabase
          .from('water_logs')
          .select('amount_ml, created_at')
          .eq('user_id', userId)
          .gte('created_at', startDateStr);

      // 3. Group logs by date
      final Map<String, int> dailyTotals = {};
      for (var i = 0; i < 7; i++) {
        final date = sevenDaysAgo.add(Duration(days: i));
        final dateKey = DateFormat('yyyy-MM-dd').format(date);
        dailyTotals[dateKey] = 0;
      }

      for (var log in (logsRes as List)) {
        final createdAt = DateTime.parse(
          log['created_at'].toString(),
        ).toLocal();
        final dateKey = DateFormat('yyyy-MM-dd').format(createdAt);
        final amount = (log['amount_ml'] as num).toInt();
        if (dailyTotals.containsKey(dateKey)) {
          dailyTotals[dateKey] = (dailyTotals[dateKey] ?? 0) + amount;
        }
      }

      // 4. Map into daily chart items
      final List<DailyHydrationData> chartItems = [];
      dailyTotals.forEach((dateStr, totalMl) {
        final date = DateTime.parse(dateStr);
        final dayLabel = DateFormat('E').format(date); // e.g. Mon, Tue
        chartItems.add(
          DailyHydrationData(dayLabel: dayLabel, totalMl: totalMl),
        );
      });

      state = state.copyWith(
        weeklyData: chartItems,
        dailyGoalMl: goal,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error fetching weekly chart data: $e');
      state = state.copyWith(isLoading: false);
    }
  }
}

final weeklyChartProvider =
    StateNotifierProvider<WeeklyChartNotifier, WeeklyChartState>((ref) {
      return WeeklyChartNotifier();
    });

// ==========================================
// 2. GLASSMORPHISM WEEKLY CHART WIDGET
// ==========================================

class WeeklyChartWidget extends ConsumerWidget {
  const WeeklyChartWidget({super.key});

  static const Color _aqua = Color(0xFF90E0EF);
  static const Color _cyan = Color(0xFF00B4D8);
  static const Color _deepBlue = Color(0xFF023E8A);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartState = ref.watch(weeklyChartProvider);

    final data = chartState.weeklyData;
    final goal = chartState.dailyGoalMl > 0 ? chartState.dailyGoalMl : 2000;

    final totalMl = data.fold<int>(0, (sum, item) => sum + item.totalMl);

    final averageMl = data.isEmpty ? 0 : totalMl ~/ data.length;

    final goalReachedDays = data.where((item) => item.totalMl >= goal).length;

    final highestIntake = data.isEmpty
        ? 0
        : data.map((item) => item.totalMl).reduce((a, b) => a > b ? a : b);

    final maxY = [
      (goal * 1.25).toDouble(),
      (highestIntake * 1.2).toDouble(),
      500.0,
    ].reduce((a, b) => a > b ? a : b);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _aqua.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
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
                          'Weekly Analytics',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Your hydration overview',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: chartState.isLoading
                          ? null
                          : () => ref
                                .read(weeklyChartProvider.notifier)
                                .fetchWeeklyData(),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Icon(
                          Icons.refresh_rounded,
                          color: chartState.isLoading
                              ? Colors.white30
                              : Colors.white70,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // SUMMARY STATISTICS
              Row(
                children: [
                  _buildMetric(
                    icon: Icons.water_drop_rounded,
                    label: 'TOTAL INTAKE',
                    value: '${(totalMl / 1000).toStringAsFixed(1)} L',
                    iconColor: _aqua,
                  ),
                  const SizedBox(width: 10),
                  _buildMetric(
                    icon: Icons.show_chart_rounded,
                    label: 'DAILY AVERAGE',
                    value: '${(averageMl / 1000).toStringAsFixed(1)} L',
                    iconColor: const Color(0xFF80FFDB),
                  ),
                  const SizedBox(width: 10),
                  _buildMetric(
                    icon: Icons.emoji_events_rounded,
                    label: 'GOAL DAYS',
                    value: '$goalReachedDays/7',
                    iconColor: const Color(0xFFFFD166),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              // CHART SECTION HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Daily Progress',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Goal: ${(goal / 1000).toStringAsFixed(1)} L',
                    style: const TextStyle(
                      color: _aqua,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // CHART LEGEND
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: _cyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Water intake',
                    style: TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                  const SizedBox(width: 16),
                  Container(width: 17, height: 2, color: _aqua),
                  const SizedBox(width: 6),
                  const Text(
                    'Daily goal',
                    style: TextStyle(color: Colors.white60, fontSize: 10),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // CHART / LOADING / EMPTY STATE
              if (chartState.isLoading)
                const SizedBox(
                  height: 190,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _aqua,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else if (data.isEmpty)
                _buildEmptyState()
              else
                SizedBox(
                  height: 190,
                  child: BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceAround,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => _deepBlue,
                          tooltipRoundedRadius: 12,
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (groupIndex >= data.length) {
                              return null;
                            }

                            final day = data[groupIndex].dayLabel;

                            return BarTooltipItem(
                              '$day\n${rod.toY.round()} ml',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                height: 1.5,
                              ),
                            );
                          },
                        ),
                      ),

                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();

                              if (index < 0 || index >= data.length) {
                                return const SizedBox.shrink();
                              }

                              final isToday = index == data.length - 1;

                              return Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  data[index].dayLabel,
                                  style: TextStyle(
                                    color: isToday ? _aqua : Colors.white60,
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 4,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.white.withValues(alpha: 0.07),
                            strokeWidth: 1,
                          );
                        },
                      ),

                      borderData: FlBorderData(show: false),

                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: goal.toDouble(),
                            color: _aqua.withValues(alpha: 0.75),
                            strokeWidth: 1.5,
                            dashArray: [5, 5],
                          ),
                        ],
                      ),

                      barGroups: data.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;

                        final reachedGoal = item.totalMl >= goal;

                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: item.totalMl.toDouble(),
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(7),
                              ),
                              gradient: LinearGradient(
                                colors: reachedGoal
                                    ? [
                                        const Color(0xFF90E0EF),
                                        const Color(0xFF00B4D8),
                                      ]
                                    : [
                                        Colors.white.withValues(alpha: 0.30),
                                        Colors.white.withValues(alpha: 0.65),
                                      ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),

              const SizedBox(height: 18),

              // FOOTER
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insights_rounded, color: _aqua, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        goalReachedDays == 7
                            ? 'Amazing! You reached your goal every day.'
                            : goalReachedDays == 0
                            ? 'Keep going! Aim to reach your daily goal.'
                            : 'You reached your hydration goal on $goalReachedDays of 7 days.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 17),
            const SizedBox(height: 9),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 190,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.water_drop_outlined,
            color: Colors.white.withValues(alpha: 0.4),
            size: 38,
          ),
          const SizedBox(height: 10),
          const Text(
            'No hydration data yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Start tracking your water intake!',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
