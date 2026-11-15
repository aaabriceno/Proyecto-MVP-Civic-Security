import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/media/photo_picker.dart';
import '../../../core/media/photo_processor.dart';
import '../../../core/network/api_failure.dart';
import '../../incident/domain/incident.dart';
import '../../map/presentation/incident_style.dart';
import '../domain/new_incident.dart';
import 'adjust_location_screen.dart';
import 'report_controller.dart';
import 'report_sent_screen.dart';

const _red = Color(0xFFDC2626);

/// Frame 06. Se cierra con el [Incident] creado si el usuario elige "Ver en
/// el mapa", o con `null` si cancela o cierra la confirmación.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({
    super.key,
    required this.initialLocation,
    required this.isUserLocation,
    this.userPosition,
  });

  final LatLng initialLocation;

  /// ¿Esa ubicación es la del usuario (o la eligió en el mapa)?
  final bool isUserLocation;

  /// Dónde está el usuario, si se conoce (para ajustar y medir distancia).
  final LatLng? userPosition;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _description = TextEditingController();
  late LatLng _location = widget.initialLocation;
  late bool _isUserLocation = widget.isUserLocation;
  IncidentType? _type;
  bool _typeMissing = false;

  // La foto adjunta, ya preparada (sin ubicación ni datos del teléfono)
  Uint8List? _photo;
  bool _preparingPhoto = false;
  String? _photoError;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_type == null) {
      setState(() => _typeMissing = true);
      return;
    }
    ref
        .read(reportControllerProvider.notifier)
        .submit(
          NewIncident(
            tipo: _type!,
            descripcion: _description.text,
            lat: _location.latitude,
            lng: _location.longitude,
          ),
          photo: _photo,
        );
  }

  /// Pide la foto a la cámara o a la galería y la prepara. Cada error tiene su
  /// mensaje y deja intentar de nuevo; ninguno rompe el formulario.
  Future<void> _pickPhoto(PhotoSource source) async {
    setState(() => _photoError = null);

    Uint8List? picked;
    try {
      picked = await ref.read(photoPickerProvider).pick(source);
    } on PhotoPickerException {
      if (mounted) {
        setState(
          () => _photoError = source == PhotoSource.camera
              ? 'No pudimos abrir la cámara. Revisa los permisos de la app.'
              : 'No pudimos abrir la galería.',
        );
      }
      return;
    } on Object {
      if (mounted) {
        setState(
          () => _photoError = 'No pudimos obtener la foto. Intenta de nuevo.',
        );
      }
      return;
    }
    // `null`: la persona canceló
    if (picked == null || !mounted) return;

    setState(() => _preparingPhoto = true);
    try {
      final ready = await ref.read(photoPreparerProvider)(picked);
      if (!mounted) return;
      setState(() {
        _photo = ready;
        _preparingPhoto = false;
      });
    } on UnreadablePhotoException {
      _photoFailed(
        'Esa foto no se puede usar (formato no compatible o dañada). Elige otra.',
      );
    } on PhotoTooLargeException {
      _photoFailed('La foto es demasiado grande. Elige otra.');
    } on Object {
      _photoFailed('No pudimos preparar la foto. Intenta con otra.');
    }
  }

  void _photoFailed(String message) {
    if (!mounted) return;
    setState(() {
      _preparingPhoto = false;
      _photoError = message;
    });
  }

  Future<void> _adjustLocation() async {
    final chosen = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => AdjustLocationScreen(
          initialCenter: _location,
          userPosition: widget.userPosition,
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    final user = widget.userPosition;
    setState(() {
      _location = chosen;
      // Si lo ajustó justo a su posición, sigue siendo "su ubicación actual"
      _isUserLocation =
          user != null &&
          const Distance().as(LengthUnit.Meter, user, chosen) < 5;
    });
  }

  Future<void> _onCreated(Incident incident) async {
    final viewOnMap = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReportSentScreen(incident: incident)),
    );
    if (!mounted) return;
    Navigator.of(context).pop(viewOnMap == true ? incident : null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reportControllerProvider, (previous, next) {
      if (next.created != null && previous?.created == null) {
        _onCreated(next.created!);
      }
    });

    final state = ref.watch(reportControllerProvider);
    final failure = state.failure;
    final fields = failure?.fields ?? const <String, List<String>>{};

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                TextButton.icon(
                  key: const Key('cancelar-reporte'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancelar'),
                ),
                const Spacer(),
                const _AnonymousBadge(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '¿Qué está pasando?',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _TypeGrid(
              selected: _type,
              onSelected: (t) => setState(() {
                _type = t;
                _typeMissing = false;
              }),
            ),
            if (_typeMissing || fields.containsKey('tipo'))
              _FieldError(
                _typeMissing
                    ? 'Elige un tipo de incidente'
                    : fields['tipo']!.join(' '),
              ),
            const SizedBox(height: 20),
            _sectionTitle('Ubicación'),
            _LocationCard(
              location: _location,
              isUserLocation: _isUserLocation,
              onChange: _adjustLocation,
            ),
            for (final key in const ['ubicacion', 'lat', 'lng'])
              if (fields.containsKey(key)) _FieldError(fields[key]!.join(' ')),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'La ubicación del pin es pública. Si estás en tu casa, ajústala '
                'para no revelar dónde vives.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Descripción (opcional)'),
            TextField(
              key: const Key('descripcion'),
              controller: _description,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText:
                    'Ej. Dos personas en moto arrebataron un celular. Huyeron '
                    'hacia el puente.',
                helperText:
                    'No escribas nombres, DNI, teléfonos ni correos: tu '
                    'reporte es anónimo.',
                helperMaxLines: 2,
                errorText: fields['descripcion']?.join(' '),
                errorMaxLines: 3,
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Foto (opcional)'),
            _PhotoSection(
              photo: _photo,
              preparing: _preparingPhoto,
              error: _photoError,
              // Con el reporte enviándose no se cambia la foto
              enabled: !state.sending,
              onPick: _pickPhoto,
              onRemove: () => setState(() {
                _photo = null;
                _photoError = null;
              }),
            ),
            if (failure != null && fields.isEmpty) _FailureBanner(failure),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('enviar-reporte'),
              style: FilledButton.styleFrom(
                backgroundColor: _red,
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: state.sending ? null : _submit,
              child: state.sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enviar reporte anónimo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: Colors.black54),
    ),
  );
}

/// La foto opcional del reporte: elegirla, ver cómo quedó y quitarla.
class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.photo,
    required this.preparing,
    required this.error,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? photo;
  final bool preparing;
  final String? error;
  final bool enabled;
  final ValueChanged<PhotoSource> onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preparing)
          Container(
            key: const Key('foto-preparando'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 12),
                Text('Preparando la foto…'),
              ],
            ),
          )
        else if (photo != null)
          _PhotoPreview(bytes: photo, enabled: enabled, onRemove: onRemove)
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('foto-camara'),
                  onPressed: enabled ? () => onPick(PhotoSource.camera) : null,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('foto-galeria'),
                  onPressed: enabled ? () => onPick(PhotoSource.gallery) : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error!,
              key: const Key('error-foto'),
              style: const TextStyle(color: _red, fontSize: 12.5),
            ),
          ),
        const Padding(
          key: Key('aviso-foto'),
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Evita fotos con rostros o placas: se verán en el mapa.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.bytes,
    required this.enabled,
    required this.onRemove,
  });

  final Uint8List bytes;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              key: const Key('foto-previa'),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 72,
                height: 72,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Se envía sin ubicación ni datos del teléfono.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            key: const Key('foto-quitar'),
            onPressed: enabled ? onRemove : null,
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
  }
}

class _AnonymousBadge extends StatelessWidget {
  const _AnonymousBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Text('Anónimo', style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({required this.selected, required this.onSelected});

  final IncidentType? selected;
  final ValueChanged<IncidentType> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: [
        for (final type in IncidentType.values)
          _TypeTile(
            key: Key('tipo-${type.wire}'),
            type: type,
            selected: type == selected,
            onTap: () => onSelected(type),
          ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final IncidentType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = typeColor(type);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.08)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: color,
              child: Icon(typeIcon(type), size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reportLabel(type),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.location,
    required this.isUserLocation,
    required this.onChange,
  });

  final LatLng location;
  final bool isUserLocation;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.place, color: _red),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUserLocation
                      ? 'Tu ubicación actual'
                      : 'Ubicación elegida en el mapa',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  formatCoordinates(location),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('cambiar-ubicacion'),
            onPressed: onChange,
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(message, style: const TextStyle(color: _red, fontSize: 12.5)),
  );
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner(this.failure);

  final ApiFailure failure;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('error-envio'),
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(failure.message, style: const TextStyle(color: _red)),
  );
}
