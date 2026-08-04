import 'package:flutter/material.dart';
import '../services/incidents_service.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class NetworkStatusScreen extends StatefulWidget {
  const NetworkStatusScreen({super.key});

  @override
  State<NetworkStatusScreen> createState() => _NetworkStatusScreenState();
}

class _NetworkStatusScreenState extends State<NetworkStatusScreen> {
  bool _loading = true;
  String? _error;
  List<Incident> _activeIncidents = [];
  List<Incident> _historyIncidents = [];
  bool _historyLoading = false;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final active = await IncidentsService.fetchActiveIncidents();
      if (!mounted) return;
      setState(() {
        _activeIncidents = active;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    if (_historyLoaded || _historyLoading) return;
    setState(() {
      _historyLoading = true;
    });
    try {
      final history = await IncidentsService.fetchHistoryIncidents();
      if (!mounted) return;
      setState(() {
        _historyIncidents = history;
        _historyLoading = false;
        _historyLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
      });
    }
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      if (m == 0) return 'только что';
      return '$m мин. назад';
    } else if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ч. назад';
    } else {
      final d = diff.inDays;
      return '$d дн. назад';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Статус сети')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brand),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_off_rounded,
                    color: AppColors.danger, size: 34),
              ),
              const SizedBox(height: 22),
              Text(
                'Не удалось загрузить статус сети.\nПроверьте подключение и повторите попытку.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.p.ink,
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.brand,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_activeIncidents.isEmpty)
            _buildEmptyState()
          else
            ..._activeIncidents.map((i) => _buildIncidentCard(i)),
          const SizedBox(height: 24),
          _buildHistorySection(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.ok.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                size: 64, color: AppColors.ok),
          ),
          const SizedBox(height: 24),
          Text(
            'Все системы работают штатно',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.p.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'В данный момент аварий и плановых работ на сети нет.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: context.p.inkMute,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentCard(Incident incident) {
    final isResolved = incident.status == 'resolved';
    final isIncident = incident.type == 'incident';
    
    final Color color = isResolved
        ? AppColors.ok
        : (isIncident ? AppColors.danger : AppColors.accent);
    
    final IconData icon = isResolved
        ? Icons.check_circle_rounded
        : (isIncident ? Icons.warning_rounded : Icons.build_rounded);
    
    final timeStr = _formatRelativeTime(isResolved && incident.resolvedAt != null 
        ? incident.resolvedAt! 
        : incident.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        clip: true,
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: color, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  incident.title,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    decoration: isResolved ? TextDecoration.lineThrough : null,
                                    color: isResolved ? context.p.inkFaint : context.p.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.p.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (incident.affectedArea != null && incident.affectedArea!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.p.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            incident.affectedArea!,
                            style: TextStyle(fontSize: 12, color: context.p.inkMute),
                          ),
                        ),
                      ],
                      if (incident.description != null && incident.description!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          incident.description!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: isResolved ? context.p.inkFaint : context.p.inkMute,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: ExpansionTile(
        title: const Text(
          'История',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        collapsedIconColor: context.p.inkMute,
        iconColor: AppColors.brand,
        onExpansionChanged: (expanded) {
          if (expanded) _loadHistory();
        },
        children: [
          if (_historyLoading)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2.5),
              ),
            )
          else if (_historyLoaded && _historyIncidents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'История пуста',
                style: TextStyle(color: context.p.inkFaint),
              ),
            )
          else if (_historyLoaded)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: _historyIncidents.map((i) => _buildIncidentCard(i)).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
