import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/firebase_service.dart';

class WeightChart extends StatefulWidget {
  final String catId;
  const WeightChart({super.key, required this.catId});

  @override
  State<WeightChart> createState() => _WeightChartState();
}

class _WeightChartState extends State<WeightChart> {
  final FirebaseService _db = FirebaseService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _db.getWeightLogs(widget.catId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No weight data yet. Add weight logs to see chart.'),
          );
        }
        
        final logs = snapshot.data!;
        final recentLogs = logs.take(6).toList().reversed.toList();
        
        List<FlSpot> spots = [];
        for (int i = 0; i < recentLogs.length; i++) {
          spots.add(FlSpot(i.toDouble(), recentLogs[i].weight));
        }
        
        return Container(
          height: 200,
          padding: const EdgeInsets.all(16),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      int index = value.toInt();
                      if (index >= 0 && index < recentLogs.length) {
                        return Text(
                          '${recentLogs[index].date.month}/${recentLogs[index].date.day}',
                          style: const TextStyle(fontSize: 10),
                        );
                      }
                      return const Text('');
                    },
                    reservedSize: 30,
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Colors.orange,
                  barWidth: 3,
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.orange.withValues(alpha: 0.2),
                  ),
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}