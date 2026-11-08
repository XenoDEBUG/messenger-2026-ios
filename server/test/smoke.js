// Проверка сервера: регистрация, вход, сообщения, личка и сигналинг звонка.
process.env.PORT = process.env.PORT || "3999";
const { io: ioc } = require("socket.io-client");
const { server, start } = require("../index.js");

const base = `http://localhost:${process.env.PORT}`;
const assert = (c, m) => { if (!c) throw new Error("ПРОВАЛ: " + m); console.log("ok -", m); };
const post = (path, body, token) => fetch(base + path, {
  method: "POST", headers: { "content-type": "application/json", ...(token ? { authorization: "Bearer " + token } : {}) }, body: JSON.stringify(body)
}).then(async r => ({ status: r.status, body: await r.json() }));
const get = (path, token) => fetch(base + path, { headers: { authorization: "Bearer " + token } }).then(async r => ({ status: r.status, body: await r.json() }));
const connect = token => new Promise((res, rej) => {
  const s = ioc(base, { auth: { token }, transports: ["websocket"] });
  s.on("connect", () => res(s)); s.on("connect_error", rej);
});
const once = (s, ev) => new Promise(r => s.once(ev, r));

(async () => {
  await start();
  const uniq = Math.random().toString(36).slice(2, 7);
  const a = "ann_" + uniq, b = "bob_" + uniq;

  let r = await post("/api/register", { username: a, displayName: "Анна", password: "secret1" });
  assert(r.status === 200 && r.body.token, "регистрация первого пользователя");
  const tokA = r.body.token;

  r = await post("/api/register", { username: b, displayName: "Боб", password: "secret2" });
  assert(r.status === 200, "регистрация второго пользователя");
  const tokB = r.body.token;

  r = await post("/api/register", { username: a, displayName: "Копия", password: "secret1" });
  assert(r.status === 409, "повторный юзернейм отклоняется");

  r = await post("/api/register", { username: "Bad Name!", displayName: "X", password: "secret1" });
  assert(r.status === 400, "плохой юзернейм отклоняется");

  r = await post("/api/login", { username: a, password: "wrong" });
  assert(r.status === 401, "неверный пароль отклоняется");

  r = await post("/api/login", { username: a.toUpperCase(), password: "secret1" });
  assert(r.status === 200, "вход без учёта регистра ника");

  r = await get("/api/me", tokA);
  assert(r.body.user.username === a, "/api/me возвращает пользователя");

  const sa = await connect(tokA), sb = await connect(tokB);
  const dm = `dm:${[a, b].sort().join("|")}`;

  const got = once(sb, "message:new");
  const ack = await new Promise(res => sa.emit("message:send", { scope: dm, text: "привет" }, res));
  assert(ack.ok, "отправка личного сообщения");
  const m = await got;
  assert(m.text === "привет" && m.author === a, "получатель получает сообщение в реальном времени");

  r = await get("/api/messages?scope=" + encodeURIComponent(dm), tokB);
  assert(r.body.messages.length === 1, "история личного чата сохраняется");

  r = await get("/api/messages?scope=" + encodeURIComponent("dm:x|y"), tokA);
  assert(r.status === 403, "чужой личный чат недоступен");

  sa.emit("scope:join", "ch:general");
  sb.emit("scope:join", "ch:general");
  await new Promise(r => setTimeout(r, 200));
  const chGot = once(sb, "message:new");
  sa.emit("message:send", { scope: "ch:general", text: "всем привет" });
  assert((await chGot).text === "всем привет", "сообщение канала доходит подписчикам");

  const offerGot = once(sb, "call:incoming");
  sa.emit("call:invite", { to: b, offer: { type: "offer", sdp: "x" } });
  const inv = await offerGot;
  assert(inv.from === a && inv.offer.sdp === "x", "звонок: приглашение доходит до адресата");

  const ansGot = once(sa, "call:answered");
  sb.emit("call:answer", { to: a, answer: { type: "answer", sdp: "y" } });
  assert((await ansGot).answer.sdp === "y", "звонок: ответ возвращается инициатору");

  sa.close(); sb.close();
  server.close();
  console.log("\nВсе проверки пройдены");
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
