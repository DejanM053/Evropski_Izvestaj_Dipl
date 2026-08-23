import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../widgets/widgets.dart';

/// Scaffolding only: renders every shared widget in every state so the
/// design-token extraction can be checked visually on a device. No longer
/// the app's home route as of Phase 6 (see `main.dart`/`home_screen.dart`)
/// — reachable only via the debug-only gallery icon on the Home screen's
/// header, which is itself gated on `kDebugMode` and absent from release
/// builds.
class DevGalleryScreen extends StatefulWidget {
  const DevGalleryScreen({super.key});

  @override
  State<DevGalleryScreen> createState() => _DevGalleryScreenState();
}

class _DevGalleryScreenState extends State<DevGalleryScreen> {
  final Set<int> _checkedCircumstances = {0, 3};
  final _plateController = TextEditingController(text: 'BG 482-ŽD');
  final _nameController = TextEditingController(text: 'Miloš Jovanović');

  @override
  void dispose() {
    _plateController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Component gallery')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _GallerySection(
            title: 'Colors',
            child: _ColorSwatches(),
          ),
          _GallerySection(
            title: 'Typography',
            child: _TypographySpecimen(),
          ),
          _GallerySection(
            title: 'Spacing & radii',
            child: _SpacingRadiiDemo(),
          ),
          _GallerySection(
            title: 'Buttons',
            child: Column(
              children: [
                const AppButton(label: 'Primarna akcija', onPressed: _noop),
                const SizedBox(height: AppSpacing.sm),
                const AppButton(label: 'Primarna (onemogućena)', onPressed: null),
                const SizedBox(height: AppSpacing.sm),
                const AppButton(
                  label: 'Sekundarna',
                  onPressed: _noop,
                  variant: AppButtonVariant.secondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                const AppButton(
                  label: 'Sekundarna (onemogućena)',
                  onPressed: null,
                  variant: AppButtonVariant.secondary,
                ),
                const SizedBox(height: AppSpacing.sm),
                const AppButton(
                  label: 'Obriši izveštaj',
                  onPressed: _noop,
                  variant: AppButtonVariant.destructive,
                ),
                const SizedBox(height: AppSpacing.sm),
                const AppButton(
                  label: 'Destruktivna (onemogućena)',
                  onPressed: null,
                  variant: AppButtonVariant.destructive,
                ),
              ],
            ),
          ),
          _GallerySection(
            title: 'Text fields',
            child: Column(
              children: [
                AppTextField(
                  label: 'Ime i prezime',
                  controller: _nameController,
                  helperText: 'Normalno stanje — dodirnite polje ispod za fokus.',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Reg. tablica',
                  controller: _plateController,
                  monospace: true,
                  helperText: 'Monospace vrednost (tablice, šifre, heš).',
                ),
                const SizedBox(height: AppSpacing.md),
                const AppTextField(
                  label: 'Broj police',
                  hintText: 'AO-2026-000-000000',
                  errorText: 'Obavezno polje.',
                ),
                const SizedBox(height: AppSpacing.md),
                const AppTextField(
                  label: 'Ime i prezime',
                  hintText: 'Popunjava drugi vozač',
                  enabled: false,
                ),
              ],
            ),
          ),
          _GallerySection(
            title: 'Circumstances checkbox tile',
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.5,
              children: List.generate(4, (i) {
                final labels = [
                  'Kretao se pravo istom saobraćajnom trakom',
                  'Bio je parkiran / zaustavljen',
                  'Kočio zbog vozila ispred',
                  'Menjao saobraćajnu traku',
                ];
                return CircumstanceTile(
                  label: labels[i],
                  checked: _checkedCircumstances.contains(i),
                  onTap: () => setState(() {
                    if (!_checkedCircumstances.remove(i)) {
                      _checkedCircumstances.add(i);
                    }
                  }),
                );
              }),
            ),
          ),
          _GallerySection(
            title: 'Section header + card',
            child: Container(
              decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(label: 'Vreme i mesto'),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md + 1),
                    child: const MonoDataRow(label: 'Datum i čas', value: '17.08.2026 · 14:04'),
                  ),
                ],
              ),
            ),
          ),
          _GallerySection(
            title: 'Status chips',
            child: const Column(
              children: [
                StatusChip(label: 'Čeka potpis B', variant: AppStatusChipVariant.pending),
                SizedBox(height: AppSpacing.sm),
                StatusChip(label: 'Potvrđeno · 14:12', variant: AppStatusChipVariant.confirmed),
                SizedBox(height: AppSpacing.sm),
                StatusChip(label: 'Neizmenjen — hešovi se poklapaju', variant: AppStatusChipVariant.verified),
                SizedBox(height: AppSpacing.sm),
                StatusChip(label: 'Falsifikovano — heš se ne poklapa', variant: AppStatusChipVariant.tampered),
              ],
            ),
          ),
          _GallerySection(
            title: 'Monospace data row',
            child: Container(
              decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border)),
              padding: const EdgeInsets.all(AppSpacing.md + 1),
              child: const Column(
                children: [
                  MonoDataRow(label: 'Transakcija', value: '0x7f3a…c19e'),
                  SizedBox(height: AppSpacing.sm),
                  MonoDataRow(label: 'Potpisi', value: '2 od 2'),
                  SizedBox(height: AppSpacing.md),
                  Divider(height: 1),
                  SizedBox(height: AppSpacing.md),
                  MonoDataRow(
                    label: 'Heš iz dokumenta',
                    value: '4f9c1a7b2e83d5610af4c8b977e2d40cbb31a9f0e6d70b',
                    stacked: true,
                  ),
                ],
              ),
            ),
          ),
          _GallerySection(
            title: 'Session progress header',
            padded: false,
            child: const SessionProgressHeader(
              sessionCode: 'K7M-4RQ2',
              self: SessionPartyProgress(
                label: 'VI · VOZAČ A',
                stageLabel: 'Okolnosti',
                progress: 0.62,
                isSelf: true,
              ),
              other: SessionPartyProgress(
                label: 'DRUGI VOZAČ · B',
                stageLabel: 'Popunjava podatke…',
                progress: 0.34,
                isSelf: false,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

void _noop() {}

class _GallerySection extends StatelessWidget {
  const _GallerySection({required this.title, required this.child, this.padded = true});

  final String title;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          padded ? child : ClipRect(child: child),
        ],
      ),
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches();

  static const _swatches = <String, Color>{
    'navy': AppColors.navy,
    'cobalt': AppColors.cobalt,
    'amber': AppColors.amber,
    'paper': AppColors.paper,
    'surface': AppColors.surface,
    'surfaceAlt': AppColors.surfaceAlt,
    'border': AppColors.border,
    'textPrimary': AppColors.textPrimary,
    'textMuted': AppColors.textMuted,
    'successBorder': AppColors.successBorder,
    'pendingBorder': AppColors.pendingBorder,
    'errorBorder': AppColors.errorBorder,
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: _swatches.entries.map((entry) {
        return SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 96,
                decoration: BoxDecoration(
                  color: entry.value,
                  border: Border.all(color: AppColors.border),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(entry.key, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TypographySpecimen extends StatelessWidget {
  const _TypographySpecimen();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Evropski izveštaj', style: AppTypography.displayLarge.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text('Neizmenjen', style: AppTypography.headlineLarge.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text('Novi izveštaj', style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text('Pregled izveštaja', style: AppTypography.titleSmall.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Potpisom potvrđujete tačnost svoje polovine izveštaja.',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('BG 482-ŽD · 0x7f3a…c19e', style: AppTypography.monoValueMedium.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        Text('KORAK 3 / 8 · OZNAČITE SVE ŠTO VAŽI', style: AppTypography.monoEyebrow.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: AppSpacing.sm),
        Text('M. Jovanović', style: AppTypography.signatureInline.copyWith(color: AppColors.navy)),
      ],
    );
  }
}

class _SpacingRadiiDemo extends StatelessWidget {
  const _SpacingRadiiDemo();

  static const _steps = [AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl];
  static const _radii = {'none (fields)': AppRadii.none, 'button': AppRadii.button, 'badge': AppRadii.badge};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _steps
              .map((s) => Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: Container(width: s, height: s, color: AppColors.navy),
                  ))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: _radii.entries
              .map((e) => Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(e.value),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(e.key, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
