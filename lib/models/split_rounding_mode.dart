enum SplitRoundingMode { even, floor }

extension SplitRoundingModeLabel on SplitRoundingMode {
  String get label => switch (this) {
        SplitRoundingMode.even => '均等（端数を均等配分）',
        SplitRoundingMode.floor => '切り捨て（端数は依頼者負担）',
      };

  String get shortLabel => switch (this) {
        SplitRoundingMode.even => '均等',
        SplitRoundingMode.floor => '切り捨て',
      };
}
