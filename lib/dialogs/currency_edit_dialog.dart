import 'package:flutter/material.dart';

import '../models/community.dart';
import '../services/community_service.dart';

Future<void> showCurrencyEditDialog(
  BuildContext context, {
  required String communityId,
  required CommunityCurrency currency,
  required CommunityPolicy policy,
  required CommunityService service,
}) async {
  final nameCtrl = TextEditingController(text: currency.name);
  final precisionCtrl =
      TextEditingController(text: currency.precision.toString());
  final maxSupplyCtrl = TextEditingController(
      text: currency.maxSupply == null ? '' : currency.maxSupply!.toString());
  final txFeeCtrl = TextEditingController(text: currency.txFeeBps.toString());
  final borrowLimitCtrl = TextEditingController(
      text: currency.borrowLimitPerMember == null
          ? ''
          : currency.borrowLimitPerMember!.toString());
  final interestCtrl =
      TextEditingController(text: currency.interestBps.toString());
  bool allowMinting = currency.allowMinting;
  bool requiresApproval = policy.requiresApproval;
  bool saving = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (stateCtx, setState) {
          return AlertDialog(
            title: const Text('中央銀行設定を編集'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '通貨名'),
                  ),
                  TextField(
                    controller: precisionCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '小数点以下桁数'),
                  ),
                  TextField(
                    controller: maxSupplyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: '最大発行枚数（空欄で無制限）'),
                  ),
                  TextField(
                    controller: txFeeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '取引手数料（bps）'),
                  ),
                  TextField(
                    controller: borrowLimitCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'メンバー借入上限（空欄で制限なし）'),
                  ),
                  TextField(
                    controller: interestCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '年利（bps）'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    title: const Text('メンバーによる発行/焼却を許可'),
                    value: allowMinting,
                    onChanged: (v) => setState(() => allowMinting = v),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('参加には管理者の承認が必要'),
                    value: requiresApproval,
                    onChanged: (v) => setState(() => requiresApproval = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogCtx).pop(false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final parsedPrecision =
                            int.tryParse(precisionCtrl.text.trim()) ??
                                currency.precision;
                        final clampedPrecision = parsedPrecision < 0
                            ? 0
                            : (parsedPrecision > 8 ? 8 : parsedPrecision);
                        final maxSupply = maxSupplyCtrl.text.trim().isEmpty
                            ? null
                            : double.tryParse(maxSupplyCtrl.text.trim());
                        final txFee = int.tryParse(txFeeCtrl.text.trim()) ??
                            currency.txFeeBps;
                        final borrowLimit = borrowLimitCtrl.text.trim().isEmpty
                            ? null
                            : double.tryParse(borrowLimitCtrl.text.trim());
                        final interest =
                            int.tryParse(interestCtrl.text.trim()) ??
                                currency.interestBps;

                        final updatedCurrency = CommunityCurrency(
                          name: nameCtrl.text.trim().isEmpty
                              ? currency.code
                              : nameCtrl.text.trim(),
                          code: currency.code,
                          precision: clampedPrecision,
                          supplyModel:
                              maxSupply == null ? 'unlimited' : 'capped',
                          txFeeBps: txFee,
                          expireDays: currency.expireDays,
                          creditLimit:
                              borrowLimit?.round() ?? currency.creditLimit,
                          interestBps: interest,
                          maxSupply: maxSupply,
                          allowMinting: allowMinting,
                          borrowLimitPerMember: borrowLimit,
                        );
                        final updatedPolicy =
                            policy.copyWith(requiresApproval: requiresApproval);

                        setState(() => saving = true);
                        try {
                          await service.updateCurrencyAndPolicy(
                            communityId: communityId,
                            currency: updatedCurrency,
                            policy: updatedPolicy,
                          );
                          if (context.mounted) {
                            Navigator.of(dialogCtx).pop(true);
                          }
                        } catch (e) {
                          setState(() => saving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('更新に失敗しました: $e')),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('中央銀行設定を更新しました')),
    );
  }
}
