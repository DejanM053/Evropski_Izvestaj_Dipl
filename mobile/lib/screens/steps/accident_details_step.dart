import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../models/report_model.dart';
import '../../state/session_controller.dart';
import '../../theme/theme.dart';
import '../../utils/sample_data.dart';
import '../../widgets/widgets.dart';

/// Screen 5 (docs/master_plan.md §6) — accident details. Shared between
/// both parties (`accident.*` — last-write-wins, per .claude/rules/backend.md),
/// unlike screen 6's own-subtree fields. Not present in the design's 16-screen
/// set at all (only "1e" My details onward are mocked) — laid out from the
/// same tokens/section pattern as "1e" per docs/master_plan.md §1's
/// "derive it from the existing tokens" instruction.
class AccidentDetailsStep extends StatefulWidget {
  const AccidentDetailsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<AccidentDetailsStep> createState() => _AccidentDetailsStepState();
}

class _AccidentDetailsStepState extends State<AccidentDetailsStep> {
  bool _locating = false;
  final List<_WitnessDraft> _witnesses = [];
  bool _witnessesInitialized = false;
  DateTime? _witnessesLocalEditAt;

  void _patch(String path, dynamic value) => context.read<SessionController>().sendPatch(path, value);

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showSnack('Dozvola za lokaciju je odbijena. Unesite lokaciju ručno.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnack('GPS je isključen. Unesite lokaciju ručno.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _patch('accident.location.lat', position.latitude);
      _patch('accident.location.lng', position.longitude);
    } catch (_) {
      _showSnack('Nije moguće očitati lokaciju.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool get _anyWitnessFieldFocused => _witnesses.any((w) => w.nameFocus.hasFocus || w.phoneFocus.hasFocus);

  bool _witnessesMatchRemote(List<WitnessModel> remote) {
    if (remote.length != _witnesses.length) return false;
    for (var i = 0; i < remote.length; i++) {
      if ((remote[i].name ?? '') != _witnesses[i].nameController.text) return false;
      if ((remote[i].phone ?? '') != _witnesses[i].phoneController.text) return false;
    }
    return true;
  }

  void _syncWitnessesFromRemote(List<WitnessModel> remote) {
    if (_anyWitnessFieldFocused) return;
    // Guards the same race for add/remove/fill as focus does for typing:
    // a local mutation's patch hasn't round-tripped yet, so `remote` here
    // is still the pre-mutation value. Without this, the very next build
    // (triggered by the setState the mutation just did) would see
    // local != remote and "resync" straight back to the stale value —
    // e.g. a just-removed witness reappearing for a frame, or a fill
    // getting immediately overwritten by what was there before it.
    final recentLocalEdit =
        _witnessesLocalEditAt != null && DateTime.now().difference(_witnessesLocalEditAt!) < const Duration(seconds: 1);
    if (recentLocalEdit) return;
    if (_witnessesInitialized && _witnessesMatchRemote(remote)) return;
    _witnessesInitialized = true;

    for (final w in _witnesses) {
      w.dispose();
    }
    _witnesses
      ..clear()
      ..addAll(remote.map((w) => _WitnessDraft(name: w.name ?? '', phone: w.phone ?? '')));
  }

  void _sendWitnesses() {
    _witnessesLocalEditAt = DateTime.now();
    _patch('accident.witnesses', _witnesses.map((w) => w.toJson()).toList());
  }

  void _addWitness() {
    setState(() => _witnesses.add(_WitnessDraft(name: '', phone: '')));
    _sendWitnesses();
  }

  void _removeWitness(int index) {
    setState(() {
      _witnesses[index].dispose();
      _witnesses.removeAt(index);
    });
    _sendWitnesses();
  }

  Timer? _witnessDebounce;
  void _onWitnessFieldChanged() {
    _witnessDebounce?.cancel();
    _witnessDebounce = Timer(const Duration(milliseconds: 400), _sendWitnesses);
  }

  void _fillSampleData() {
    _patch('accident.dateTime', SampleAccidentData.dateTime().toIso8601String());
    _patch('accident.location.address', SampleAccidentData.address);
    _patch('accident.location.lat', SampleAccidentData.lat);
    _patch('accident.location.lng', SampleAccidentData.lng);
    _patch('accident.injuries', false);
    _patch('accident.otherVehicleDamage', true);
    _patch('accident.thirdPartyDamage', false);

    setState(() {
      for (final w in _witnesses) {
        w.dispose();
      }
      _witnesses
        ..clear()
        ..add(_WitnessDraft(name: SampleAccidentData.witnessName, phone: SampleAccidentData.witnessPhone));
    });
    _witnessesInitialized = true;
    _sendWitnesses();
  }

  @override
  void dispose() {
    _witnessDebounce?.cancel();
    for (final w in _witnesses) {
      w.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final accident = controller.report?.accident ?? const AccidentModel();
    _syncWitnessesFromRemote(accident.witnesses);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ovi podaci su zajednički — oba vozača ih vide i mogu urediti u realnom vremenu.',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                FillSampleDataButton(onPressed: _fillSampleData),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Vreme i mesto',
                  children: [
                    AppDateField(
                      label: 'Datum i vreme nezgode',
                      value: accident.dateTime,
                      includeTime: true,
                      lastDate: DateTime.now(),
                      onChanged: (dt) => _patch('accident.dateTime', dt.toIso8601String()),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PatchTextField(
                      label: 'Mesto / adresa',
                      path: 'accident.location.address',
                      remoteValue: accident.location.address,
                      onPatch: _patch,
                      hintText: 'Ulica, mesto…',
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    Row(
                      children: [
                        Expanded(
                          child: accident.location.lat != null && accident.location.lng != null
                              ? MonoDataRow(
                                  label: 'GPS koordinate',
                                  value:
                                      '${accident.location.lat!.toStringAsFixed(4)}, ${accident.location.lng!.toStringAsFixed(4)}',
                                )
                              : Text(
                                  'Koordinate nisu snimljene',
                                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                                ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        OutlinedButton.icon(
                          onPressed: _locating ? null : _useGps,
                          icon: _locating
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy),
                                )
                              : const Icon(Icons.my_location, size: 16, color: AppColors.navy),
                          label: Text(
                            'GPS',
                            style: AppTypography.buttonLabel.copyWith(color: AppColors.navy, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.navy, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button)),
                            minimumSize: const Size(0, AppSpacing.minTapTarget - 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Posledice',
                  children: [
                    PatchToggleRow(
                      label: 'Ima povređenih',
                      path: 'accident.injuries',
                      value: accident.injuries,
                      onPatch: _patch,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PatchToggleRow(
                      label: 'Oštećena druga vozila',
                      path: 'accident.otherVehicleDamage',
                      value: accident.otherVehicleDamage,
                      onPatch: _patch,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PatchToggleRow(
                      label: 'Oštećena imovina trećih lica',
                      path: 'accident.thirdPartyDamage',
                      value: accident.thirdPartyDamage,
                      onPatch: _patch,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Svedoci',
                  children: [
                    if (_witnesses.isEmpty)
                      Text(
                        'Nema dodatih svedoka.',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                      ),
                    for (var i = 0; i < _witnesses.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.md),
                      _WitnessRow(
                        draft: _witnesses[i],
                        onChanged: _onWitnessFieldChanged,
                        onRemove: () => _removeWitness(i),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _addWitness,
                      icon: const Icon(Icons.add, size: 18, color: AppColors.navy),
                      label: Text('Dodaj svedoka', style: AppTypography.buttonLabel.copyWith(color: AppColors.navy)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.navy, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.button)),
                        minimumSize: const Size(double.infinity, AppSpacing.minTapTarget - 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: AppButton(label: 'Sačuvaj i nastavi', onPressed: widget.onNext),
        ),
      ],
    );
  }
}

class _WitnessDraft {
  _WitnessDraft({required String name, required String phone})
      : nameController = TextEditingController(text: name),
        phoneController = TextEditingController(text: phone),
        nameFocus = FocusNode(),
        phoneFocus = FocusNode();

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final FocusNode nameFocus;
  final FocusNode phoneFocus;

  Map<String, dynamic> toJson() => {'name': nameController.text, 'phone': phoneController.text};

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
  }
}

class _WitnessRow extends StatelessWidget {
  const _WitnessRow({required this.draft, required this.onChanged, required this.onRemove});

  final _WitnessDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: AppTextField(
            label: 'Ime i prezime',
            controller: draft.nameController,
            focusNode: draft.nameFocus,
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: AppTextField(
            label: 'Telefon',
            controller: draft.phoneController,
            focusNode: draft.phoneFocus,
            monospace: true,
            keyboardType: TextInputType.phone,
            onChanged: (_) => onChanged(),
          ),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
          tooltip: 'Ukloni svedoka',
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(label: title),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}
