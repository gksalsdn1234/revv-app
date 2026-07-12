import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import '../ui/route_share_card_content.dart';
import '../ui/route_share_card_widget.dart';

/// Opens the sender-only check before an invite leaves the device.
///
/// The returned draft is deliberately narrow: it contains only the default
/// schedule and one optional, pre-approved meeting area. Delivery stays with
/// the route-detail flow so it can later attach the rendered card without
/// changing this UI contract.
Future<DriveInviteDraft?> showRouteInvitePreviewSheet(
  BuildContext context, {
  required RevvRoute route,
  required AppLanguage language,
}) {
  return showModalBottomSheet<DriveInviteDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RouteInvitePreviewSheet(route: route, language: language),
  );
}

class RouteInvitePreviewSheet extends StatefulWidget {
  final RevvRoute route;
  final AppLanguage language;

  const RouteInvitePreviewSheet({
    super.key,
    required this.route,
    required this.language,
  });

  @override
  State<RouteInvitePreviewSheet> createState() =>
      _RouteInvitePreviewSheetState();
}

class _RouteInvitePreviewSheetState extends State<RouteInvitePreviewSheet> {
  late DriveInviteDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = DriveInviteDraft.forLanguage(widget.language);
  }

  @override
  Widget build(BuildContext context) {
    final content = buildRouteShareCardContent(
      route: widget.route,
      draft: _draft,
      language: widget.language,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          key: const ValueKey('route-invite-preview-sheet'),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title(widget.language),
                        style: AppText.technicalLabel(
                          size: 10,
                          color: AppColors.primaryContainer,
                          letterSpacing: 1.7,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('dismiss-invite-preview'),
                      tooltip: _dismissLabel(widget.language),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceHigh,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle(widget.language),
                  style: AppText.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 194),
                    child: Semantics(
                      label: _cardPreviewLabel(widget.language),
                      child: ExcludeSemantics(
                        child: SizedBox(
                          key: const ValueKey('route-invite-card-preview'),
                          width: 194,
                          child: RouteShareCardWidget(content: content),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _meetingAreaLabel(widget.language),
                  style: AppText.technicalLabel(
                    size: 9,
                    color: AppColors.textHint,
                    letterSpacing: 1.15,
                  ),
                ),
                const SizedBox(height: 7),
                Semantics(
                  label: _meetingAreaLabel(widget.language),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.26),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<DriveInviteMeetingArea?>(
                        key: const ValueKey('invite-meeting-area-selector'),
                        value: _draft.meetingArea,
                        isExpanded: true,
                        dropdownColor: AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(16),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textHint,
                        ),
                        style: AppText.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        items: [
                          DropdownMenuItem<DriveInviteMeetingArea?>(
                            value: null,
                            child: Text(_noMeetingAreaLabel(widget.language)),
                          ),
                          for (final area in DriveInviteMeetingArea.values)
                            DropdownMenuItem<DriveInviteMeetingArea?>(
                              value: area,
                              child: Text(_areaLabel(area, widget.language)),
                            ),
                        ],
                        onChanged: (area) {
                          setState(() => _draft = _draft.withMeetingArea(area));
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('share-invite-draft'),
                    onPressed: () => Navigator.of(context).pop(_draft),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(
                      _shareLabel(widget.language),
                      style: AppText.body(
                        size: 14,
                        weight: FontWeight.w900,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: AppColors.onPrimary,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
  }
}

String _title(AppLanguage language) => AppCopy.t(
  language,
  ko: '드라이브 초대',
  en: 'DRIVE INVITE',
  fr: 'INVITATION ROUTE',
);

String _subtitle(AppLanguage language) => AppCopy.t(
  language,
  ko: '카드를 확인하고, 원하면 대략적인 만남 지역만 추가하세요.',
  en: 'Check the card, then add an optional meeting area.',
  fr: 'Vérifiez la carte, puis ajoutez une zone de rendez-vous facultative.',
);

String _cardPreviewLabel(AppLanguage language) => AppCopy.t(
  language,
  ko: '공유 카드 미리보기',
  en: 'Invite card preview',
  fr: 'Aperçu de la carte d’invitation',
);

String _meetingAreaLabel(AppLanguage language) => AppCopy.t(
  language,
  ko: '만남 지역 · 선택 사항',
  en: 'MEETING AREA · OPTIONAL',
  fr: 'ZONE DE RENDEZ-VOUS · FACULTATIVE',
);

String _noMeetingAreaLabel(AppLanguage language) => AppCopy.t(
  language,
  ko: '만남 지역 없음',
  en: 'No meeting area',
  fr: 'Aucune zone de rendez-vous',
);

String _shareLabel(AppLanguage language) => AppCopy.t(
  language,
  ko: '초대 공유하기',
  en: 'Share invite',
  fr: 'Partager l’invitation',
);

String _dismissLabel(AppLanguage language) => AppCopy.t(
  language,
  ko: '초대 닫기',
  en: 'Dismiss invite',
  fr: 'Fermer l’invitation',
);

String _areaLabel(DriveInviteMeetingArea area, AppLanguage language) {
  return switch ((area, language)) {
    (DriveInviteMeetingArea.oldPort, AppLanguage.korean) => '올드 포트 근처',
    (DriveInviteMeetingArea.oldPort, AppLanguage.english) => 'Near Old Port',
    (DriveInviteMeetingArea.oldPort, AppLanguage.french) =>
      'Près du Vieux-Port',
    (DriveInviteMeetingArea.westIsland, AppLanguage.korean) => '웨스트 아일랜드',
    (DriveInviteMeetingArea.westIsland, AppLanguage.english) => 'West Island',
    (DriveInviteMeetingArea.westIsland, AppLanguage.french) => 'Ouest-de-l’Île',
    (DriveInviteMeetingArea.northShore, AppLanguage.korean) => '노스 쇼어',
    (DriveInviteMeetingArea.northShore, AppLanguage.english) => 'North Shore',
    (DriveInviteMeetingArea.northShore, AppLanguage.french) => 'Rive-Nord',
    (DriveInviteMeetingArea.easternTownships, AppLanguage.korean) => '이스턴 타운십스',
    (DriveInviteMeetingArea.easternTownships, AppLanguage.english) =>
      'Eastern Townships',
    (DriveInviteMeetingArea.easternTownships, AppLanguage.french) =>
      'Cantons-de-l’Est',
  };
}
