-- Главный файл инициализации
\i /docker-entrypoint-initdb.d/01_tables.sql
\i /docker-entrypoint-initdb.d/02_indexes.sql
\i /docker-entrypoint-initdb.d/03_triggers.sql
\i /docker-entrypoint-initdb.d/04_views.sql
\i /docker-entrypoint-initdb.d/05_functions.sql
\i /docker-entrypoint-initdb.d/06_load_generated.sql
\i /docker-entrypoint-initdb.d/07_seed_basic.sql