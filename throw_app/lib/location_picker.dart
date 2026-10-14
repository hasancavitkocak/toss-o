import 'package:flutter/material.dart';
import 'api.dart';
import 'i18n.dart';
import 'models.dart';
import 'widgets.dart';

/// Türkçe büyük/küçük harf duyarsız arama için (İ→i, I→ı)
String trFold(String s) => s
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('û', 'u');

/// Aranabilir liste (ülke ya da il seçimi)
Future<GeoOption?> pickOption(BuildContext context,
        {required String title, required Future<List<GeoOption>> items}) =>
    showModalBottomSheet<GeoOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _PickerSheet(title: title, items: items),
    );

class _PickerSheet extends StatefulWidget {
  final String title;
  final Future<List<GeoOption>> items;
  const _PickerSheet({required this.title, required this.items});
  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String q = '';

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              18, 18, 18, MediaQuery.viewInsetsOf(context).bottom),
          child: Column(children: [
            Text(widget.title, style: ui(19, weight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => q = trFold(v.trim())),
              decoration: InputDecoration(
                hintText: txt.search,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: kGround,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: FutureBuilder<List<GeoOption>>(
                future: widget.items,
                builder: (context, snap) {
                  if (snap.hasError) {
                    final e = snap.error;
                    return Center(
                        child: Text(
                            e is ApiException ? e.message : txt.listFailed,
                            style: ui(14, color: kRed)));
                  }
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(color: kNavy));
                  }
                  final list = q.isEmpty
                      ? snap.data!
                      : snap.data!
                          .where((o) => trFold(o.name).contains(q))
                          .toList();
                  if (list.isEmpty) {
                    return Center(
                        child:
                            Text(txt.noResults, style: ui(14, color: kMuted)));
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(list[i].name, style: ui(15)),
                      onTap: () => Navigator.pop(context, list[i]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      );
}

/// Hizmet verilen tek ülke
const kServiceCountry = GeoOption('TR', 'Türkiye');

/// İl seçim alanı (ülke sabit: Türkiye)
class LocationFields extends StatelessWidget {
  final Api api;
  final GeoOption? country, region;
  final void Function(GeoOption? country, GeoOption? region) onChanged;
  const LocationFields(
      {super.key,
      required this.api,
      required this.country,
      required this.region,
      required this.onChanged});

  Widget _field(
          String label, String? value, IconData icon, VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
              color: kGround, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Icon(icon, color: kNavy.withValues(alpha: .6)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: ui(value == null ? 14 : 11, color: kMuted)),
                    if (value != null)
                      Text(value,
                          overflow: TextOverflow.ellipsis,
                          style: ui(15, weight: FontWeight.w600)),
                  ]),
            ),
            Icon(Icons.chevron_right,
                color: onTap == null ? Colors.black12 : kMuted),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = country ?? kServiceCountry;
    return Column(children: [
      _field(txt.regionLabel(true), region?.name, Icons.place_outlined,
          () async {
        final r = await pickOption(context,
            title: txt.pickRegion(c.code, c.name), items: api.regions(c.code));
        if (r != null) onChanged(c, r);
      }),
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.lock_outline, size: 14, color: kMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(txt.locationPrivacy, style: ui(11.5, color: kMuted)),
        ),
      ]),
    ]);
  }
}
