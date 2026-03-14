from backend.config.settings import get_settings
import psycopg

settings = get_settings()

conn = psycopg.connect(
    host=settings.db_host,
    port=settings.db_port,
    dbname=settings.db_name,
    user=settings.db_user,
    password=settings.db_password,
    sslmode="require",
)

print("Connected")
