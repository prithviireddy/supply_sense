# backend/test_scripts/test_connections.py

import sys

sys.path.append("..")

import boto3
from google import genai
from tavily import TavilyClient

from backend.config.settings import get_settings
from backend.utils.database_utils import test_connection

settings = get_settings()

print("\n=== RiskWise Connection Tests ===\n")

# Test 1: Database
print("1. Testing PostgreSQL (RDS)...")
test_connection()

# Test 2: AWS S3
print("\n2. Testing AWS S3...")
s3 = boto3.client("s3", region_name=settings.aws_region)
buckets = s3.list_buckets()
print(f"✅ S3 connected. Buckets: {[b['Name'] for b in buckets['Buckets']]}")

# Test 3: Gemini
print("\n3. Testing Gemini...")
client = genai.Client(api_key=settings.google_api_key)
response = client.models.generate_content(
    model=settings.gemini_model,
    contents="Say: SupplySense Online" 
)

print(f"✅ Gemini: {response.text}")

# Test 4: Tavily
print("\n4. Testing Tavily...")
tavily = TavilyClient(api_key=settings.tavily_api_key)
results = tavily.search("supply chain risk 2025", max_results=1)
print(f"✅ Tavily: Got {len(results['results'])} result(s)")

print("\n=== All systems go! Ready for Phase 1 ===\n")
