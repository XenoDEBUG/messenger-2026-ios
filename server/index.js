require('dotenv').config();

const http = require('http');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');
const UPLOAD_DIR = path.join(__dirname, 'uploads');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });
const MAX_FILE = 25 * 1024 * 1024;
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Server: SocketIO } = require('socket.io');

const PORT = process.env.PORT || 3000;
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/messenger';
const JWT_SECRET = process.env.JWT_SECRET || '';
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';

if (JWT_SECRET.length < 16) {
  console.error('Ошибка: задайте JWT_SECRET (не короче 16 символов) в .env');
  process.exit(1);
}

// ---------- Модели ----------

// verified: true выдаётся только вручную в базе (Compass или Atlas).
// Через API поле изменить нельзя.
const User = mongoose.model('User', new mongoose.Schema({
  username: { type: String, required: true, unique: true, lowercase: true, trim: true },
  displayName: { type: String, default: '' },
  passwordHash: { type: String, required: true },
  color: { type: String, default: '#7c5cff' },
  bio: { type: String, default: '' },
  status: { type: String, default: '' },
  verified: { type: Boolean, default: false },
  avatar: { type: String, default: null },
  banner: { type: String, default: null },
  g: { type: String, default: null },
  decor: { type: String, default: null },
  links: { type: mongoose.Schema.Types.Mixed, default: {} },
  custom: { type: mongoose.Schema.Types.Mixed, default: null },
  st: { type: String, default: 'online' },
  createdAt: { type: Date, default: Date.now }
}));

// Сервер (гильдия): владелец, участники, роли с правами и код приглашения
const ServerModel = mongoose.model('Server', new mongoose.Schema({
  name: { type: String, required: true, maxlength: 40 },
  owner: { type: String, required: true },
  avatar: { type: String, default: null },
  inviteCode: { type: String, required: true, unique: true },
  members: [{ type: String }],
  roles: [{
    rid: { type: String, required: true },
    name: { type: String, required: true, maxlength: 32 },
    color: { type: String, default: '#8a8fa8' },
    emoji: { type: String, default: '' },
    perms: [{ type: String }]
  }],
  memberRoles: [{ user: { type: String, required: true }, roleIds: [{ type: String }] }],
  createdAt: { type: Date, default: Date.now }
}));

// Каналы создаются владельцем или участниками с правом manageChannels. Новый сервер без каналов.
const Channel = mongoose.model('Channel', new mongoose.Schema({
  serverId: { type: mongoose.Schema.Types.ObjectId, required: true, index: true },
  name: { type: String, required: true, maxlength: 32 },
  avatar: { type: String, default: null },
  createdAt: { type: Date, default: Date.now }
}));

// Дружба: одна запись на пару (a < b по алфавиту)
const Friend = mongoose.model('Friend', new mongoose.Schema({
  a: { type: String, required: true },
  b: { type: String, required: true },
  requester: { type: String, required: true },
  status: { type: String, enum: ['pending', 'accepted'], default: 'pending' }
}));
Friend.collection.createIndex({ a: 1, b: 1 }, { unique: true }).catch(() => {});

// delivered: собеседник был онлайн или зашёл позже (✓✓)
// readBy: собеседник открыл чат (синие ✓✓)
const Message = mongoose.model('Message', new mongoose.Schema({
  chatType: { type: String, enum: ['channel', 'dm'], required: true },
  chatId: { type: String, required: true },
  from: { type: String, required: true },
  to: { type: String, default: null },
  text: { type: String, default: '', maxlength: 4000 },
  audio: { type: String, default: null },
  dur: { type: Number, default: 0 },
  file: { type: mongoose.Schema.Types.Mixed, default: null },
  delivered: { type: Boolean, default: false },
  readBy: [{ type: String }],
  createdAt: { type: Date, default: Date.now }
}));
Message.collection.createIndex({ chatType: 1, chatId: 1, createdAt: 1 }).catch(() => {});

// ---------- Роли и права ----------

const ALL_PERMS = ['manageChannels', 'manageRoles', 'invite', 'kick'];
const EVERYONE = 'everyone'; // базовая роль, есть у всех участников
const MAX_ROLES = 20;

const defaultRoles = () => [{ rid: EVERYONE, name: 'Участник', color: '#8a8fa8', emoji: '', perms: [] }];
const cleanEmoji = (v) => String(v || '').trim().slice(0, 8);
// Аватарка: картинка в data-URL до 600 КБ (клиент сжимает до 256 px)
const isAvatarData = (v) => typeof v === 'string' && v.startsWith('data:image/') && v.length <= 600000;

// Владелец имеет все права. Остальные — объединение прав всех своих ролей (включая базовую).
function permsOf(guild, username) {
  if (guild.owner === username) return ALL_PERMS;
  const mr = guild.memberRoles.find((m) => m.user === username);
  const ids = new Set([EVERYONE, ...(mr ? mr.roleIds : [])]);
  const set = new Set();
  for (const r of guild.roles) {
    if (ids.has(r.rid)) r.perms.forEach((p) => set.add(p));
  }
  return [...set];
}
const hasPerm = (guild, username, perm) => permsOf(guild, username).includes(perm);

// Загружает сервер, проверяя членство и (если указано) право
async function loadGuild(id, username, perm) {
  if (!mongoose.isValidObjectId(id)) return { status: 400, error: 'Неверный сервер' };
  const guild = await ServerModel.findById(id);
  if (!guild || !guild.members.includes(username)) return { status: 403, error: 'Нет доступа к серверу' };
  if (perm && !hasPerm(guild, username, perm)) return { status: 403, error: 'Нет прав на это действие' };
  return { guild };
}

// Данные сервера для клиента. Код приглашения видят только те, у кого есть право invite.
function guildView(guild, username, channels) {
  const perms = permsOf(guild, username);
  const mrById = new Map(guild.memberRoles.map((m) => [m.user, m.roleIds]));
  return {
    id: guild._id.toString(),
    name: guild.name,
    owner: guild.owner,
    avatar: guild.avatar || null,
    myPerms: perms,
    inviteCode: perms.includes('invite') ? guild.inviteCode : undefined,
    roles: guild.roles.map((r) => ({ id: r.rid, name: r.name, color: r.color, emoji: r.emoji || '', perms: r.perms })),
    members: guild.members.map((u) => ({
      username: u,
      owner: u === guild.owner,
      roleIds: mrById.get(u) || []
    })),
    channels: (channels || []).map((c) => ({ id: c._id.toString(), name: c.name, avatar: c.avatar || null }))
  };
}

const notifyGuild = (guild, extra = []) => {
  for (const u of [...guild.members, ...extra]) io.to('user:' + u).emit('servers:update');
};

// ---------- Помощники ----------

const USERNAME_RE = /^[a-z0-9_.]{3,20}$/;
const CHANNEL_RE = /^[a-z0-9_-]{1,32}$/;
const COLOR_RE = /^#[0-9a-f]{6}$/i;

const normalize = (v) => String(v || '').trim().toLowerCase();
const pairKey = (a, b) => [a, b].sort().join('|');
const pairOf = (a, b) => [a, b].sort();
const newInviteCode = () => crypto.randomBytes(4).toString('hex').toUpperCase();

const publicUser = (u) => ({
  username: u.username,
  displayName: u.displayName || u.username,
  color: u.color || null,
  g: u.g || null,
  bio: u.bio || '',
  status: u.status || '',
  verified: !!u.verified,
  avatar: u.avatar || null,
  banner: u.banner || null,
  decor: u.decor || null,
  links: u.links || {},
  custom: u.custom || null,
  st: u.st || 'online'
});

const toMessage = (m) => ({
  id: m._id.toString(),
  chatType: m.chatType,
  chatId: m.chatId,
  from: m.from,
  to: m.to,
  text: m.text,
  audio: m.audio || null,
  dur: m.dur || 0,
  file: m.file || null,
  createdAt: m.createdAt,
  status: m.chatType !== 'dm' ? 'sent' : m.readBy.length ? 'read' : m.delivered ? 'delivered' : 'sent'
});

const signToken = (username) => jwt.sign({ username }, JWT_SECRET, { expiresIn: '30d' });

function auth(req, res, next) {
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  try {
    req.username = jwt.verify(token, JWT_SECRET).username;
    next();
  } catch {
    res.status(401).json({ error: 'Нужно войти в аккаунт' });
  }
}

const route = (fn) => (req, res) =>
  fn(req, res).catch((err) => {
    console.error(err);
    res.status(500).json({ error: 'Ошибка сервера' });
  });

async function areFriends(a, b) {
  const [x, y] = pairOf(a, b);
  return !!(await Friend.findOne({ a: x, b: y, status: 'accepted' }));
}

// Канал доступен, если пользователь участник его сервера
async function accessibleChannel(channelId, username) {
  if (!mongoose.isValidObjectId(channelId)) return null;
  const channel = await Channel.findById(channelId);
  if (!channel) return null;
  const guild = await ServerModel.findById(channel.serverId);
  return guild && guild.members.includes(username) ? channel : null;
}

// ---------- HTTP API ----------

const app = express();
app.use(cors({ origin: CORS_ORIGIN }));
app.use(express.json({ limit: '2mb' }));

app.get('/health', (req, res) => res.json({ ok: true }));

// Аккаунты
app.post('/api/register', route(async (req, res) => {
  const username = normalize(req.body.username);
  const password = String(req.body.password || '');
  if (!USERNAME_RE.test(username)) {
    return res.status(400).json({ error: 'Юзернейм: 3–20 символов, латиница, цифры, _ и .' });
  }
  if (password.length < 6) return res.status(400).json({ error: 'Пароль не короче 6 символов' });
  if (await User.exists({ username })) return res.status(409).json({ error: 'Юзернейм занят' });

  const user = await User.create({
    username,
    displayName: String(req.body.displayName || '').trim().slice(0, 32),
    passwordHash: await bcrypt.hash(password, 10)
  });
  res.status(201).json({ token: signToken(username), user: publicUser(user) });
}));

app.post('/api/login', route(async (req, res) => {
  const username = normalize(req.body.username);
  const user = await User.findOne({ username });
  const ok = user && (await bcrypt.compare(String(req.body.password || ''), user.passwordHash));
  if (!ok) return res.status(401).json({ error: 'Неверный юзернейм или пароль' });
  res.json({ token: signToken(username), user: publicUser(user) });
}));

app.get('/api/me', auth, route(async (req, res) => {
  const user = await User.findOne({ username: req.username });
  if (!user) return res.status(404).json({ error: 'Пользователь не найден' });
  res.json({ user: publicUser(user) });
}));

app.patch('/api/me', auth, route(async (req, res) => {
  const b = req.body || {};
  const update = {};
  const str = (v, max) => (typeof v === 'string' ? v.slice(0, max) : '');
  if (typeof b.displayName === 'string') update.displayName = b.displayName.trim().slice(0, 32);
  if (typeof b.bio === 'string') update.bio = b.bio.slice(0, 190);
  if (typeof b.status === 'string') update.status = b.status.slice(0, 64);
  if (b.color === null || /^#[0-9a-f]{6}$/i.test(b.color || '')) update.color = b.color;
  if (b.g === null || (typeof b.g === 'string' && b.g.startsWith('linear-gradient(') && b.g.length <= 300)) update.g = b.g;
  if (['online', 'dnd', 'idle', 'invis'].includes(b.st)) update.st = b.st;
  if (b.custom === null) update.custom = null;
  else if (b.custom && typeof b.custom === 'object') update.custom = { e: str(b.custom.e, 8), t: str(b.custom.t, 60) };
  if (b.decor === null) update.decor = null;
  else if (typeof b.decor === 'string' && b.decor.length <= 30) update.decor = b.decor;
  if (b.links && typeof b.links === 'object') {
    update.links = { yt: str(b.links.yt, 120), tg: str(b.links.tg, 120), tt: str(b.links.tt, 120) };
  }
  for (const k of ['avatar', 'banner']) {
    if (b[k] === null) { update[k] = null; continue; }
    if (typeof b[k] !== 'string') continue;
    const isImage = b[k].startsWith('data:image/') && b[k].length <= 600000;
    const isGradient = k === 'banner' && b[k].startsWith('linear-gradient(') && b[k].length <= 300;
    if (!isImage && !isGradient) return res.status(400).json({ error: 'Слишком большой файл или неверный формат: ' + k });
    update[k] = b[k];
  }
  const user = await User.findOneAndUpdate({ username: req.username }, update, { new: true });
  res.json({ user: publicUser(user) });
}));

app.get('/api/users', auth, route(async (req, res) => {
  const q = normalize(req.query.q).replace(/[^a-z0-9_.]/g, '');
  if (!q) return res.json({ users: [] });
  const users = await User.find({ username: { $regex: '^' + q } }).limit(20);
  res.json({ users: users.map(publicUser) });
}));

// Друзья
app.get('/api/friends', auth, route(async (req, res) => {
  const me = req.username;
  const rows = await Friend.find({ $or: [{ a: me }, { b: me }] });
  const out = { friends: [], incoming: [], outgoing: [] };
  for (const r of rows) {
    const other = r.a === me ? r.b : r.a;
    if (r.status === 'accepted') out.friends.push(other);
    else if (r.requester === me) out.outgoing.push(other);
    else out.incoming.push(other);
  }
  res.json(out);
}));

// Если собеседник уже отправил заявку, она принимается сразу
app.post('/api/friends/request', auth, route(async (req, res) => {
  const me = req.username;
  const target = normalize(req.body.username);
  if (!USERNAME_RE.test(target) || target === me) return res.status(400).json({ error: 'Неверный пользователь' });
  if (!(await User.exists({ username: target }))) return res.status(404).json({ error: 'Пользователь не найден' });

  const [a, b] = pairOf(me, target);
  const f = await Friend.findOne({ a, b });
  if (f && f.status === 'accepted') return res.status(409).json({ error: 'Вы уже друзья' });
  if (f && f.requester === me) return res.status(409).json({ error: 'Заявка уже отправлена' });
  if (f) {
    f.status = 'accepted';
    await f.save();
  } else {
    await Friend.create({ a, b, requester: me });
  }
  io.to('user:' + target).to('user:' + me).emit('friend:update');
  res.json({ ok: true });
}));

app.post('/api/friends/accept', auth, route(async (req, res) => {
  const me = req.username;
  const from = normalize(req.body.username);
  const [a, b] = pairOf(me, from);
  const f = await Friend.findOne({ a, b, status: 'pending', requester: from });
  if (!f) return res.status(404).json({ error: 'Заявка не найдена' });
  f.status = 'accepted';
  await f.save();
  io.to('user:' + from).to('user:' + me).emit('friend:update');
  res.json({ ok: true });
}));

// Удалить из друзей, отклонить или отменить заявку
app.post('/api/friends/remove', auth, route(async (req, res) => {
  const me = req.username;
  const other = normalize(req.body.username);
  const [a, b] = pairOf(me, other);
  await Friend.deleteOne({ a, b });
  io.to('user:' + other).to('user:' + me).emit('friend:update');
  res.json({ ok: true });
}));

// ---------- Серверы ----------

// Список серверов пользователя с ролями, правами, участниками и каналами
app.get('/api/servers', auth, route(async (req, res) => {
  const guilds = await ServerModel.find({ members: req.username });
  const channels = await Channel.find({ serverId: { $in: guilds.map((g) => g._id) } }).sort({ createdAt: 1 });
  res.json({
    servers: guilds.map((g) => guildView(g, req.username, channels.filter((c) => c.serverId.equals(g._id))))
  });
}));

// Новый сервер: без каналов, с базовой ролью «Участник» и кодом приглашения
app.post('/api/servers', auth, route(async (req, res) => {
  const name = String(req.body.name || '').trim().slice(0, 40);
  if (name.length < 2) return res.status(400).json({ error: 'Название не короче 2 символов' });
  const guild = await ServerModel.create({
    name,
    owner: req.username,
    inviteCode: newInviteCode(),
    members: [req.username],
    roles: defaultRoles(),
    memberRoles: []
  });
  res.status(201).json({ server: guildView(guild, req.username, []) });
}));

// Вступление по коду приглашения
app.post('/api/servers/join', auth, route(async (req, res) => {
  const code = String(req.body.code || '').trim().toUpperCase();
  if (!code) return res.status(400).json({ error: 'Введите код приглашения' });
  const guild = await ServerModel.findOne({ inviteCode: code });
  if (!guild) return res.status(404).json({ error: 'Сервер с таким кодом не найден' });
  if (!guild.members.includes(req.username)) {
    await ServerModel.updateOne({ _id: guild._id }, { $addToSet: { members: req.username } });
    notifyGuild(guild, [req.username]);
  }
  res.json({ ok: true, serverId: guild._id.toString() });
}));

// Выход с сервера (владелец не может выйти — только удалить сервер)
app.post('/api/servers/:id/leave', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username);
  if (g.error) return res.status(g.status).json({ error: g.error });
  if (g.guild.owner === req.username) return res.status(400).json({ error: 'Владелец не может выйти. Удалите сервер' });
  await ServerModel.updateOne({ _id: g.guild._id }, {
    $pull: { members: req.username, memberRoles: { user: req.username } }
  });
  notifyGuild(g.guild, [req.username]);
  res.json({ ok: true });
}));

// Название и аватарка сервера (только владелец)
app.patch('/api/servers/:id', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username);
  if (g.error) return res.status(g.status).json({ error: g.error });
  if (g.guild.owner !== req.username) return res.status(403).json({ error: 'Менять сервер может только владелец' });
  const b = req.body || {};
  if (typeof b.name === 'string') {
    const name = b.name.trim().slice(0, 40);
    if (name.length < 2) return res.status(400).json({ error: 'Название не короче 2 символов' });
    g.guild.name = name;
  }
  if (b.avatar === null) g.guild.avatar = null;
  else if (b.avatar !== undefined) {
    if (!isAvatarData(b.avatar)) return res.status(400).json({ error: 'Картинка слишком большая или неверного формата' });
    g.guild.avatar = b.avatar;
  }
  await g.guild.save();
  const channels = await Channel.find({ serverId: g.guild._id }).sort({ createdAt: 1 });
  notifyGuild(g.guild);
  res.json({ server: guildView(g.guild, req.username, channels) });
}));

// Название и аватарка канала (право manageChannels)
app.patch('/api/servers/:id/channels/:chId', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'manageChannels');
  if (g.error) return res.status(g.status).json({ error: g.error });
  if (!mongoose.isValidObjectId(req.params.chId)) return res.status(400).json({ error: 'Неверный канал' });
  const channel = await Channel.findOne({ _id: req.params.chId, serverId: g.guild._id });
  if (!channel) return res.status(404).json({ error: 'Канал не найден' });
  const b = req.body || {};
  if (typeof b.name === 'string') {
    const name = b.name.trim().toLowerCase().replace(/\s+/g, '-');
    if (!CHANNEL_RE.test(name)) return res.status(400).json({ error: 'Название канала: латиница, цифры, - и _' });
    if (await Channel.exists({ serverId: g.guild._id, name, _id: { $ne: channel._id } })) {
      return res.status(409).json({ error: 'Такой канал уже есть' });
    }
    channel.name = name;
  }
  if (b.avatar === null) channel.avatar = null;
  else if (b.avatar !== undefined) {
    if (!isAvatarData(b.avatar)) return res.status(400).json({ error: 'Картинка слишком большая или неверного формата' });
    channel.avatar = b.avatar;
  }
  await channel.save();
  notifyGuild(g.guild);
  res.json({ channel: { id: channel._id.toString(), name: channel.name, avatar: channel.avatar || null } });
}));

// Удаление сервера (только владелец): вместе с каналами и сообщениями
app.delete('/api/servers/:id', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username);
  if (g.error) return res.status(g.status).json({ error: g.error });
  if (g.guild.owner !== req.username) return res.status(403).json({ error: 'Удалить сервер может только владелец' });
  const channels = await Channel.find({ serverId: g.guild._id });
  const ids = channels.map((c) => String(c._id));
  await Message.deleteMany({ chatType: 'channel', chatId: { $in: ids } });
  await Channel.deleteMany({ serverId: g.guild._id });
  await ServerModel.deleteOne({ _id: g.guild._id });
  notifyGuild(g.guild);
  res.json({ ok: true });
}));

// Новый код приглашения (нужно право invite)
app.post('/api/servers/:id/invite', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'invite');
  if (g.error) return res.status(g.status).json({ error: g.error });
  g.guild.inviteCode = newInviteCode();
  await g.guild.save();
  res.json({ inviteCode: g.guild.inviteCode });
}));

// Каналы (нужно право manageChannels). Названия уникальны внутри сервера.
app.post('/api/servers/:id/channels', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'manageChannels');
  if (g.error) return res.status(g.status).json({ error: g.error });
  const name = String(req.body.name || '').trim().toLowerCase().replace(/\s+/g, '-');
  if (!CHANNEL_RE.test(name)) return res.status(400).json({ error: 'Название канала: латиница, цифры, - и _' });
  if (await Channel.exists({ serverId: g.guild._id, name })) return res.status(409).json({ error: 'Такой канал уже есть' });
  const channel = await Channel.create({ serverId: g.guild._id, name });
  notifyGuild(g.guild);
  res.status(201).json({ channel: { id: channel._id.toString(), name } });
}));

// Удаление канала (нужно право manageChannels) вместе с его сообщениями
app.delete('/api/servers/:id/channels/:chId', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'manageChannels');
  if (g.error) return res.status(g.status).json({ error: g.error });
  if (!mongoose.isValidObjectId(req.params.chId)) return res.status(400).json({ error: 'Неверный канал' });
  const channel = await Channel.findOne({ _id: req.params.chId, serverId: g.guild._id });
  if (!channel) return res.status(404).json({ error: 'Канал не найден' });
  await Message.deleteMany({ chatType: 'channel', chatId: String(channel._id) });
  await channel.deleteOne();
  notifyGuild(g.guild);
  res.json({ ok: true });
}));

// Роли: создание (manageRoles)
app.post('/api/servers/:id/roles', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'manageRoles');
  if (g.error) return res.status(g.status).json({ error: g.error });
  const name = String(req.body.name || '').trim().slice(0, 32);
  if (!name) return res.status(400).json({ error: 'Укажите название роли' });
  if (g.guild.roles.length >= MAX_ROLES) return res.status(400).json({ error: 'Слишком много ролей' });
  const color = COLOR_RE.test(req.body.color || '') ? req.body.color : '#8a8fa8';
  const perms = (Array.isArray(req.body.perms) ? req.body.perms : []).filter((p) => ALL_PERMS.includes(p));
  const emoji = cleanEmoji(req.body.emoji);
  g.guild.roles.push({ rid: crypto.randomBytes(6).toString('hex'), name, color, emoji, perms: [...new Set(perms)] });
  await g.guild.save();
  notifyGuild(g.guild);
  res.status(201).json({ server: guildView(g.guild, req.username) });
}));

// Роли: изменение (manageRoles). Базовую роль можно менять, но не удалять.
app.patch('/api/servers/:id/roles/:rid', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'manageRoles');
  if (g.error) return res.status(g.status).json({ error: g.error });
  const role = g.guild.roles.find((r) => r.rid === req.params.rid);
  if (!role) return res.status(404).json({ error: 'Роль не найдена' });
  const b = req.body || {};
  if (typeof b.name === 'string' && b.name.trim()) role.name = b.name.trim().slice(0, 32);
  if (COLOR_RE.test(b.color || '')) role.color = b.color;
  if (typeof b.emoji === 'string') role.emoji = cleanEmoji(b.emoji);
  if (Array.isArray(b.perms)) role.perms = [...new Set(b.perms.filter((p) => ALL_PERMS.includes(p)))];
  await g.guild.save();
  notifyGuild(g.guild);
  res.json({ server: guildView(g.guild, req.username) });
}));

// Роли: удаление (manageRoles). Базовую роль удалить нельзя.
app.delete('/api/servers/:id/roles/:rid', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'manageRoles');
  if (g.error) return res.status(g.status).json({ error: g.error });
  if (req.params.rid === EVERYONE) return res.status(400).json({ error: 'Базовую роль нельзя удалить' });
  g.guild.roles = g.guild.roles.filter((r) => r.rid !== req.params.rid);
  for (const m of g.guild.memberRoles) m.roleIds = m.roleIds.filter((id) => id !== req.params.rid);
  await g.guild.save();
  notifyGuild(g.guild);
  res.json({ server: guildView(g.guild, req.username) });
}));

// Выдать участнику роли (manageRoles). Владельцу роли не нужны — у него все права.
app.put('/api/servers/:id/members/:user/roles', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'manageRoles');
  if (g.error) return res.status(g.status).json({ error: g.error });
  const target = normalize(req.params.user);
  if (!g.guild.members.includes(target)) return res.status(404).json({ error: 'Участник не найден на сервере' });
  if (target === g.guild.owner) return res.status(400).json({ error: 'Владельцу роли не назначаются' });
  const known = new Set(g.guild.roles.map((r) => r.rid));
  const roleIds = (Array.isArray(req.body.roleIds) ? req.body.roleIds : [])
    .filter((id) => known.has(id) && id !== EVERYONE);
  const uniq = [...new Set(roleIds)];
  const entry = g.guild.memberRoles.find((m) => m.user === target);
  if (entry) entry.roleIds = uniq;
  else g.guild.memberRoles.push({ user: target, roleIds: uniq });
  await g.guild.save();
  notifyGuild(g.guild);
  res.json({ server: guildView(g.guild, req.username) });
}));

// Исключить участника (право kick). Владельца исключить нельзя, себя тоже.
app.delete('/api/servers/:id/members/:user', auth, route(async (req, res) => {
  const g = await loadGuild(req.params.id, req.username, 'kick');
  if (g.error) return res.status(g.status).json({ error: g.error });
  const target = normalize(req.params.user);
  if (target === req.username) return res.status(400).json({ error: 'Себя нельзя исключить, используйте «Выйти»' });
  if (target === g.guild.owner) return res.status(400).json({ error: 'Владельца нельзя исключить' });
  if (!g.guild.members.includes(target)) return res.status(404).json({ error: 'Участник не найден на сервере' });
  await ServerModel.updateOne({ _id: g.guild._id }, {
    $pull: { members: target, memberRoles: { user: target } }
  });
  notifyGuild(g.guild, [target]);
  res.json({ ok: true });
}));

// История: ?chatType=channel&chatId=<id> или ?chatType=dm&with=<username>
app.get('/api/messages', auth, route(async (req, res) => {
  const me = req.username;
  const limit = Math.min(Number(req.query.limit) || 50, 200);
  let chatId;

  if (req.query.chatType === 'channel') {
    const channel = await accessibleChannel(String(req.query.chatId || ''), me);
    if (!channel) return res.status(403).json({ error: 'Нет доступа к каналу' });
    chatId = String(channel._id);
  } else if (req.query.chatType === 'dm') {
    const other = normalize(req.query.with);
    if (!(await areFriends(me, other))) return res.status(403).json({ error: 'Чат доступен только друзьям' });
    chatId = pairKey(me, other);
  } else {
    return res.status(400).json({ error: 'Неверный тип чата' });
  }

  const messages = await Message.find({ chatType: req.query.chatType, chatId })
    .sort({ createdAt: -1 })
    .limit(limit);
  res.json({ messages: messages.reverse().map(toMessage) });
}));

// Страница мессенджера по адресу сервера
app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'messenger.html')));

// Любой неизвестный адрес /api отвечает JSON-ошибкой
app.use('/api', (req, res) => res.status(404).json({ error: 'Такого адреса нет на сервере. Обновите index.js на панели' }));

// ---------- Групповые звонки: комнаты в памяти, только для приглашённых ----------
const gcRooms = new Map(); // room -> { invited: Set, joined: Set }

// ---------- Файлы ----------

const safeName = (n) => String(n || 'file').replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').slice(0, 120) || 'file';

app.post('/api/upload', auth, express.raw({ type: () => true, limit: MAX_FILE }), route(async (req, res) => {
  if (!Buffer.isBuffer(req.body) || !req.body.length) return res.status(400).json({ error: 'Пустой файл' });
  const name = safeName(decodeURIComponent(String(req.headers['x-filename'] || 'file')));
  const ext = path.extname(name).replace(/[^.\w]/g, '').slice(0, 10);
  const id = crypto.randomBytes(12).toString('hex');
  await fs.promises.writeFile(path.join(UPLOAD_DIR, id + ext), req.body);
  res.status(201).json({
    url: '/files/' + id + ext,
    name,
    mime: String(req.headers['x-mime'] || '').slice(0, 100),
    size: req.body.length
  });
}));

app.get('/files/:name', route(async (req, res) => {
  try { jwt.verify(String(req.query.token || ''), JWT_SECRET); }
  catch { return res.status(401).end(); }
  const full = path.join(UPLOAD_DIR, path.basename(req.params.name));
  if (!fs.existsSync(full)) return res.status(404).end();
  res.set('Cache-Control', 'private, max-age=86400');
  res.sendFile(full);
}));

// ---------- Realtime ----------

const server = http.createServer(app);
const io = new SocketIO(server, { cors: { origin: CORS_ORIGIN }, maxHttpBufferSize: 2e6 });

io.use((socket, next) => {
  try {
    socket.username = jwt.verify(socket.handshake.auth?.token || '', JWT_SECRET).username;
    next();
  } catch {
    next(new Error('unauthorized'));
  }
});

io.on('connection', async (socket) => {
  const me = socket.username;
  socket.join('user:' + me);

  // Всё, что пришло, пока пользователь был офлайн, теперь доставлено (✓✓)
  // не ждём: обработчики событий ниже должны зарегистрироваться сразу
  Message.updateMany({ chatType: 'dm', to: me, delivered: false }, { delivered: true }).catch(() => {});

  socket.on('channel:join', async (channelId, ack) => {
    const channel = await accessibleChannel(String(channelId || ''), me);
    if (channel) socket.join('channel:' + channel._id);
    if (typeof ack === 'function') ack({ ok: !!channel });
  });

  // { chatType: 'channel', chatId } или { chatType: 'dm', to, text }
  socket.on('message:send', async (data, ack) => {
    const reply = typeof ack === 'function' ? ack : () => {};
    try {
      const text = String(data?.text || '').trim();
      const audio = typeof data?.audio === 'string' && data.audio.startsWith('data:audio/') ? data.audio : null;
      const dur = Math.min(60, Math.max(0, Math.round(Number(data?.dur) || 0)));
      if (audio && audio.length > 1.9e6) return reply({ ok: false, error: 'Голосовое слишком длинное' });
      const file = data?.file && typeof data.file.url === 'string' && data.file.url.startsWith('/files/')
        ? { url: data.file.url, name: String(data.file.name || 'file').slice(0, 120), mime: String(data.file.mime || '').slice(0, 100), size: Math.max(0, Number(data.file.size) || 0) }
        : null;
      if ((!text && !audio && !file) || text.length > 4000) return reply({ ok: false, error: 'Пустое или слишком длинное сообщение' });

      if (data.chatType === 'channel') {
        const channel = await accessibleChannel(String(data.chatId || ''), me);
        if (!channel) return reply({ ok: false, error: 'Нет доступа к каналу' });
        const msg = toMessage(await Message.create({ chatType: 'channel', chatId: String(channel._id), from: me, text, audio, dur, file }));
        io.to('channel:' + channel._id).emit('message:new', msg);
        return reply({ ok: true, message: msg });
      }

      if (data.chatType === 'dm') {
        const to = normalize(data.to);
        if (!(await areFriends(me, to))) return reply({ ok: false, error: 'Чат доступен только друзьям' });
        const online = (await io.in('user:' + to).fetchSockets()).length > 0;
        const msg = toMessage(await Message.create({
          chatType: 'dm', chatId: pairKey(me, to), from: me, to, text, audio, dur, file, delivered: online
        }));
        io.to('user:' + me).to('user:' + to).emit('message:new', msg);
        return reply({ ok: true, message: msg });
      }

      reply({ ok: false, error: 'Неверный тип чата' });
    } catch (err) {
      console.error(err);
      reply({ ok: false, error: 'Ошибка сервера' });
    }
  });

  // Прочитано: { chatType: 'channel', chatId } или { chatType: 'dm', with }
  socket.on('messages:read', async (data) => {
    try {
      if (data.chatType === 'channel') {
        const channel = await accessibleChannel(String(data.chatId || ''), me);
        if (!channel) return;
        const chatId = String(channel._id);
        await Message.updateMany({ chatType: 'channel', chatId, from: { $ne: me } }, { $addToSet: { readBy: me } });
        io.to('channel:' + chatId).emit('message:read', { chatType: 'channel', chatId, reader: me });
      } else if (data.chatType === 'dm') {
        const other = normalize(data.with);
        if (!(await areFriends(me, other))) return;
        const chatId = pairKey(me, other);
        await Message.updateMany({ chatType: 'dm', chatId, from: { $ne: me } }, { $addToSet: { readBy: me } });
        io.to('user:' + me).to('user:' + other).emit('message:read', { chatType: 'dm', chatId, reader: me });
      }
    } catch (err) {
      console.error(err);
    }
  });

  // Звонки 1 на 1 только между друзьями. Сервер передаёт сигналы, голос и видео идут напрямую.
  const relay = (event, key) => {
    socket.on(event, async (data) => {
      const to = normalize(data?.to);
      if (await areFriends(me, to)) io.to('user:' + to).emit(event, { from: me, [key]: data[key], video: !!data.video });
    });
  };
  relay('call:invite', 'offer');
  relay('call:answer', 'answer');
  relay('call:ice', 'candidate');
  socket.on('call:end', (data) => io.to('user:' + normalize(data?.to)).emit('call:end', { from: me }));

  // Групповой звонок
  socket.on('gcall:start', async (data, ack) => {
    const reply = typeof ack === 'function' ? ack : () => {};
    try {
      const names = [...new Set((Array.isArray(data?.members) ? data.members : []).map(normalize))]
        .filter((n) => USERNAME_RE.test(n) && n !== me);
      const friends = [];
      for (const n of names) if (await areFriends(me, n)) friends.push(n);
      if (!friends.length) return reply({ ok: false, error: 'Нет друзей из группы для звонка' });
      const room = crypto.randomBytes(8).toString('hex');
      const title = String(data?.title || 'Групповой звонок').slice(0, 40);
      const video = !!data?.video;
      gcRooms.set(room, { invited: new Set([me, ...friends]), joined: new Set([me]) });
      for (const n of friends) io.to('user:' + n).emit('gcall:ring', { room, from: me, title, video });
      reply({ ok: true, room });
    } catch (err) {
      console.error(err);
      reply({ ok: false, error: 'Ошибка сервера' });
    }
  });

  socket.on('gcall:join', (data, ack) => {
    const reply = typeof ack === 'function' ? ack : () => {};
    const room = String(data?.room || '');
    const r = gcRooms.get(room);
    if (!r || !r.invited.has(me)) return reply({ ok: false, error: 'Звонок не найден' });
    const peers = [...r.joined].filter((p) => p !== me);
    r.joined.add(me);
    for (const p of peers) io.to('user:' + p).emit('gcall:peer', { room, peer: me });
    reply({ ok: true, peers });
  });

  socket.on('gcall:signal', (data) => {
    const room = String(data?.room || '');
    const r = gcRooms.get(room);
    const to = normalize(data?.to);
    if (!r || !r.joined.has(me) || !r.joined.has(to)) return;
    io.to('user:' + to).emit('gcall:signal', { room, from: me, data: data.data });
  });

  socket.on('gcall:leave', (data) => {
    const room = String(data?.room || '');
    const r = gcRooms.get(room);
    if (!r) return;
    r.joined.delete(me);
    r.invited.delete(me);
    for (const p of r.joined) io.to('user:' + p).emit('gcall:left', { room, peer: me });
    if (!r.joined.size) gcRooms.delete(room);
  });

  socket.on('gcall:decline', (data) => {
    const room = String(data?.room || '');
    const r = gcRooms.get(room);
    if (!r) return;
    r.invited.delete(me);
    for (const p of r.joined) io.to('user:' + p).emit('gcall:declined', { room, peer: me });
  });
});

// ---------- Запуск ----------

mongoose.connect(MONGODB_URI)
  .then(() => {
    console.log('MongoDB подключена');
    server.listen(PORT, () => console.log(`Сервер запущен на порту ${PORT}`));
  })
  .catch((err) => {
    console.error('Не удалось подключиться к MongoDB:', err.message);
    process.exit(1);
  });
