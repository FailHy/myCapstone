import asyncio
import websockets
import json
import urllib.request
import time

async def test_training_ws():
    print("1. Meminta Session ID baru (POST /session/start)...")
    try:
        # Melakukan HTTP POST untuk membuat sesi (sesuai dengan main.py)
        req_data = json.dumps({"user_id": "test_user_1", "exercise_type": "biceps"}).encode("utf-8")
        req = urllib.request.Request(
            "http://localhost:8000/session/start", 
            data=req_data,
            headers={'Content-Type': 'application/json'}
        )
        
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read())
            session_id = result["session_id"]
            print(f"✅ Sesi berhasil dibuat! Session ID: {session_id}")
            
    except urllib.error.URLError as e:
        print(f"❌ Gagal membuat sesi. Pastikan server FastAPI menyala. Error: {e}")
        return
    except Exception as e:
        print(f"❌ Terjadi kesalahan saat request HTTP: {e}")
        return

    # Target endpoint WebSocket menggunakan session_id yang baru didapat
    uri = f"ws://localhost:8000/ws/{session_id}"
    
    # Format data disesuaikan dengan schema PredictRequest
    # Mengubah format menjadi dictionary spesifik untuk shoulder, elbow, hip, dan wrist
    dummy_pose_data = {
        "timestamp": time.time(),
        "landmarks": {
            "shoulder": {"x": 0.5, "y": 0.5, "z": 0.0, "visibility": 0.99},
            "elbow": {"x": 0.5, "y": 0.5, "z": 0.0, "visibility": 0.99},
            "hip": {"x": 0.5, "y": 0.5, "z": 0.0, "visibility": 0.99},
            "wrist": {"x": 0.5, "y": 0.5, "z": 0.0, "visibility": 0.99}
        }
    }

    print(f"\n2. Mencoba koneksi WebSocket ke {uri}...")
    try:
        async with websockets.connect(uri) as websocket:
            print("✅ Berhasil terkoneksi ke WebSocket!")
            
            # --- Test 1: Kirim data yang benar ---
            message = json.dumps(dummy_pose_data)
            print("\n[Test 1] Mengirim payload dummy MediaPipe yang sudah diubah ke Dictionary...")
            await websocket.send(message)
            
            # Tunggu dan print balasan (hasil dari evaluator.process_frame)
            print("⏳ Menunggu balasan dari server FastAPI...")
            response_str = await websocket.recv()
            
            response_json = json.loads(response_str)
            print("⬅️ Diterima (Test 1):")
            print(json.dumps(response_json, indent=2))
            
            # --- Test 2: Kirim data dengan format salah untuk memicu ValidationError ---
            print("\n[Test 2] Mengirim payload format salah (tanpa timestamp)...")
            bad_data = {"wrong_key": [1, 2, 3]}
            await websocket.send(json.dumps(bad_data))
            
            response_str = await websocket.recv()
            print("⬅️ Diterima (Test 2):")
            print(response_str)
            
            print("\n✅ Semua pengujian selesai. Memutus koneksi.")

    except ConnectionRefusedError:
        print("❌ Koneksi ditolak.")
        print("Pastikan server FastAPI Anda sedang berjalan.")
    except websockets.exceptions.InvalidStatus as e:
         print(f"❌ Handshake gagal dengan status code: {e.status_code}")
         if e.status_code == 403:
             print("👉 Error 403 Forbidden: Server FastAPI menolak koneksi WebSocket.")
         else:
             print(f"Pesan error: {e}")
    except websockets.exceptions.ConnectionClosed as e:
        print(f"\n❌ Server FastAPI memutus koneksi secara tiba-tiba (Connection Closed: {e})")
        print("👉 PENYEBAB UTAMA: Terjadi error internal di backend Anda saat memproses 'Test 1'.")
        print("👉 SOLUSI: Silakan cek jendela terminal tempat server FastAPI Anda berjalan.")
    except Exception as e:
        print(f"\n❌ Terjadi kesalahan tidak terduga: {e}")

if __name__ == "__main__":
    asyncio.run(test_training_ws())