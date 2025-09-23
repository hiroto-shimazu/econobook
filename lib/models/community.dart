import 'package:cloud_firestore/cloud_firestore.dart';

class Community {
  Community({
    required this.id,
    required this.name,
    required this.symbol,
    required this.description,
    required this.coverUrl,
    required this.discoverable,
    required this.ownerUid,
    required this.adminUids,
    required this.membersCount,
    required this.inviteCode,
    required this.createdAt,
    required this.updatedAt,
    required this.currency,
    required this.policy,
    required this.visibility,
    required this.treasury,
  });

  final String id;
  final String name;
  final String symbol;
  final String? description;
  final String? coverUrl;
  final bool discoverable;
  final String ownerUid;
  final List<String> adminUids;
  final int membersCount;
  final String inviteCode;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final CommunityCurrency currency;
  final CommunityPolicy policy;
  final CommunityVisibility visibility;
  final CommunityTreasury treasury;

  factory Community.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return Community.fromMap(id: snap.id, data: data);
  }

  factory Community.fromMap(
      {required String id, required Map<String, dynamic> data}) {
    final currencyMap = (data['currency'] as Map<String, dynamic>?) ?? const {};
    final policyMap = (data['policy'] as Map<String, dynamic>?) ?? const {};
    return Community(
      id: id,
      name: (data['name'] as String?)?.trim() ?? '',
      symbol: (data['symbol'] as String?)?.trim() ?? '',
      description: (data['description'] as String?)?.trim(),
      coverUrl: (data['coverUrl'] as String?)?.trim(),
      discoverable: data['discoverable'] == true,
      ownerUid: (data['ownerUid'] as String?) ?? '',
      adminUids: List<String>.from((data['admins'] as List?) ?? const []),
      membersCount: (data['membersCount'] as num?)?.toInt() ?? 0,
      inviteCode: (data['inviteCode'] as String?) ?? '',
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      currency: CommunityCurrency.fromMap(currencyMap),
      policy: CommunityPolicy.fromMap(policyMap),
      visibility: CommunityVisibility.fromMap(
          (data['visibility'] as Map<String, dynamic>?) ?? const {}),
      treasury: CommunityTreasury.fromMap(
          (data['treasury'] as Map<String, dynamic>?) ?? const {}),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'symbol': symbol,
      'description': description,
      'coverUrl': coverUrl,
      'discoverable': discoverable,
      'ownerUid': ownerUid,
      'admins': adminUids,
      'membersCount': membersCount,
      'inviteCode': inviteCode,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'currency': currency.toMap(),
      'policy': policy.toMap(),
      'visibility': visibility.toMap(),
      'treasury': treasury.toMap(),
    };
  }

  Community copyWith({
    String? name,
    String? symbol,
    String? description,
    String? coverUrl,
    bool? discoverable,
    String? ownerUid,
    List<String>? adminUids,
    int? membersCount,
    String? inviteCode,
    DateTime? createdAt,
    DateTime? updatedAt,
    CommunityCurrency? currency,
    CommunityPolicy? policy,
    CommunityVisibility? visibility,
    CommunityTreasury? treasury,
  }) {
    return Community(
      id: id,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      discoverable: discoverable ?? this.discoverable,
      ownerUid: ownerUid ?? this.ownerUid,
      adminUids: adminUids ?? this.adminUids,
      membersCount: membersCount ?? this.membersCount,
      inviteCode: inviteCode ?? this.inviteCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currency: currency ?? this.currency,
      policy: policy ?? this.policy,
      visibility: visibility ?? this.visibility,
      treasury: treasury ?? this.treasury,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class CommunityVisibility {
  const CommunityVisibility({
    required this.balanceMode,
    this.customMembers = const [],
  });

  final String balanceMode; // everyone | private | custom
  final List<String> customMembers;

  factory CommunityVisibility.fromMap(Map<String, dynamic> map) {
    final mode = (map['balanceMode'] as String?) ?? 'private';
    return CommunityVisibility(
      balanceMode: mode,
      customMembers:
          List<String>.from((map['customMembers'] as List?) ?? const []),
    );
  }

  Map<String, Object?> toMap() => {
        'balanceMode': balanceMode,
        'customMembers': customMembers,
      };

  CommunityVisibility copyWith(
      {String? balanceMode, List<String>? customMembers}) {
    return CommunityVisibility(
      balanceMode: balanceMode ?? this.balanceMode,
      customMembers: customMembers ?? this.customMembers,
    );
  }
}

class CommunityTreasury {
  const CommunityTreasury({
    required this.balance,
    required this.initialGrant,
  });

  final num balance;
  final num initialGrant;

  factory CommunityTreasury.fromMap(Map<String, dynamic> map) {
    return CommunityTreasury(
      balance: (map['balance'] as num?) ?? 0,
      initialGrant: (map['initialGrant'] as num?) ?? 0,
    );
  }

  Map<String, Object?> toMap() => {
        'balance': balance,
        'initialGrant': initialGrant,
      };

  CommunityTreasury copyWith({num? balance, num? initialGrant}) {
    return CommunityTreasury(
      balance: balance ?? this.balance,
      initialGrant: initialGrant ?? this.initialGrant,
    );
  }
}

class CommunityCurrency {
  const CommunityCurrency({
    required this.name,
    required this.code,
    required this.precision,
    required this.supplyModel,
    required this.txFeeBps,
    required this.expireDays,
    required this.creditLimit,
    required this.interestBps,
    this.maxSupply,
    this.allowMinting = true,
    this.borrowLimitPerMember,
  });

  final String name;
  final String code;
  final int precision;
  final String supplyModel; // unlimited / capped / custom
  final int txFeeBps;
  final int? expireDays;
  final int creditLimit;
  final int interestBps;
  final double? maxSupply;
  final bool allowMinting;
  final double? borrowLimitPerMember;

  factory CommunityCurrency.fromMap(Map<String, dynamic> map) {
    return CommunityCurrency(
      name: (map['name'] as String?) ?? ((map['code'] as String?) ?? 'PTS'),
      code: (map['code'] as String?) ?? 'PTS',
      precision: (map['precision'] as num?)?.toInt() ?? 2,
      supplyModel: (map['supplyModel'] as String?) ?? 'unlimited',
      txFeeBps: (map['txFeeBps'] as num?)?.toInt() ?? 0,
      expireDays: (map['expireDays'] as num?)?.toInt(),
      creditLimit: (map['creditLimit'] as num?)?.toInt() ?? 0,
      interestBps: (map['interestBps'] as num?)?.toInt() ?? 0,
      maxSupply: (map['maxSupply'] as num?)?.toDouble(),
      allowMinting: map['allowMinting'] != false,
      borrowLimitPerMember: (map['borrowLimitPerMember'] as num?)?.toDouble(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'code': code,
      'precision': precision,
      'supplyModel': supplyModel,
      'txFeeBps': txFeeBps,
      'expireDays': expireDays,
      'creditLimit': creditLimit,
      'interestBps': interestBps,
      'maxSupply': maxSupply,
      'allowMinting': allowMinting,
      'borrowLimitPerMember': borrowLimitPerMember,
    };
  }

  CommunityCurrency copyWith({
    String? name,
    String? code,
    int? precision,
    String? supplyModel,
    int? txFeeBps,
    int? expireDays,
    int? creditLimit,
    int? interestBps,
    double? maxSupply,
    bool? allowMinting,
    double? borrowLimitPerMember,
  }) {
    return CommunityCurrency(
      name: name ?? this.name,
      code: code ?? this.code,
      precision: precision ?? this.precision,
      supplyModel: supplyModel ?? this.supplyModel,
      txFeeBps: txFeeBps ?? this.txFeeBps,
      expireDays: expireDays ?? this.expireDays,
      creditLimit: creditLimit ?? this.creditLimit,
      interestBps: interestBps ?? this.interestBps,
      maxSupply: maxSupply ?? this.maxSupply,
      allowMinting: allowMinting ?? this.allowMinting,
      borrowLimitPerMember: borrowLimitPerMember ?? this.borrowLimitPerMember,
    );
  }
}

class CommunityPolicy {
  const CommunityPolicy({
    required this.enableRequests,
    required this.enableSplitBill,
    required this.enableTasks,
    required this.enableMediation,
    required this.minorsRequireGuardian,
    required this.postVisibilityDefault,
    required this.requiresApproval,
  });

  final bool enableRequests;
  final bool enableSplitBill;
  final bool enableTasks;
  final bool enableMediation;
  final bool minorsRequireGuardian;
  final String postVisibilityDefault; // self / community / public
  final bool requiresApproval;

  factory CommunityPolicy.fromMap(Map<String, dynamic> map) {
    return CommunityPolicy(
      enableRequests: map['enableRequests'] != false,
      enableSplitBill: map['enableSplitBill'] != false,
      enableTasks: map['enableTasks'] != false,
      enableMediation: map['enableMediation'] == true,
      minorsRequireGuardian: map['minorsRequireGuardian'] != false,
      postVisibilityDefault:
          (map['postVisibilityDefault'] as String?) ?? 'community',
      requiresApproval: map['requiresApproval'] == true,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'enableRequests': enableRequests,
      'enableSplitBill': enableSplitBill,
      'enableTasks': enableTasks,
      'enableMediation': enableMediation,
      'minorsRequireGuardian': minorsRequireGuardian,
      'postVisibilityDefault': postVisibilityDefault,
      'requiresApproval': requiresApproval,
    };
  }

  CommunityPolicy copyWith({
    bool? enableRequests,
    bool? enableSplitBill,
    bool? enableTasks,
    bool? enableMediation,
    bool? minorsRequireGuardian,
    String? postVisibilityDefault,
    bool? requiresApproval,
  }) {
    return CommunityPolicy(
      enableRequests: enableRequests ?? this.enableRequests,
      enableSplitBill: enableSplitBill ?? this.enableSplitBill,
      enableTasks: enableTasks ?? this.enableTasks,
      enableMediation: enableMediation ?? this.enableMediation,
      minorsRequireGuardian:
          minorsRequireGuardian ?? this.minorsRequireGuardian,
      postVisibilityDefault:
          postVisibilityDefault ?? this.postVisibilityDefault,
      requiresApproval: requiresApproval ?? this.requiresApproval,
    );
  }
}
