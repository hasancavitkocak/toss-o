import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'i18n.dart';
import 'legal.dart';
import 'models.dart';
import 'widgets.dart';

/// Profil sayfası: fotoğraf, isim, istatistik ve hesap ayarları.
/// [onChanged] güncellenen kullanıcıyı ana ekrana iletir.
Future<void> showProfileSheet(
  BuildContext context, {
  required Api api,
  required Person me,
  required Stats stats,
  required ValueChanged<Person> onChanged,
  required VoidCallback onChangeLocation,
  required VoidCallback onLogout,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _ProfileSheet(
        api: api,
        me: me,
        stats: stats,
        onChanged: onChanged,
        onChangeLocation: onChangeLocation,
        onLogout: onLogout,
      ),
    );

Future<T?> _subSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(top: false, child: child),
      ),
    );

InputDecoration _field(String hint, {IconData? icon}) => InputDecoration(
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: kGround,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );

class _ProfileSheet extends StatefulWidget {
  final Api api;
  final Person me;
  final Stats stats;
  final ValueChanged<Person> onChanged;
  final VoidCallback onChangeLocation, onLogout;
  const _ProfileSheet(
      {required this.api,
      required this.me,
      required this.stats,
      required this.onChanged,
      required this.onChangeLocation,
      required this.onLogout});
  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late Person me = widget.me;
  bool photoBusy = false, editing = false, nameBusy = false;
  late final name = TextEditingController(text: me.name);

  Api get api => widget.api;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _update(Person p) {
    setState(() => me = p);
    widget.onChanged(p);
  }

  // ---------- fotoğraf ----------

  Future<void> _photoMenu() async {
    final choice = await _subSheet<String>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(txt.profilePhoto, style: ui(18, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: kNavy),
            title:
                Text(txt.fromGallery, style: ui(15, weight: FontWeight.w600)),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          if (!kIsWeb)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: kNavy),
              title:
                  Text(txt.takePhoto, style: ui(15, weight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
          if (me.photo != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: kRed),
              title: Text(txt.removePhoto,
                  style: ui(15, weight: FontWeight.w600, color: kRed)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') return _photoTask(api.deletePhoto);

    final XFile? file;
    try {
      // Yüklemeden önce küçült: hem hızlı hem sunucu sınırının altında
      file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (_) {
      if (mounted) showToast(context, txt.photoFailed);
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 2400 * 1024) {
      if (mounted) {
        showToast(context, txt.photoTooBig);
      }
      return;
    }
    await _photoTask(() => api.uploadPhoto(bytes));
  }

  Future<void> _photoTask(Future<Person> Function() f) async {
    setState(() => photoBusy = true);
    try {
      final p = await f();
      if (!mounted) return;
      _update(p);
      showToast(context, p.photo == null ? txt.photoRemoved : txt.photoUpdated);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => photoBusy = false);
    }
  }

  // ---------- isim ----------

  Future<void> _saveName() async {
    final v = name.text.trim();
    if (v.isEmpty || v == me.name) return setState(() => editing = false);
    setState(() => nameBusy = true);
    try {
      _update(await api.updateName(v));
      if (mounted) setState(() => editing = false);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => nameBusy = false);
    }
  }

  // ---------- menü ----------

  Widget _tile(IconData icon, String label, VoidCallback onTap,
          {Color color = kNavy}) =>
      ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: Icon(icon, color: color, size: 22),
        title:
            Text(label, style: ui(15, weight: FontWeight.w600, color: color)),
        trailing: const Icon(Icons.chevron_right, color: kMuted),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final st = widget.stats;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            22, 10, 22, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: photoBusy ? null : _photoMenu,
              child: Stack(clipBehavior: Clip.none, children: [
                Avatar(person: me, size: 96),
                if (photoBusy)
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.black38, shape: BoxShape.circle),
                      child: const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white)),
                    ),
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: kNavy,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3)),
                    child: const Icon(Icons.photo_camera,
                        size: 16, color: Colors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (editing)
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 30,
                    textAlign: TextAlign.center,
                    style: ui(17, weight: FontWeight.w700),
                    onSubmitted: (_) => _saveName(),
                    decoration:
                        _field(txt.yourNameHint).copyWith(counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                nameBusy
                    ? const SizedBox(
                        width: 40,
                        child: Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: kNavy))))
                    : IconButton.filled(
                        onPressed: _saveName,
                        style: IconButton.styleFrom(backgroundColor: kNavy),
                        icon: const Icon(Icons.check, color: Colors.white)),
              ])
            else
              GestureDetector(
                onTap: () => setState(() {
                  name.text = me.name;
                  editing = true;
                }),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(me.name,
                        overflow: TextOverflow.ellipsis,
                        style: ui(21, weight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_outlined, size: 17, color: kMuted),
                ]),
              ),
            Text('@${me.username}', style: ui(13, color: kMuted)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.place_outlined, size: 15, color: kRed),
              const SizedBox(width: 4),
              Flexible(
                child: Text(me.location,
                    overflow: TextOverflow.ellipsis,
                    style: ui(13, weight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              Stat(icon: '✈️', count: st.sent, label: txt.sent),
              Stat(icon: '📬', count: st.received, label: txt.received),
              Stat(icon: '🌍', count: st.cities, label: txt.cities),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 6),
            _tile(Icons.edit_location_alt_outlined, txt.changeRegion, () {
              Navigator.pop(context);
              widget.onChangeLocation();
            }),
            _tile(Icons.lock_outline, txt.changePassword,
                () => _subSheet(context, _PasswordSheet(api: api))),
            _tile(Icons.block, txt.blockedUsers,
                () => _subSheet(context, _BlocksSheet(api: api))),
            _tile(Icons.privacy_tip_outlined, txt.legal,
                () => showLegalSheet(context, api)),
            _tile(Icons.logout, txt.logout, () {
              Navigator.pop(context);
              widget.onLogout();
            }),
            _tile(Icons.delete_forever_outlined, txt.deleteAccount, () async {
              final deleted =
                  await _subSheet<bool>(context, _DeleteAccountSheet(api: api));
              if (deleted == true && context.mounted) {
                Navigator.pop(context);
                widget.onLogout();
              }
            }, color: kRed),
          ]),
        ),
      ),
    );
  }
}

/// Şifre değiştir: mevcut + yeni şifre
class _PasswordSheet extends StatefulWidget {
  final Api api;
  const _PasswordSheet({required this.api});
  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final current = TextEditingController(), next = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (next.text.length < 6) {
      return setState(() => error = txt.newPasswordShort);
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.changePassword(current.text, next.text);
      if (!mounted) return;
      showToast(context, txt.passwordChanged);
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(txt.changePassword, style: ui(19, weight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
              controller: current,
              obscureText: true,
              decoration:
                  _field(txt.currentPassword, icon: Icons.lock_outline)),
          const SizedBox(height: 10),
          TextField(
              controller: next,
              obscureText: true,
              onSubmitted: (_) => _save(),
              decoration: _field(txt.newPassword, icon: Icons.lock_reset)),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error!, style: ui(13, color: kRed)),
            ),
          const SizedBox(height: 16),
          PrimaryButton(label: txt.save, busy: busy, onTap: _save),
        ]),
      );
}

/// Engellenen kişiler ve engeli kaldırma
class _BlocksSheet extends StatefulWidget {
  final Api api;
  const _BlocksSheet({required this.api});
  @override
  State<_BlocksSheet> createState() => _BlocksSheetState();
}

class _BlocksSheetState extends State<_BlocksSheet> {
  List<Person>? list;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await widget.api.blocks();
      if (mounted) setState(() => list = l);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
  }

  Future<void> _unblock(Person p) async {
    setState(() => _busy.add(p.id));
    try {
      await widget.api.unblock(p.id);
      if (!mounted) return;
      showToast(context, txt.unblocked(p.name));
      await _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(txt.blockedUsers, style: ui(19, weight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(txt.blockedInfo,
                textAlign: TextAlign.center, style: ui(12, color: kMuted)),
            const SizedBox(height: 10),
            if (list == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: kNavy),
              )
            else if (list!.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(txt.noBlocked, style: ui(14, color: kMuted)),
              )
            else
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final p in list!)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Avatar(person: p, size: 42),
                      title:
                          Text(p.name, style: ui(15, weight: FontWeight.w700)),
                      subtitle:
                          Text('@${p.username}', style: ui(12, color: kMuted)),
                      trailing: TextButton(
                        onPressed:
                            _busy.contains(p.id) ? null : () => _unblock(p),
                        child: Text(txt.unblock,
                            style: ui(13, weight: FontWeight.w700)),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      );
}

/// Hesabı kalıcı olarak sil: şifreyle onay
class _DeleteAccountSheet extends StatefulWidget {
  final Api api;
  const _DeleteAccountSheet({required this.api});
  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.deleteAccount(password.text);
      if (!mounted) return;
      showToast(context, txt.accountDeleted);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_amber_rounded, color: kRed, size: 40),
          const SizedBox(height: 6),
          Text(txt.deleteTitle, style: ui(19, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(txt.deleteWarning,
              textAlign: TextAlign.center, style: ui(13, color: kMuted)),
          const SizedBox(height: 16),
          TextField(
              controller: password,
              obscureText: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _delete(),
              decoration:
                  _field(txt.confirmPassword, icon: Icons.lock_outline)),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error!, style: ui(13, color: kRed)),
            ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: busy || password.text.isEmpty ? null : _delete,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: kRed, borderRadius: BorderRadius.circular(26)),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Text(txt.deleteForever,
                      style:
                          ui(15, weight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ]),
      );
}
