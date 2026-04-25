import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ffastdb/ffastdb.dart';
import 'package:ffastdb_analytics/ffastdb_analytics.dart';

/// Flujo de caja acumulado — rendered with [cumulativeSumStream].
///
/// Streams CumSumPoint values as they are emitted and paints a live
/// sparkline via [CustomPaint] — zero third-party chart dependencies.
class CashFlowPage extends StatelessWidget {
  const CashFlowPage({super.key, required this.db});
  final FastDB db;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flujo de caja acumulado'),
        centerTitle: false,
      ),
      body: _CashFlowBody(db: db),
    );
  }
}

class _CashFlowBody extends StatefulWidget {
  const _CashFlowBody({required this.db});
  final FastDB db;

  @override
  State<_CashFlowBody> createState() => _CashFlowBodyState();
}

class _CashFlowBodyState extends State<_CashFlowBody> {
  final List<CumSumPoint> _points = [];
  late final StreamSubscription<CumSumPoint> _sub;

  @override
  void initState() {
    super.initState();
    // Stream created once here — no double-subscription risk
    final stream = widget.db.analytics
        .where((q) => q.where('tipo').equals('INGRESO').findIds())
        .cumulativeSumStream('monto', orderBy: 'mes');
    _sub = stream.listen((p) {
      if (mounted) setState(() => _points.add(p));
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_points.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final last = _points.last;
    final total = last.cumSum;
    final maxCumSum =
        _points.fold(0.0, (m, p) => p.cumSum > m ? p.cumSum : m);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── KPI banner ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A6B4A), Color(0xFF2E8B6A)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Flujo acumulado total',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                _fmt(total),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text('${_points.length} movimientos procesados',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Sparkline ────────────────────────────────────────────────────────
        const Text('Acumulado por movimiento',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
            child: SizedBox(
              height: 180,
              child: _Sparkline(points: _points, maxVal: maxCumSum),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Individual points table ──────────────────────────────────────────
        const Text('Detalle de movimientos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ..._points.reversed.take(20).map((p) => _PointRow(point: p)),
        if (_points.length > 20)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '... y ${_points.length - 20} movimientos más',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

// ─── Sparkline via CustomPaint ────────────────────────────────────────────────

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.points, required this.maxVal});
  final List<CumSumPoint> points;
  final double maxVal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _SparklinePainter(
          points: points,
          maxVal: maxVal,
          color: const Color(0xFF1A6B4A),
        ),
      );
    });
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(
      {required this.points, required this.maxVal, required this.color});
  final List<CumSumPoint> points;
  final double maxVal;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || maxVal == 0) return;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withAlpha(40)
      ..style = PaintingStyle.fill;

    final n = points.length;
    Offset toOffset(int i) {
      final x = size.width * i / (n - 1);
      final y = size.height - (size.height * points[i].cumSum / maxVal);
      return Offset(x, y.clamp(0.0, size.height));
    }

    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, toOffset(0).dy);
    for (int i = 1; i < n; i++) {
      path.lineTo(toOffset(i).dx, toOffset(i).dy);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, fillPaint);

    final linePath = Path();
    linePath.moveTo(toOffset(0).dx, toOffset(0).dy);
    for (int i = 1; i < n; i++) {
      linePath.lineTo(toOffset(i).dx, toOffset(i).dy);
    }
    canvas.drawPath(linePath, linePaint);

    // Draw last dot
    canvas.drawCircle(toOffset(n - 1), 4, Paint()..color = color);
    // Y-axis labels
    final textStyle = TextStyle(
        color: Colors.grey.shade600,
        fontSize: 10,
        fontFeatures: const []);
    void drawLabel(String text, Offset pos) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos);
    }

    drawLabel(_fmtShort(maxVal), const Offset(2, 2));
    drawLabel(_fmtShort(0), Offset(2, size.height - 14));
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points.length != points.length || old.maxVal != maxVal;
}

// ─── Row widget ───────────────────────────────────────────────────────────────

class _PointRow extends StatelessWidget {
  const _PointRow({required this.point});
  final CumSumPoint point;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('#${point.index + 1}',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: point.cumSum > 0
                  ? math.min(1.0, point.value / point.cumSum)
                  : 0,
              backgroundColor: const Color(0xFF1A6B4A).withAlpha(20),
              valueColor:
                  const AlwaysStoppedAnimation(Color(0xFF1A6B4A)),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(_fmt(point.value),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 100,
            child: Text('Σ ${_fmt(point.cumSum)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A6B4A))),
          ),
        ],
      ),
    );
  }
}

String _fmt(double n) =>
    '\$${n.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';

String _fmtShort(double n) {
  if (n >= 1e6) return '\$${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1e3) return '\$${(n / 1e3).toStringAsFixed(0)}k';
  return '\$${n.toStringAsFixed(0)}';
}
