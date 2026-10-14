import 'package:flutter/material.dart';
import 'api.dart';
import 'i18n.dart';
import 'legal_texts.dart';
import 'widgets.dart';

String legalTitle(LegalDoc d) => (txt.en ? legalTitlesEn : legalTitlesTr)[d]!;
String legalText(LegalDoc d) => (txt.en ? legalTextsEn : legalTextsTr)[d]!;

Future<T?> _sheet<T>(BuildContext context, Widget child, {double h = .88}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * h,
          child: SafeArea(top: false, child: child)),
    );

Widget _handle() => Container(
    width: 40,
    height: 4,
    margin: const EdgeInsets.only(top: 10),
    decoration: BoxDecoration(
        color: Colors.black12, borderRadius: BorderRadius.circular(2)));

/// Tek bir yasal metni okut
Future<void> showLegalDoc(BuildContext context, LegalDoc doc) => _sheet(
      context,
      Column(children: [
        _handle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 8, 4),
          child: Row(children: [
            Expanded(
                child: Text(legalTitle(doc),
                    style: ui(18, weight: FontWeight.w800))),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: kNavy)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            child: SelectableText(legalText(doc).trim(),
                style: ui(13.5, color: const Color(0xFF283548))
                    .copyWith(height: 1.5)),
          ),
        ),
      ]),
    );

/// Onay kutusu satırı: metin + "oku" bağlantısı
class ConsentTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final LegalDoc doc;
  final bool required;
  const ConsentTile(
      {super.key,
      required this.value,
      required this.onChanged,
      required this.label,
      required this.doc,
      this.required = true});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: kNavy,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: label),
                      if (!required)
                        TextSpan(
                            text: txt.en ? ' (optional)' : ' (isteğe bağlı)',
                            style: ui(12, color: kMuted)),
                      const TextSpan(text: '  '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: () => showLegalDoc(context, doc),
                          child: Text(txt.read,
                              style: ui(12.5,
                                      weight: FontWeight.w700, color: kRed)
                                  .copyWith(
                                      decoration: TextDecoration.underline)),
                        ),
                      ),
                    ]),
                    style: ui(12.5, color: const Color(0xFF34405A))),
              ),
            ),
          ),
        ],
      );
}

/// Profil > KVKK ve yasal metinler: metinler, yurt dışı rızası, veri dökümü
Future<void> showLegalSheet(BuildContext context, Api api) =>
    _sheet(context, _LegalSheet(api: api), h: .8);

class _LegalSheet extends StatefulWidget {
  final Api api;
  const _LegalSheet({required this.api});
  @override
  State<_LegalSheet> createState() => _LegalSheetState();
}

class _LegalSheetState extends State<_LegalSheet> {
  Widget _doc(LegalDoc d, IconData icon) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: Icon(icon, color: kNavy),
        title: Text(legalTitle(d), style: ui(15, weight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, color: kMuted),
        onTap: () => showLegalDoc(context, d),
      );

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _handle(),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
        child: Text(txt.legal, style: ui(19, weight: FontWeight.w800)),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            _doc(LegalDoc.notice, Icons.privacy_tip_outlined),
            _doc(LegalDoc.terms, Icons.description_outlined),
          ],
        ),
      ),
    ]);
  }
}

/// Yasal metinler güncellendiyse (ya da eski hesapsa) yeniden onay iste.
/// Onaylamadan uygulama kullanılamaz; "çıkış yap" seçeneği vardır.
Future<void> askLegalConsent(BuildContext context, Api api,
        {required VoidCallback onLogout}) =>
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => PopScope(
          canPop: false, child: _Reconsent(api: api, onLogout: onLogout)),
    );

class _Reconsent extends StatefulWidget {
  final Api api;
  final VoidCallback onLogout;
  const _Reconsent({required this.api, required this.onLogout});
  @override
  State<_Reconsent> createState() => _ReconsentState();
}

class _ReconsentState extends State<_Reconsent> {
  bool notice = false, terms = false, busy = false;

  Future<void> _ok() async {
    setState(() => busy = true);
    try {
      await widget.api.updateMe(acceptLegal: true);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.privacy_tip_outlined, color: kNavy, size: 36),
            const SizedBox(height: 8),
            Text(
                txt.en
                    ? 'Our privacy texts were updated'
                    : 'Gizlilik metinlerimiz güncellendi',
                textAlign: TextAlign.center,
                style: ui(18, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
                txt.en
                    ? 'Please read and confirm to keep using toss-o.'
                    : "toss-o'yu kullanmaya devam etmek için lütfen okuyup onayla.",
                textAlign: TextAlign.center,
                style: ui(13, color: kMuted)),
            const SizedBox(height: 12),
            ConsentTile(
                value: notice,
                onChanged: (v) => setState(() => notice = v),
                label: txt.consentNotice,
                doc: LegalDoc.notice),
            ConsentTile(
                value: terms,
                onChanged: (v) => setState(() => terms = v),
                label: txt.consentTerms,
                doc: LegalDoc.terms),
            const SizedBox(height: 14),
            PrimaryButton(
                label: txt.en ? 'Confirm' : 'Onayla',
                busy: busy,
                onTap: notice && terms ? _ok : null),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onLogout();
              },
              child: Text(txt.logout, style: ui(13, color: kMuted)),
            ),
          ]),
        ),
      );
}
