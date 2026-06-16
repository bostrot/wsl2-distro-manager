import 'package:fluent_ui/fluent_ui.dart';
import 'package:localization/localization.dart';
import 'package:wsl2distromanager/api/recommender_service.dart';
import 'package:wsl2distromanager/nav/router.dart';

class RecommendationsPanel extends StatelessWidget {
  final List<String> distroNames;

  const RecommendationsPanel({
    Key? key,
    required this.distroNames,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final recommender = RecommenderService();
    final recommendations = recommender.analyze(distroNames);

    if (recommendations.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).brightness.isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.lightbulb,
                size: 14,
                color: FluentTheme.of(context).accentColor,
              ),
              const SizedBox(width: 6),
              Text(
                'recommendations-title'.i18n(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FluentTheme.of(context).accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recommendations.map((rec) {
            if (recommender.isDismissed(rec.key)) return const SizedBox.shrink();
            return _buildRecommendationItem(
              context,
              rec,
              recommender,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRecommendationItem(
    BuildContext context,
    Recommendation rec,
    RecommenderService recommender,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.key.i18n(),
                  style: const TextStyle(fontSize: 11),
                ),
                if (rec.actionRoute != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () {
                      RecommenderService.clearDismissed(rec.key);
                      router.pushNamed(rec.actionRoute!);
                    },
                    child: Text(
                      'Go to ${rec.actionRoute == '/templates' ? 'Templates' : 'Settings'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: FluentTheme.of(context).accentColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(FluentIcons.cancel, size: 12),
            onPressed: () {
              RecommenderService.clearDismissed(rec.key);
            },
          ),
        ],
      ),
    );
  }
}
