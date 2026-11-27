#!/usr/bin/env python3
"""yi-detector: person / animal detection for YI-Hack-Tiz cameras.

The camera itself is far too small for a neural network, so this service runs
on a server (NAS, mini PC, Raspberry Pi 4/5, Home Assistant host):

* reads the camera stream (RTSP) or snapshots (HTTP),
* runs YOLOv8n (ONNX) on EVERY sampled frame - the whole picture, not only
  the moving parts - so people and animals are found even when they do not move,
* draws a coloured box per object (default: person blue, dog green),
* serves the annotated picture as MJPEG stream / JPEG snapshot,
* publishes presence to MQTT with Home Assistant discovery (optional).
"""

import argparse
import base64
import json
import logging
import os
import signal
import hmac
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2
import numpy as np
import onnxruntime as ort
import yaml

log = logging.getLogger("yi-detector")

# COCO class names (YOLOv8 order)
COCO = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
    "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
    "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
    "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
    "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
    "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
    "toothbrush",
]

# Default objects: colours are RGB (converted to OpenCV BGR when drawing)
DEFAULT_OBJECTS = {
    "person": {"name": "Person", "color": [0, 102, 255]},   # blue
    "dog":    {"name": "Hund",   "color": [0, 200, 0]},     # green
    "cat":    {"name": "Katze",  "color": [255, 165, 0]},   # orange
    "bird":   {"name": "Vogel",  "color": [255, 165, 0]},
    "horse":  {"name": "Pferd",  "color": [255, 165, 0]},
}


# --------------------------------------------------------------------------
# Detector
# --------------------------------------------------------------------------
class Yolo:
    def __init__(self, model_path, size=640, threads=0):
        opts = ort.SessionOptions()
        if threads:
            opts.intra_op_num_threads = threads
        self.session = ort.InferenceSession(model_path, sess_options=opts,
                                            providers=["CPUExecutionProvider"])
        self.input = self.session.get_inputs()[0].name
        self.size = size
        self.lock = threading.Lock()

    def detect(self, frame, wanted, conf_min, iou=0.45):
        """Return [(label, conf, x1, y1, x2, y2)] for the classes in `wanted`."""
        h, w = frame.shape[:2]
        scale = min(self.size / w, self.size / h)
        nw, nh = int(round(w * scale)), int(round(h * scale))
        pad_x, pad_y = (self.size - nw) // 2, (self.size - nh) // 2
        canvas = np.full((self.size, self.size, 3), 114, dtype=np.uint8)
        canvas[pad_y:pad_y + nh, pad_x:pad_x + nw] = cv2.resize(frame, (nw, nh))
        blob = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB).transpose(2, 0, 1)
        blob = np.ascontiguousarray(blob, dtype=np.float32)[None] / 255.0

        with self.lock:
            out = self.session.run(None, {self.input: blob})[0]
        pred = out[0].T                      # (8400, 84): cx, cy, w, h, 80 scores
        scores = pred[:, 4:]
        cls = scores.argmax(axis=1)
        conf = scores[np.arange(len(cls)), cls]

        wanted_ids = [COCO.index(n) for n in wanted if n in COCO]
        keep = (conf >= min(conf_min.values())) & np.isin(cls, wanted_ids)
        pred, cls, conf = pred[keep], cls[keep], conf[keep]
        if len(pred) == 0:
            return []

        boxes = []
        for (cx, cy, bw, bh) in pred[:, :4]:
            x1 = (cx - bw / 2 - pad_x) / scale
            y1 = (cy - bh / 2 - pad_y) / scale
            boxes.append([float(x1), float(y1), float(bw / scale), float(bh / scale)])

        results = []
        for cid in set(cls.tolist()):
            idx = np.where(cls == cid)[0]
            label = COCO[cid]
            sel = cv2.dnn.NMSBoxes([boxes[i] for i in idx], [float(conf[i]) for i in idx],
                                   conf_min.get(label, 0.5), iou)
            for j in np.array(sel).flatten():
                i = idx[int(j)]
                x, y, bw, bh = boxes[i]
                results.append((label, float(conf[i]),
                                max(0, int(x)), max(0, int(y)),
                                min(w - 1, int(x + bw)), min(h - 1, int(y + bh))))
        return results


def draw(frame, detections, objects, thickness=3):
    img = frame.copy()
    font_scale = max(0.5, img.shape[1] / 1600)
    for label, conf, x1, y1, x2, y2 in detections:
        r, g, b = objects[label]["color"]
        color = (b, g, r)
        cv2.rectangle(img, (x1, y1), (x2, y2), color, thickness)
        text = f'{objects[label]["name"]} {int(conf * 100)}%'
        (tw, th), base = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, font_scale, 2)
        ty = y1 - 4 if y1 - th - base - 4 > 0 else y1 + th + base + 4
        cv2.rectangle(img, (x1, ty - th - base), (x1 + tw + 6, ty + base // 2), color, -1)
        cv2.putText(img, text, (x1 + 3, ty - base // 2), cv2.FONT_HERSHEY_SIMPLEX,
                    font_scale, (255, 255, 255), 2, cv2.LINE_AA)
    return img


# --------------------------------------------------------------------------
# Frame sources
# --------------------------------------------------------------------------
class RtspSource(threading.Thread):
    """Keeps ONE connection to the camera and always holds the newest frame."""

    def __init__(self, url):
        super().__init__(daemon=True)
        self.url = url
        self.frame = None
        self.frame_time = 0.0
        self.lock = threading.Lock()
        self.running = True
        os.environ.setdefault("OPENCV_FFMPEG_CAPTURE_OPTIONS", "rtsp_transport;tcp")

    def run(self):
        while self.running:
            cap = cv2.VideoCapture(self.url, cv2.CAP_FFMPEG)
            if not cap.isOpened():
                log.warning("cannot open %s, retrying in 5 s", redact(self.url))
                time.sleep(5)
                continue
            log.info("connected to %s", redact(self.url))
            fails = 0
            while self.running:
                ok, frame = cap.read()
                if not ok:
                    fails += 1
                    if fails > 50:
                        break
                    time.sleep(0.05)
                    continue
                fails = 0
                with self.lock:
                    self.frame, self.frame_time = frame, time.time()
            cap.release()
            log.warning("stream %s lost, reconnecting", redact(self.url))
            time.sleep(2)

    def get(self):
        with self.lock:
            if self.frame is None or time.time() - self.frame_time > 10:
                return None
            return self.frame


class SnapshotSource:
    """Fetches a JPEG per detection (light on the camera, no stream needed)."""

    def __init__(self, url, username=None, password=None):
        self.url = url
        self.auth = None
        if username:
            token = base64.b64encode(f"{username}:{password or ''}".encode()).decode()
            self.auth = f"Basic {token}"

    def start(self):
        pass

    def get(self):
        req = urllib.request.Request(self.url)
        if self.auth:
            req.add_header("Authorization", self.auth)
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = np.frombuffer(resp.read(), dtype=np.uint8)
            return cv2.imdecode(data, cv2.IMREAD_COLOR)
        except Exception as exc:  # noqa: BLE001
            log.warning("snapshot %s failed: %s", redact(self.url), exc)
            return None


def redact(url):
    if "@" in url and "://" in url:
        scheme, rest = url.split("://", 1)
        return f"{scheme}://***@{rest.split('@', 1)[1]}"
    return url


# --------------------------------------------------------------------------
# Camera worker
# --------------------------------------------------------------------------
class Camera(threading.Thread):
    def __init__(self, cfg, yolo, objects, mqtt):
        super().__init__(daemon=True)
        self.name = cfg["name"]
        self.id = "".join(c if c.isalnum() else "_" for c in self.name.lower())
        self.interval = float(cfg.get("interval", 1.0))
        self.hold = float(cfg.get("off_delay", 10))
        self.objects = {k: v for k, v in objects.items() if k in cfg.get("objects", objects)}
        self.conf = {k: float(v.get("min_score", cfg.get("min_score", 0.5)))
                     for k, v in self.objects.items()}
        self.yolo = yolo
        self.mqtt = mqtt
        url = cfg["url"]
        if url.startswith("http"):
            self.source = SnapshotSource(url, cfg.get("username"), cfg.get("password"))
        else:
            self.source = RtspSource(url)
        self.jpeg = None
        self.jpeg_cond = threading.Condition()
        self.last_seen = {k: 0.0 for k in self.objects}
        self.present = {k: False for k in self.objects}
        self.counts = {k: 0 for k in self.objects}
        self.last_detections = []
        self.last_update = 0.0
        self.running = True

    def run(self):
        self.source.start()
        if self.mqtt:
            self.mqtt.announce(self)
        while self.running:
            t0 = time.time()
            frame = self.source.get()
            if frame is not None:
                try:
                    dets = self.yolo.detect(frame, list(self.objects), self.conf)
                except Exception:  # noqa: BLE001
                    log.exception("detection failed on %s", self.name)
                    dets = []
                self.update(frame, dets)
            time.sleep(max(0.05, self.interval - (time.time() - t0)))

    def update(self, frame, dets):
        now = time.time()
        counts = {k: 0 for k in self.objects}
        for d in dets:
            counts[d[0]] += 1
            self.last_seen[d[0]] = now
        changed = counts != self.counts
        self.counts = counts
        for k in self.objects:
            # Hysteresis: stay "present" for off_delay seconds after the last hit
            p = (now - self.last_seen[k]) <= self.hold
            if p != self.present[k]:
                changed = True
                log.info("%s: %s %s", self.name, self.objects[k]["name"],
                         "erkannt" if p else "weg")
            self.present[k] = p
        self.last_detections = dets
        self.last_update = now
        ok, buf = cv2.imencode(".jpg", draw(frame, dets, self.objects),
                               [cv2.IMWRITE_JPEG_QUALITY, 80])
        if ok:
            with self.jpeg_cond:
                self.jpeg = buf.tobytes()
                self.jpeg_cond.notify_all()
        if self.mqtt:
            self.mqtt.publish(self, changed)

    def status(self):
        return {
            "name": self.name,
            "last_update": self.last_update,
            "present": self.present,
            "counts": self.counts,
            "detections": [
                {"label": l, "score": round(c, 3), "box": [x1, y1, x2, y2]}
                for l, c, x1, y1, x2, y2 in self.last_detections
            ],
        }


# --------------------------------------------------------------------------
# MQTT (Home Assistant discovery)
# --------------------------------------------------------------------------
class Mqtt:
    def __init__(self, cfg):
        import paho.mqtt.client as mqtt
        self.prefix = cfg.get("topic_prefix", "yi-detector")
        self.discovery = cfg.get("discovery_prefix", "homeassistant")
        self.image_interval = float(cfg.get("image_interval", 2))
        self.last_image = {}
        try:
            self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="yi-detector")
        except AttributeError:
            self.client = mqtt.Client(client_id="yi-detector")
        if cfg.get("username"):
            self.client.username_pw_set(cfg["username"], cfg.get("password"))
        self.cameras = []
        self.client.will_set(f"{self.prefix}/status", "offline", qos=1, retain=True)
        self.client.on_connect = self._on_connect
        self.client.reconnect_delay_set(1, 60)
        self.client.connect_async(cfg.get("host", "localhost"), int(cfg.get("port", 1883)), 60)
        self.client.loop_start()

    def _on_connect(self, client, userdata, flags, rc, *args):
        # (Re)announce everything after every (re)connect: messages sent while
        # disconnected are lost
        log.info("MQTT connected (%s)", rc)
        client.publish(f"{self.prefix}/status", "online", qos=1, retain=True)
        for cam in list(self.cameras):
            self._discovery(cam)
            self.publish(cam, True)

    def announce(self, cam):
        if cam not in self.cameras:
            self.cameras.append(cam)
        if self.client.is_connected():
            self._discovery(cam)

    def _discovery(self, cam):
        device = {"identifiers": [f"yi_detector_{cam.id}"], "name": f"{cam.name} Erkennung",
                  "manufacturer": "YI-Hack-Tiz", "model": "yi-detector"}
        avail = {"availability_topic": f"{self.prefix}/status"}
        base = f"{self.prefix}/{cam.id}"
        for key, obj in cam.objects.items():
            oid = key.replace(" ", "_")
            self.client.publish(
                f"{self.discovery}/binary_sensor/yi_detector_{cam.id}/{oid}/config",
                json.dumps({"name": obj["name"], "unique_id": f"yi_det_{cam.id}_{oid}",
                            "state_topic": f"{base}/{oid}", "device_class": "occupancy",
                            "device": device, **avail}), qos=1, retain=True)
            self.client.publish(
                f"{self.discovery}/sensor/yi_detector_{cam.id}/{oid}_count/config",
                json.dumps({"name": f'{obj["name"]} Anzahl', "unique_id": f"yi_det_{cam.id}_{oid}_count",
                            "state_topic": f"{base}/{oid}/count", "state_class": "measurement",
                            "device": device, **avail}), qos=1, retain=True)
        self.client.publish(
            f"{self.discovery}/camera/yi_detector_{cam.id}/annotated/config",
            json.dumps({"name": "Erkennung", "unique_id": f"yi_det_{cam.id}_image",
                        "topic": f"{base}/image", "device": device, **avail}), qos=1, retain=True)

    def publish(self, cam, changed):
        base = f"{self.prefix}/{cam.id}"
        if changed:
            for key in cam.objects:
                oid = key.replace(" ", "_")
                self.client.publish(f"{base}/{oid}", "ON" if cam.present[key] else "OFF", retain=True)
                self.client.publish(f"{base}/{oid}/count", cam.counts[key], retain=True)
            self.client.publish(f"{base}/detections", json.dumps(cam.status()))
        now = time.time()
        if cam.jpeg and (changed or now - self.last_image.get(cam.id, 0) >= self.image_interval):
            self.client.publish(f"{base}/image", cam.jpeg)
            self.last_image[cam.id] = now


# --------------------------------------------------------------------------
# HTTP server
# --------------------------------------------------------------------------
def make_handler(cameras, auth):
    by_id = {c.id: c for c in cameras}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _auth_ok(self):
            if not auth:
                return True
            if hmac.compare_digest(self.headers.get("Authorization", ""), auth):
                return True
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="yi-detector"')
            self.end_headers()
            return False

        def _send(self, code, ctype, body):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):  # noqa: N802
            path = self.path.split("?")[0].strip("/")
            if path == "health":
                return self._send(200, "text/plain", b"ok")
            if not self._auth_ok():
                return None
            if path == "":
                rows = "".join(
                    f'<h2>{c.name}</h2><img src="/{c.id}/stream.mjpg" style="max-width:100%">'
                    f'<p><a href="/{c.id}/snapshot.jpg">snapshot.jpg</a> · '
                    f'<a href="/{c.id}/status.json">status.json</a></p>' for c in cameras)
                html = (f"<!doctype html><meta charset=utf-8><meta name=viewport "
                        f"content='width=device-width'><title>yi-detector</title>"
                        f"<body style='font-family:sans-serif;background:#111;color:#eee'>{rows}")
                return self._send(200, "text/html; charset=utf-8", html.encode())
            parts = path.split("/")
            cam = by_id.get(parts[0])
            if not cam or len(parts) != 2:
                return self._send(404, "text/plain", b"not found")
            if parts[1] == "status.json":
                return self._send(200, "application/json", json.dumps(cam.status()).encode())
            if parts[1] == "snapshot.jpg":
                if cam.jpeg is None:
                    return self._send(503, "text/plain", b"no picture yet")
                return self._send(200, "image/jpeg", cam.jpeg)
            if parts[1] == "stream.mjpg":
                self.send_response(200)
                self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                try:
                    while True:
                        with cam.jpeg_cond:
                            cam.jpeg_cond.wait(timeout=10)
                            jpg = cam.jpeg
                        if jpg is None:
                            continue
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n")
                        self.wfile.write(f"Content-Length: {len(jpg)}\r\n\r\n".encode())
                        self.wfile.write(jpg + b"\r\n")
                except (BrokenPipeError, ConnectionResetError):
                    return None
            return self._send(404, "text/plain", b"not found")

    return Handler


def load_config(path):
    with open(path, encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh) or {}
    objects = {}
    for key, val in (cfg.get("objects") or DEFAULT_OBJECTS).items():
        if key not in COCO:
            raise SystemExit(f"unknown object '{key}' (use COCO names like person, dog, cat)")
        base = DEFAULT_OBJECTS.get(key, {"name": key, "color": [255, 255, 0]})
        objects[key] = {**base, **(val or {})}
    if not cfg.get("cameras"):
        raise SystemExit("no cameras in config")
    return cfg, objects


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    default_cfg = os.environ.get("CONFIG", "/config/config.yaml")
    if not os.environ.get("CONFIG") and not os.path.exists(default_cfg) \
            and os.path.exists("/data/options.json"):
        default_cfg = "/data/options.json"      # Home Assistant add-on
    ap.add_argument("-c", "--config", default=default_cfg)
    ap.add_argument("--image", help="test: detect on an image file and write <name>_detected.jpg")
    args = ap.parse_args()
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"),
                        format="%(asctime)s %(levelname)s %(message)s")

    model = os.environ.get("MODEL", "/app/yolov8n.onnx")

    if args.image:
        yolo = Yolo(model)
        frame = cv2.imread(args.image)
        dets = yolo.detect(frame, list(DEFAULT_OBJECTS), {k: 0.5 for k in DEFAULT_OBJECTS})
        for d in dets:
            print(d)
        out = os.path.splitext(args.image)[0] + "_detected.jpg"
        cv2.imwrite(out, draw(frame, dets, DEFAULT_OBJECTS))
        print("written", out)
        return

    cfg, objects = load_config(args.config)
    yolo = Yolo(model, int(cfg.get("model_size", 640)), int(cfg.get("threads", 0)))
    mqtt = Mqtt(cfg["mqtt"]) if cfg.get("mqtt", {}).get("host") else None

    cameras = [Camera(c, yolo, objects, mqtt) for c in cfg["cameras"]]
    for cam in cameras:
        cam.start()

    auth = None
    http = cfg.get("http", {})
    if http.get("username"):
        token = base64.b64encode(f'{http["username"]}:{http.get("password", "")}'.encode()).decode()
        auth = f"Basic {token}"
    else:
        log.warning("web interface WITHOUT password: everyone in the network can watch the "
                    "cameras. Set http.username / http.password (needed for indoor cameras).")
    server = ThreadingHTTPServer(("0.0.0.0", int(http.get("port", 8090))), make_handler(cameras, auth))
    server.daemon_threads = True
    log.info("web interface on port %s, objects: %s", server.server_port,
             ", ".join(f'{o["name"]}' for o in objects.values()))
    signal.signal(signal.SIGTERM, lambda *_: os._exit(0))
    server.serve_forever()


if __name__ == "__main__":
    main()
