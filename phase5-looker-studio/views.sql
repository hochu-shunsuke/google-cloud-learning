-- ================================================================
-- Phase 5: Looker Studio 用 BigQuery ビュー
-- BigQuery コンソール または bq コマンドで実行してください
-- 実行: bq query --use_legacy_sql=false < views.sql
-- ================================================================

-- ----------------------------------------------------------------
-- ビュー 1: ラベル別・日別カウント
-- Looker Studio での「棒グラフ / 時系列グラフ」用
-- ----------------------------------------------------------------
CREATE OR REPLACE VIEW `image_analysis.v_label_daily_count` AS
SELECT
  TRIM(label)       AS label,
  DATE(analyzed_at) AS analyzed_date,
  COUNT(*)          AS count
FROM
  `image_analysis.results`,
  UNNEST(SPLIT(labels, ',')) AS label
WHERE
  labels IS NOT NULL
  AND TRIM(label) != ''
GROUP BY
  label,
  analyzed_date
ORDER BY
  analyzed_date DESC,
  count DESC;

-- ----------------------------------------------------------------
-- ビュー 2: 日別アップロード数
-- Looker Studio での「折れ線グラフ / スコアカード」用
-- ----------------------------------------------------------------
CREATE OR REPLACE VIEW `image_analysis.v_daily_uploads` AS
SELECT
  DATE(analyzed_at) AS analyzed_date,
  COUNT(*)          AS upload_count
FROM
  `image_analysis.results`
WHERE
  analyzed_at IS NOT NULL
GROUP BY
  analyzed_date
ORDER BY
  analyzed_date DESC;

-- ----------------------------------------------------------------
-- ビュー 3: ラベル総合ランキング（全期間）
-- Looker Studio での「円グラフ / 表」用
-- ----------------------------------------------------------------
CREATE OR REPLACE VIEW `image_analysis.v_label_ranking` AS
SELECT
  TRIM(label) AS label,
  COUNT(*)    AS total_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage
FROM
  `image_analysis.results`,
  UNNEST(SPLIT(labels, ',')) AS label
WHERE
  labels IS NOT NULL
  AND TRIM(label) != ''
GROUP BY
  label
ORDER BY
  total_count DESC;

-- ----------------------------------------------------------------
-- ビュー 4: 最新解析結果（直近100件）
-- Looker Studio での「テーブル」用
-- ----------------------------------------------------------------
CREATE OR REPLACE VIEW `image_analysis.v_recent_results` AS
SELECT
  object_name,
  labels,
  description,
  analyzed_at,
  DATE(analyzed_at) AS analyzed_date
FROM
  `image_analysis.results`
ORDER BY
  analyzed_at DESC
LIMIT 100;
