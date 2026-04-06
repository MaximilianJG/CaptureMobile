#!/usr/bin/env python3
"""
Quick test script for the Capture backend API.
Usage: python test_api.py [local|prod]
"""

import sys
import base64
import requests

LOCAL_URL = "http://localhost:8000"
PROD_URL = "https://capturemobile-production.up.railway.app"
API_KEY = "bad3515c210e9b769dcb3276cb18553ebff1f0b3935c84f4f1d3aedc064c30e4"


def get_base_url():
    if len(sys.argv) > 1 and sys.argv[1] == "local":
        return LOCAL_URL
    return PROD_URL


def test_health():
    url = f"{get_base_url()}/health"
    print(f"\nTesting: GET {url}")
    try:
        r = requests.get(url, timeout=10)
        print(f"  Status: {r.status_code}  Response: {r.json()}")
        return r.status_code == 200
    except Exception as e:
        print(f"  Error: {e}")
        return False


def test_stats():
    url = f"{get_base_url()}/stats"
    print(f"\nTesting: GET {url}")
    try:
        r = requests.get(url, headers={"X-API-Key": API_KEY}, timeout=10)
        print(f"  Status: {r.status_code}  Response: {r.json()}")
        return r.status_code == 200
    except Exception as e:
        print(f"  Error: {e}")
        return False


def test_capture(image_path: str = None):
    url = f"{get_base_url()}/capture"
    print(f"\nTesting: POST {url}")

    if image_path:
        with open(image_path, "rb") as f:
            image_data = base64.b64encode(f.read()).decode()
        print(f"  Using image: {image_path}")
    else:
        print("  Using text-only capture")
        image_data = None

    payload = {"user_id": "test_user_123", "source": "screenshot"}
    if image_data:
        payload["image"] = image_data
    else:
        payload["text"] = "Dinner at Tantris Munich, modern European cuisine, 8pm Friday"

    try:
        r = requests.post(url, json=payload, headers={
            "Content-Type": "application/json", "X-API-Key": API_KEY
        }, timeout=30)
        print(f"  Status: {r.status_code}  Response: {r.json()}")
        return r.status_code == 200
    except Exception as e:
        print(f"  Error: {e}")
        return False


def main():
    base = get_base_url()
    print(f"Testing Capture Backend API — {base}")
    print("=" * 50)

    results = [
        ("Health", test_health()),
        ("Stats", test_stats()),
    ]

    if len(sys.argv) > 2:
        results.append(("Capture (image)", test_capture(sys.argv[2])))
    else:
        results.append(("Capture (text)", test_capture()))
        print("\nTip: Pass an image path to test with an image:")
        print("  python test_api.py local /path/to/screenshot.png")

    print("\n" + "=" * 50)
    for name, passed in results:
        print(f"  {'PASS' if passed else 'FAIL'} — {name}")


if __name__ == "__main__":
    main()
