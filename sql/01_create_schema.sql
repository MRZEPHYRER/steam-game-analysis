CREATE TABLE IF NOT EXISTS games (
  appid INT UNSIGNED NOT NULL,
  sample_id SMALLINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  release_date DATE NOT NULL,
  release_month CHAR(7) NOT NULL,
  developer JSON NOT NULL,
  publisher JSON NULL,
  is_free BOOLEAN NOT NULL,
  platform_windows BOOLEAN NOT NULL,
  platform_mac BOOLEAN NOT NULL,
  platform_linux BOOLEAN NOT NULL,
  is_early_access BOOLEAN NULL,
  metadata_collected_at DATETIME(6) NOT NULL,
  sample_seed INT UNSIGNED NOT NULL,
  sampling_stratum CHAR(7) NOT NULL,
  sampling_source VARCHAR(64) NOT NULL,
  PRIMARY KEY (appid),
  UNIQUE KEY uq_games_sample_id (sample_id),
  CONSTRAINT chk_games_release_month
    CHECK (release_month REGEXP '^[0-9]{4}-[0-9]{2}$'),
  CONSTRAINT chk_games_boolean_values
    CHECK (
      is_free IN (0, 1)
      AND platform_windows IN (0, 1)
      AND platform_mac IN (0, 1)
      AND platform_linux IN (0, 1)
      AND (is_early_access IS NULL OR is_early_access IN (0, 1))
    )
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS genres (
  genre_id SMALLINT UNSIGNED NOT NULL,
  genre_name VARCHAR(100) NOT NULL,
  PRIMARY KEY (genre_id),
  UNIQUE KEY uq_genres_name (genre_name)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS game_genres (
  appid INT UNSIGNED NOT NULL,
  genre_id SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (appid, genre_id),
  CONSTRAINT fk_game_genres_game
    FOREIGN KEY (appid) REFERENCES games (appid),
  CONSTRAINT fk_game_genres_genre
    FOREIGN KEY (genre_id) REFERENCES genres (genre_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS review_snapshots (
  appid INT UNSIGNED NOT NULL,
  total_reviews INT UNSIGNED NOT NULL,
  positive_reviews INT UNSIGNED NOT NULL,
  negative_reviews INT UNSIGNED NOT NULL,
  positive_rate DECIMAL(20,18) NULL,
  review_score TINYINT UNSIGNED NULL,
  review_score_desc VARCHAR(100) NULL,
  review_language VARCHAR(32) NOT NULL,
  review_purchase_type VARCHAR(32) NOT NULL,
  review_type VARCHAR(32) NOT NULL,
  filter_offtopic_activity BOOLEAN NOT NULL,
  day_range SMALLINT UNSIGNED NOT NULL,
  review_collected_at DATETIME(6) NOT NULL,
  review_status VARCHAR(32) NOT NULL,
  schema_error TEXT NULL,
  http_status SMALLINT UNSIGNED NULL,
  request_retry_count SMALLINT UNSIGNED NULL,
  request_latency_seconds DECIMAL(16,6) NULL,
  http_429_count SMALLINT UNSIGNED NULL,
  http_5xx_count SMALLINT UNSIGNED NULL,
  transport_error_count SMALLINT UNSIGNED NULL,
  PRIMARY KEY (appid),
  CONSTRAINT fk_review_snapshots_game
    FOREIGN KEY (appid) REFERENCES games (appid),
  CONSTRAINT chk_review_count_identity
    CHECK (positive_reviews + negative_reviews = total_reviews),
  CONSTRAINT chk_review_positive_rate
    CHECK (
      (total_reviews = 0 AND positive_rate IS NULL)
      OR
      (total_reviews > 0 AND positive_rate BETWEEN 0 AND 1)
    ),
  CONSTRAINT chk_review_status
    CHECK (
      review_status IN (
        'success', 'unavailable', 'request_failed', 'schema_invalid'
      )
    )
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS price_snapshots (
  price_snapshot_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  appid INT UNSIGNED NOT NULL,
  list_price_cents INT UNSIGNED NULL,
  current_price_cents INT UNSIGNED NULL,
  discount_percent TINYINT UNSIGNED NULL,
  price_currency CHAR(3) NULL,
  price_collected_at DATETIME(6) NOT NULL,
  PRIMARY KEY (price_snapshot_id),
  UNIQUE KEY uq_price_game_time (appid, price_collected_at),
  CONSTRAINT fk_price_snapshots_game
    FOREIGN KEY (appid) REFERENCES games (appid),
  CONSTRAINT chk_price_discount
    CHECK (
      discount_percent IS NULL
      OR discount_percent BETWEEN 0 AND 100
    )
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS collection_runs (
  run_id VARCHAR(64) NOT NULL,
  source_type VARCHAR(32) NOT NULL,
  dataset_name VARCHAR(128) NOT NULL,
  started_at DATETIME(6) NULL,
  completed_at DATETIME(6) NOT NULL,
  row_count INT UNSIGNED NOT NULL,
  status VARCHAR(32) NOT NULL,
  query_contract JSON NULL,
  dataset_sha256 CHAR(64) NOT NULL,
  notes TEXT NULL,
  PRIMARY KEY (run_id),
  CONSTRAINT chk_collection_run_hash
    CHECK (dataset_sha256 REGEXP '^[0-9A-F]{64}$')
) ENGINE=InnoDB;
