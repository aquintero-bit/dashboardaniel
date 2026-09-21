// ════════════════════════════════════════════════════════════════════════
//  FEBECA · Semilla de usuarios, jefes, catálogo y asignaciones
//
//  Corre UNA vez tras aplicar febeca-supabase-consolidado.sql.
//  Necesita la SERVICE ROLE KEY (Settings → API), nunca la anon key.
//
//    SUPABASE_URL=https://xxxx.supabase.co \
//    SUPABASE_SERVICE_ROLE=eyJ... \
//    node seed.mjs [ruta/al/export-marcas-del-SIM.xlsx]
// ════════════════════════════════════════════════════════════════════════
import { createClient } from "@supabase/supabase-js";
import * as XLSX from "xlsx";
import fs from "node:fs";

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE;
if (!url || !key) { console.error("Faltan SUPABASE_URL y SUPABASE_SERVICE_ROLE"); process.exit(1); }

const sb = createClient(url, key, { auth: { persistSession: false }, db: { schema: "app" } });

// ── 1. Usuarios ─────────────────────────────────────────────────────────
//  Edita esta lista. La contraseña inicial se debe cambiar en el primer
//  ingreso; también puedes usar inviteUserByEmail en vez de createUser.
const USUARIOS = [
  { email: "admin@febeca.com",       nombre: "Administrador",      rol: "admin",        pass: "Cambiar.2026!" },
  { email: "gerencia@febeca.com",    nombre: "Gerencia Compras",   rol: "gerencia",     pass: "Cambiar.2026!" },
  { email: "jefe.intl@febeca.com",   nombre: "Jefe Internacional", rol: "jefe_compras", pass: "Cambiar.2026!", jefatura: "internacional" },
  { email: "jefe.nac@febeca.com",    nombre: "Jefe Nacional",      rol: "jefe_compras", pass: "Cambiar.2026!", jefatura: "nacional" },
  { email: "adriana@febeca.com",     nombre: "Adriana",            rol: "comprador",    pass: "Cambiar.2026!", marcas: ["PCP"] },
];

// ── 2. Clasificación inicial de marcas (el resto queda pendiente) ───────
const CLASIFICACION = {
  internacional: ["PCP","BOSCH","DAEWOO","EMTOP","PEDROLLO","STANLEY","DEWALT","BEST VALUE","RALI","BELLOTA","CA MEJIA","ITALGRIF","AQUA NUOVA","GLADIATOR","EAGLE","ASMACO","TEZZA","AVTEK","GATO","FURIUS"],
  nacional:      ["TUBRICA","WEQUP","CODIRE","HIERRO NACIONAL","REINCO","ICONEL","METALES ALEADOS","RCA","SUNICO","FERMTETAL","ENERGY-ARCVEN"],
};

const ids = {};

async function crearUsuario(u) {
  const { data: lista } = await sb.auth.admin.listUsers({ perPage: 1000 });
  let user = lista.users.find((x) => x.email === u.email);
  if (!user) {
    const { data, error } = await sb.auth.admin.createUser({
      email: u.email, password: u.pass, email_confirm: true,
      user_metadata: { nombre: u.nombre },
    });
    if (error) throw error;
    user = data.user;
    console.log(`  + ${u.email}`);
  } else console.log(`  = ${u.email} (ya existía)`);
  ids[u.email] = user.id;
  // El trigger crea el perfil con 'lectura'; aquí se pone el rol real.
  const { error } = await sb.from("perfiles").update({ rol: u.rol, nombre: u.nombre, activo: true }).eq("id", user.id);
  if (error) throw error;
}

async function importarCatalogo(ruta) {
  if (!ruta || !fs.existsSync(ruta)) {
    console.log("  (sin archivo del SIM: se registran solo las marcas de la clasificación inicial)");
    const marcas = [...CLASIFICACION.internacional, ...CLASIFICACION.nacional].map((c) => ({ codigo: c, nombre: c }));
    await upsertMarcas(marcas); return;
  }
  // Exportación del SIM con Parameter = Marca, sin filtro, 12 meses, Venta Neta
  const wb = XLSX.read(fs.readFileSync(ruta));
  const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, defval: null });
  const marcas = [];
  for (let r = 2; r < rows.length; r++) {
    const f = rows[r]; if (!f || !f[0] || f[0] === "Total" || String(f[0]).startsWith("Filtros")) continue;
    const venta = f.slice(1).filter((v) => typeof v === "number").reduce((a, b) => a + b, 0) * 1000;
    marcas.push({ codigo: String(f[0]).trim(), nombre: String(f[0]).trim(), venta_12m_usd: Math.round(venta) });
  }
  console.log(`   ${marcas.length} marcas leídas`);
  await upsertMarcas(marcas);
}

// La RPC importar_catalogo_marcas exige un usuario admin o gerencia (auth.uid()),
// y la service role no tiene usuario: la llamada falla con "Solo admin o gerencia".
// La semilla escribe directo en marcas; la service role salta RLS. Misma lógica
// que la función: upsert por código, nombre solo si faltaba, activa = true.
async function upsertMarcas(marcas) {
  const filas = marcas.map((m) => {
    const codigo = String(m.codigo).trim().toUpperCase();
    return { codigo, nombre: String(m.nombre ?? codigo).trim() || codigo, venta_12m_usd: m.venta_12m_usd ?? null };
  });
  const { data: previas, error: e1 } = await sb.from("marcas").select("codigo,nombre");
  if (e1) throw e1;
  const nombreActual = new Map(previas.map((x) => [x.codigo, x.nombre]));

  const nuevas = filas.filter((f) => !nombreActual.has(f.codigo)).map((f) => ({ ...f, activa: true }));
  if (nuevas.length) {
    const { error } = await sb.from("marcas").insert(nuevas);
    if (error) throw error;
  }
  for (const f of filas.filter((x) => nombreActual.has(x.codigo))) {
    const cambios = { activa: true };
    if (f.venta_12m_usd != null) cambios.venta_12m_usd = f.venta_12m_usd;
    if (nombreActual.get(f.codigo) === f.codigo && f.nombre !== f.codigo) cambios.nombre = f.nombre;
    const { error } = await sb.from("marcas").update(cambios).eq("codigo", f.codigo);
    if (error) throw error;
  }
  const { count: pendientes, error: e2 } = await sb.from("marcas").select("id", { count: "exact", head: true }).is("origen", null).eq("activa", true);
  if (e2) throw e2;
  console.log(`   nuevas=${nuevas.length} actualizadas=${filas.length - nuevas.length} sin_clasificar=${pendientes}`);
}

async function clasificar() {
  const { data: marcas } = await sb.from("marcas").select("id,codigo");
  for (const [origen, lista] of Object.entries(CLASIFICACION)) {
    for (const cod of lista) {
      const m = marcas.find((x) => x.codigo === cod);
      if (!m) continue;
      await sb.from("marcas").update({ origen }).eq("id", m.id);
    }
    console.log(`   ${lista.length} como ${origen}`);
  }
}

async function main() {
  console.log("1. Usuarios");
  for (const u of USUARIOS) await crearUsuario(u);

  console.log("2. Catálogo de marcas");
  await importarCatalogo(process.argv[2]);

  console.log("3. Clasificación inicial");
  await clasificar();

  console.log("4. Jefaturas");
  for (const u of USUARIOS.filter((x) => x.jefatura)) {
    const { error } = await sb.from("jefaturas").insert({ usuario_id: ids[u.email], origen: u.jefatura, motivo: "Semilla inicial" });
    if (error && !String(error.message).includes("jefatura_sin_solapes")) throw error;
    console.log(`   ${u.nombre} → ${u.jefatura}`);
  }

  console.log("5. Asignaciones");
  const { data: marcas } = await sb.from("marcas").select("id,codigo");
  for (const u of USUARIOS.filter((x) => x.marcas)) {
    for (const cod of u.marcas) {
      const m = marcas.find((x) => x.codigo === cod);
      if (!m) { console.log(`   ! ${cod} no existe`); continue; }
      const { error } = await sb.from("usuario_marca").insert({ usuario_id: ids[u.email], marca_id: m.id, titular: true, motivo: "Semilla inicial" });
      if (error && !String(error.message).includes("sin_solapes")) throw error;
      console.log(`   ${u.nombre} ← ${cod}`);
    }
  }

  console.log("\nEstado de marcas:");
  const { data: est } = await sb.from("v_marcas").select("codigo,origen,estado,responsables").order("codigo");
  for (const m of est) console.log(`   ${m.codigo.padEnd(18)} ${String(m.origen ?? "—").padEnd(14)} ${m.estado.padEnd(16)} ${m.responsables ?? ""}`);
  console.log("\nListo. Cambia las contraseñas iniciales en el primer ingreso.");
}
main().catch((e) => { console.error("\nERROR:", e.message ?? e); process.exit(1); });
