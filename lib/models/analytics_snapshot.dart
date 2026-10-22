class DayMetric {
  const DayMetric({required this.dayLabel, required this.viewers, required this.orders});

  final String dayLabel;
  final double viewers;
  final double orders;
}

class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.liveHours,
    required this.avgViewers,
    required this.inquiries,
    required this.orders,
    required this.aiCostYuan,
    required this.weekTrend,
  });

  final double liveHours;
  final int avgViewers;
  final int inquiries;
  final int orders;
  final double aiCostYuan;
  final List<DayMetric> weekTrend;
}
