import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api.dart';
import 'i18n.dart';
import 'legal.dart';
import 'legal_texts.dart';
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
      await loadProducts(kProductIds);
    } catch (_) {
      available = false;
    }
  }

  /// Paketlerin Google Play'deki fiyatlarını getir (admin panelindeki paketler)
  Future<void> loadProducts(Set<String> ids) async {
    if (kIsWeb || !available || ids.isEmpty) return;
    final missing = ids.difference(products.value.keys.toSet());
    if (missing.isEmpty) return;
    try {
      final r = await InAppPurchase.instance.queryProductDetails(missing);
      products.value = {
        ...products.value,
        for (final p in r.productDetails) p.id: p
      };
    } catch (_) {}
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
  String? busy;

  @override
  void initState() {
    super.initState();
    widget.api.refreshCredits().then(
        (c) => widget.store.loadProducts(c.products.keys.toSet()),
        onError: (_) {});
  }

  /// Pakete dokununca Google Play'in kendi ödeme ekranı açılır;
  /// sonuç satın alma akışından (Store._onPurchases) gelir
  Future<void> _buy(String id, ProductDetails? product, bool test) async {
    setState(() => busy = id);
    try {
      if (product != null) {
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
    Widget line(IconData icon, String text,
            {Color color = kNavy, bool strong = true}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: strong
                        ? ui(13.5, weight: FontWeight.w700)
                        : ui(12.5, color: kMuted))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
          color: kGround, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        line(
            c.dailyLeft > 0 ? Icons.wb_sunny_outlined : Icons.schedule,
            c.dailyLeft > 0
                ? txt.dailyFreeLeft
                : txt.dailyUsed(left == null ? '' : _dur(left))),
        line(Icons.confirmation_number_outlined, txt.bonusCount(c.bonus)),
        line(Icons.reply, txt.replyFreeInfo, color: kRed, strong: false),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
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
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(txt.buyMore,
                        style: ui(13, weight: FontWeight.w800, color: kMuted)),
                  ),
                  const SizedBox(height: 6),
                  for (final e in ids.entries)
                    _pack(e.key, e.value, products[e.key], c.testPurchases,
                        canBuy),
                  const SizedBox(height: 6),
                  // Google Play'deki gibi: ödeme bilgisi ve koşullar altta not olarak
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text:
                              canBuy ? txt.purchaseNote : txt.storeUnavailable),
                      const TextSpan(text: ' '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: GestureDetector(
                          onTap: () => showLegalDoc(context, LegalDoc.terms),
                          child: Text(legalTitle(LegalDoc.terms),
                              style: ui(11.5, weight: FontWeight.w700).copyWith(
                                  decoration: TextDecoration.underline)),
                        ),
                      ),
                    ]),
                    textAlign: TextAlign.center,
                    style: ui(11.5, color: kMuted),
                  ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? () => _buy(id, product, test) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: kRed.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.confirmation_number_outlined,
                color: kRed, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(txt.packLabel(n), style: ui(15, weight: FontWeight.w700)),
              Text('toss-o', style: ui(12, color: kMuted)),
            ]),
          ),
          busy == id
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: kNavy))
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: enabled
                          ? const Color(0xFF01875F) // Google Play yeşili
                          : kMuted.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(18)),
                  child: Text(price,
                      style: ui(13.5,
                          weight: FontWeight.w700, color: Colors.white)),
                ),
        ]),
      ),
    );
  }
}

/// Üst çubuktaki hak göstergesi: alışveriş çantası + kalan toplam hak
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
              Icon(Icons.shopping_bag_outlined,
                  size: 19, color: c.total > 0 ? kNavy : kRed),
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
