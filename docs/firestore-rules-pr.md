# Firestore rules 変更（community_chats の読み取り制限）

概要
- 目的: チャットのメッセージ/スレッド閲覧に関して、該当コミュニティのメンバーのみ読み取りを許可するセキュリティ強化。
- 変更箇所: `firestore.rules` を更新し、`community_chats/{cid}/threads/{threadId}` と `community_chats/{cid}/threads/{threadId}/messages/{messageId}` の `read`/`create` を、`memberships/{cid}_{uid}` ドキュメントが存在する場合にのみ許可するようにしました。加えて `ledger`, `requests`, `tasks` の読み取りをコミュニティメンバーに限定しています。

デプロイ手順
1. Firebase CLI にログイン
   - `firebase login`
2. （任意）既存ルールのバックアップ
   - `firebase firestore:rules:get > backup-firestore.rules`
3. ルールをデプロイ
   - `firebase deploy --only firestore:rules`
4. デプロイ後、Firestore コンソールの "Rules" タブで反映されたルールを確認

動作確認手順
- 管理者は Firestore コンソールで対象ユーザーの `memberships/{cid}_{uid}` ドキュメントが存在することを確認してください（例: `A2DEMtNcsN63pKVLH8zI_4DuTMUT0hNPr3SBfxyyHQocXBJu1`）。
- そのユーザーでログインして、チャット UI（`community_chats/{cid}/threads` の一覧と `.../messages`）が読み取れるかテストしてください。
- ルールのシミュレータを使って、未認証ユーザーや別コミュニティの UID によるアクセスをテストしてください。

リスクとロールバック
- リスク:
  - ルールの誤設定により、予期せず読み取りがブロックされる可能性があります。特に membership ドキュメントの生成ロジックに不整合があると、正当なユーザーがアクセスできなくなる恐れがあります。
- ロールバック手順:
  1. デプロイ前に保存したバックアップファイルを用意する（`backup-firestore.rules`）。
  2. `firebase deploy --only firestore:rules --force` でバックアップ内容をリストアするか、現在の rules ファイルを直接上書きして再デプロイしてください。

追加検討事項（今後）
- メッセージ書き込みや中央バンク操作（issue/redeem/lend 等）は role（`canManageBank` など）ベースでさらに制限することを推奨します。これに関しては別 PR で role ベースルール案を用意できます。

備考
- 本 PR はクライアント側での permission-denied を解消することが目的です。サーバ側の membership 作成フローが正しく動作していることも同時に確認してください。

