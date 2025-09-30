part of 'package:econobook/screens/community_screen.dart';

Widget _talkEmptyState({String message = 'まだトークはありません'}) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: kCardWhite,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: kTextMain,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '新しいトークを開始してみましょう。',
          style: TextStyle(color: kTextSub),
        ),
      ],
    ),
  );
}

Widget _loadingState() {
  return Column(
    children: [
      for (int i = 0; i < 2; i++) ...[
        Container(
          margin: EdgeInsets.only(bottom: i == 1 ? 0 : 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: kLightGray,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: kLightGray,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: kLightGray,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ]
    ],
  );
}

Widget _errorNotice(String message) {
  return Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: kCardWhite,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.red.withOpacity(0.2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: kTextSub),
          ),
        ),
      ],
    ),
  );
}
