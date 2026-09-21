import React, { useState, useEffect, useCallback, useMemo } from "react";
import * as XLSX from "xlsx";
import {
  Users, Tag, Link2, Crown, Activity, UsersRound, LogOut, Plus, Check, X,
  AlertTriangle, ShieldCheck, Upload, Calendar, RefreshCw, Loader2, KeyRound,
  ChevronDown, Search, Ban, CheckCircle2, Clock,
} from "lucide-react";

/* ══════════════════════════════════════════════════════════════════════
   FEBECA · Administración de usuarios, marcas y asignaciones
   Habla directo con Supabase (Auth + PostgREST) usando fetch.
   Requisitos en Supabase:
     · Esquema `app` en Settings → API → Exposed schemas
     · febeca-supabase-consolidado.sql aplicado
   ══════════════════════════════════════════════════════════════════════ */

/* ── Cliente mínimo de Supabase ─────────────────────────────────────── */
function crearApi(url, anon) {
  let token = null;
  const base = url.replace(/\/+$/, "");
  const cab = (extra = {}) => ({
    apikey: anon,
    Authorization: "Bearer " + (token || anon),
    "Content-Type": "application/json",
    ...extra,
  });
  async function leer(res) {
    const txt = await res.text();
    let data = null;
    try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
    if (!res.ok) {
      const m = data?.message || data?.msg || data?.error_description || data?.error || res.statusText;
      const hint = data?.hint ? " · " + data.hint : "";
      throw new Error((m || "Error") + hint);
    }
    return data;
  }
  return {
    get token() { return token; },
    setToken(t) { token = t; },
    async login(email, password) {
      const r = await fetch(base + "/auth/v1/token?grant_type=password", {
        method: "POST", headers: { apikey: anon, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });
      const d = await leer(r); token = d.access_token; return d;
    },
    async signup(email, password, nombre) {
      const r = await fetch(base + "/auth/v1/signup", {
        method: "POST", headers: { apikey: anon, "Content-Type": "application/json" },
        body: JSON.stringify({ email, password, data: { nombre } }),
      });
      return leer(r);
    },
    async select(rel, q = "select=*") {
      const r = await fetch(base + "/rest/v1/" + rel + "?" + q, { headers: cab({ "Accept-Profile": "app" }) });
      return leer(r);
    },
    async rpc(fn, args = {}) {
      const r = await fetch(base + "/rest/v1/rpc/" + fn, {
        method: "POST", headers: cab({ "Content-Profile": "app", "Accept-Profile": "app" }),
        body: JSON.stringify(args),
      });
      return leer(r);
    },
    async patch(rel, filtro, body) {
      const r = await fetch(base + "/rest/v1/" + rel + "?" + filtro, {
        method: "PATCH", headers: cab({ "Content-Profile": "app", Prefer: "return=minimal" }),
        body: JSON.stringify(body),
      });
      return leer(r);
    },
  };
}

const ROLES = ["admin", "gerencia", "jefe_compras", "comprador", "lectura"];
const ROL_ET = { admin: "Admin", gerencia: "Gerencia", jefe_compras: "Jefe de compras", comprador: "Comprador", lectura: "Lectura" };
const ROL_COL = { admin: "text-rose-300 bg-rose-500", gerencia: "text-violet-300 bg-violet-500",
  jefe_compras: "text-amber-300 bg-amber-500", comprador: "text-sky-300 bg-sky-500", lectura: "text-slate-300 bg-slate-500" };
const hoy = () => new Date().toISOString().slice(0, 10);
const fFecha = (d) => d ? new Date(d).toLocaleDateString("es-VE", { day: "2-digit", month: "short", year: "numeric" }) : "—";
const fHora = (d) => d ? new Date(d).toLocaleString("es-VE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "";
const fUSD = (v) => v == null ? "—" : "$" + Math.round(v).toLocaleString("es-VE");

/* ── Piezas de UI ────────────────────────────────────────────────────── */
const CARD = "rounded-2xl border border-slate-800 shadow-2xl";
const CARDBG = { background: "rgba(15,23,42,.9)", backdropFilter: "blur(12px)" };
const INPUT = "w-full rounded-xl border border-slate-800 bg-slate-950 px-3 py-2.5 text-sm text-slate-200 outline-none focus:border-sky-600";
const BTN = "rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-40";
const BTN_P = BTN + " bg-sky-500 text-slate-950 hover:bg-sky-400";
const BTN_G = BTN + " border border-slate-700 text-slate-300 hover:border-slate-500";

function Card({ children, className = "" }) {
  return <section className={CARD + " " + className} style={CARDBG}>{children}</section>;
}
function Head({ t, s, extra }) {
  return (
    <header className="flex flex-wrap items-start justify-between gap-3 px-5 pt-5">
      <div><h2 className="text-sm font-semibold text-white">{t}</h2>{s && <p className="mt-0.5 text-xs text-slate-500">{s}</p>}</div>
      {extra}
    </header>
  );
}
function Pill({ children, cls }) {
  return <span className={"inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-semibold " + cls} style={{ borderColor: "currentColor", background: "transparent" }}>{children}</span>;
}
function RolPill({ rol }) { return <Pill cls={(ROL_COL[rol] || ROL_COL.lectura).split(" ")[0]}>{ROL_ET[rol] || rol}</Pill>; }
function Estado({ e }) {
  const m = {
    operativa: ["text-emerald-300", CheckCircle2], vigente: ["text-emerald-300", CheckCircle2], "al día": ["text-emerald-300", CheckCircle2],
    "sin clasificar": ["text-rose-300", AlertTriangle], "sin responsable": ["text-amber-300", AlertTriangle], "sin datos": ["text-sky-300", Clock],
    programada: ["text-sky-300", Calendar], "suplencia activa": ["text-amber-300", Clock], "cobertura temporal": ["text-amber-300", Clock],
    terminada: ["text-slate-500", X], pendiente: ["text-amber-300", Clock], atrasado: ["text-rose-300", AlertTriangle], "sin cargar nunca": ["text-rose-300", Ban],
  };
  const [c, I] = m[e] || ["text-slate-400", Clock];
  return <Pill cls={c}><I size={11} />{e}</Pill>;
}
function Aviso({ tipo = "info", children }) {
  const c = { info: ["text-sky-300", "rgba(56,189,248,.08)"], ok: ["text-emerald-300", "rgba(16,185,129,.08)"], err: ["text-rose-300", "rgba(244,63,94,.08)"], warn: ["text-amber-300", "rgba(245,158,11,.08)"] }[tipo];
  return <div className={"flex gap-2 rounded-xl border border-slate-800 p-3 text-xs " + c[0]} style={{ background: c[1] }}>{tipo === "err" || tipo === "warn" ? <AlertTriangle size={14} className="mt-0.5 shrink-0" /> : <ShieldCheck size={14} className="mt-0.5 shrink-0" />}<span className="leading-relaxed">{children}</span></div>;
}
function Campo({ l, children }) { return <label className="block"><span className="mb-1 block text-[11px] font-medium text-slate-500">{l}</span>{children}</label>; }
function Tabla({ cols, filas, vacio = "Sin datos." }) {
  if (!filas?.length) return <p className="px-5 pb-5 text-xs text-slate-500">{vacio}</p>;
  return (
    <div className="overflow-x-auto px-5 pb-5">
      <table className="w-full text-xs">
        <thead><tr className="text-slate-500">{cols.map((c) => <th key={c.k} className={"pb-2 font-medium " + (c.r ? "text-right" : "text-left")}>{c.t}</th>)}</tr></thead>
        <tbody>{filas.map((f, i) => (
          <tr key={f.id ?? i} className="border-t border-slate-800">
            {cols.map((c) => <td key={c.k} className={"py-2.5 pr-3 " + (c.r ? "text-right" : "")}>{c.f ? c.f(f) : (f[c.k] ?? "—")}</td>)}
          </tr>))}</tbody>
      </table>
    </div>
  );
}

/* ══════════════════════════ APP ══════════════════════════ */
export default function App() {
  const [cfg, setCfg] = useState({ url: "", anon: "" });
  const [api, setApi] = useState(null);
  const [yo, setYo] = useState(null);
  const [tab, setTab] = useState("usuarios");
  const [msg, setMsg] = useState(null);
  const [ocupado, setOcupado] = useState(false);

  const correr = useCallback(async (fn, okMsg) => {
    setOcupado(true); setMsg(null);
    try { const r = await fn(); if (okMsg) setMsg({ t: "ok", m: typeof okMsg === "function" ? okMsg(r) : okMsg }); return r; }
    catch (e) { setMsg({ t: "err", m: e.message }); }
    finally { setOcupado(false); }
  }, []);

  if (!api) return <Conexion onOk={(u, a) => { setCfg({ url: u, anon: a }); setApi(crearApi(u, a)); }} />;
  if (!yo) return <Login api={api} onOk={setYo} />;

  const puedeGestionar = ["admin", "gerencia"].includes(yo.rol);
  const esJefe = yo.rol === "jefe_compras";
  const TABS = [
    puedeGestionar && { id: "usuarios", l: "Usuarios", I: Users },
    (puedeGestionar || esJefe) && { id: "marcas", l: "Marcas", I: Tag },
    (puedeGestionar || esJefe) && { id: "asignaciones", l: "Asignaciones", I: Link2 },
    puedeGestionar && { id: "jefaturas", l: "Jefaturas", I: Crown },
    { id: "actividad", l: "Actividad", I: Activity },
    { id: "equipo", l: "Equipo", I: UsersRound },
  ].filter(Boolean);
  const tabActual = TABS.find((t) => t.id === tab) ? tab : TABS[0].id;
  const ctx = { api, yo, correr, ocupado, setMsg };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-200" style={{ fontFamily: "ui-sans-serif, system-ui, sans-serif" }}>
      <div className="pointer-events-none fixed inset-0" style={{ background: "radial-gradient(760px circle at 10% -10%, rgba(56,189,248,.10), transparent 55%), radial-gradient(680px circle at 92% 2%, rgba(139,92,246,.09), transparent 55%)" }} />
      <div className="relative">
        <header className="sticky top-0 z-30 border-b border-slate-800" style={{ background: "rgba(2,6,23,.85)", backdropFilter: "blur(14px)" }}>
          <div className="mx-auto flex max-w-[1400px] flex-wrap items-center gap-3 px-5 py-3">
            <div className="flex items-center gap-3">
              <div className="grid h-9 w-9 place-items-center rounded-xl font-bold text-slate-950" style={{ background: "linear-gradient(135deg,#38bdf8,#6366f1)" }}>F</div>
              <div className="leading-tight"><div className="text-sm font-semibold tracking-wide text-white">FEBECA</div><div className="text-xs text-slate-500">Administración · Compras</div></div>
            </div>
            <div className="ml-auto flex items-center gap-3">
              <div className="flex items-center gap-2.5 rounded-full border border-slate-800 bg-slate-900 py-1.5 pl-1.5 pr-3.5">
                <div className="grid h-7 w-7 place-items-center rounded-full text-xs font-bold text-white" style={{ background: "linear-gradient(135deg,#8b5cf6,#d946ef)" }}>{yo.nombre?.slice(0, 2).toUpperCase()}</div>
                <div className="leading-tight"><div className="text-xs font-medium text-white">{yo.nombre}</div><div className="text-[11px] text-slate-500">{ROL_ET[yo.rol]}</div></div>
              </div>
              <button onClick={() => { api.setToken(null); setYo(null); }} className="grid h-9 w-9 place-items-center rounded-full border border-slate-800 text-slate-400 hover:text-white"><LogOut size={15} /></button>
            </div>
          </div>
          <div className="mx-auto flex max-w-[1400px] gap-1 overflow-x-auto px-5 pb-2">
            {TABS.map((t) => (
              <button key={t.id} onClick={() => setTab(t.id)} className={"flex shrink-0 items-center gap-2 rounded-full px-3.5 py-2 text-sm font-medium " + (tabActual === t.id ? "bg-sky-500 text-slate-950" : "text-slate-400 hover:text-slate-200")}>
                <t.I size={15} />{t.l}
              </button>))}
          </div>
        </header>

        <main className="mx-auto max-w-[1400px] space-y-5 px-5 py-6">
          {msg && <Aviso tipo={msg.t}>{msg.m}</Aviso>}
          {ocupado && <div className="flex items-center gap-2 text-xs text-slate-500"><Loader2 size={13} className="animate-spin" />Procesando…</div>}
          {tabActual === "usuarios" && <Usuarios {...ctx} />}
          {tabActual === "marcas" && <Marcas {...ctx} />}
          {tabActual === "asignaciones" && <Asignaciones {...ctx} />}
          {tabActual === "jefaturas" && <Jefaturas {...ctx} />}
          {tabActual === "actividad" && <Actividad {...ctx} />}
          {tabActual === "equipo" && <Equipo {...ctx} />}
          <p className="pt-6 text-center text-xs text-slate-700">{cfg.url}</p>
        </main>
      </div>
    </div>
  );
}

/* ══════════ Conexión y login ══════════ */
function Conexion({ onOk }) {
  const [u, setU] = useState(""); const [a, setA] = useState("");
  return (
    <Pantalla titulo="Conectar con Supabase" sub="Settings → API en tu proyecto">
      <Campo l="Project URL"><input className={INPUT} value={u} onChange={(e) => setU(e.target.value)} placeholder="https://xxxx.supabase.co" /></Campo>
      <Campo l="anon public key"><input className={INPUT} value={a} onChange={(e) => setA(e.target.value)} placeholder="eyJhbGciOi…" /></Campo>
      <button className={BTN_P + " w-full"} disabled={!u || !a} onClick={() => onOk(u.trim(), a.trim())}>Continuar</button>
      <Aviso>Recuerda agregar <b>app</b> a «Exposed schemas» en Settings → API. Sin eso, todas las consultas devuelven 404.</Aviso>
    </Pantalla>
  );
}
function Login({ api, onOk }) {
  const [e, setE] = useState(""); const [p, setP] = useState(""); const [err, setErr] = useState(null); const [ld, setLd] = useState(false);
  const entrar = async () => {
    setLd(true); setErr(null);
    try {
      const d = await api.login(e.trim(), p);
      const perf = await api.select("perfiles", "select=id,nombre,rol,activo&id=eq." + d.user.id);
      if (!perf?.[0]) throw new Error("Tu perfil no existe todavía. Pide al administrador que active tu cuenta.");
      if (!perf[0].activo) throw new Error("Tu cuenta está desactivada.");
      onOk(perf[0]);
    } catch (x) { setErr(x.message); } finally { setLd(false); }
  };
  return (
    <Pantalla titulo="Iniciar sesión" sub="Dashboard de Compras · Febeca">
      <Campo l="Correo"><input className={INPUT} value={e} onChange={(x) => setE(x.target.value)} type="email" /></Campo>
      <Campo l="Contraseña"><input className={INPUT} value={p} onChange={(x) => setP(x.target.value)} type="password" onKeyDown={(k) => k.key === "Enter" && entrar()} /></Campo>
      {err && <Aviso tipo="err">{err}</Aviso>}
      <button className={BTN_P + " w-full"} disabled={ld || !e || !p} onClick={entrar}>{ld ? "Entrando…" : "Entrar"}</button>
    </Pantalla>
  );
}
function Pantalla({ titulo, sub, children }) {
  return (
    <div className="grid min-h-screen place-items-center bg-slate-950 px-4 text-slate-200" style={{ fontFamily: "ui-sans-serif, system-ui, sans-serif" }}>
      <Card className="w-full max-w-md p-7">
        <div className="mb-6 flex items-center gap-3">
          <div className="grid h-11 w-11 place-items-center rounded-xl text-lg font-bold text-slate-950" style={{ background: "linear-gradient(135deg,#38bdf8,#6366f1)" }}>F</div>
          <div><h1 className="text-lg font-semibold text-white">{titulo}</h1><p className="text-xs text-slate-500">{sub}</p></div>
        </div>
        <div className="space-y-4">{children}</div>
      </Card>
    </div>
  );
}

/* ══════════ Usuarios ══════════ */
function Usuarios({ api, yo, correr, ocupado }) {
  const [lista, setLista] = useState([]); const [q, setQ] = useState("");
  const [nuevo, setNuevo] = useState({ email: "", pass: "", nombre: "" }); const [abrir, setAbrir] = useState(false);
  const cargar = useCallback(() => correr(async () => setLista(await api.select("perfiles", "select=id,nombre,rol,activo,creado_en&order=nombre"))), [api, correr]);
  useEffect(() => { cargar(); }, [cargar]);
  const filtradas = lista.filter((u) => (u.nombre || "").toLowerCase().includes(q.toLowerCase()));

  const cambiarRol = (u, rol) => correr(() => api.rpc("cambiar_rol", { p_usuario: u.id, p_rol: rol }), `Rol de ${u.nombre}: ${ROL_ET[rol]}`).then(cargar);
  const desactivar = (u) => correr(() => api.rpc("desactivar_usuario", { p_usuario_id: u.id }), `${u.nombre} desactivado`).then(cargar);
  const reactivar = (u) => correr(() => api.patch("perfiles", "id=eq." + u.id, { activo: true }), `${u.nombre} reactivado`).then(cargar);
  const registrar = () => correr(async () => {
    await api.signup(nuevo.email.trim(), nuevo.pass, nuevo.nombre.trim());
    setNuevo({ email: "", pass: "", nombre: "" }); setAbrir(false);
  }, "Usuario registrado con rol Lectura. Asígnale un rol y sus marcas.").then(cargar);

  return (
    <div className="space-y-5">
      <Card>
        <Head t="Usuarios" s={`${lista.length} cuentas · el rol se cambia aquí, las marcas en Asignaciones`}
              extra={<button className={BTN_P + " flex items-center gap-1.5"} onClick={() => setAbrir((v) => !v)}><Plus size={14} />Registrar</button>} />
        {abrir && (
          <div className="mx-5 mt-4 grid gap-3 rounded-xl border border-slate-800 p-4 sm:grid-cols-4" style={{ background: "rgba(2,6,23,.5)" }}>
            <Campo l="Nombre"><input className={INPUT} value={nuevo.nombre} onChange={(e) => setNuevo({ ...nuevo, nombre: e.target.value })} /></Campo>
            <Campo l="Correo"><input className={INPUT} type="email" value={nuevo.email} onChange={(e) => setNuevo({ ...nuevo, email: e.target.value })} /></Campo>
            <Campo l="Contraseña inicial"><input className={INPUT} type="text" value={nuevo.pass} onChange={(e) => setNuevo({ ...nuevo, pass: e.target.value })} /></Campo>
            <div className="flex items-end"><button className={BTN_P + " w-full"} disabled={ocupado || !nuevo.email || nuevo.pass.length < 8} onClick={registrar}>Crear</button></div>
            <p className="text-[11px] text-slate-500 sm:col-span-4">Nace con rol Lectura y sin marcas. Si el proyecto exige confirmar correo, recibirá un enlace antes de poder entrar.</p>
          </div>
        )}
        <div className="px-5 pt-4"><div className="relative"><Search size={14} className="absolute left-3 top-3 text-slate-500" /><input className={INPUT + " pl-9"} placeholder="Buscar…" value={q} onChange={(e) => setQ(e.target.value)} /></div></div>
        <div className="pt-3">
          <Tabla filas={filtradas} cols={[
            { k: "nombre", t: "Nombre", f: (u) => <span className={u.activo ? "text-slate-200" : "text-slate-600 line-through"}>{u.nombre}{u.id === yo.id && <span className="ml-2 text-[10px] text-sky-400">tú</span>}</span> },
            { k: "rol", t: "Rol", f: (u) => u.id === yo.id ? <RolPill rol={u.rol} /> : (
              <div className="relative inline-block">
                <select value={u.rol} disabled={ocupado} onChange={(e) => cambiarRol(u, e.target.value)}
                        className="appearance-none rounded-full border border-slate-700 bg-slate-900 py-1 pl-3 pr-7 text-[11px] font-semibold text-slate-200">
                  {ROLES.map((r) => <option key={r} value={r} disabled={r === "admin" && yo.rol !== "admin"}>{ROL_ET[r]}</option>)}
                </select><ChevronDown size={12} className="pointer-events-none absolute right-2 top-1.5 text-slate-500" />
              </div>) },
            { k: "activo", t: "Estado", f: (u) => u.activo ? <Pill cls="text-emerald-300">activo</Pill> : <Pill cls="text-slate-500">inactivo</Pill> },
            { k: "creado_en", t: "Alta", f: (u) => <span className="text-slate-500">{fFecha(u.creado_en)}</span> },
            { k: "acc", t: "", r: 1, f: (u) => u.id === yo.id ? null : u.activo
                ? <button className="text-[11px] text-rose-400 hover:underline" disabled={ocupado} onClick={() => desactivar(u)}>Desactivar</button>
                : <button className="text-[11px] text-emerald-400 hover:underline" disabled={ocupado} onClick={() => reactivar(u)}>Reactivar</button> },
          ]} />
        </div>
      </Card>
      <Aviso>Desactivar no borra: cierra sus asignaciones y conserva la historia de sus cargas. Solo un admin puede nombrar a otro admin, y nadie cambia su propio rol.</Aviso>
    </div>
  );
}

/* ══════════ Marcas ══════════ */
function Marcas({ api, yo, correr, ocupado }) {
  const [lista, setLista] = useState([]); const [filtro, setFiltro] = useState("todas"); const [q, setQ] = useState("");
  const gestiona = ["admin", "gerencia"].includes(yo.rol);
  const cargar = useCallback(() => correr(async () => setLista(await api.select("v_marcas", "select=*&order=venta_12m_usd.desc.nullslast"))), [api, correr]);
  useEffect(() => { cargar(); }, [cargar]);
  const clasificar = (m, o) => correr(() => api.rpc("clasificar_marca", { p_marca: m.id, p_origen: o }), `${m.codigo} clasificada como ${o}`).then(cargar);
  const importar = (file) => correr(async () => {
    const wb = XLSX.read(await file.arrayBuffer(), { type: "array" });
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, defval: null });
    const marcas = [];
    for (let r = 2; r < rows.length; r++) {
      const f = rows[r]; if (!f || !f[0] || f[0] === "Total" || String(f[0]).startsWith("Filtros")) continue;
      const venta = f.slice(1).filter((v) => typeof v === "number").reduce((a, b) => a + b, 0) * 1000;
      marcas.push({ codigo: String(f[0]).trim(), nombre: String(f[0]).trim(), venta_12m_usd: Math.round(venta) });
    }
    if (!marcas.length) throw new Error("El archivo no tiene filas de marca. ¿Es la exportación con Parameter = Marca?");
    const [r] = await api.rpc("importar_catalogo_marcas", { p_marcas: marcas });
    return r;
  }, (r) => `Catálogo: ${r.nuevas} nuevas, ${r.actualizadas} actualizadas, ${r.sin_clasificar} pendientes de clasificar`).then(cargar);

  const conteo = useMemo(() => lista.reduce((a, m) => { a[m.estado] = (a[m.estado] || 0) + 1; return a; }, {}), [lista]);
  const filas = lista.filter((m) => (filtro === "todas" || m.estado === filtro) && (m.codigo + " " + (m.nombre || "")).toLowerCase().includes(q.toLowerCase()));

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[["sin clasificar", "#f43f5e"], ["sin responsable", "#f59e0b"], ["sin datos", "#38bdf8"], ["operativa", "#34d399"]].map(([e, c]) => (
          <button key={e} onClick={() => setFiltro(filtro === e ? "todas" : e)} className={CARD + " p-4 text-left"} style={{ ...CARDBG, borderColor: filtro === e ? c : undefined }}>
            <div className="text-xs text-slate-400 capitalize">{e}</div><div className="mt-1 text-3xl font-semibold" style={{ color: c }}>{conteo[e] || 0}</div>
          </button>))}
      </div>
      <Card>
        <Head t="Catálogo de marcas" s={gestiona ? "La lista viva sale del SIM: Parameter = Marca, sin filtro, 12 meses, Venta Neta" : "Marcas de tu ámbito"}
              extra={gestiona && <label className={BTN_P + " flex cursor-pointer items-center gap-1.5"}><Upload size={14} />Importar del SIM<input type="file" accept=".xlsx,.xls" hidden onChange={(e) => e.target.files[0] && importar(e.target.files[0])} /></label>} />
        <div className="px-5 pt-4"><div className="relative"><Search size={14} className="absolute left-3 top-3 text-slate-500" /><input className={INPUT + " pl-9"} placeholder="Buscar marca…" value={q} onChange={(e) => setQ(e.target.value)} /></div></div>
        <div className="pt-3">
          <Tabla filas={filas} vacio="Ninguna marca en este filtro." cols={[
            { k: "codigo", t: "Marca", f: (m) => <div><div className="font-medium text-slate-200">{m.codigo}</div>{m.proveedor && <div className="text-[11px] text-slate-600">{m.proveedor}</div>}</div> },
            { k: "origen", t: "Origen", f: (m) => m.origen ? <span className="capitalize text-slate-300">{m.origen}</span> : gestiona ? (
                <div className="flex gap-1.5">
                  <button className="rounded-full border border-sky-800 px-2.5 py-0.5 text-[11px] text-sky-300 hover:bg-sky-950" disabled={ocupado} onClick={() => clasificar(m, "internacional")}>internacional</button>
                  <button className="rounded-full border border-emerald-800 px-2.5 py-0.5 text-[11px] text-emerald-300 hover:bg-emerald-950" disabled={ocupado} onClick={() => clasificar(m, "nacional")}>nacional</button>
                </div>) : <span className="text-rose-400">pendiente</span> },
            { k: "venta_12m_usd", t: "Venta 12m", r: 1, f: (m) => <span className="text-slate-300">{fUSD(m.venta_12m_usd)}</span> },
            { k: "responsables", t: "Responsables", f: (m) => <span className="text-slate-400">{m.responsables || "—"}</span> },
            { k: "jefe", t: "Jefe", f: (m) => <span className="text-slate-500">{m.jefe || "—"}</span> },
            { k: "ultima_carga", t: "Última carga", f: (m) => <span className="text-slate-500">{fFecha(m.ultima_carga)}</span> },
            { k: "estado", t: "Estado", f: (m) => <Estado e={m.estado} /> },
          ]} />
        </div>
      </Card>
    </div>
  );
}

/* ══════════ Asignaciones ══════════ */
function Asignaciones({ api, yo, correr, ocupado }) {
  const [lista, setLista] = useState([]); const [marcas, setMarcas] = useState([]); const [gente, setGente] = useState([]);
  const [modo, setModo] = useState(null);
  const [f, setF] = useState({ marca: "", usuario: "", desde: hoy(), hasta: "", motivo: "", suspender: false, quitar: "" });
  const cargar = useCallback(() => correr(async () => {
    const [a, m, g] = await Promise.all([
      api.select("v_asignaciones", "select=*&order=estado,vigente_desde.desc"),
      api.select("v_marcas", "select=id,codigo,origen,estado,responsables&origen=not.is.null&activa=is.true&order=codigo"),
      api.select("v_compradores", "select=*&activo=is.true&order=nombre"),
    ]);
    setLista(a); setMarcas(m); setGente(g);
  }), [api, correr]);
  useEffect(() => { cargar(); }, [cargar]);

  const ejecutar = () => correr(async () => {
    const m = marcas.find((x) => x.id === f.marca); const u = gente.find((x) => x.id === f.usuario);
    if (modo === "asignar") await api.rpc("asignar_marca", { p_marca_id: f.marca, p_usuario: f.usuario, p_desde: f.desde, p_hasta: f.hasta || null, p_titular: true, p_motivo: f.motivo || null });
    if (modo === "suplencia") await api.rpc("programar_suplencia", { p_marca_id: f.marca, p_suplente: f.usuario, p_desde: f.desde, p_hasta: f.hasta, p_motivo: f.motivo || "Suplencia por ausencia", p_suspender_titular: f.suspender });
    if (modo === "traspaso") await api.rpc("reasignar_marca", { p_marca_id: f.marca, p_nuevo_id: f.usuario, p_quitar_al: f.quitar || null, p_desde: f.desde, p_motivo: f.motivo || "Traspaso de marca" });
    setModo(null); return `${m?.codigo} → ${u?.nombre}`;
  }, (r) => r).then(cargar);
  const terminar = (a) => correr(() => api.rpc("terminar_asignacion", { p_id: a.id, p_hasta: hoy(), p_motivo: "Terminada desde administración" }), `Asignación de ${a.marca} a ${a.usuario} terminada hoy`).then(cargar);

  const responsablesDe = (marcaId) => lista.filter((a) => a.marca_id === marcaId && a.estado === "vigente");
  const valido = f.marca && f.usuario && f.desde && (modo !== "suplencia" || f.hasta);

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap gap-2">
        {[["asignar", "Asignar marca", Plus], ["suplencia", "Programar suplencia", Calendar], ["traspaso", "Traspaso definitivo", RefreshCw]].map(([k, l, I]) => (
          <button key={k} onClick={() => setModo(modo === k ? null : k)} className={(modo === k ? BTN_P : BTN_G) + " flex items-center gap-1.5"}><I size={14} />{l}</button>))}
      </div>
      {modo && (
        <Card className="p-5">
          <div className="grid gap-3 md:grid-cols-3 lg:grid-cols-6">
            <Campo l="Marca"><select className={INPUT} value={f.marca} onChange={(e) => setF({ ...f, marca: e.target.value })}><option value="">—</option>{marcas.map((m) => <option key={m.id} value={m.id}>{m.codigo} · {m.origen}</option>)}</select></Campo>
            <Campo l={modo === "suplencia" ? "Suplente" : modo === "traspaso" ? "Nuevo responsable" : "Comprador"}><select className={INPUT} value={f.usuario} onChange={(e) => setF({ ...f, usuario: e.target.value })}><option value="">—</option>{gente.map((g) => <option key={g.id} value={g.id}>{g.nombre} ({g.marcas_vigentes} marcas)</option>)}</select></Campo>
            {modo === "traspaso" && <Campo l="Quitar a"><select className={INPUT} value={f.quitar} onChange={(e) => setF({ ...f, quitar: e.target.value })}><option value="">(nadie)</option>{responsablesDe(f.marca).map((a) => <option key={a.id} value={a.usuario_id}>{a.usuario}</option>)}</select></Campo>}
            <Campo l="Desde"><input type="date" className={INPUT} value={f.desde} onChange={(e) => setF({ ...f, desde: e.target.value })} /></Campo>
            {modo !== "traspaso" && <Campo l={modo === "suplencia" ? "Hasta (obligatorio)" : "Hasta (opcional)"}><input type="date" className={INPUT} value={f.hasta} onChange={(e) => setF({ ...f, hasta: e.target.value })} /></Campo>}
            <Campo l="Motivo"><input className={INPUT} value={f.motivo} onChange={(e) => setF({ ...f, motivo: e.target.value })} placeholder={modo === "suplencia" ? "Vacaciones de…" : ""} /></Campo>
            {modo === "suplencia" && <label className="flex items-center gap-2 self-end pb-2 text-xs text-slate-400"><input type="checkbox" checked={f.suspender} onChange={(e) => setF({ ...f, suspender: e.target.checked })} className="accent-sky-500" />Suspender al titular mientras dure</label>}
          </div>
          {f.marca && responsablesDe(f.marca).length > 0 && <p className="mt-3 text-[11px] text-slate-500">Responsables actuales de esta marca: {responsablesDe(f.marca).map((a) => a.usuario).join(", ")}</p>}
          <div className="mt-4 flex gap-2"><button className={BTN_P} disabled={!valido || ocupado} onClick={ejecutar}>Confirmar</button><button className={BTN_G} onClick={() => setModo(null)}>Cancelar</button></div>
        </Card>
      )}
      <Card>
        <Head t="Asignaciones" s={`${lista.filter((a) => a.estado === "vigente").length} vigentes · ${lista.filter((a) => a.estado === "programada").length} programadas · ${lista.filter((a) => a.estado.includes("suplencia")).length} suplencias activas`} />
        <div className="pt-4">
          <Tabla filas={lista} cols={[
            { k: "marca", t: "Marca", f: (a) => <div><div className="font-medium text-slate-200">{a.marca}</div><div className="text-[11px] capitalize text-slate-600">{a.origen}</div></div> },
            { k: "usuario", t: "Persona", f: (a) => <div><div className="text-slate-200">{a.usuario}</div><div className="text-[11px] text-slate-600">{a.titular ? "titular" : "suplente"}</div></div> },
            { k: "vigente_desde", t: "Desde", f: (a) => <span className="text-slate-400">{fFecha(a.vigente_desde)}</span> },
            { k: "vigente_hasta", t: "Hasta", f: (a) => <span className="text-slate-400">{a.vigente_hasta ? fFecha(a.vigente_hasta) : "indefinido"}{a.dias_restantes != null && a.dias_restantes <= 7 && <span className="ml-1 text-amber-400">· {a.dias_restantes} d</span>}</span> },
            { k: "motivo", t: "Motivo", f: (a) => <span className="text-slate-500">{a.motivo || "—"}</span> },
            { k: "estado", t: "Estado", f: (a) => <Estado e={a.estado} /> },
            { k: "acc", t: "", r: 1, f: (a) => ["vigente", "suplencia activa"].includes(a.estado) && <button className="text-[11px] text-rose-400 hover:underline" disabled={ocupado} onClick={() => terminar(a)}>Terminar hoy</button> },
          ]} />
        </div>
      </Card>
    </div>
  );
}

/* ══════════ Jefaturas ══════════ */
function Jefaturas({ api, yo, correr, ocupado }) {
  const [lista, setLista] = useState([]); const [huerfanos, setHuerfanos] = useState([]); const [gente, setGente] = useState([]);
  const [f, setF] = useState({ usuario: "", origen: "internacional", desde: hoy(), hasta: "", motivo: "" }); const [abrir, setAbrir] = useState(false);
  const cargar = useCallback(() => correr(async () => {
    const [j, h, p] = await Promise.all([api.select("v_jefaturas", "select=*&order=origen,vigente_desde.desc"), api.select("v_origenes_sin_jefe", "select=*"), api.select("perfiles", "select=id,nombre,rol&activo=is.true&rol=in.(jefe_compras,comprador,lectura)&order=nombre")]);
    setLista(j); setHuerfanos(h); setGente(p);
  }), [api, correr]);
  useEffect(() => { cargar(); }, [cargar]);
  const nombrar = () => correr(async () => {
    const fn = f.hasta ? "cubrir_jefatura" : "nombrar_jefe";
    const args = f.hasta ? { p_suplente: f.usuario, p_origen: f.origen, p_desde: f.desde, p_hasta: f.hasta, p_motivo: f.motivo || "Cobertura de jefatura" }
                         : { p_usuario: f.usuario, p_origen: f.origen, p_desde: f.desde, p_hasta: null, p_motivo: f.motivo || null };
    await api.rpc(fn, args); setAbrir(false);
  }, "Jefatura registrada").then(cargar);

  return (
    <div className="space-y-5">
      {huerfanos.length > 0 && <Aviso tipo="warn">Sin jefe vigente: {huerfanos.map((h) => `${h.origen} (${h.marcas} marcas)`).join(", ")}. Las marcas de ese origen no tienen quién las supervise ni quién asigne compradores.</Aviso>}
      <Card>
        <Head t="Jefes de compras" s="Uno por origen. Un jefe puede cubrir el otro origen con fecha de fin."
              extra={<button className={BTN_P + " flex items-center gap-1.5"} onClick={() => setAbrir((v) => !v)}><Crown size={14} />Nombrar</button>} />
        {abrir && (
          <div className="mx-5 mt-4 grid gap-3 rounded-xl border border-slate-800 p-4 md:grid-cols-5" style={{ background: "rgba(2,6,23,.5)" }}>
            <Campo l="Persona"><select className={INPUT} value={f.usuario} onChange={(e) => setF({ ...f, usuario: e.target.value })}><option value="">—</option>{gente.map((g) => <option key={g.id} value={g.id}>{g.nombre} · {ROL_ET[g.rol]}</option>)}</select></Campo>
            <Campo l="Origen"><select className={INPUT} value={f.origen} onChange={(e) => setF({ ...f, origen: e.target.value })}><option value="internacional">Internacional</option><option value="nacional">Nacional</option></select></Campo>
            <Campo l="Desde"><input type="date" className={INPUT} value={f.desde} onChange={(e) => setF({ ...f, desde: e.target.value })} /></Campo>
            <Campo l="Hasta (vacío = permanente)"><input type="date" className={INPUT} value={f.hasta} onChange={(e) => setF({ ...f, hasta: e.target.value })} /></Campo>
            <div className="flex items-end"><button className={BTN_P + " w-full"} disabled={!f.usuario || ocupado} onClick={nombrar}>Confirmar</button></div>
            <p className="text-[11px] text-slate-500 md:col-span-5">Al nombrar, la persona pasa a rol Jefe de compras si no era admin o gerencia. Con fecha de fin se registra como cobertura temporal.</p>
          </div>
        )}
        <div className="pt-4">
          <Tabla filas={lista} vacio="Todavía no hay jefes nombrados." cols={[
            { k: "jefe", t: "Jefe", f: (j) => <span className="font-medium text-slate-200">{j.jefe}</span> },
            { k: "origen", t: "Origen", f: (j) => <span className="capitalize text-slate-300">{j.origen}</span> },
            { k: "marcas_en_ambito", t: "Marcas", r: 1 },
            { k: "vigente_desde", t: "Desde", f: (j) => <span className="text-slate-400">{fFecha(j.vigente_desde)}</span> },
            { k: "vigente_hasta", t: "Hasta", f: (j) => <span className="text-slate-400">{j.vigente_hasta ? fFecha(j.vigente_hasta) : "permanente"}</span> },
            { k: "estado", t: "Estado", f: (j) => <Estado e={j.estado} /> },
          ]} />
        </div>
      </Card>
    </div>
  );
}

/* ══════════ Actividad ══════════ */
function Actividad({ api, correr }) {
  const [lista, setLista] = useState([]); const [solo, setSolo] = useState(false);
  useEffect(() => { correr(async () => setLista(await api.select("v_actividad", "select=*&order=cuando.desc&limit=200"))); }, [api, correr]);
  const filas = solo ? lista.filter((a) => a.requiere_atencion) : lista;
  return (
    <Card>
      <Head t="Actividad" s="Cargas y cambios, lo más reciente primero"
            extra={<label className="flex items-center gap-2 text-xs text-slate-400"><input type="checkbox" checked={solo} onChange={(e) => setSolo(e.target.checked)} className="accent-amber-500" />Solo lo que requiere atención</label>} />
      <div className="space-y-2 px-5 pb-5 pt-4">
        {!filas.length && <p className="text-xs text-slate-500">Sin actividad.</p>}
        {filas.map((a, i) => (
          <div key={i} className="flex gap-3 rounded-xl border border-slate-800 p-3" style={{ background: a.requiere_atencion ? "rgba(245,158,11,.05)" : "rgba(2,6,23,.5)" }}>
            <div className={"mt-0.5 shrink-0 " + (a.tipo === "carga" ? "text-sky-400" : "text-violet-400")}>{a.tipo === "carga" ? <Upload size={14} /> : <KeyRound size={14} />}</div>
            <div className="min-w-0 flex-1">
              <div className="text-xs text-slate-200">{a.detalle}</div>
              <div className="mt-0.5 flex flex-wrap gap-x-3 text-[11px] text-slate-500"><span>{a.quien}{a.rol && ` · ${ROL_ET[a.rol]}`}</span>{a.marca && <span className="text-slate-400">{a.marca}</span>}<span>{fHora(a.cuando)}</span></div>
            </div>
            {a.requiere_atencion && <AlertTriangle size={14} className="shrink-0 text-amber-400" />}
          </div>))}
      </div>
    </Card>
  );
}

/* ══════════ Equipo ══════════ */
function Equipo({ api, yo, correr }) {
  const [eq, setEq] = useState([]); const [cump, setCump] = useState([]);
  useEffect(() => { correr(async () => { const [a, b] = await Promise.all([api.select("v_equipo", "select=*&order=marcas_sin_cargar_esta_semana.desc,nombre"), api.select("v_cumplimiento_carga", "select=*&order=estado,marca")]); setEq(a); setCump(b); }); }, [api, correr]);
  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {[["al día", "#34d399"], ["pendiente", "#f59e0b"], ["atrasado", "#f43f5e"], ["sin cargar nunca", "#64748b"]].map(([e, c]) => (
          <div key={e} className={CARD + " p-4"} style={CARDBG}><div className="text-xs capitalize text-slate-400">{e}</div><div className="mt-1 text-3xl font-semibold" style={{ color: c }}>{cump.filter((x) => x.estado === e).length}</div></div>))}
      </div>
      <Card>
        <Head t="Equipo" s={yo.rol === "jefe_compras" ? "Compradores de tu ámbito" : "Todos los compradores con marcas vigentes"} />
        <div className="pt-4"><Tabla filas={eq} vacio="Nadie tiene marcas asignadas todavía." cols={[
          { k: "nombre", t: "Comprador", f: (e) => <div><div className="font-medium text-slate-200">{e.nombre}</div><div className="text-[11px] text-slate-600">{ROL_ET[e.rol]}</div></div> },
          { k: "marcas", t: "Marcas", r: 1 }, { k: "como_suplente", t: "Como suplente", r: 1 },
          { k: "ultima_carga", t: "Última carga", f: (e) => <span className="text-slate-400">{fHora(e.ultima_carga) || "nunca"}</span> },
          { k: "marcas_sin_cargar_esta_semana", t: "Sin cargar esta semana", r: 1, f: (e) => <span className={e.marcas_sin_cargar_esta_semana > 0 ? "font-semibold text-amber-400" : "text-emerald-400"}>{e.marcas_sin_cargar_esta_semana}</span> },
        ]} /></div>
      </Card>
      <Card>
        <Head t="Cumplimiento de carga por marca" s="Al día = cargó en los últimos 7 días" />
        <div className="pt-4"><Tabla filas={cump} cols={[
          { k: "marca", t: "Marca", f: (c) => <span className="font-medium text-slate-200">{c.marca}</span> },
          { k: "nombre", t: "Responsable", f: (c) => <span className="text-slate-300">{c.nombre}{!c.titular && <span className="ml-1 text-[10px] text-amber-400">suplente</span>}</span> },
          { k: "ultima_carga", t: "Última carga", f: (c) => <span className="text-slate-400">{fHora(c.ultima_carga) || "—"}</span> },
          { k: "cargas_semana", t: "Cargas 7d", r: 1 },
          { k: "tuvo_truncados", t: "", f: (c) => c.tuvo_truncados && <Pill cls="text-amber-300"><AlertTriangle size={11} />truncados</Pill> },
          { k: "estado", t: "Estado", f: (c) => <Estado e={c.estado} /> },
        ]} /></div>
      </Card>
    </div>
  );
}
