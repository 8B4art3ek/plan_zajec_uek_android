import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/transit_service.dart';
import '../../domain/entities/transit_journey.dart';
import '../providers/transit_provider.dart';

class TransitPlaceField extends ConsumerStatefulWidget {
  const TransitPlaceField(
      {super.key,
      required this.label,
      required this.icon,
      required this.value,
      required this.onChanged,
      this.enabled = true});
  final String label;
  final IconData icon;
  final TransitPlace? value;
  final ValueChanged<TransitPlace?> onChanged;
  final bool enabled;
  @override
  ConsumerState<TransitPlaceField> createState() => _TransitPlaceFieldState();
}

class _TransitPlaceFieldState extends ConsumerState<TransitPlaceField> {
  late final _controller =
      TextEditingController(text: widget.value?.name ?? '');
  final _focus = FocusNode();
  final _menu = MenuController();
  Timer? _timer;
  int _generation = 0;
  bool _loading = false, _searched = false;
  List<TransitPlace> _places = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    if (_focus.hasFocus) _showOptions();
  }

  void _showOptions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.enabled &&
          _focus.hasFocus &&
          !_loading &&
          _places.isNotEmpty &&
          !_menu.isOpen) {
        _menu.open();
      }
    });
  }

  void _cancel() {
    _generation++;
    _timer?.cancel();
  }

  @override
  void didUpdateWidget(covariant TransitPlaceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        (widget.value != null || _controller.text == oldWidget.value?.name)) {
      _cancel();
      _controller.text = widget.value?.name ?? '';
      _loading = false;
      _searched = false;
      _error = null;
      _places = const [];
    }
  }

  @override
  void dispose() {
    _cancel();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _edited(String text) {
    _cancel();
    _menu.close();
    final query = text.trim();
    final generation = _generation;
    final shouldSearch = query.length >= 3 && text != widget.value?.name;
    setState(() {
      _loading = shouldSearch;
      _searched = false;
      _error = null;
      _places = const [];
    });
    if (text != widget.value?.name) widget.onChanged(null);
    if (!shouldSearch) return;
    _timer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final places =
            await ref.read(transitServiceProvider).searchPlaces(query);
        if (!mounted || generation != _generation) return;
        setState(() {
          _places = places;
          _loading = false;
          _searched = true;
        });
        _showOptions();
      } catch (error) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _loading = false;
          _error = error is TransitException
              ? error.message
              : 'Nie udało się pobrać podpowiedzi.';
        });
      }
    });
  }

  void _select(TransitPlace place) {
    _cancel();
    _menu.close();
    _controller.text = place.name;
    setState(() {
      _loading = false;
      _error = null;
      _places = const [];
      _searched = false;
    });
    widget.onChanged(place);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final availableHeight = MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            120;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MenuAnchor(
                controller: _menu,
                childFocusNode: _focus,
                style: MenuStyle(
                  alignment: AlignmentDirectional.bottomStart,
                  minimumSize: WidgetStatePropertyAll(Size(width, 0)),
                  maximumSize: WidgetStatePropertyAll(Size(
                      width, math.max(48, math.min(300, availableHeight)))),
                  shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
                ),
                alignmentOffset: const Offset(0, 4),
                menuChildren: [
                  for (final place in _places)
                    MenuItemButton(
                      requestFocusOnHover: false,
                      onPressed: () => _select(place),
                      leadingIcon: const Icon(Icons.place_outlined),
                      child: SizedBox(
                          width: math.max(0, width - 80),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(place.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    if (place.description.isNotEmpty)
                                      Text(place.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                  ]))),
                    ),
                ],
                builder: (context, controller, child) => TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  maxLength: 200,
                  textInputAction: TextInputAction.search,
                  onChanged: _edited,
                  onSubmitted: (_) {
                    if (!_loading && _places.isNotEmpty) _select(_places.first);
                  },
                  decoration: InputDecoration(
                      labelText: widget.label,
                      counterText: '',
                      prefixIcon: Icon(widget.icon),
                      suffixIcon: _error != null
                          ? IconButton(
                              tooltip: 'Ponów wyszukiwanie',
                              onPressed: widget.enabled
                                  ? () {
                                      _focus.requestFocus();
                                      _edited(_controller.text);
                                    }
                                  : null,
                              icon: const Icon(Icons.refresh))
                          : _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip:
                                      'Wyczyść ${widget.label.toLowerCase()}',
                                  onPressed: widget.enabled
                                      ? () {
                                          _controller.clear();
                                          _edited('');
                                          _focus.requestFocus();
                                        }
                                      : null,
                                  icon: const Icon(Icons.close, size: 20))),
                ),
              ),
              if (_loading && _focus.hasFocus)
                const LinearProgressIndicator(minHeight: 2),
              if (_focus.hasFocus &&
                  (_error != null || (_searched && _places.isEmpty)))
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        _error ??
                            'Brak pasujących miejsc. Dodaj nazwę miejscowości.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _error != null
                                ? Theme.of(context).colorScheme.error
                                : null))),
            ]);
      });
}
