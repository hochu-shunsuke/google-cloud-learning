# Phase 5: Looker Studio ダッシュボード

BigQuery に蓄積した画像解析結果を [Looker Studio](https://lookerstudio.google.com/) で可視化します。  
**無料・ノーコード**で動作するBIツールです。

## ダッシュボード完成イメージ

```
┌─────────────────────────────────────────────────────┐
│  AI画像解析ダッシュボード                             │
│                                                     │
│  [スコアカード]     [スコアカード]                    │
│  総解析数: 42      今日の解析: 5                      │
│                                                     │
│  [折れ線グラフ: 日別アップロード数推移]                │
│                                                     │
│  [棒グラフ: ラベルランキング TOP10]                   │
│                                                     │
│  [円グラフ: ラベル分布]                               │
│                                                     │
│  [テーブル: 最新解析結果]                             │
└─────────────────────────────────────────────────────┘
```

## 手順1: BigQuery ビューを作成

```bash
cd phase5-looker-studio

# ビューを一括作成
bq query \
  --use_legacy_sql=false \
  --project_id=gen-lang-client-0213648671 \
  "$(cat views.sql)"
```

作成されるビュー:

| ビュー名 | 内容 | 推奨チャート |
|---------|------|-------------|
| `v_label_daily_count` | ラベル別・日別カウント | 棒グラフ・折れ線グラフ |
| `v_daily_uploads` | 日別アップロード数 | 折れ線グラフ・スコアカード |
| `v_label_ranking` | ラベル総合ランキング | 棒グラフ・円グラフ |
| `v_recent_results` | 最新100件 | テーブル |

## 手順2: Looker Studio でデータソース接続

1. [Looker Studio](https://lookerstudio.google.com/) を開く
2. **「空のレポート」** をクリック
3. 「データを追加」→ **「BigQuery」** を選択
4. GCP プロジェクト `gen-lang-client-0213648671` を選択
5. データセット `image_analysis` → ビュー（例: `v_label_ranking`）を選択
6. 「追加」をクリック

> **ヒント**: グラフごとに異なるビューをデータソースとして追加できます

## 手順3: ダッシュボードを構築

### スコアカード（総解析数）

1. 「グラフを追加」→「スコアカード」
2. データソース: `v_daily_uploads`
3. 指標: `upload_count`（SUM）
4. タイトル: 「総解析数」

### 折れ線グラフ（日別アップロード数推移）

1. 「グラフを追加」→「折れ線グラフ」
2. データソース: `v_daily_uploads`
3. ディメンション: `analyzed_date`
4. 指標: `upload_count`

### 棒グラフ（ラベルランキング TOP10）

1. 「グラフを追加」→「棒グラフ」
2. データソース: `v_label_ranking`
3. ディメンション: `label`
4. 指標: `total_count`
5. 並べ替え: `total_count` 降順
6. 行数の上限: 10

### 円グラフ（ラベル分布）

1. 「グラフを追加」→「円グラフ」
2. データソース: `v_label_ranking`
3. ディメンション: `label`
4. 指標: `percentage`

### テーブル（最新解析結果）

1. 「グラフを追加」→「テーブル」
2. データソース: `v_recent_results`
3. ディメンション: `object_name`, `labels`, `analyzed_at`

## 手順4: 自動更新の設定

1. 右上の「...」→「レポートの設定」
2. 「データキャッシュ」を **「12時間ごと」** に設定
   - 無料枠では頻繁な更新はクエリコスト増大につながるため適度に設定

## 手順5: 共有

1. 右上の「共有」をクリック
2. URLリンクを共有、または「埋め込む」でWebに貼り付け可能

## 参考: BigQuery でデータを確認

```bash
# ラベルランキング確認
bq query --use_legacy_sql=false \
  'SELECT label, total_count, percentage FROM `gen-lang-client-0213648671.image_analysis.v_label_ranking` LIMIT 10'

# 日別アップロード数確認
bq query --use_legacy_sql=false \
  'SELECT analyzed_date, upload_count FROM `gen-lang-client-0213648671.image_analysis.v_daily_uploads` ORDER BY analyzed_date DESC'
```

## アーキテクチャ上の位置づけ

```
画像アップロード (Phase1)
    ↓
Vision AI 解析 (Phase3)
    ↓
BigQuery 蓄積 (Phase4)
    ↓
Looker Studio 可視化 (Phase5) ← ここ
```
