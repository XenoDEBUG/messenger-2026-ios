const { app, BrowserWindow, session, desktopCapturer, Menu } = require("electron");
const path = require("path");
const fs = require("fs");

// Страница открывается из файла, поэтому браузер считает её безопасной:
// микрофон и камера для голосовых и звонков работают без https.
const MEDIA_PERMISSIONS = ["media", "audioCapture", "videoCapture", "display-capture", "notifications"];

// ---- Масштаб интерфейса (уменьшить / увеличить всё) ----
const ZOOM_MIN = 0.5;
const ZOOM_MAX = 2.0;
const ZOOM_STEP = 0.1;
let zoomLevel = 1.0;
let mainWin = null;

function zoomFile() {
  return path.join(app.getPath("userData"), "zoom.json");
}
function loadZoom() {
  try {
    const v = JSON.parse(fs.readFileSync(zoomFile(), "utf8")).zoom;
    if (typeof v === "number" && v >= ZOOM_MIN && v <= ZOOM_MAX) zoomLevel = v;
  } catch (_) { /* первого запуска файла нет — берём 100% */ }
}
function saveZoom() {
  try {
    fs.mkdirSync(app.getPath("userData"), { recursive: true });
    fs.writeFileSync(zoomFile(), JSON.stringify({ zoom: zoomLevel }));
  } catch (_) { /* не критично */ }
}
function applyZoom(delta) {
  if (!mainWin) return;
  zoomLevel = delta === 0 ? 1.0 : Math.round((zoomLevel + delta) * 10) / 10;
  zoomLevel = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoomLevel));
  mainWin.webContents.setZoomFactor(zoomLevel);
  saveZoom();
}

function buildMenu() {
  const template = [
    {
      label: "Вид",
      submenu: [
        { label: "Увеличить", accelerator: "CmdOrCtrl+=", click: () => applyZoom(ZOOM_STEP) },
        { label: "Уменьшить", accelerator: "CmdOrCtrl+-", click: () => applyZoom(-ZOOM_STEP) },
        { label: "Сбросить масштаб", accelerator: "CmdOrCtrl+0", click: () => applyZoom(0) },
        { type: "separator" },
        { label: "Перезагрузить", accelerator: "CmdOrCtrl+R", click: () => mainWin && mainWin.reload() },
        { label: "Инструменты разработчика", accelerator: "CmdOrCtrl+Shift+I", click: () => mainWin && mainWin.webContents.toggleDevTools() }
      ]
    }
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

function allowMedia() {
  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(MEDIA_PERMISSIONS.includes(permission));
  });
  session.defaultSession.setPermissionCheckHandler((_wc, permission) => {
    return MEDIA_PERMISSIONS.includes(permission);
  });
  // Демонстрация экрана: отдаём основной экран без системного диалога.
  session.defaultSession.setDisplayMediaRequestHandler((_request, callback) => {
    desktopCapturer.getSources({ types: ["screen"] }).then((sources) => {
      if (sources.length) callback({ video: sources[0], audio: "loopback" });
      else callback({});
    }).catch(() => callback({}));
  });
}

function createWindow() {
  mainWin = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 700,
    minHeight: 500,
    title: "Messenger 2026",
    autoHideMenuBar: true,
    backgroundColor: "#060a1c",
    // звук собеседника должен играть сразу, без клика по окну
    webPreferences: { contextIsolation: true, autoplayPolicy: "no-user-gesture-required" }
  });
  mainWin.webContents.on("did-finish-load", () => {
    mainWin.webContents.setZoomFactor(zoomLevel);
  });
  // Ctrl + колесо мыши тоже меняет масштаб
  mainWin.webContents.on("before-input-event", (event, input) => {
    if (input.type === "keyDown" && (input.control || input.meta)) {
      if (input.key === "=" || input.key === "+") { applyZoom(ZOOM_STEP); event.preventDefault(); }
      else if (input.key === "-") { applyZoom(-ZOOM_STEP); event.preventDefault(); }
      else if (input.key === "0") { applyZoom(0); event.preventDefault(); }
    }
  });
  mainWin.webContents.on("zoom-changed", (_event, direction) => {
    applyZoom(direction === "in" ? ZOOM_STEP : -ZOOM_STEP);
  });
  mainWin.loadFile(path.join(__dirname, "www", "index.html"));
  mainWin.on("closed", () => { mainWin = null; });
}

app.whenReady().then(() => {
  loadZoom();
  allowMedia();
  buildMenu();
  createWindow();
  app.on("activate", () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
