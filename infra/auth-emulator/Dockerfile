# Local-only Firebase Auth emulator for KiuPop (project demo-kiupop: offline, no real Firebase project).
# The Auth emulator is pure Node; no Java needed.
FROM node:24.11.1-alpine3.22
RUN npm install -g firebase-tools@15.34.2 && npm cache clean --force
WORKDIR /emulator
COPY firebase.json .firebaserc ./
EXPOSE 9099
HEALTHCHECK --interval=5s --timeout=3s --retries=30 CMD wget -qO- http://127.0.0.1:9099/ >/dev/null || exit 1
# Accounts persist in the authdata volume across restarts (export on graceful stop).
CMD ["sh", "-c", "mkdir -p /data/export && firebase emulators:start --only auth --project demo-kiupop --import=/data/export --export-on-exit=/data/export"]
