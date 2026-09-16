-- Run interactively as a MySQL administrative account.
-- Replace <SET_PASSWORD_MANUALLY> before execution. Never commit the password.
CREATE DATABASE IF NOT EXISTS steam_game_analysis
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE USER IF NOT EXISTS 'steam_analyst'@'localhost'
  IDENTIFIED BY '<SET_PASSWORD_MANUALLY>';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX,
      REFERENCES, CREATE VIEW, SHOW VIEW
  ON steam_game_analysis.*
  TO 'steam_analyst'@'localhost';

FLUSH PRIVILEGES;
