import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api.dart';
import 'i18n.dart';
import 'models.dart';
import 'widgets.dart';

/// Google Play'deki tek seferlik paketler (sunucudaki PRODUCTS ile aynı)
const kProductIds = {'tosso_hak_5', 'tosso_hak_15', 'tosso_hak_40'};

/// Google Play satın almaları. Uygulama açıkken gelen bütün satın alma
/// güncellemelerini dinler, sunucuya doğrulatır ve ancak ondan sonra
/// tamamlar; doğrulanamayan satın alma bir sonraki açılışta yeniden denenir.
class Store {
  Store(this.api);
  final Api api;
  final products = ValueNotifier<Map<String, ProductDetails>>({});
  bool available = false;
  void Function(String message)? onMessage;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> init() async {
    if (kIsWeb) return;
    final iap = InAppPurchase.instance;
    _sub = iap.purchaseStream.listen(_onPurchases, onError: (_) {});
    try {
      available = await iap.isAvailable();
      if (!available) return;
      final r = await iap.queryProductDetails(kProductIds);
      products.value = {for (final p in r.productDetails) p.id: p};
    } catch (_) {
      available = false;
    }
  }

  Future<void> buy(ProductDetails p) => InAppPurchase.instance
      .buyConsumable(purchaseParam: PurchaseParam(productDetails: p));

  Future<void> _complete(PurchaseDetails p) async {
    if (p.pendingCompletePurchase) {
      await InAppPurchase.instance.completePurchase(p);
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            final before = api.credits.value.bonus;
            final c = await api.verifyGooglePurchase(
                p.productID, p.verificationData.serverVerificationData);
            await _complete(p);
            final added = c.bonus - before;
            if (added > 0) onMessage?.call(txt.creditsAdded(added));
          } on ApiException catch (e) {
            onMessage?.call(e.message);
            // Geçersiz ya da başka hesapta kullanılmış: tekrar denemenin anlamı yok
            if (e.status == 400 || e.status == 409) await _complete(p);
          }
        case PurchaseStatus.pending:
          onMessage?.call(txt.purchasePending);
        case PurchaseStatus.error:
          onMessage?.call(txt.purchaseFailed);
          await _complete(p);
        case PurchaseStatus.canceled:
          await _complete(p);
      }
    }
  }

  void dispose() => _sub?.cancel();
}

/// "3 sa 20 dk" / "45 dk"
String _dur(Duration d) {
  final m = d.inMinutes.clamp(1, 100000);
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return txt.en ? '$r min' : '$r dk';
  if (r == 0) return txt.en ? '$h h' : '$h sa';
  return txt.en ? '$h h $r min' : '$h sa $r dk';
}

/// Mektup hakları ve paket satın alma sayfası
Future<void> showStoreSheet(BuildContext context,
        {required Api api, required Store store, String? reason}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _StoreSheet(api: api, store: store, reason: reason),
    );

class _StoreSheet extends StatefulWidget {
  final Api api;
  final Store store;
  final String? reason;
  const _StoreSheet({required this.api, required this.store, this.reason});
  @override
  State<_StoreSheet> createState() => _StoreSheetState();
}

class _StoreSheetState extends State<_StoreSheet> {
  bool consent = false;
  String? busy;

  @override
  void initState() {
    super.initState();
    widget.api.refreshCredits().catchError((_) => widget.api.credits.value);
  }

  Future<void> _buy(String id, ProductDetails? product, bool test) async {
    if (!consent) return showToast(context, txt.purchaseConsentNeeded);
    setState(() => busy = id);
    try {
      if (product != null) {
        // Sonuç satın alma akışından (Store._onPurchases) gelir
        await widget.store.buy(product);
      } else if (test) {
        final before = widget.api.credits.value.bonus;
        final c = await widget.api.testPurchase(id);
        if (mounted) showToast(context, txt.creditsAdded(c.bonus - before));
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (_) {
      if (mounted) showToast(context, txt.purchaseFailed);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Widget _status(Credits c) {
    final left = c.resetsAt?.difference(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kGround, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(c.dailyLeft > 0 ? Icons.mail_outline : Icons.schedule,
              size: 18, color: kNavy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                c.dailyLeft > 0
                    ? txt.dailyFreeLeft
                    : txt.dailyUsed(left == null ? '' : _dur(left)),
                style: ui(13.5, weight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.local_post_office_outlined, size: 18, color: kNavy),
          const SizedBox(width: 8),
          Text(txt.bonusCount(c.bonus),
              style: ui(13.5, weight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.reply, size: 18, color: kRed),
          const SizedBox(width: 8),
          Expanded(
              child: Text(txt.replyFreeInfo, style: ui(12.5, color: kMuted))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: ValueListenableBuilder<Credits>(
            valueListenable: widget.api.credits,
            builder: (context, c, _) => ValueListenableBuilder(
              valueListenable: widget.store.products,
              builder: (context, products, _) {
                final ids = c.products.isEmpty
                    ? {for (final id in kProductIds) id: 0}
                    : c.products;
                final canBuy = products.isNotEmpty || c.testPurchases;
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 14),
                  if (widget.reason != null) ...[
                    Text(widget.reason!,
                        textAlign: TextAlign.center,
                        style: ui(17, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                  ],
                  Text(txt.creditsTitle,
                      style: ui(widget.reason == null ? 19 : 14,
                          weight: FontWeight.w800,
                          color: widget.reason == null ? kNavy : kMuted)),
                  const SizedBox(height: 12),
                  _status(c),
                  const SizedBox(height: 14),
                  for (final e in ids.entries)
                    _pack(e.key, e.value, products[e.key], c.testPurchases,
                        canBuy),
                  if (!canBuy)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(txt.storeUnavailable,
                          textAlign: TextAlign.center,
                          style: ui(12, color: kMuted)),
                    ),
                  if (canBuy)
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                              value: consent,
                              activeColor: kNavy,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) =>
                                  setState(() => consent = v ?? false)),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => consent = !consent),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 9),
                                child: Text(txt.purchaseConsent,
                                    style: ui(11.5,
                                        color: const Color(0xFF34405A))),
                              ),
                            ),
                          ),
                        ]),
                ]);
              },
            ),
          ),
        ),
      );

  Widget _pack(
      String id, int count, ProductDetails? product, bool test, bool canBuy) {
    final n = count > 0 ? count : int.tryParse(id.split('_').last) ?? 0;
    final price = product?.price ?? (test ? txt.testFree : '—');
    final enabled = canBuy && (product != null || test) && busy == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE3E6EC))),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? () => _buy(id, product, test) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: kRed.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('$n',
                    style: ui(17, weight: FontWeight.w800, color: kRed)),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(txt.packLabel(n),
                      style: ui(15, weight: FontWeight.w700))),
              busy == id
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kNavy))
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                          color: enabled ? kNavy : kNavy.withValues(alpha: .3),
                          borderRadius: BorderRadius.circular(16)),
                      child: Text(price,
                          style: ui(13,
                              weight: FontWeight.w700, color: Colors.white)),
                    ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Üst çubuktaki hak göstergesi: ✉ kalan toplam hak
class CreditsChip extends StatelessWidget {
  final Api api;
  final VoidCallback onTap;
  const CreditsChip({super.key, required this.api, required this.onTap});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Credits>(
        valueListenable: api.credits,
        builder: (context, c, _) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: glass(21),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.mail_outline,
                  size: 18, color: c.total > 0 ? kNavy : kRed),
              const SizedBox(width: 5),
              Text('${c.total}',
                  style: ui(14,
                      weight: FontWeight.w800,
                      color: c.total > 0 ? kNavy : kRed)),
            ]),
          ),
        ),
      );
}

/// Varışa kalan süre metni: "yaklaşık 3 sa 20 dk sonra varır (18:40)"
String arrivalText(DateTime at) {
  final hm =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  return txt.arrivesIn(_dur(at.difference(DateTime.now())), hm);
}

/// Gönderilen mektubun durumu: yolda / ulaştı / okundu
String sentStatus(Letter l) => l.inFlight
    ? txt.inFlight(_dur(l.deliverAt.difference(DateTime.now())))
    : (l.unread ? txt.delivered : txt.readMark);
