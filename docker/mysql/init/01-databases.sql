CREATE DATABASE IF NOT EXISTS requests_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE DATABASE IF NOT EXISTS catalog_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE DATABASE IF NOT EXISTS crews_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

CREATE DATABASE IF NOT EXISTS report_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

GRANT ALL PRIVILEGES ON requests_db.* TO 'barriodigital_app'@'%';
GRANT ALL PRIVILEGES ON catalog_db.* TO 'barriodigital_app'@'%';
GRANT ALL PRIVILEGES ON crews_db.* TO 'barriodigital_app'@'%';
GRANT ALL PRIVILEGES ON report_db.* TO 'barriodigital_app'@'%';
