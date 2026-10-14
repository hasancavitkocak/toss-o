import 'package:flutter/material.dart';
import 'api.dart';
import 'legal.dart';
import 'legal_texts.dart';
import 'i18n.dart';
import 'location_picker.dart';
import 'models.dart';
import 'widgets.dart';

class LoginScreen extends StatefulWidget {
  final Api api;
  final void Function(Session) onSession;
  const LoginScreen({super.key, required this.api, required this.onSession});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool register = false, busy = false;
  // KVKK: aydınlatma + koşullar zorunlu, yurt dışı aktarım rızası isteğe bağlı
  bool notice = false, terms = false, abroad = false;
  String? error;
  // Türkçe kullanan çoğunlukla Türkiye'dedir; İngilizcede ülke boş başlar
  GeoOption? country =
          language.value == Lang.tr ? const GeoOption('TR', 'Türkiye') : null,
      region;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  void _toggle() => setState(() {
        register = !register;
        error = null;
      });

  Future<void> _submit() async {
    final u = username.text.trim().toLowerCase();
    final p = password.text;
    if (u.isEmpty || p.isEmpty) {
      return setState(() => error = txt.errCredentials);
    }
    if (register) {
      if (name.text.trim().isEmpty) return setState(() => error = txt.errName);
      if (country == null || region == null) {
        return setState(() => error = txt.errLocation);
      }
      if (!RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(u)) {
        return setState(() => error = txt.errUsername);
      }
      if (p.length < 6) {
        return setState(() => error = txt.errPassword);
      }
      if (!notice || !terms) return setState(() => error = txt.errConsent);
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final s = register
          ? await widget.api.register(
              username: u,
              password: p,
              displayName: name.text.trim(),
              country: country!.code,
              region: region!.code,
              lang: txt.code,
              acceptTerms: terms,
              acceptNotice: notice,
              consentAbroad: abroad)
          : await widget.api.login(u, p);
      widget.onSession(s);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration _field(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: ui(14, color: kMuted),
        prefixIcon: Icon(icon, color: kNavy.withValues(alpha: .6)),
        filled: true,
        fillColor: kGround,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: kNavy, width: 1.4)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                      alignment: Alignment.centerRight, child: LangSwitch()),
                  const Logo(height: 120),
                  const SizedBox(height: 10),
                  Text(txt.tagline,
                      textAlign: TextAlign.center, style: hand(26, .9)),
                  const SizedBox(height: 28),
                  if (register) ...[
                    TextField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: _field(txt.yourName, Icons.badge_outlined),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: username,
                    autocorrect: false,
                    decoration:
                        _field(txt.username, Icons.alternate_email_rounded),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration:
                        _field(txt.password, Icons.lock_outline_rounded),
                  ),
                  if (register) ...[
                    const SizedBox(height: 12),
                    LocationFields(
                      api: widget.api,
                      country: country,
                      region: region,
                      onChanged: (c, r) => setState(() {
                        country = c;
                        region = r;
                      }),
                    ),
                    const SizedBox(height: 10),
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
                    ConsentTile(
                        value: abroad,
                        onChanged: (v) => setState(() => abroad = v),
                        label: txt.consentExplicit,
                        doc: LegalDoc.consent,
                        required: false),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Text(error!,
                        textAlign: TextAlign.center,
                        style: ui(13, weight: FontWeight.w600, color: kRed)),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: register ? txt.createAccount : txt.login,
                    busy: busy,
                    onTap: _submit,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: busy ? null : _toggle,
                    child: Text(register ? txt.haveAccount : txt.noAccount,
                        style: ui(14, weight: FontWeight.w600)),
                  ),
                  if (!register) ...[
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: () {
                        username.text = 'hasan';
                        password.text = 'toss1234';
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: kGround,
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Icon(Icons.science_outlined,
                              size: 20, color: kMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(txt.testAccount,
                                style: ui(12, color: kMuted)),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
