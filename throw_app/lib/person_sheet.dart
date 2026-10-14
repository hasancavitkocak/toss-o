import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'api.dart';
import 'i18n.dart';
import 'models.dart';
import 'widgets.dart';

/// Kişi kartından dönen sonuç: o kişiye mektup yaz ya da ilişki değişti
enum PersonAction { write, changed }

/// Kişinin profil kartı: konum, aradaki mektuplar, arkadaşlık işlemleri, engelle
Future<PersonAction?> showPersonSheet(BuildContext context,
        {required Api api, required Person person, required LatLng home}) =>
    showModalBottomSheet<PersonAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _PersonSheet(api: api, person: person, home: home),
    );

class _PersonSheet extends StatefulWidget {
  final Api api;
  final Person person;
  final LatLng home;
  const _PersonSheet(
      {required this.api, required this.person, required this.home});
  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  UserProfile? profile;
  String? error;
  bool busy = false, changed = false;

  /// İki adımlı onay bekleyen işlem: 'unfriend' | 'block'
  String? confirm;
  Timer? _confirmTimer;

  Api get api => widget.api;
  Person get p => profile?.user ?? widget.person;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await api.user(widget.person.id);
      if (mounted) setState(() => profile = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _run(Future<void> Function() f,
      {String? toast, bool close = false}) async {
    setState(() {
      busy = true;
      confirm = null;
    });
    try {
      await f();
      changed = true;
      if (!mounted) return;
      if (toast != null) showToast(context, toast);
      if (close) return Navigator.pop(context, PersonAction.changed);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// İlk dokunuş onay ister, 4 sn içinde ikinci dokunuş işlemi yapar
  void _confirmed(String key, VoidCallback action) {
    if (confirm == key) return action();
    _confirmTimer?.cancel();
    setState(() => confirm = key);
    _confirmTimer = Timer(const Duration(seconds: 4),
        () => mounted ? setState(() => confirm = null) : null);
  }

  void _close() =>
      Navigator.pop(context, changed ? PersonAction.changed : null);

  Widget _chip(String icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: kGround, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(text, style: ui(12.5, weight: FontWeight.w600)),
        ]),
      );

  Widget _textAction(String label, String key, VoidCallback action,
          {Color color = kNavy, IconData? icon}) =>
      TextButton.icon(
        onPressed: busy ? null : () => _confirmed(key, action),
        icon: Icon(icon, size: 18, color: color),
        label: Text(confirm == key ? txt.areYouSure : label,
            style: ui(14, weight: FontWeight.w700, color: color)),
      );

  Widget _primary() {
    final pr = profile!;
    if (pr.blocked) {
      return PrimaryButton(
        label: txt.unblock,
        busy: busy,
        onTap: () =>
            _run(() => api.unblock(p.id), toast: txt.unblocked(p.name)),
      );
    }
    return switch (pr.relation) {
      Relation.friend => PrimaryButton(
          label: txt.writeLetterTo(p.name),
          onTap: () => Navigator.pop(context, PersonAction.write),
        ),
      Relation.incoming => Row(children: [
          Expanded(
            child: PrimaryButton(
              label: txt.acceptRequest,
              busy: busy,
              onTap: () => _run(() => api.acceptRequest(pr.requestId!),
                  toast: txt.nowFriends(p.name)),
            ),
          ),
          const SizedBox(width: 10),
          GlassButton(
            size: 52,
            onTap: () => _run(() => api.declineRequest(pr.requestId!)),
            child: const Icon(Icons.close, color: kMuted),
          ),
        ]),
      Relation.outgoing => PrimaryButton(
          label: txt.requestSentUndo,
          busy: busy,
          onTap: () => _run(() => api.cancelRequest(pr.requestId!),
              toast: txt.requestCancelled),
        ),
      Relation.none => PrimaryButton(
          label: txt.sendFriendRequest,
          busy: busy,
          onTap: () => _run(() async {
            final s = await api.sendRequest(p.username);
            if (mounted) {
              showToast(
                  context,
                  s == 'accepted'
                      ? txt.nowFriends(p.name)
                      : txt.requestSent(p.name));
            }
          }),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pr = profile;
    final dist = distanceKm(widget.home, p.at);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: kNavy)),
            ),
            Avatar(person: p, size: 92),
            const SizedBox(height: 10),
            Text(p.name, style: ui(21, weight: FontWeight.w800)),
            Text('@${p.username}', style: ui(13, color: kMuted)),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.place_outlined, size: 15, color: kRed),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                    [p.location, if (p.countryName != null) p.countryName]
                        .join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: ui(13, weight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 14),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(error!, style: ui(14, color: kRed)),
              )
            else if (pr == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: CircularProgressIndicator(color: kNavy),
              )
            else ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('📍', txt.away(txt.km(dist))),
                  _chip('✈️', txt.youSent(pr.sent)),
                  _chip('📬', txt.theySent(pr.received)),
                  if (pr.friendsSince != null)
                    _chip('🤝', txt.friendsSince(pr.friendsSince!)),
                ],
              ),
              const SizedBox(height: 20),
              _primary(),
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.center, children: [
                if (pr.relation == Relation.friend && !pr.blocked)
                  _textAction(
                      txt.unfriend,
                      'unfriend',
                      () => _run(() => api.unfriend(p.id),
                          toast: txt.unfriended(p.name)),
                      icon: Icons.person_remove_outlined),
                if (!pr.blocked)
                  _textAction(
                      txt.block,
                      'block',
                      () => _run(() => api.block(p.id),
                          toast: txt.blockedToast(p.name), close: true),
                      color: kRed,
                      icon: Icons.block),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
