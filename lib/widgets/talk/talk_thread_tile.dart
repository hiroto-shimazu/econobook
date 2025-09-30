part of 'package:econobook/screens/community_screen.dart';

class _TalkThreadTile extends StatelessWidget {
  const _TalkThreadTile({
    required this.entry,
    required this.timeLabel,
    required this.onTap,
    required this.onTogglePin,
  });

  final _TalkEntry entry;
  final String? timeLabel;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _avatar(entry),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.partnerDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: kTextMain,
                              ),
                            ),
                          ),
                          if (timeLabel != null)
                            Text(
                              timeLabel!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: kTextSub,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.previewText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: kTextSub,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (entry.isPinned)
                            const Icon(Icons.push_pin, size: 14, color: kTextSub),
                          if (entry.isPinned) const SizedBox(width: 8),
                          if (entry.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: kBrandBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${entry.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              entry.isPinned ? Icons.star : Icons.star_border,
                              size: 20,
                              color: entry.isPinned ? kAccentOrange : kTextSub,
                            ),
                            onPressed: onTogglePin,
                            tooltip: entry.isPinned ? 'ピンを外す' : 'ピン留め',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(_TalkEntry e) {
    if (e.partnerPhotoUrl != null && e.partnerPhotoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          e.partnerPhotoUrl!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: kBrandBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.person_outline, color: kBrandBlue),
    );
  }
}
