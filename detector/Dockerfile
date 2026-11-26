# yi-detector: person / animal detection with coloured boxes
#
# Stage 1 (runs on the build machine): export YOLOv8n to ONNX
FROM --platform=$BUILDPLATFORM python:3.12-slim AS model
RUN pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir ultralytics onnx
WORKDIR /model
RUN yolo export model=yolov8n.pt format=onnx imgsz=640 opset=12 \
 && ls -la /model/yolov8n.onnx

# Stage 2: small runtime (amd64 / arm64)
FROM python:3.12-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libglib2.0-0 libgomp1 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --from=model /model/yolov8n.onnx /app/yolov8n.onnx
COPY detector.py /app/detector.py
ENV MODEL=/app/yolov8n.onnx PYTHONUNBUFFERED=1
EXPOSE 8090
HEALTHCHECK --interval=60s --timeout=5s CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8090/health',timeout=4)"
CMD ["python", "/app/detector.py"]
