library wsl2distromanager.analytics;

import 'package:plausible_analytics/plausible_analytics.dart';

String analyticsUrl = "https://analytics.bostrot.com";
const String analyticsName = "wslmanager.bostrot.com";

Plausible plausible = Plausible(analyticsUrl, analyticsName);
