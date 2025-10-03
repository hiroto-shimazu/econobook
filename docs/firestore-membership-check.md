## Firestore membership 確認とルールデプロイ手順

このドキュメントは、チャットの `permission-denied` を解消するために管理者が行うべき最小限の手順を示します。

1) membership ドキュメントの確認
- Firestore コンソールで `memberships` コレクションを開く。
- 対象コミュニティの ID（例: `A2DEMtNcsN63pKVLH8zI`）とユーザーの UID（例: `4DuTMUT0hNPr3SBfxyyHQocXBJu1`）を組み合わせたドキュメント ID を探す。
  - 形式: `${cid}_${uid}` 例: `A2DEMtNcsN63pKVLH8zI_4DuTMUT0hNPr3SBfxyyHQocXBJu1`
- ドキュメントが存在し、`role`, `canManageBank`, `joinedAt` などのフィールドがあることを確認する。

2) ドキュメントが存在しない場合
- 開発環境であればコンソールから手動でドキュメントを追加できます。
- 本番ではユーザー参加フローで memberships ドキュメントが作成されるはずです。必要ならば招待／参加処理を確認してください。

3) `firestore.rules` のデプロイ手順（Firebase CLI を使用）
- Firebase CLI がインストールされていることを確認してください。
  - インストール: `npm install -g firebase-tools`
- プロジェクトにログイン: `firebase login`
- プロジェクトのルールをデプロイ:
  - `firebase deploy --only firestore:rules`

4) 注意点
- ここにあるルールは最小限の案です。運用環境ではさらに細かい検証（例えば書き込み権限の制御や role ベースのチェック）を追加してください。
- ルールをデプロイする前に、Firestore セキュリティルールのシミュレータでサンプルユーザーの読み取り/書き込みをテストしてください。


