from fastapi import FastAPI, UploadFile, File
from faster_whisper import WhisperModel
import tempfile


app = FastAPI()

model = WhisperModel("large-v3", device="cuda", compute_type="float16")


@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile = File(...)):
  with tempfile.NamedTemporaryFile(delete=False) as tmp:
    tmp.write(await file.read())
    segments, _ = model.transcribe(tmp.name)
    text = " ".join([s.text for s in segments])
  return { "text": text }
