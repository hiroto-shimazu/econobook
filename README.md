# 目的定義（EconoBook）

## 1) ひとことで（1-liner）
家族・友人・学生コミュニティの小さな貸し借りを、**コミュ内“中央銀行”が発行する安全なポイント**と**透明な台帳**で、揉めずに**合意→実行→月次精算**まで完走させる。

---

## 2) 1段落（Problem → Value → Outcome）
現金や一般の送金アプリでは、少額の立替・割り勘・手伝い報酬に**合意のズレ**や**後追い確認の負担**が残り、月末精算も煩雑。  
EconoBookは各コミュニティに**唯一の中央銀行（発行主体）**を置き、コミュ独自の**複数通貨（例：ECO, SCORE, CLUB）**を**二重仕訳台帳**で厳格管理。**発行/回収権限**と**公開範囲**を統制し、**月次まとめ精算**は**外部決済リンク**で実通貨と橋渡し。結果、**合意→実行→記録→精算**が高速・公平・監査可能となり、関係性を壊さず取引を完了できる。

---

## 3) 成功指標（KPI / NSM）
- **NSM**：月次の**円滑完了取引数**（posted・争議なし）
- **一次KPI**
  - 取引承認までの中央値 **< 2時間**
  - 月次まとめ精算の実行率 **≥ 60%**（対象コミュ）
  - 争議率 **< 1%**、争議の48h以内解決率 **≥ 90%**
- **銀行モデルKPI**
  - 台帳整合性**0件**（通貨ごとに Σaccounts ≡ Σledger、夜間検算アラート=0）
  - 不正検知率（重複投稿/改ざん検知）**≥ 99%**
  - 発行/回収SLA：リクエスト→反映 **< 3秒**、監査ログ**100%**即時記録
  - 方針変更の透明性：通貨ポリシー変更を**100%履歴化**（誰が/何を/いつ）

---

## 4) 対象ユーザー / ペルソナ
- **家族**：家事ポイント・お小遣い・立替の可視化  
- **学生グループ**：課題手伝い・部費・飲み会割り勘  
- **小規模チーム**：イベント精算・役割報酬  
※未成年を想定し、**保護者同意・上限・時間帯制限**を提供。

---

## 5) 提供価値（JTBD）
- **JTBD1**：揉めずに**合意→記録→精算**を素早く完了したい  
- **JTBD2**：貢献度や履歴を**第三者にも説明可能**に残したい  
- **JTBD3**：実通貨決済は外部で、**取り決めと記録はアプリ内で完結**したい

---

## 6) スコープ（MVPで必須 / 後回し）
**必須（MVP）**
- 1コミュ=1中央銀行、**複数通貨**発行（`isActive`／供給上限／小数／失効）
- **二重仕訳台帳**、発行/回収（mint/burn）の**権限ロール**
- **送受信・請求・割り勘・タスク報酬**（承認フロー付き）
- **月次まとめ精算**（外部決済リンク＋完了チェック）
- 公開範囲（本人／コミュ／全体）、**信用スコア通貨**（`isScore=true`）
- **監査ログ・夜間検算・冪等キー・アラート**

**後回し**
- コミュ間通貨交換、**金利/貸付**、暗号資産連携、高度なマーケット

---

## 7) 非ゴール（やらないこと）
- アプリ内での**実通貨の保管/移転/換金**
- **利息付与・貸金・送金業**に該当する機能
- 外部送金サービスの**代理/媒介**

---

## 8) 制約 / コンプラ方針（中央銀行モデルの前提）
- 「中央銀行」はUX上の呼称。規約上は**発行主体（Issuer）**
- **ポイントは金銭債権でない／換金不可／失効あり**を明記
- 実通貨との関係は**参考レート表示＋外部決済リンク**に限定
- **セキュリティ**：Auth必須、書込みは**Functions経由のみ**、App Check、レート制限
- **監査**：発行/回収/ポリシー変更は**監査ログ**へ（改ざん不可ID付き）

---

## 9) リスクと対策
- **発行裁量の恣意性** → 役割分離（発行／監査／運営）＋履歴公開
- **通貨乱立によるUX低下** → `default_currency` を明示、非推奨通貨は `isActive=false`
- **整合性破綻** → **二重仕訳・冪等・夜間検算・ロールバック手順**を標準装備

---

## 10) 実証計画（中央銀行モデル特有の検証）
- **仮説**：「**通貨の見える化＋月次まとめ**」が争議率と手間を下げ、継続率を高める
- **設計**：A/Bで「まとめ精算導線の強化」「既定通貨セレクタの有無」を比較
- **追跡イベント**：`mint_created/posted`, `policy_changed`, `reconciliation_passed/failed`




# 要件定義書（PRD）— EconoBook v0.1

最終更新: 2025-09-25

---

## 0. 概要

* 対象プラットフォーム: iOS / Android / Web（Flutter）
* バックエンド: Firebase（Auth / Firestore / Functions / Storage / Hosting / FCM）
* 基本コンセプト:

  * **モードA: 独自通貨モード（Issuer＝中央銀行あり）**
  * **モードB: 家計簿モード（Issuerなし / JPY記録のみ）**
* 目的（要約）: コミュニティ内の小さな貸し借り・割り勘・タスク報酬を、**透明な記録**と**月次まとめ**で揉めずに完了させる。

> 法務注記: 本PRDはプロダクト仕様であり法的助言ではありません。展開前に専門家確認を推奨。

---

## 1. スコープ

### 1.1 MVP（必須）

* コミュ作成/参加（招待コード or 承認制）、**作成者=Owner**
* **モード選択**: `points`（独自通貨） / `ledger`（家計簿）。**作成後の変更不可**
* モードA:

  * 1コミュ=1中央銀行（Issuer）
  * **複数通貨**（例: ECO/SCORE）、**二重仕訳台帳**、送受信/請求/割り勘/タスク報酬（承認フロー）
  * **月次まとめ精算**（外部決済リンク共有＋完了チェック）
  * 通貨の**発行/回収（mint/burn）**は権限者のみ。**利息はMVP禁止（0%固定/非表示）**
* モードB:

  * **JPY家計簿記録**、割り勘メモ、月次レポート（CSV/PDF）
  * 銀行/通貨/発行関連UI/APIは**存在しない**
* 公開範囲: 本人 / コミュ / 全体
* セキュリティ/整合性: Functions経由のみ書込、冪等キー、夜間検算、監査ログ

### 1.2 非MVP（後回し）

* コミュ間通貨交換、利息・貸付（法務レビュー要）、暗号資産連携、高度マーケット

### 1.3 非ゴール（やらないこと）

* アプリ内での**現金の保管/移転/換金**
* **利息付与・貸金・送金業**に該当し得る機能（MVPでは不実装）

---

## 2. 運用モード定義

| 項目    | モードA: 独自通貨（Issuerあり） | モードB: 家計簿（Issuerなし） |
| ----- | -------------------- | ------------------- |
| 主体    | 中央銀行（Issuer）= 発行主体   | なし（外部決済前提）          |
| 単位    | 複数通貨（ECO/SCORE等）     | 日本円（JPY）            |
| 記録    | **二重仕訳**台帳           | 取引メモ/家計簿エントリ        |
| 機能    | 送受金/請求/割り勘/タスク/発行回収  | 収支入力/割り勘メモ/レポート     |
| 月次まとめ | ネット債権→外部決済リンク→完了チェック | 集計レポート（CSV/PDF）     |
| 利息    | **MVP禁止**（将来検討）      | 概念なし                |

---

## 3. 機能要件（ユースケース別）

### 3.1 コミュニティ & 役割

* コミュ作成者に `Owner` 自動付与（初期 `BankAdmin` も兼務 / モードBはBankAdmin不要）
* Ownerは `BankAdmin` / `CommunityAdmin` / `Auditor` を付与/剥奪可能
* **Owner移譲**フロー（2段階確認）。Owner不在禁止

### 3.2 モードA: 送受金/請求/割り勘/タスク

* **送金**: A → B（通貨/金額/メモ/公開範囲）→ 承認 → post
* **請求**: B → A（期限/自動失効）→ 承認 → post
* **割り勘**: 合計/参加者/按分（均等/端数切捨て）→ 個別承認 → 自動post
* **タスク**: 発注（報酬/締切）→ 応募/担当 → 完了提出 → 発注者承認 → 自動送付
* **月次まとめ**: ネット債権表（人×人）→ 外部決済リンク共有 → 完了チェック

### 3.3 モードA: 銀行/通貨（Issuer）

* **通貨作成/編集**: `symbol`, `displayName`, `decimals`, `supplyCap`, `isActive`, `isScore`

  * `decimals`の**減少は禁止**（桁落ち防止）
* **発行/回収（mint/burn）**: `BankAdmin` 以上のみ
* **既定通貨**: `default_currency_id` を設定（UI初期値）
* **禁止（MVP）**: 貸付利息/預金利息/自動利息ジョブ

### 3.4 モードB: 家計簿

* **収支登録**: `amountJPY`, `category`, `memo`, `participants`
* **割り勘メモ**: 計算→記録（承認postなし）
* **レポート**: 月次集計、CSV/PDFエクスポート

### 3.5 タイムライン & 可視性（共通）

* 活動ログ（取引・請求・タスク・ポリシー変更）
* 公開範囲: 本人/コミュ/全体
* 通報/ブロック/モデレーション

---

## 4. 非機能要件

* パフォーマンス: 主要画面 < 1s, 書込API P50 < 300ms
* 可用性: 99.9%（Firebase標準SLA前提）
* 監査・整合性: 毎日02:00に通貨ごと `Σaccounts ≡ Σledger` 検算、差異=0を目標
* セキュリティ: Auth必須、**Functionsのみ書込**、入力検証、レート制限、App Check
* プライバシー: 未成年モード（上限/時間帯制限）

---

## 5. 権限（RBAC）

### 5.1 役割と初期割当

* **Owner**（作成者・唯一） / **BankAdmin**（Issuer管理） / **CommunityAdmin** / **Auditor** / **Member**
* Ownerは委任/剥奪/移譲が可能（Owner剥奪は移譲のみ）

### 5.2 マトリクス（抜粋）

| 操作               | Owner | BankAdmin | CommunityAdmin | Auditor | Member |
| ---------------- | :---: | :-------: | :------------: | :-----: | :----: |
| コミュ設定編集          |   ○   |     △     |        ○       |    −    |    −   |
| 銀行（Issuer）設定編集   |   ○   |     ○     |        −       |    −    |    −   |
| 通貨 作成/有効・無効      |   ○   |     ○     |        −       |    −    |    −   |
| 発行/回収（mint/burn） |   ○   |     ○     |        −       |    −    |    −   |
| 送金/請求/割り勘/タスク    |   ○   |     ○     |        ○       |    −    |    ○   |
| 監査ログ・台帳閲覧        |   ○   |     ○     |        △       |    ○    |    −   |
| 役割付与/剥奪          |   ○   |     −     |        −       |    −    |    −   |
| Owner移譲          |   ○   |     −     |        −       |    −    |    −   |

---

## 6. データモデル（概略）

### 6.1 共通

```json
communities/{cid}: {
  "name": "Uemura Lab",
  "ownerUid": "uid",
  "mode": "points" | "ledger",
  "default_currency_id": "ECO",     // mode=points のみ
  "policy": { "minorMode": true }
}
memberships/{cid_uid}: {
  "cid": "cid", "uid": "uid", "roles": ["Owner","BankAdmin"], "joinedAt": 1732500000000
}
audit_logs/{id}: {
  "ts": 1732500000000, "actorUid": "uid", "action": "currency_created",
  "target": {"type":"currency","id":"ECO"}, "diff": {...}
}
```

### 6.2 モードA（points）

```json
banks/{bankId}: {
  "cid": "cid",
  "displayName": "Central Bank",
  "status": "active",
  "mintRoles": ["uid_owner"],
  "policy": {"defaultCurrencyId": "ECO", "allowNegative": false, "reconciliationTime": "02:00"}
}
currencies/{curId}: {
  "cid": "cid", "symbol": "ECO", "displayName": "Econo", "decimals": 2,
  "supplyCap": 1000000, "isActive": true, "isScore": false
}
accounts/{accId}: {
  "cid": "cid", "owner_type": "user|bank", "owner_id": "uid_or_bankId",
  "currency_id": "ECO", "balance": 1200
}
ledger/{cid}/entries/{id}: {
  "currency_id": "ECO",
  "type": "transfer|request|split|task|mint|burn|settlement",
  "ts": 1732500000000,
  "lines": [{"account_id":"accA","delta":-100},{"account_id":"accB","delta":100}],
  "createdBy": "uid", "idempotencyKey": "uuid", "status": "posted"
}
requests/{cid}/{reqId}: { "fromUid":"A","toUid":"B","currency_id":"ECO","amount":100,"memo":"", "status":"pending", "expireAt":1732590000000 }
tasks/{cid}/{taskId}: { "title":"実験手伝い","reward":120,"deadline":1732590000000,"status":"open","assigneeUid":null }
```

### 6.3 モードB（ledger）

```json
books/{cid}/entries/{id}: {
  "ts": 1732500000000, "amountJPY": 2400, "category": "food",
  "memo": "飲み会", "participants": ["uidA","uidB"], "splitMode": "equal",
  "externalLink": null, "visibility": "community"
}
reports/{cid}/{month}: {
  "totalsByCategory": {"food": 12000, "transport": 3400},
  "topPartners": [{"uid":"B","totalJPY": 5600}],
  "csvUrl": "gs://...", "pdfUrl": "gs://..."
}
```

**不変条件（mode=points）**

* すべての `ledger` エントリは **二重仕訳**: `sum(lines.delta) == 0`
* `accounts.balance` はトリガで更新（真実は台帳の総和）。夜間検算で `Σaccounts ≡ Σledger`

---

## 7. API（Cloud Functions）サーフェス（擬似）

```ts
// 共通・認証必須・AppCheck・RateLimit・Idempotency
grantRole({ cid, targetUid, role })                // Owner
revokeRole({ cid, targetUid, role })               // Owner
transferOwnership({ cid, newOwnerUid })            // Owner

// モードA（points）
updateBankProfile({ cid, displayName?, policyPatch? })            // Owner/BankAdmin
createCurrency({ cid, symbol, displayName, decimals, supplyCap }) // Owner/BankAdmin
updateCurrency({ cid, currencyId, patch })                        // Owner/BankAdmin
mint({ cid, currencyId, toAccountId, amount, reason, idempotencyKey })  // BankAdmin+
burn({ cid, currencyId, fromAccountId, amount, reason, idempotencyKey }) // BankAdmin+
transfer({ cid, currencyId, fromAccountId, toAccountId, amount, memo, idempotencyKey })
createRequest({ cid, currencyId, fromUid, toUid, amount, memo, expireAt })
approveRequest({ cid, reqId })
createSplit({ cid, currencyId, total, participants[], mode })
createTask({ cid, title, reward, deadline })
completeTask({ cid, taskId })
approveTask({ cid, taskId })
generateMonthlySettlement({ cid, month })
markSettlementDone({ cid, id })

// モードB（ledger）
createLedgerEntry({ cid, amountJPY, category, memo, participants[], splitMode })
updateLedgerEntry({ cid, entryId, patch })
generateMonthlyReport({ cid, month })
exportCSV({ cid, month }); exportPDF({ cid, month })
```

---

## 8. セキュリティ / 整合性 / 監査

* Firestore書込は**すべてFunctions経由**。クライアント直書き禁止（特に `ledger` / `accounts`）
* **冪等性**: すべての書込系APIは `idempotencyKey` 必須
* **夜間検算**: `policy.reconciliationTime`（既定 02:00）で通貨ごと検算。差異は `reconciliation_failed` を発報
* **監査ログ**: 役割変更・通貨作成/編集・発行/回収・ポリシー変更を100%記録（actor/target/diff/ts）
* **ルール方針（例）**

  * mode=points 以外の `ledger` 書込は403
  * `mint/burn` は `BankAdmin` 以上のみ
  * `decimals` 減少のパッチ禁止
  * `default_currency_id` は `currencies.isActive=true` のみ許容

---

## 9. KPI / NSM（運用指標）

* **NSM**: 月次の**円滑完了取引数**（posted・争議なし）
* **一次KPI**: 承認中央値 < 2h / 月次まとめ実行率 ≥ 60% / 争議率 < 1%（48h解決 ≥ 90%）
* **銀行モデルKPI（mode=points）**: 台帳整合性アラート=0 / 不正検知捕捉率 ≥ 99% / ポリシー変更100%履歴化

---

## 10. UX要件（抜粋）

* 既定通貨の明示（モードA） / 当月サマリーの即視（モードB）
* 承認待ちをホーム最上段に固定表示
* 送金/発行/回収は**2段階確認**＋取り消し導線
* 配色: 金融の安心感（ブルー/グリーン系）、シンプル導線

---

## 11. 受入基準（MVP）

* **E2E**: 代表ユースケース（送金 or 請求）が **合意→実行→記録→月次完了** まで通る
* **二重仕訳**: `sum(lines.delta)=0` 未達=0件
* **監査**: 通貨作成/発行/回収/ポリシー変更の**100%記録**
* **RBAC**: `Member` の `mint/burn` が403、Owner移譲が正常動作
* **モード分岐**:

  * mode=points: 銀行/通貨/台帳UI/APIが利用可
  * mode=ledger: それらが**非表示/403**、家計簿機能のみ可

---

## 12. リスクと対策（要点）

* 発行裁量の恣意性 → 役割分離（発行/監査/運営）＋履歴公開
* 通貨乱立→ `default_currency` 指定、非推奨は `isActive=false`
* 法規制リスク→ **利息なし**運用、現金チャージ・換金不可、外部決済リンクのみ

---

## 13. 付録A: 用語

* **中央銀行（Issuer）**: コミュ内ポイントの唯一の発行主体（UX呼称）。規約上はIssuerと表記
* **二重仕訳**: 仕訳行の増減合計=0にする会計方式
* **月次まとめ**: ネット債権表示→外部決済→完了チェック

---

## 14. 付録B: 代表イベント（テレメトリ）

```
community_created
currency_created/updated
transfer_created/approved/posted/failed
request_created/approved/expired
split_created/posted
task_created/completed/approved
mint_posted / burn_posted
policy_changed
reconciliation_passed/failed
report_submitted
```

---

## 15. 今後の拡張（ドラフト）

* 無利息与信（credit line）・ボーナス配布ルール
* まとめ精算の自動リマインド/A/B導線最適化
* 監査ビュー（差異の自動診断、再計算ツール）

---














iosアプリ、Androidアプリ、webアプリ
アプリ名: EconoBook

### **1
. 基本的な金融・取引機能**

* **コミュニティ内通貨の発行**
  各コミュニティが自由に独自通貨を設定できる。自分でコミュニティを作成可能だし、存在するコミュニティに参加も可能。
  独自の中央銀行を設置でき、通貨の発行枚数や単位、借入制限や利息など、自由に銀行システムを構築できる。
  その通貨を利用し、家族であれば家事の手伝いや、学生であれば課題の手伝いなど、そのコミュニティにあった取引が可能である。
  また、先に自分の報酬通貨料と仕事内容を決めることも可能ですし、トークで話し合って決めることも可能。
* **複数通貨対応**
  独自通貨と円（実通貨）を関連させることもできる。「日本円 = 独自通貨×数字」　のように。ただし、アプリ内での実通貨を移動させることは考えていない。ペイペイなどの送金リンクを作成できるまでとし、お互いの認証により円として交換記録を残すことも可能。
* **送金・受取・請求**
  個人間・グループ間でお金や通貨をやりとりできる。
* **割り勘機能**
  食事会などで自動計算して精算。
* **月次まとめ払い**
  家族や友人間の取引を一度に精算（振込手数料の削減にもつながる）。

### **2. SNS的機能**

* **コミュニティ作成・参加機能**
  家族、サークル、会社など自由にグループを作れる。
* **取引履歴のタイムライン表示**
  （プライベート設定を含めて）活動や取引のログを見られる。
* **ニュース/トラブル共有欄**
  他コミュニティの問題事例を共有、仲裁や学びに使える。
* **プロフィール/信用スコア**
  取引履歴から「信用度」「信頼スコア」を可視化。
* 全体共通の通貨として仮名「信用スコア」を作成する。
  この通貨はトラブルの仲介に入って解決したなどにより、恩恵を受けた人から信用スコアが渡される。これは累積されていく。
  信用スコアの使い道は他にも考えていく。

### **3. 分析機能**

* **グラフ表示**
  支出・収入を円グラフや棒グラフで可視化。
* **予算設定とアラート**
  月ごとに「交際費1万円まで」など設定でき、超えると通知。

### **4. セキュリティ・認証**

* **二段階認証**（Google/LINE連携など）
* **トランザクション承認**
  PIN/生体認証で送金を確認。
* **取引の非公開設定**
  公開範囲を「本人のみ」「コミュニティ内」「全体」から選択。

---

## **🔹 非機能要件（Non-functional Requirements）**

* **UX/UI**
  * LINE感覚で使えるシンプルな操作感
  * アプリ色（ブルーやグリーン系で「金融」「安心感」を表現）
* **パフォーマンス**
  * 1秒以内のレスポンスで送金・表示が行える
* **スケーラビリティ**
  * コミュニティ数・ユーザー数が増えても耐えられる設計
* **セキュリティ**
  * 金融取引のため暗号化・データ保護必須
  * 不正検知・アラート機能
* **法令遵守**
  * 資金決済法や電子マネー規制に準拠

---

## **🔹 ユーザーが喜ぶポイント**

1. **「家族でも友達でも使える」柔軟さ**
   → 家計簿、割り勘、授業の代行など多様なケースに対応。
2. **「実際のお金＋仮想通貨」両方扱える**
   → 遊びの通貨と現金の使い分け。
3. **「信頼感」**
   → 透明性のある履歴と信用スコアで安心してやり取りできる。
4. **「便利さ」**
   → 毎回送金する必要がなく月次まとめ払いで楽。
5. **「学び・安全」**
   → ニュース/トラブル共有から知見を得て、安心感も高まる。

「**仮想通貨・ポイント型の金融系SNS**」として、**個人開発でも始めやすく、法規制のハードルを下げる前提**で要件をまとめます。Flutter＋Firebase（Auth/Firestore/Functions）前提に落とし込みも付けました。

# **1) プロダクト方針（コンプラ前提）**

* **法的位置付け：****ゲーム内ポイント/コミュニティ内ポイント**
  * **現金等価ではない（** **換金不可** **・** **利息不可** **・** **外部送金不可** **）**
  * 利用規約に「ポイントは事業者の裁量で付与/没収/失効可」「金銭請求権なし」を明記
* 実通貨は**外部決済サービス**（PayPay/Stripe/銀行振込など）へリンクのみ（アプリ外で精算）
* コミュニティ間のポイント相互交換は当面なし（相場/両替回避）
* **年齢制限・未成年保護**：親権者同意、上限額/時間制限
* **禁止用途**：報酬型バイト仲介などのグレー行為を規約で抑止、通報・BAN

# **2) コア機能（MVP）**

## **A. コミュニティ＆ポイント**

* コミュニティ作成/参加（招待コード or 承認制）
* コミュニティごとの**独自ポイント**（名称/シンボル/桁数/失効期限/上限）
* 権限ロール：Owner / Admin / Member（鑑定人/仲介人は拡張）

## **B. 取引（ポイント）**

* **P2P送受信** **／** **請求（Request）** **／****割り勘（Split）**
* **月次まとめ精算（擬似）**
  * 月末にコミュニティが**ネット債権マトリクス**を提示 → 外部決済で実際に送金（アプリ内は「完了チェック」）
* **タスク型取引**（大学の課題手伝い等）：
  * 投稿（タイトル/報酬ポイント/締切）→ 申込 → 完了承認で自動送付

## **C. タイムライン / SNS**

* 取引・タスクの**活動ログ**（公開範囲：本人/コミュ内/全体）
* **ニュース/トラブル掲示板**（事例共有、学び、仲介募集）
* いいね/コメント/通報

## **D. 家計簿・可視化**

* カテゴリ自動付与（フード/交通/学業…）
* **ダッシュボード**：月次支出・ポイント収支・トップ相手・タグ別
* 予算アラート（カテゴリ上限）

## **E. 信用/安全**

* **信用スコア**（遅延率、完了率、相手評価、通報率）
* **エスクロー風の承認フロー**（タスク完了→発注者承認→送付）
* 通報・モデレーション（違反回数で自動制限）

# **3) 非機能要件**

* **パフォーマンス**：主要画面<1s表示、一覧は無限スクロール
* **スケーラビリティ** **：ポイントは****二重仕訳台帳**で整合性担保
* **セキュリティ**：Auth必須／Cloud Functions経由で**サーバーサイド検証**／Cloud Logging
* **プライバシー**：公開範囲の既定値は「コミュ内」、未成年はさらに制約
* **信頼性**：冪等エンドポイント（重複送信防止）、整合性ジョブ（夜間検算）

# **4) データモデル（Firestore案）**

```
users/{uid}
  displayName, photoUrl, dob, role, communityIds[]
  score: {trust, completionRate, disputeRate, lastCalcAt}

communities/{cid}
  name, icon, ownerUid, policy, point: {symbol, decimals, expireDays, dailyCap}

memberships/{cid_uid}
  cid, uid, role, joinedAt, balance  // ← 集計キャッシュ（正は受取超過）

ledger/{cid}/entries/{entryId}  // 二重仕訳
  ts, type: 'transfer'|'request'|'split'|'task',
  fromUid, toUid, amount, memo, status:'pending|posted|reversed',
  lines: [
    {uid:A, delta:-100}, {uid:B, delta:+100}
  ],
  requestRef, taskRef, splitGroupId, createdBy, idempotencyKey

requests/{cid}/{reqId}
  fromUid, toUid, amount, memo, status, expireAt

tasks/{cid}/{taskId}
  title, desc, reward, deadline, status, assigneeUid, proofUrl

news/{cid}/{postId}
  category:'lesson|trouble|mediator', body, visibility, reports[], comments[]
```

> **ポイント計算**は**ledger.linesの総和＝0**、ユーザ残高は定期ジョブで再集計 or トランザクションで更新。

> **idempotencyKey**で多重POST防止。

# **5) セキュリティルール（要点）**

* 取引作成は**Cloud Functions**のみ許可（クライアント直書き禁止）
* **所有者本人以外は自残高更新不可**
* 可視性：**visibility**に応じて読取制御
* 児童保護：未成年は夜間投稿制限/高額上限

# **6) ワークフロー（主要ユースケース）**

1. **送金**：A→Bへ100pt請求 → B承認 → Functionsが二重仕訳→**posted**
2. **タスク**：Aが課題手伝い募集（100pt）→ Bが完了提出 → A承認→送付
3. **割り勘**：レシート金額入力→参加者選択→自動按分→各自に請求→承認
4. **月次まとめ**：コミュのネット債権算出→外部決済リンク共有→完了チェック

# **7) 画面（Flutter想定）**

* **Home**：検索/フィルタ（内部/外部）＋直近取引＋タスク
* **Talk/コミュ**：スレッド＋ポイント小計＋割り勘作成
* **Bank**：ポイント残高、入出力履歴、エクスポート
* **News**：事例/トラブル、仲介応募
* **Account**：本人設定、未成年モード、上限、通知設定

> ※今のコードではHomeScreen**が複数ファイルで重複定義されています（**sign_in_screen.dart**や**sign_up_screen.dart**内）。****クラス名を画面ごとに分離**（SignInScreen**, **SignUpScreen**, **HomeScreen**）し、**main.dart**の**if (user==null) return SignInScreen();** の****const**を外す**とホットリロードのエラーは消えます。**

# **8) ユーザーが特に喜ぶ差別化ポイント**

* **まとめ精算の強力UI**（「今月はA→B 1,240pt相当、C→D 820pt…」を自動提示）
* **信頼スコアの透明な算出式**（遅延・通報・相互評価を明示）
* **仲介ロール**と**エスカレーション**（揉めた時に第三者が入りやすい）
* **タスク市場**（授業・研究・日常の軽作業に即時ポイント）
* **学びのニュース欄**（失敗事例のテンプレ化→再発防止）

# **9) 開発ロードマップ**

* **M0（2–3週間）**：コミュ作成/参加・P2P送受信（Functions+二重仕訳）・家計簿自動分類
* **M1**：割り勘・請求、ダッシュボード、信用スコアv1
* **M2**：タスク市場、ニュース/トラブル、仲介ロール
* **M3**：月次まとめ精算の外部決済連携（リンク共有）・未成年モード

# **10) 失敗しない運用・法務メモ（軽量版）**

* **利用規約／プラポリ：ポイントは** **金銭債権でない** **、** **換金不可** **、** **有効期限** **、** **付与/失効** **、** **禁止行為** **、** **通報** **、****仲裁フロー**
* 監査ログ：全取引に署名・操作ユーザ・端末情報（不正検知）
* サポート：チャット通報→モデレーションキュー→SLA目標

通貨は信用ポイントに変換できたりする。
