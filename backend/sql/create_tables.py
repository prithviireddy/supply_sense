"""file that actually creates the tables"""
import os
from dotenv import load_dotenv
import psycopg2
from pathlib import Path
load_dotenv()

conn = psycopg2.connect(
    host=os.getenv("DB_HOST"),
    port=os.getenv("DB_PORT", 5432),
    dbname=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
)
conn.autocommit = True
cursor = conn.cursor()

BASE_DIR = Path(__file__).resolve().parents[0]
sql_path = BASE_DIR / "create_table.sql"

with open(sql_path, "r") as f:
    sql = f.read()

print("⏳ Running create_table.sql ...")
cursor.execute(sql)
print("✅ All tables created successfully!")

# Verify — list all tables
cursor.execute("""
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public'
    ORDER BY table_name;
""")
tables = cursor.fetchall()
print(f"\n📋 Tables in database ({len(tables)} total):")
for t in tables:
    print(f"  • {t[0]}")

cursor.close()
conn.close()
