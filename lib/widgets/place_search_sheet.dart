import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../models/revv_route.dart';
import '../services/place_search_service.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../ui/app_copy.dart';
import 'revv_ui.dart';

const plannerPlaceSearchFieldKey = Key('planner-place-search-field');

class PlaceSearchMapPinSelection {
  const PlaceSearchMapPinSelection();
}

class PlaceSearchSheet extends StatefulWidget {
  final AppLanguage language;
  final PlaceSearchService service;
  final LatLng proximity;
  final bool allowMapPin;

  const PlaceSearchSheet({
    super.key,
    required this.language,
    required this.service,
    required this.proximity,
    this.allowMapPin = true,
  });

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _searching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _hasSearched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_search(query));
    });
  }

  Future<void> _search(String query) async {
    if (!widget.service.isEnabled) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _hasSearched = true;
      });
      return;
    }

    setState(() {
      _searching = true;
      _hasSearched = true;
    });
    final results = await widget.service.searchPlaces(
      query,
      proximity: widget.proximity,
      language: _languageCode(widget.language),
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: RevvGlassCard(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        radius: 18,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _copy(
                        widget.language,
                        ko: '장소 검색',
                        en: 'Place search',
                        fr: 'Recherche de lieu',
                      ),
                      style: AppText.body(size: 18, weight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textHint,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: plannerPlaceSearchFieldKey,
                controller: _controller,
                enabled: widget.service.isEnabled,
                autofocus: widget.service.isEnabled,
                onChanged: _onQueryChanged,
                style: AppText.body(weight: FontWeight.w800),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: _copy(
                    widget.language,
                    ko: '목적지 이름 입력',
                    en: 'Search by destination name',
                    fr: 'Nom de la destination',
                  ),
                  hintStyle: AppText.body(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surface.withValues(alpha: 0.88),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.28),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.28),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.red),
                  ),
                ),
              ),
              if (widget.allowMapPin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    const PlaceSearchMapPinSelection(),
                  ),
                  icon: const Icon(Icons.location_pin, size: 18),
                  label: Text(
                    _copy(
                      widget.language,
                      ko: '지도 핀으로 지정',
                      en: 'Use map pin',
                      fr: 'Utiliser le repère',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.28),
                    ),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: _buildResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!widget.service.isEnabled || (_hasSearched && _results.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _copy(
            widget.language,
            ko: '찾지 못했어요 — 지도 핀으로 지정할 수도 있어요',
            en: 'No place found — you can also set it with the map pin',
            fr: 'Aucun lieu trouvé — vous pouvez aussi utiliser le repère',
          ),
          style: AppText.body(size: 13, color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: AppColors.outlineVariant.withValues(alpha: 0.18),
      ),
      itemBuilder: (context, index) {
        final result = _results[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.place_rounded,
            color: AppColors.primaryContainer,
          ),
          title: Text(
            result.name,
            style: AppText.body(size: 14, weight: FontWeight.w900),
          ),
          subtitle: result.address.isEmpty
              ? null
              : Text(
                  result.address,
                  style: AppText.body(size: 12, color: AppColors.textSecondary),
                ),
          onTap: () => Navigator.pop(context, result),
        );
      },
    );
  }
}

String _languageCode(AppLanguage language) {
  return switch (language) {
    AppLanguage.korean => 'ko',
    AppLanguage.english => 'en',
    AppLanguage.french => 'fr',
  };
}

String _copy(
  AppLanguage language, {
  String? ko,
  required String en,
  required String fr,
}) {
  return AppCopy.t(language, ko: ko, en: en, fr: fr);
}
