const { app, BrowserWindow, session } = require("electron");
const path = require("path");

// Страница открывается из файла, поэтому браузер считает её безопасной:
// микрофон и камера для голосовых и звонков работают без https.
const MEDIA_PERMISSIONS = ["media", "audioCapture", "videoCapture", "notifications"];

function allowMedia() {
  session.defaultSession.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(MEDIA_PERMISSIONS.includes(permission));
  });
  session.defaultSession.setPermissionCheckHandler((_wc, permission) => {
    return MEDIA_PERMISSIONS.includes(permission);
  });
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 900,
    minHeight: 600,
    title: "Messenger 2026",
    autoHideMenuBar: true,
    backgroundColor: "#060a1c",
    webPreferences: { contextIsolation: true }
  });
  win.loadFile(path.join(__dirname, "www", "index.html"));
}

app.whenReady().then(() => {
  allowMedia();
  createWindow();
  app.on("activate", () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
