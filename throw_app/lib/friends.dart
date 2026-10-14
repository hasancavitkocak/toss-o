import 'dart:async';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'api.dart';
import 'i18n.dart';
import 'models.dart';
import 'person_sheet.dart';
import 'widgets.dart';

/// Arkadaşlar sayfası: gelen/gönderilen istekler, arkadaş listesi, kişi arama.
/// Kişi kartından "mektup yaz" seçilirse o kişiyi döndürür.
Future<Person?> showFriendsSheet(BuildContext context,
        {required Api api,
        required List<Person> friends,
        required LatLng home}) =>
    showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _FriendsSheet(api: api, friends: friends, home: home),
    );

class _FriendsSheet extends StatefulWidget {
  final Api api;
  final List<Person> friends;
  final LatLng home;
  const _FriendsSheet(
      {required this.api, required this.friends, required this.home});
  @override
  State<_FriendsSheet> createState() => _FriendsSheetState();
}

class _FriendsSheetState extends State<_FriendsSheet>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 3, vsync: this);
  List<FriendRequest> incoming = [], outgoing = [];
  late List<Person> friends = widget.friends;
  bool loading = true;
  String? error;

  // arama
  final q = TextEditingController();
  List<SearchResult> results = [];
  bool searching = false;
  Timer? _debounce;
  final _busy = <String>{};

  Api get api => widget.api;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    tabs.dispose();
    q.dispose();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    try {
      final r = await api.requests();
      final fr = await api.friends();
      if (!mounted) return;
      setState(() {
        incoming = r.incoming;
        outgoing = r.outgoing;
        friends = fr;
        loading = false;
        error = null;
      });
      // İstek yoksa doğrudan aramaya aç
      if (first && incoming.isEmpty) tabs.index = 2;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.message;
        });
      }
    }
  }

  Future<void> _act(String key, Future<void> Function() f,
      {String? toast}) async {
    setState(() => _busy.add(key));
    try {
      await f();
      if (toast != null && mounted) showToast(context, toast);
      await _load();
      if (q.text.trim().isNotEmpty) await _runSearch(q.text);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(v));
  }

  Future<void> _runSearch(String v) async {
    if (v.trim().isEmpty) return setState(() => results = []);
    setState(() => searching = true);
    try {
      final r = await api.search(v.trim());
      if (mounted) setState(() => results = r);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> _sendRequest(Person p) => _act(p.id, () async {
        final status = await api.sendRequest(p.username);
        if (mounted) {
          showToast(
              context,
              status == 'accepted'
                  ? txt.nowFriends(p.name)
                  : txt.requestSent(p.name));
        }
      });

  /// Kişi kartı: mektup yaz seçilirse sayfa o kişiyle kapanır
  Future<void> _openPerson(Person p) async {
    final r =
        await showPersonSheet(context, api: api, person: p, home: widget.home);
    if (!mounted || r == null) return;
    if (r == PersonAction.write) return Navigator.pop(context, p);
    await _load();
    if (q.text.trim().isNotEmpty) await _runSearch(q.text);
  }

  // ---------- parçalar ----------

  Widget _person(Person p, {String? sub, Widget? trailing}) => ListTile(
        onTap: () => _openPerson(p),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Avatar(person: p, size: 44),
        title: Text(p.name, style: ui(15, weight: FontWeight.w700)),
        subtitle: Text(sub ?? '@${p.username} · ${p.location}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ui(12, color: kMuted)),
        trailing: trailing,
      );

  Widget _pill(String label, VoidCallback? onTap,
          {bool primary = false, bool busy = false}) =>
      GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: primary ? kNavy : kGround,
            borderRadius: BorderRadius.circular(18),
          ),
          child: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: primary ? Colors.white : kNavy))
              : Text(label,
                  style: ui(13,
                      weight: FontWeight.w700,
                      color: primary ? Colors.white : kNavy)),
        ),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Text(text,
            textAlign: TextAlign.center, style: ui(14, color: kMuted)),
      );

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
        child:
            Text(text, style: ui(12, weight: FontWeight.w800, color: kMuted)),
      );

  Widget _requestsTab() => ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        children: [
          if (incoming.isEmpty && outgoing.isEmpty) _empty(txt.noRequests),
          if (incoming.isNotEmpty) _section(txt.incomingSection),
          for (final r in incoming)
            _person(r.user,
                sub: '${r.user.location} · ${txt.ago(r.createdAt)}',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _pill(
                      txt.accept,
                      () => _act('a${r.id}', () => api.acceptRequest(r.id),
                          toast: txt.nowFriends(r.user.name)),
                      primary: true,
                      busy: _busy.contains('a${r.id}')),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: txt.decline,
                    onPressed: _busy.contains('d${r.id}')
                        ? null
                        : () =>
                            _act('d${r.id}', () => api.declineRequest(r.id)),
                    icon: const Icon(Icons.close, color: kMuted),
                  ),
                ])),
          if (outgoing.isNotEmpty) _section(txt.outgoingSection),
          for (final r in outgoing)
            _person(r.user,
                sub: '${txt.waitingApproval} · ${txt.ago(r.createdAt)}',
                trailing: _pill(txt.undo,
                    () => _act('c${r.id}', () => api.cancelRequest(r.id)),
                    busy: _busy.contains('c${r.id}'))),
        ],
      );

  Widget _friendsTab() => ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
        children: [
          if (friends.isEmpty) _empty(txt.noFriends),
          for (final p in friends)
            _person(p,
                trailing: const Icon(Icons.chevron_right, color: kMuted)),
          if (friends.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(txt.tapPersonHint,
                  textAlign: TextAlign.center, style: ui(11.5, color: kMuted)),
            ),
        ],
      );

  Widget _searchTab() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Column(children: [
          TextField(
            controller: q,
            onChanged: _search,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: txt.searchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
              filled: true,
              fillColor: kGround,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? _empty(q.text.trim().isEmpty
                    ? txt.searchEmpty
                    : searching
                        ? ''
                        : txt.nobodyFound)
                : ListView(
                    padding: const EdgeInsets.only(top: 6, bottom: 24),
                    children: [
                      for (final r in results)
                        _person(r.user,
                            trailing: switch (r.relation) {
                              Relation.friend => Text(txt.yourFriend,
                                  style: ui(12,
                                      weight: FontWeight.w700,
                                      color: const Color(0xFF22B45A))),
                              Relation.outgoing => _pill(
                                  txt.requestSentShort,
                                  () => _act('c${r.requestId}',
                                      () => api.cancelRequest(r.requestId!),
                                      toast: txt.requestCancelled),
                                  busy: _busy.contains('c${r.requestId}')),
                              Relation.incoming => _pill(
                                  txt.accept,
                                  () => _act('a${r.requestId}',
                                      () => api.acceptRequest(r.requestId!),
                                      toast: txt.nowFriends(r.user.name)),
                                  primary: true,
                                  busy: _busy.contains('a${r.requestId}')),
                              Relation.none => _pill(
                                  txt.sendRequest, () => _sendRequest(r.user),
                                  primary: true,
                                  busy: _busy.contains(r.user.id)),
                            }),
                    ],
                  ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 10, 0),
              child: Row(children: [
                Text(txt.friends, style: ui(20, weight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: kNavy),
                ),
              ]),
            ),
            TabBar(
              controller: tabs,
              labelColor: kNavy,
              unselectedLabelColor: kMuted,
              indicatorColor: kRed,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              labelStyle: ui(13.5, weight: FontWeight.w700),
              tabs: [
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(txt.requests),
                    if (incoming.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: kRed,
                            borderRadius: BorderRadius.circular(9)),
                        child: Text('${incoming.length}',
                            style: ui(11,
                                weight: FontWeight.w800, color: Colors.white)),
                      ),
                    ],
                  ]),
                ),
                Tab(text: txt.friendsCount(friends.length)),
                Tab(text: txt.add),
              ],
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator(color: kNavy))
                  : error != null
                      ? _empty(error!)
                      : TabBarView(controller: tabs, children: [
                          _requestsTab(),
                          _friendsTab(),
                          _searchTab(),
                        ]),
            ),
          ]),
        ),
      );
}
