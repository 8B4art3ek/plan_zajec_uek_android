import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_identity.dart';
import '../../domain/entities/university.dart';
import '../providers/providers.dart';

class UniversityScreen extends ConsumerStatefulWidget {
  const UniversityScreen({super.key});
  @override
  ConsumerState<UniversityScreen> createState() => _UniversityScreenState();
}

class _UniversityScreenState extends ConsumerState<UniversityScreen> {
  University _selected = University.uek;
  bool _saving = false;
  String? _error;

  Future<void> _continue() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (ref.read(universityProvider).hasError) {
        ref.invalidate(universityProvider);
      }
      await ref.read(universityProvider.future);
      await ref.read(universityProvider.notifier).select(_selected);
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Nie udało się zapisać uczelni. Spróbuj ponownie.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(appName)),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Center(
                            child: Image.asset(appIconAsset,
                                width: 72, height: 72)),
                        const SizedBox(height: 24),
                        Text('Wybierz uczelnię',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        RadioGroup<University>(
                          groupValue: _selected,
                          onChanged: (value) {
                            if (!_saving && value != null) {
                              setState(() => _selected = value);
                            }
                          },
                          child: Column(children: [
                            for (final university in University.values)
                              RadioListTile<University>(
                                title: Text(university.shortName),
                                subtitle: Text(university.name),
                                value: university,
                                enabled: !_saving,
                              )
                          ]),
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                          const SizedBox(height: 16)
                        ],
                        FilledButton(
                            onPressed: _saving ? null : _continue,
                            child:
                                Text(_saving ? 'Zapisywanie…' : 'Kontynuuj')),
                      ],
                    )))),
      );
}
