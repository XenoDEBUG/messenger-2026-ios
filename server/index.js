const express = require("express");
const http = require("http");
const cors = require("cors");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const mongoose = require("mongoose");
const { Server } = require("socket.io");

const PORT = process.env.PORT || 3000;
const MONGODB_URI = process.env.MONGODB_URI;
const JWT_SECRET = process.env.JWT_SECRET || "dev-only-change-me";
const ORIGIN = process.env.CORS_ORIGIN || "*";

const USERNAME_RE = /^[a-z0-9_.]{3,20}$/;

const User = mongoose.model("User", new mongoose.Schema({
  username: { type: String, required: true, unique: true, lowercase: true },
  displayName: { type: String, required: true },
  passHash: { type: String, required: true },
  color: { type: String, default: "#5b8cff" },
  createdAt: { type: Date, default: Date.now }
}));

const Message = mongoose.model("Message", new mongoose.Schema({
  scope: { type: String, required: true, index: true },
  author: { type: String, required: true },
  text: { type: String, required: true, maxlength: 2000 },
  createdAt: { type: Date, default: Date.now, index: true }
}));

// Личные сообщения: общий ключ для двух ников, отсортированный
const dmScope = (a, b) => "dm:" + [a, b].sort().join("|");
const isChannel = s => /^ch:[a-z0-9_-]{1,40}$/.test(s);
const isDm = s => /^dm:[a-z0-9_.]+\|[a-z0-9_.]+$/.test(s);

function publicUser(u) {
  return { username: u.username, displayName: u.displayName, color: u.color };
}

function makeToken(username) {
  return jwt.sign({ u: username }, JWT_SECRET, { expiresIn: "30d" });
}

function auth(req, res, next) {
  const h = req.headers.authorization || "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : null;
  try {
    req.user = jwt.verify(token, JWT_SECRET).u;
    next();
  } catch {
    res.status(401).json({ error: "Нужен вход" });
  }
}

const app = express();
app.use(cors({ origin: ORIGIN }));
app.use(express.json({ limit: "100kb" }));

app.get("/", (_req, res) => res.json({ ok: true, name: "messenger-2026" }));

app.post("/api/register", async (req, res) => {
  const username = String(req.body.username || "").trim().toLowerCase();
  const displayName = String(req.body.displayName || "").trim();
  const password = String(req.body.password || "");
  if (!USERNAME_RE.test(username)) return res.status(400).json({ error: "Юзернейм: 3–20 символов, латиница, цифры, _ и ." });
  if (displayName.length < 2 || displayName.length > 32) return res.status(400).json({ error: "Имя: от 2 до 32 символов" });
  if (password.length < 6) return res.status(400).json({ error: "Пароль: минимум 6 символов" });
  if (await User.exists({ username })) return res.status(409).json({ error: "Такой юзернейм уже занят" });
  const user = await User.create({ username, displayName, passHash: await bcrypt.hash(password, 10) });
  res.json({ token: makeToken(username), user: publicUser(user) });
});

app.post("/api/login", async (req, res) => {
  const username = String(req.body.username || "").trim().toLowerCase();
  const password = String(req.body.password || "");
  const user = await User.findOne({ username });
  if (!user || !(await bcrypt.compare(password, user.passHash))) {
    return res.status(401).json({ error: "Неверный юзернейм или пароль" });
  }
  res.json({ token: makeToken(username), user: publicUser(user) });
});

app.get("/api/me", auth, async (req, res) => {
  const user = await User.findOne({ username: req.user });
  if (!user) return res.status(404).json({ error: "Нет такого пользователя" });
  res.json({ user: publicUser(user) });
});

app.get("/api/users", auth, async (req, res) => {
  const q = String(req.query.q || "").toLowerCase().replace(/[^a-z0-9_.]/g, "");
  const filter = q ? { username: new RegExp("^" + q) } : {};
  const users = await User.find(filter).limit(50);
  res.json({ users: users.map(publicUser) });
});

app.get("/api/messages", auth, async (req, res) => {
  const scope = String(req.query.scope || "");
  if (!isChannel(scope) && !isDm(scope)) return res.status(400).json({ error: "Неверный чат" });
  if (isDm(scope) && !scope.includes(req.user)) return res.status(403).json({ error: "Нет доступа" });
  const messages = await Message.find({ scope }).sort({ createdAt: -1 }).limit(50);
  res.json({ messages: messages.reverse() });
});

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: ORIGIN } });

io.use((socket, next) => {
  try {
    socket.data.user = jwt.verify(socket.handshake.auth.token, JWT_SECRET).u;
    next();
  } catch {
    next(new Error("unauthorized"));
  }
});

io.on("connection", socket => {
  const me = socket.data.user;
  socket.join("u:" + me);

  // подписка на канал сервера
  socket.on("scope:join", scope => {
    if (isChannel(scope)) socket.join(scope);
  });

  socket.on("message:send", async (payload, ack) => {
    const scope = String(payload && payload.scope || "");
    const text = String(payload && payload.text || "").trim().slice(0, 2000);
    if (!text) return ack && ack({ error: "Пустое сообщение" });
    if (!isChannel(scope) && !isDm(scope)) return ack && ack({ error: "Неверный чат" });
    if (isDm(scope) && !scope.includes(me)) return ack && ack({ error: "Нет доступа" });
    const msg = await Message.create({ scope, author: me, text });
    const out = { scope, author: me, text, createdAt: msg.createdAt };
    if (isChannel(scope)) io.to(scope).emit("message:new", out);
    else scope.slice(3).split("|").forEach(u => io.to("u:" + u).emit("message:new", out));
    ack && ack({ ok: true });
  });

  // сигналинг звонков 1 на 1 (WebRTC): сервер только пересылает
  const relay = (event, target, data) => io.to("u:" + target).emit(event, { from: me, ...data });
  socket.on("call:invite", ({ to, offer }) => to && relay("call:incoming", to, { offer }));
  socket.on("call:answer", ({ to, answer }) => to && relay("call:answered", to, { answer }));
  socket.on("call:ice", ({ to, candidate }) => to && relay("call:ice", to, { candidate }));
  socket.on("call:end", ({ to }) => to && relay("call:ended", to, {}));
});

async function start() {
  if (!MONGODB_URI) throw new Error("Не задан MONGODB_URI");
  await mongoose.connect(MONGODB_URI);
  await User.init();
  server.listen(PORT, () => console.log("Сервер запущен на порту " + PORT));
}

if (require.main === module) start().catch(e => { console.error(e); process.exit(1); });

module.exports = { app, server, start, io };
