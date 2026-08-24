import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/report_model.dart';
import '../../state/session_controller.dart';
import '../../theme/theme.dart';
import '../../utils/sample_data.dart';
import '../../widgets/widgets.dart';

String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Obavezno polje' : null;

String? _plateError(String? v) {
  if (v == null || v.trim().isEmpty) return 'Obavezno polje';
  final ok = RegExp(r'^[A-ZČĆŽŠĐ0-9][A-ZČĆŽŠĐ0-9 -]{2,10}$', caseSensitive: false).hasMatch(v.trim());
  return ok ? null : 'Proverite format tablice';
}

String? _emailError(String? v) {
  if (v == null || v.trim().isEmpty) return null;
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
  return ok ? null : 'Neispravna e-mail adresa';
}

/// Screen 6 (docs/master_plan.md §6) — driver / vehicle / insurer /
/// policyholder, own-subtree only (`partyA.*`/`partyB.*`). Matches the
/// design's "1e" section pattern (LIČNI PODACI / VOZILO / OSIGURANJE) —
/// extended with the policyholder and visible-damage/remarks fields the
/// mockup doesn't show but the schema (§5.1) requires, plus per-field
/// validation per the screen 6 spec.
class MyDetailsStep extends StatefulWidget {
  const MyDetailsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<MyDetailsStep> createState() => _MyDetailsStepState();
}

class _MyDetailsStepState extends State<MyDetailsStep> {
  final Map<String, String> _local = {};
  bool _submitted = false;

  void _patch(String path, dynamic value) => context.read<SessionController>().sendPatch(path, value);

  void _track(String path, String value) => setState(() => _local[path] = value);

  String? _valueFor(String path, String? remote) => _local[path] ?? remote ?? '';

  void _fillSampleData(String party) {
    final sample = SamplePartyData.forParty(context.read<SessionController>().selfParty);

    final fields = <String, String>{
      '$party.driver.firstName': sample.firstName,
      '$party.driver.lastName': sample.lastName,
      '$party.driver.address': sample.address,
      '$party.driver.phone': sample.phone,
      '$party.driver.email': sample.email,
      '$party.driver.licenceNumber': sample.licenceNumber,
      '$party.driver.licenceCategory': sample.licenceCategory,
      '$party.vehicle.make': sample.make,
      '$party.vehicle.model': sample.model,
      '$party.vehicle.plate': sample.plate,
      '$party.vehicle.country': sample.country,
      '$party.vehicle.vin': sample.vin,
      '$party.insurer.company': sample.insurerCompany,
      '$party.insurer.policyNumber': sample.policyNumber,
      '$party.insurer.greenCardNumber': sample.greenCardNumber,
      '$party.insurer.agency': sample.agency,
      '$party.visibleDamage': sample.visibleDamage,
      '$party.remarks': sample.remarks,
    };
    for (final entry in fields.entries) {
      _patch(entry.key, entry.value);
    }
    // Dates aren't tracked in `_local` (only required-field text is, for
    // validation) — AppDateField always reads straight from the report, so
    // the round-tripped patch is enough to update its display.
    _patch('$party.driver.licenceValidUntil', sample.licenceValidUntil.toIso8601String());
    _patch('$party.insurer.validFrom', sample.insurerValidFrom.toIso8601String());
    _patch('$party.insurer.validTo', sample.insurerValidTo.toIso8601String());

    setState(() => _local.addAll(fields));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final party = controller.selfParty == 'A' ? 'partyA' : 'partyB';
    final own = controller.report?.partyFor(controller.selfParty) ?? const PartyReportModel();

    final firstName = _valueFor('$party.driver.firstName', own.driver.firstName);
    final lastName = _valueFor('$party.driver.lastName', own.driver.lastName);
    final email = _valueFor('$party.driver.email', own.driver.email);
    final plate = _valueFor('$party.vehicle.plate', own.vehicle.plate);

    final firstNameError = _submitted ? _required(firstName) : null;
    final lastNameError = _submitted ? _required(lastName) : null;
    final plateError = _submitted ? _plateError(plate) : null;
    final emailError = _emailError(email);

    final validFrom = own.insurer.validFrom;
    final validTo = own.insurer.validTo;
    final dateRangeError =
        (validFrom != null && validTo != null && validTo.isBefore(validFrom)) ? 'Datum važenja je pre datuma od' : null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ovo je vaša polovina izveštaja — drugi vozač je vidi u pregledu, ali je ne može menjati.',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                FillSampleDataButton(onPressed: () => _fillSampleData(party)),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Vozač',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: PatchTextField(
                            label: 'Ime',
                            path: '$party.driver.firstName',
                            remoteValue: own.driver.firstName,
                            onPatch: _patch,
                            onChanged: (v) => _track('$party.driver.firstName', v),
                            errorText: firstNameError,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: PatchTextField(
                            label: 'Prezime',
                            path: '$party.driver.lastName',
                            remoteValue: own.driver.lastName,
                            onPatch: _patch,
                            onChanged: (v) => _track('$party.driver.lastName', v),
                            errorText: lastNameError,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PatchTextField(
                      label: 'Adresa',
                      path: '$party.driver.address',
                      remoteValue: own.driver.address,
                      onPatch: _patch,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: PatchTextField(
                            label: 'Telefon',
                            path: '$party.driver.phone',
                            remoteValue: own.driver.phone,
                            onPatch: _patch,
                            monospace: true,
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: PatchTextField(
                            label: 'E-mail',
                            path: '$party.driver.email',
                            remoteValue: own.driver.email,
                            onPatch: _patch,
                            onChanged: (v) => _track('$party.driver.email', v),
                            errorText: emailError,
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: PatchTextField(
                            label: 'Br. vozačke',
                            path: '$party.driver.licenceNumber',
                            remoteValue: own.driver.licenceNumber,
                            onPatch: _patch,
                            monospace: true,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: PatchTextField(
                            label: 'Kategorija',
                            path: '$party.driver.licenceCategory',
                            remoteValue: own.driver.licenceCategory,
                            onPatch: _patch,
                            monospace: true,
                            textCapitalization: TextCapitalization.characters,
                            transform: (v) => v.toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppDateField(
                      label: 'Važi do',
                      value: own.driver.licenceValidUntil,
                      onChanged: (dt) => _patch('$party.driver.licenceValidUntil', dt.toIso8601String()),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Vozilo',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: PatchTextField(
                            label: 'Reg. tablica',
                            path: '$party.vehicle.plate',
                            remoteValue: own.vehicle.plate,
                            onPatch: _patch,
                            onChanged: (v) => _track('$party.vehicle.plate', v),
                            errorText: plateError,
                            monospace: true,
                            textCapitalization: TextCapitalization.characters,
                            transform: (v) => v.toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 3,
                          child: PatchTextField(
                            label: 'Država',
                            path: '$party.vehicle.country',
                            remoteValue: own.vehicle.country,
                            onPatch: _patch,
                            monospace: true,
                            textCapitalization: TextCapitalization.characters,
                            transform: (v) => v.toUpperCase(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: PatchTextField(
                            label: 'Marka',
                            path: '$party.vehicle.make',
                            remoteValue: own.vehicle.make,
                            onPatch: _patch,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: PatchTextField(
                            label: 'Model',
                            path: '$party.vehicle.model',
                            remoteValue: own.vehicle.model,
                            onPatch: _patch,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PatchTextField(
                      label: 'Broj šasije (VIN)',
                      path: '$party.vehicle.vin',
                      remoteValue: own.vehicle.vin,
                      onPatch: _patch,
                      monospace: true,
                      textCapitalization: TextCapitalization.characters,
                      transform: (v) => v.toUpperCase(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Osiguranje',
                  children: [
                    PatchTextField(
                      label: 'Osiguravač',
                      path: '$party.insurer.company',
                      remoteValue: own.insurer.company,
                      onPatch: _patch,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: PatchTextField(
                            label: 'Broj polise',
                            path: '$party.insurer.policyNumber',
                            remoteValue: own.insurer.policyNumber,
                            onPatch: _patch,
                            monospace: true,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: PatchTextField(
                            label: 'Broj zel. karte',
                            path: '$party.insurer.greenCardNumber',
                            remoteValue: own.insurer.greenCardNumber,
                            onPatch: _patch,
                            monospace: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: AppDateField(
                            label: 'Važi od',
                            value: validFrom,
                            errorText: dateRangeError,
                            onChanged: (dt) => _patch('$party.insurer.validFrom', dt.toIso8601String()),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: AppDateField(
                            label: 'Važi do',
                            value: validTo,
                            onChanged: (dt) => _patch('$party.insurer.validTo', dt.toIso8601String()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PatchTextField(
                      label: 'Agencija / filijala',
                      path: '$party.insurer.agency',
                      remoteValue: own.insurer.agency,
                      onPatch: _patch,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Vlasnik polise (ako se razlikuje od vozača)',
                  children: [
                    PatchTextField(
                      label: 'Ime i prezime / naziv',
                      path: '$party.policyholder.name',
                      remoteValue: own.policyholder.name,
                      onPatch: _patch,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PatchTextField(
                      label: 'Adresa',
                      path: '$party.policyholder.address',
                      remoteValue: own.policyholder.address,
                      onPatch: _patch,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PatchTextField(
                      label: 'Telefon',
                      path: '$party.policyholder.phone',
                      remoteValue: own.policyholder.phone,
                      onPatch: _patch,
                      monospace: true,
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Oštećenja i napomene',
                  children: [
                    PatchTextField(
                      label: 'Vidljiva oštećenja na vozilu',
                      path: '$party.visibleDamage',
                      remoteValue: own.visibleDamage,
                      onPatch: _patch,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PatchTextField(
                      label: 'Napomene',
                      path: '$party.remarks',
                      remoteValue: own.remarks,
                      onPatch: _patch,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
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
          child: AppButton(
            label: 'Sačuvaj i nastavi',
            onPressed: () {
              setState(() => _submitted = true);
              final hasErrors =
                  _required(firstName) != null || _required(lastName) != null || _plateError(plate) != null;
              if (hasErrors) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Popunite obavezna polja pre nastavka.')),
                );
                return;
              }
              widget.onNext();
            },
          ),
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
