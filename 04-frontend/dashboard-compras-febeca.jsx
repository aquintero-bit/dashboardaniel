import React, { useState, useMemo, useCallback, useRef } from "react";
import * as XLSX from "xlsx";
import {
  ResponsiveContainer, ComposedChart, LineChart, Line, Bar, XAxis, YAxis,
  CartesianGrid, Tooltip, Legend, ReferenceLine, Area,
} from "recharts";

/* ──────────────────────────────────────────────────────────────────────────
   Dashboard de Compras · Febeca
   Lee las exportaciones del SIM tal como salen y las normaliza.
   ────────────────────────────────────────────────────────────────────────── */

const EPA_EXACTO = [
  "FERRETERIA EPA, C.A.",
  "FERRETERIA EPA S.A",
  "FERRETERIA EPA, S.A.",
];

const ADITIVOS = new Set([
  "Venta Neta", "Venta Bruta", "Contribución", "Inventario",
  "Presupuesto bruto", "Presupuesto neto", "Presupuesto de contribución",
  "Presupuesto de inventario", "OC por recibir",
]);

// El SIM entrega Presupuesto bruto en dólares absolutos y el resto en miles.
const REESCALAR = { "Presupuesto bruto": 1 / 1000 };

const MES_RE = /^(\d{1,2})-(\d{4})$/;
const mesIdx = (m) => { const x = MES_RE.exec(m); return x ? +x[2] * 12 + (+x[1] - 1) : -1; };
const mesCorto = (m) => {
  const x = MES_RE.exec(m); if (!x) return m;
  return ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"][+x[1]-1] + " " + x[2].slice(2);
};
const codigoArt = (s) => String(s || "").trim().split(/\s+/)[0];
const norm = (s) => String(s || "").trim().toUpperCase().replace(/\s+/g, " ");
const esEpa = (cliente) => EPA_EXACTO.some((e) => norm(e) === norm(cliente));

/* ── Parser de una hoja del SIM ─────────────────────────────────────────── */
function leerHojaSim(rows, nombreArchivo) {
  const filaMes = rows[0] || [], filaEnc = rows[1] || [];
  let primerMes = -1;
  for (let c = 1; c < filaMes.length; c++) {
    if (filaMes[c] && MES_RE.test(String(filaMes[c]).trim())) { primerMes = c; break; }
  }
  if (primerMes < 1) return null;

  // Cortar donde termina el bloque de meses (protege contra tablas pegadas al lado).
  let ultimoMes = primerMes;
  for (let c = primerMes; c < filaMes.length; c++) {
    if (filaMes[c] && MES_RE.test(String(filaMes[c]).trim())) ultimoMes = c; else break;
  }

  const dims = [];
  for (let c = 0; c < primerMes; c++) dims.push(String(filaEnc[c] ?? "").trim());

  const cols = [];
  for (let c = primerMes; c <= ultimoMes; c++) {
    const mes = String(filaMes[c]).trim();
    const ind = String(filaEnc[c] ?? "").trim();
    if (ind) cols.push({ c, mes, ind });
  }

  // Bloque de filtros al pie: trae marca, máscara y si viene filtrado.
  let filtros = "";
  let truncado = false;
  for (const r of rows) {
    for (const v of r || []) {
      if (typeof v !== "string") continue;
      if (v.includes("Filtros aplicados")) filtros = v;
      if (/exceeded the allowed volume/i.test(v)) truncado = true;
    }
  }

  let mascara = "usd";
  if (/Mascara es Unidad/i.test(filtros)) mascara = "unidades";
  else if (/Mascara es Tonelada/i.test(filtros)) mascara = "toneladas";
  else if (/Mascara es Miles de d/i.test(filtros)) mascara = "usd";

  const filtradoEpa = /RazonSocial es[^\n]*EPA/i.test(filtros);
  const marcaFiltro = (/U_MARCA es ([^\n]+)/i.exec(filtros) || [, ""])[1].trim();

  // Filas hoja: la última dimensión debe tener valor propio, no "Total".
  const registros = [];
  const totales = {};
  for (let r = 2; r < rows.length; r++) {
    const fila = rows[r]; if (!fila) continue;
    const vals = dims.map((_, i) => (fila[i] == null ? null : String(fila[i]).trim()));
    if (vals.every((v) => v == null || v === "")) continue;

    const ultima = vals[vals.length - 1];
    const esHoja = ultima != null && ultima !== "" && ultima !== "Total";

    const llave = {};
    dims.forEach((d, i) => { llave[d] = vals[i]; });

    // Fila de total de marca: sirve para contrastar, no para sumar.
    const esTotalMarca = !esHoja && vals.filter((v) => v === "Total").length >= 1;

    for (const { c, mes, ind } of cols) {
      let v = fila[c];
      if (v == null || v === "") continue;
      v = typeof v === "number" ? v : parseFloat(String(v).replace(/,/g, ""));
      if (!isFinite(v)) continue;
      if (REESCALAR[ind]) v *= REESCALAR[ind];

      if (esHoja) registros.push({ ...llave, mes, ind, v });
      else if (esTotalMarca) {
        totales[mes] = totales[mes] || {};
        if (totales[mes][ind] == null) totales[mes][ind] = v;
      }
    }
  }

  return { dims, registros, totales, mascara, filtradoEpa, marcaFiltro, truncado, nombreArchivo,
           meses: [...new Set(cols.map((x) => x.mes))].sort((a, b) => mesIdx(a) - mesIdx(b)) };
}

/* ── Clasificación del archivo ──────────────────────────────────────────── */
function clasificar(p) {
  const d = new Set(p.dims);
  const inds = new Set(p.registros.map((r) => r.ind));
  if (inds.has("OC por recibir")) return "oc";
  if (d.has("Articulo") && d.has("Cliente")) return p.mascara === "unidades" ? "epa_art_unid" : "epa_art_usd";
  if (d.has("Articulo")) {
    if (p.filtradoEpa) return p.mascara === "unidades" ? "epa_art_unid" : "epa_art_usd";
    if (p.mascara === "unidades") return "art_unid";
    if (p.mascara === "toneladas") return "art_ton";
    return "art_usd";
  }
  if (d.has("Vendedor")) return "vendedor";
  if (d.has("Región")) return "geo";
  if (d.has("Cliente")) return "cliente";
  return "otro";
}

const ETIQUETAS = {
  art_usd: "Artículos · dólares",
  art_unid: "Artículos · unidades",
  art_ton: "Artículos · toneladas",
  epa_art_usd: "EPA por artículo · dólares",
  epa_art_unid: "EPA por artículo · unidades",
  oc: "Orden de compra por recibir",
  vendedor: "Vendedores",
  cliente: "Clientes",
  geo: "Estados, supervisores y regiones",
  infocompras: "Infocompras (stock y costos)",
  otro: "Sin clasificar",
};

/* ── Infocompras ────────────────────────────────────────────────────────── */
function leerInfocompras(wb) {
  const hojas = {};
  for (const nombre of wb.SheetNames) {
    const rows = XLSX.utils.sheet_to_json(wb.Sheets[nombre], { header: 1, defval: null });
    let hEnc = -1;
    for (let r = 0; r < Math.min(8, rows.length); r++) {
      if ((rows[r] || []).some((v) => typeof v === "string" && /CODIGO\s+SOFTLAND/i.test(v))) { hEnc = r; break; }
    }
    if (hEnc < 0) continue;
    const enc = (rows[hEnc] || []).map((v) => String(v ?? "").trim());
    const iCod = enc.findIndex((v) => /CODIGO\s+SOFTLAND/i.test(v));
    const col = (re) => enc.findIndex((v) => re.test(v));
    const iDisp = col(/^DISP$/i), iTran = col(/^TRANSITO$/i), iCosto = col(/^Costo$/i),
          iPV = col(/^PV$/i), iDesc = col(/^DESCRIPCION$/i), iSub = col(/SUB\s*CATEGORIAS/i),
          iBdf = col(/^BDF$/i);
    const items = {};
    for (let r = hEnc + 1; r < rows.length; r++) {
      const f = rows[r]; if (!f || f[iCod] == null) continue;
      const cod = String(f[iCod]).trim(); if (!cod) continue;
      const num = (i) => (i >= 0 && typeof f[i] === "number" ? f[i] : null);
      items[cod] = {
        disp: num(iDisp), transito: num(iTran), costo: num(iCosto), pv: num(iPV),
        desc: iDesc >= 0 ? f[iDesc] : null, sub: iSub >= 0 ? f[iSub] : null,
        bdf: iBdf >= 0 ? f[iBdf] : null,
      };
    }
    if (Object.keys(items).length) hojas[nombre.trim()] = items;
  }
  return Object.keys(hojas).length ? hojas : null;
}

/* ── Pronóstico ─────────────────────────────────────────────────────────── */
function holtWinters(y, m = 12, h = 6) {
  const n = y.length;
  if (n < 2 * m) return null;
  const nivelIni = y.slice(0, m).reduce((a, b) => a + b, 0) / m;
  const est0 = y.slice(0, m).map((v) => v - nivelIni);
  let mejor = null;
  const rango = [0.05, 0.15, 0.3, 0.5, 0.75];
  for (const a of rango) for (const b of [0.01, 0.05, 0.15]) for (const g of rango) {
    let L = nivelIni, T = (y.slice(m, 2 * m).reduce((x, z) => x + z, 0) - y.slice(0, m).reduce((x, z) => x + z, 0)) / (m * m);
    const S = est0.slice(); let sse = 0;
    for (let i = 0; i < n; i++) {
      const s = S[i % m], f = L + T + s;
      sse += (y[i] - f) ** 2;
      const Lp = L;
      L = a * (y[i] - s) + (1 - a) * (L + T);
      T = b * (L - Lp) + (1 - b) * T;
      S[i % m] = g * (y[i] - L) + (1 - g) * s;
    }
    if (!mejor || sse < mejor.sse) mejor = { sse, a, b, g, L, T, S, i: n };
  }
  if (!mejor) return null;
  const out = [];
  for (let k = 1; k <= h; k++) out.push(Math.max(0, mejor.L + k * mejor.T + mejor.S[(mejor.i + k - 1) % m]));
  return { valores: out, metodo: "Holt-Winters con estacionalidad", rmse: Math.sqrt(mejor.sse / n) };
}

function mediaPonderada(y, h = 6) {
  const n = y.length; if (!n) return null;
  const k = Math.min(6, n);
  const ult = y.slice(-k);
  const pesos = ult.map((_, i) => i + 1);
  const sp = pesos.reduce((a, b) => a + b, 0);
  const base = ult.reduce((a, v, i) => a + v * pesos[i], 0) / sp;
  let tend = 0;
  if (n >= 6) {
    const a = y.slice(-6, -3).reduce((x, z) => x + z, 0) / 3;
    const b = y.slice(-3).reduce((x, z) => x + z, 0) / 3;
    tend = (b - a) / 3;
  }
  const out = [];
  for (let i = 1; i <= h; i++) out.push(Math.max(0, base + tend * i));
  const err = Math.sqrt(ult.reduce((a, v) => a + (v - base) ** 2, 0) / k);
  return { valores: out, metodo: n >= 12 ? "Promedio ponderado con tendencia" : "Promedio ponderado", rmse: err };
}

function pronosticar(serie, h = 6) {
  const y = serie.filter((v) => isFinite(v));
  if (y.length < 3) return { valores: [], metodo: "Historia insuficiente", rmse: null, meses: y.length };
  const hw = y.length >= 24 ? holtWinters(y, 12, h) : null;
  const r = hw || mediaPonderada(y, h);
  return { ...r, meses: y.length };
}

/* ── Utilidades de formato ──────────────────────────────────────────────── */
const fUSD = (v, d = 0) => v == null || !isFinite(v) ? "—" :
  "$" + (v * 1000).toLocaleString("es-VE", { maximumFractionDigits: d, minimumFractionDigits: d });
const fNum = (v, d = 0) => v == null || !isFinite(v) ? "—" :
  v.toLocaleString("es-VE", { maximumFractionDigits: d, minimumFractionDigits: d });
const fPct = (v, d = 1) => v == null || !isFinite(v) ? "—" : (v * 100).toFixed(d) + "%";

/* ── Componentes de UI ──────────────────────────────────────────────────── */
function Kpi({ etiqueta, valor, nota, tono }) {
  return (
    <div className="kpi" data-tono={tono || ""}>
      <div className="kpi-et">{etiqueta}</div>
      <div className="kpi-val">{valor}</div>
      {nota && <div className="kpi-nota">{nota}</div>}
    </div>
  );
}

function Panel({ titulo, sub, children, ancho }) {
  return (
    <section className="panel" style={ancho ? { gridColumn: `span ${ancho}` } : undefined}>
      <header className="panel-h">
        <h2>{titulo}</h2>
        {sub && <p>{sub}</p>}
      </header>
      <div className="panel-b">{children}</div>
    </section>
  );
}

function Tabla({ cols, filas, max = 12 }) {
  if (!filas.length) return <p className="vacio">Sin datos para este corte.</p>;
  return (
    <div className="tabla-wrap">
      <table className="tabla">
        <thead><tr>{cols.map((c) => <th key={c.k} style={{ textAlign: c.num ? "right" : "left" }}>{c.t}</th>)}</tr></thead>
        <tbody>
          {filas.slice(0, max).map((f, i) => (
            <tr key={i}>
              {cols.map((c) => (
                <td key={c.k} style={{ textAlign: c.num ? "right" : "left" }} className={c.num ? "num" : ""}>
                  {c.r ? c.r(f) : f[c.k]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ── Aplicación ─────────────────────────────────────────────────────────── */
export default function App() {
  const [ds, setDs] = useState({});          // tipo -> parseo
  const [info, setInfo] = useState(null);    // infocompras
  const [avisos, setAvisos] = useState([]);
  const [cargando, setCargando] = useState(false);
  const [vista, setVista] = useState("resumen");
  const [conEpa, setConEpa] = useState(true);
  const [oscuro, setOscuro] = useState(false);
  const [lt, setLt] = useState(1.5);
  const [ciclo, setCiclo] = useState(1);
  const [seg, setSeg] = useState(0.5);
  const inputRef = useRef(null);

  /* Carga de archivos */
  const cargar = useCallback(async (files) => {
    setCargando(true);
    const nuevos = {}, msgs = [];
    for (const file of files) {
      try {
        const buf = await file.arrayBuffer();
        const wb = XLSX.read(buf, { type: "array" });
        const ic = leerInfocompras(wb);
        if (ic) { setInfo(ic); msgs.push({ t: "ok", m: `${file.name} → Infocompras (${Object.keys(ic).length} marcas)` }); continue; }
        const rows = XLSX.utils.sheet_to_json(wb.Sheets[wb.SheetNames[0]], { header: 1, defval: null });
        const p = leerHojaSim(rows, file.name);
        if (!p) { msgs.push({ t: "err", m: `${file.name} → no reconocido. ¿Es una exportación del SIM?` }); continue; }
        const tipo = clasificar(p);
        nuevos[tipo] = p;
        msgs.push({
          t: p.truncado ? "warn" : "ok",
          m: `${file.name} → ${ETIQUETAS[tipo]} · ${p.meses.length} meses · ${p.registros.length.toLocaleString("es-VE")} datos` +
             (p.truncado ? " · EXPORTACIÓN TRUNCADA, faltan filas" : ""),
        });
      } catch (e) {
        msgs.push({ t: "err", m: `${file.name} → error al leer: ${e.message}` });
      }
    }
    setDs((prev) => ({ ...prev, ...nuevos }));
    setAvisos(msgs);
    setCargando(false);
  }, []);

  /* ── Modelo derivado ─────────────────────────────────────────────────── */
  const modelo = useMemo(() => {
    const art = ds.art_usd, unid = ds.art_unid, epaU = ds.epa_art_usd, epaN = ds.epa_art_unid;
    if (!art) return null;

    // El archivo trae meses de presupuesto a futuro sin venta. Solo cuentan los
    // meses que traen Venta Neta; el último de esos es el mes en curso, incompleto.
    const mesesConVenta = [...new Set(
      art.registros.filter((r) => r.ind === "Venta Neta").map((r) => r.mes)
    )].sort((a, b) => mesIdx(a) - mesIdx(b));

    const meses = mesesConVenta.length ? mesesConVenta : art.meses.slice();
    const idxUlt = meses.length - 1;
    const mesParcial = meses[idxUlt];
    const cerrados = meses.slice(0, idxUlt);

    // EPA por artículo y mes, para poder restarlo de cualquier corte.
    const epaMap = new Map();
    (epaU?.registros || []).forEach((r) => {
      const k = codigoArt(r.Articulo) + "|" + r.mes + "|" + r.ind;
      epaMap.set(k, (epaMap.get(k) || 0) + r.v);
    });
    const epaUnidMap = new Map();
    (epaN?.registros || []).forEach((r) => {
      const k = codigoArt(r.Articulo) + "|" + r.mes + "|" + r.ind;
      epaUnidMap.set(k, (epaUnidMap.get(k) || 0) + r.v);
    });

    const restaEpa = (map, cod, mes, ind, v) => conEpa ? v : v - (map.get(cod + "|" + mes + "|" + ind) || 0);

    // Agregado por artículo
    const arts = new Map();
    for (const r of art.registros) {
      const cod = codigoArt(r.Articulo);
      if (!arts.has(cod)) arts.set(cod, { cod, nombre: r.Articulo, cat: r.Categoría, usd: {}, unid: {}, inv: {}, contrib: {}, presup: {} });
      const a = arts.get(cod);
      if (r.ind === "Venta Neta") a.usd[r.mes] = (a.usd[r.mes] || 0) + r.v;
      if (r.ind === "Contribución") a.contrib[r.mes] = (a.contrib[r.mes] || 0) + r.v;
      if (r.ind === "Inventario") a.inv[r.mes] = (a.inv[r.mes] || 0) + r.v;
      if (r.ind === "Presupuesto bruto") a.presup[r.mes] = (a.presup[r.mes] || 0) + r.v;
    }
    for (const r of unid?.registros || []) {
      if (r.ind !== "Venta Neta") continue;
      const cod = codigoArt(r.Articulo);
      if (!arts.has(cod)) arts.set(cod, { cod, nombre: r.Articulo, cat: "—", usd: {}, unid: {}, inv: {}, contrib: {}, presup: {} });
      const a = arts.get(cod);
      a.unid[r.mes] = (a.unid[r.mes] || 0) + r.v;
    }

    // Aplicar exclusión de EPA
    for (const a of arts.values()) {
      for (const m of meses) {
        if (a.usd[m] != null) a.usd[m] = restaEpa(epaMap, a.cod, m, "Venta Neta", a.usd[m]);
        if (a.contrib[m] != null) a.contrib[m] = restaEpa(epaMap, a.cod, m, "Contribución", a.contrib[m]);
        if (a.unid[m] != null) a.unid[m] = restaEpa(epaUnidMap, a.cod, m, "Venta Neta", a.unid[m]);
      }
    }

    // Serie de marca
    const serie = meses.map((m) => {
      let usd = 0, un = 0, contrib = 0, inv = 0, presup = 0;
      for (const a of arts.values()) {
        usd += a.usd[m] || 0; un += a.unid[m] || 0;
        contrib += a.contrib[m] || 0; inv += a.inv[m] || 0; presup += a.presup[m] || 0;
      }
      return { mes: m, etiq: mesCorto(m), usd, unid: un, contrib, inv, presup,
               margen: usd ? contrib / usd : null, parcial: m === mesParcial };
    });
    const conVenta = serie.filter((s) => s.usd > 0);

    // Peso por unidad, desde el mes de toneladas disponible
    let kgUnidad = null;
    const ton = ds.art_ton;
    if (ton) {
      const mTon = ton.meses[ton.meses.length - 1];
      const tTon = (ton.registros.filter((r) => r.ind === "Venta Neta" && r.mes === mTon)).reduce((a, r) => a + r.v, 0);
      const fila = serie.find((s) => s.mes === mTon);
      if (tTon && fila?.unid) kgUnidad = (tTon * 1000) / fila.unid;
    }

    // Orden de compra por artículo
    const oc = new Map();
    for (const r of ds.oc?.registros || []) {
      if (r.ind !== "OC por recibir") continue;
      const cod = codigoArt(r.Articulo);
      oc.set(cod, { usd: (oc.get(cod)?.usd || 0) + r.v, mes: r.mes });
    }

    // Pronóstico de marca
    const histUsd = conVenta.filter((s) => !s.parcial).map((s) => s.usd);
    const pronMarca = pronosticar(histUsd, 6);

    const hojaInfo = info ? (info[art.marcaFiltro] || info[Object.keys(info)[0]]) : null;

    return { meses, cerrados, mesParcial, serie, conVenta, arts, kgUnidad, oc, pronMarca, hojaInfo,
             marca: art.marcaFiltro || "—" };
  }, [ds, info, conEpa]);

  /* Pedidos sugeridos */
  const pedidos = useMemo(() => {
    if (!modelo) return [];
    const cobertura = lt + ciclo + seg;
    const out = [];
    for (const a of modelo.arts.values()) {
      const serieU = modelo.cerrados.map((m) => a.unid[m] ?? 0).filter((v, i, arr) => arr.slice(0, i + 1).some((x) => x > 0));
      if (!serieU.length) continue;
      const p = pronosticar(serieU, 3);
      const demanda = p.valores.length ? p.valores.reduce((x, y) => x + y, 0) / p.valores.length : 0;
      if (demanda <= 0) continue;
      const inv = modelo.hojaInfo?.[a.cod];
      const stock = inv?.disp ?? null;
      const transito = inv?.transito ?? null;
      const necesita = demanda * cobertura;
      const disponible = (stock ?? 0) + (transito ?? 0);
      const sug = Math.max(0, necesita - disponible);
      const mesesCob = demanda ? disponible / demanda : null;
      out.push({ cod: a.cod, nombre: a.nombre, demanda, stock, transito, cobertura: mesesCob, sug,
                 metodo: p.metodo, costo: inv?.costo ?? null, faltaStock: stock == null });
    }
    return out.sort((x, y) => y.sug * (y.costo || 1) - x.sug * (x.costo || 1));
  }, [modelo, lt, ciclo, seg]);

  /* ── Render ──────────────────────────────────────────────────────────── */
  const hayDatos = !!modelo;
  const ult = modelo?.conVenta.filter((s) => !s.parcial).slice(-1)[0];
  const prev = modelo?.conVenta.filter((s) => !s.parcial).slice(-2, -1)[0];

  return (
    <div className={"app" + (oscuro ? " oscuro" : "")}>
      <style>{CSS}</style>

      <header className="top">
        <div className="marca-bloque">
          <span className="logo">FEBECA</span>
          <span className="sep" />
          <span className="titulo">Compras · {modelo?.marca || "sin marca"}</span>
        </div>
        <div className="top-acciones">
          {hayDatos && (
            <label className="toggle">
              <input type="checkbox" checked={conEpa} onChange={(e) => setConEpa(e.target.checked)} />
              <span>Incluir EPA</span>
            </label>
          )}
          <button className="btn-ghost" onClick={() => setOscuro((v) => !v)}>
            {oscuro ? "Modo claro" : "Modo oscuro"}
          </button>
          <button className="btn" onClick={() => inputRef.current?.click()}>Cargar archivos</button>
          <input ref={inputRef} type="file" multiple accept=".xlsx,.xls" hidden
                 onChange={(e) => cargar([...e.target.files])} />
        </div>
      </header>

      {!hayDatos ? (
        <main className="zona-carga"
              onDragOver={(e) => e.preventDefault()}
              onDrop={(e) => { e.preventDefault(); cargar([...e.dataTransfer.files]); }}>
          <div className="carga-caja">
            <h1>Suelta aquí las exportaciones del SIM</h1>
            <p>
              Todas juntas, en cualquier orden. El tablero lee el bloque de filtros de cada archivo
              y reconoce solo si es de artículos, vendedores, clientes, geografía, orden de compra o infocompras.
            </p>
            <button className="btn grande" onClick={() => inputRef.current?.click()}>
              {cargando ? "Leyendo…" : "Elegir archivos"}
            </button>
            <ul className="lista-req">
              {["Artículos en dólares", "Artículos en unidades", "Estados, supervisores y regiones",
                "Vendedores", "Clientes", "EPA por artículo", "Orden de compra", "Infocompras"].map((x) => (
                <li key={x}>{x}</li>
              ))}
            </ul>
            {!!avisos.length && (
              <div className="avisos">
                {avisos.map((a, i) => <div key={i} className={"aviso " + a.t}>{a.m}</div>)}
              </div>
            )}
          </div>
        </main>
      ) : (
        <>
          <nav className="tabs">
            {[["resumen", "Resumen"], ["articulos", "Artículos"], ["pronostico", "Pronóstico y pedidos"],
              ["comercial", "Comercial"], ["clientes", "Clientes"], ["archivos", "Archivos"]].map(([k, t]) => (
              <button key={k} className={"tab" + (vista === k ? " on" : "")} onClick={() => setVista(k)}>{t}</button>
            ))}
          </nav>

          <main className="cuerpo">
            {vista === "resumen" && <Resumen modelo={modelo} ds={ds} ult={ult} prev={prev} />}
            {vista === "articulos" && <Articulos modelo={modelo} />}
            {vista === "pronostico" && (
              <Pronostico modelo={modelo} pedidos={pedidos}
                          lt={lt} setLt={setLt} ciclo={ciclo} setCiclo={setCiclo} seg={seg} setSeg={setSeg} />
            )}
            {vista === "comercial" && <Comercial ds={ds} modelo={modelo} />}
            {vista === "clientes" && <Clientes ds={ds} conEpa={conEpa} modelo={modelo} />}
            {vista === "archivos" && <Archivos ds={ds} info={info} avisos={avisos} onPick={() => inputRef.current?.click()} />}
          </main>
        </>
      )}
    </div>
  );
}

/* ── Vista: Resumen ─────────────────────────────────────────────────────── */
function Resumen({ modelo, ds, ult, prev }) {
  const { serie, mesParcial, kgUnidad, oc, conVenta } = modelo;
  const parcial = serie.find((s) => s.mes === mesParcial);
  const ocTotal = [...oc.values()].reduce((a, x) => a + x.usd, 0);
  const cumpl = ult?.presup ? ult.usd / ult.presup : null;
  const var12 = (() => {
    const i = conVenta.findIndex((s) => s.mes === ult?.mes);
    const a = conVenta[i - 12];
    return a && a.usd ? ult.usd / a.usd - 1 : null;
  })();
  const graf = conVenta.map((s) => ({ ...s, presupG: s.presup || null }));
  const rot = ult?.inv ? (ult.usd * 12) / ult.inv : null;

  return (
    <div className="grid">
      <div className="kpis" style={{ gridColumn: "span 12" }}>
        <Kpi etiqueta={`Venta neta · ${mesCorto(ult.mes)}`} valor={fUSD(ult.usd)}
             nota={prev ? `${var12 != null ? (var12 >= 0 ? "▲ " : "▼ ") + fPct(Math.abs(var12)) + " vs. año pasado" : ""}` : null}
             tono={var12 >= 0 ? "ok" : "alerta"} />
        <Kpi etiqueta="Unidades" valor={fNum(ult.unid)} nota={kgUnidad ? `${fNum(ult.unid * kgUnidad / 1000, 1)} toneladas` : "sin dato de peso"} />
        <Kpi etiqueta="Margen" valor={fPct(ult.margen)} nota={`Contribución ${fUSD(ult.contrib)}`} />
        <Kpi etiqueta="Presupuesto" valor={fPct(cumpl)}
             nota={`Meta ${fUSD(ult.presup)} · ${cumpl >= 1 ? "cumplida" : "faltan " + fUSD(ult.presup - ult.usd)}`}
             tono={cumpl >= 1 ? "ok" : "alerta"} />
        <Kpi etiqueta="Inventario" valor={fUSD(ult.inv)} nota={rot ? `Rotación ${fNum(rot, 1)}×` : null} />
        <Kpi etiqueta="En tránsito" valor={fUSD(ocTotal)}
             nota={ult.usd ? `${fNum(ocTotal / ult.usd, 1)} meses de cobertura` : null} />
      </div>

      <Panel ancho={8} titulo="Venta contra presupuesto"
             sub={`${conVenta.length} meses con venta real. ${mesCorto(mesParcial)} va incompleto y queda fuera de los cálculos.`}>
        <ResponsiveContainer width="100%" height={300}>
          <ComposedChart data={graf} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <CartesianGrid stroke="var(--rule)" vertical={false} />
            <XAxis dataKey="etiq" tick={{ fontSize: 11, fill: "var(--tenue)" }} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "var(--tenue)" }} tickFormatter={(v) => "$" + Math.round(v) + "K"} />
            <Tooltip formatter={(v, n) => [fUSD(v), n]} contentStyle={TT} />
            <Legend wrapperStyle={{ fontSize: 12 }} />
            <Bar dataKey="usd" name="Venta neta" fill="var(--pvc)" radius={[2, 2, 0, 0]} />
            <Line dataKey="presupG" name="Presupuesto" stroke="var(--oxido)" strokeWidth={2} dot={false} strokeDasharray="4 3" />
          </ComposedChart>
        </ResponsiveContainer>
      </Panel>

      <Panel ancho={4} titulo="Mes en curso" sub={`${mesCorto(mesParcial)}, proyección por ritmo diario`}>
        <RitmoMes parcial={parcial} presup={ult.presup} />
      </Panel>

      <Panel ancho={6} titulo="Unidades vendidas" sub="Volumen real, al margen del precio">
        <ResponsiveContainer width="100%" height={220}>
          <LineChart data={conVenta}>
            <CartesianGrid stroke="var(--rule)" vertical={false} />
            <XAxis dataKey="etiq" tick={{ fontSize: 11, fill: "var(--tenue)" }} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "var(--tenue)" }} tickFormatter={(v) => fNum(v / 1000) + "k"} />
            <Tooltip formatter={(v) => fNum(v) + " u."} contentStyle={TT} />
            <Line dataKey="unid" stroke="var(--laton)" strokeWidth={2} dot={false} name="Unidades" />
          </LineChart>
        </ResponsiveContainer>
      </Panel>

      <Panel ancho={6} titulo="Margen mes a mes" sub="Contribución sobre venta neta">
        <ResponsiveContainer width="100%" height={220}>
          <LineChart data={conVenta}>
            <CartesianGrid stroke="var(--rule)" vertical={false} />
            <XAxis dataKey="etiq" tick={{ fontSize: 11, fill: "var(--tenue)" }} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "var(--tenue)" }} tickFormatter={(v) => (v * 100).toFixed(0) + "%"} domain={["auto", "auto"]} />
            <Tooltip formatter={(v) => fPct(v)} contentStyle={TT} />
            <ReferenceLine y={conVenta.reduce((a, s) => a + (s.margen || 0), 0) / conVenta.length}
                           stroke="var(--tenue)" strokeDasharray="3 3" />
            <Line dataKey="margen" stroke="var(--verde)" strokeWidth={2} dot={false} name="Margen" />
          </LineChart>
        </ResponsiveContainer>
      </Panel>
    </div>
  );
}

function RitmoMes({ parcial, presup }) {
  if (!parcial) return <p className="vacio">Sin datos del mes en curso.</p>;
  const hoy = new Date();
  const dias = new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0).getDate();
  const transcurrido = Math.min(hoy.getDate(), dias);
  const proy = parcial.usd * (dias / transcurrido);
  const alcanza = presup ? proy / presup : null;
  return (
    <div className="ritmo">
      <div className="ritmo-fila"><span>Vendido a hoy</span><b>{fUSD(parcial.usd)}</b></div>
      <div className="ritmo-fila"><span>Días transcurridos</span><b>{transcurrido} de {dias}</b></div>
      <div className="ritmo-fila destacada"><span>Proyección al cierre</span><b>{fUSD(proy)}</b></div>
      <div className="ritmo-fila"><span>Presupuesto del mes</span><b>{fUSD(presup)}</b></div>
      <div className="barra">
        <div className="barra-in" style={{ width: Math.min(100, (alcanza || 0) * 100) + "%",
             background: alcanza >= 1 ? "var(--verde)" : "var(--oxido)" }} />
      </div>
      <p className={"ritmo-veredicto " + (alcanza >= 1 ? "ok" : "alerta")}>
        {alcanza >= 1
          ? `A este ritmo el mes cierra ${fPct(alcanza - 1)} por encima de la meta.`
          : `A este ritmo faltan ${fUSD(presup - proy)} para la meta. Hay que vender ${fUSD((presup - parcial.usd) / Math.max(1, dias - transcurrido))} por día.`}
      </p>
    </div>
  );
}

/* ── Vista: Artículos ───────────────────────────────────────────────────── */
function Articulos({ modelo }) {
  const [orden, setOrden] = useState("usd");
  const { arts, cerrados, kgUnidad } = modelo;
  const ultM = cerrados[cerrados.length - 1], prevM = cerrados[cerrados.length - 2];
  const ult12 = cerrados.slice(-12);

  const filas = useMemo(() => {
    const out = [...arts.values()].map((a) => {
      const usd = a.usd[ultM] || 0, unid = a.unid[ultM] || 0;
      const usdPrev = a.usd[prevM] || 0;
      const anual = ult12.reduce((s, m) => s + (a.usd[m] || 0), 0);
      const contrib = a.contrib[ultM] || 0;
      return { ...a, usd, unid, anual, contrib, margen: usd ? contrib / usd : null,
               mov: usdPrev ? usd / usdPrev - 1 : null,
               kg: kgUnidad ? unid * kgUnidad : null };
    }).filter((a) => a.anual > 0 || a.usd > 0);
    const total = out.reduce((s, a) => s + a.anual, 0);
    let acum = 0;
    out.sort((x, y) => y.anual - x.anual).forEach((a) => {
      acum += a.anual;
      a.pctAcum = total ? acum / total : 0;
      a.abc = a.pctAcum <= 0.8 ? "A" : a.pctAcum <= 0.95 ? "B" : "C";
    });
    return out.sort((x, y) => (y[orden] || 0) - (x[orden] || 0));
  }, [arts, ultM, prevM, orden, kgUnidad]);

  const top = filas.slice(0, 10).map((a) => ({ n: a.nombre.slice(0, 34), usd: a.usd })).reverse();
  const conteo = { A: 0, B: 0, C: 0 };
  filas.forEach((a) => conteo[a.abc]++);

  return (
    <div className="grid">
      <Panel ancho={7} titulo={`Top de venta · ${mesCorto(ultM)}`} sub="Por venta neta del último mes cerrado">
        <ResponsiveContainer width="100%" height={330}>
          <ComposedChart data={top} layout="vertical" margin={{ left: 150, right: 16 }}>
            <CartesianGrid stroke="var(--rule)" horizontal={false} />
            <XAxis type="number" tick={{ fontSize: 11, fill: "var(--tenue)" }} tickFormatter={(v) => "$" + Math.round(v) + "K"} />
            <YAxis type="category" dataKey="n" width={150} tick={{ fontSize: 10, fill: "var(--tinta)" }} />
            <Tooltip formatter={(v) => fUSD(v)} contentStyle={TT} />
            <Bar dataKey="usd" fill="var(--pvc)" radius={[0, 2, 2, 0]} />
          </ComposedChart>
        </ResponsiveContainer>
      </Panel>

      <Panel ancho={5} titulo="Clasificación ABC" sub="Sobre los últimos 12 meses cerrados">
        <div className="abc">
          {["A", "B", "C"].map((k) => (
            <div key={k} className={"abc-caja abc-" + k}>
              <div className="abc-letra">{k}</div>
              <div className="abc-n">{conteo[k]}</div>
              <div className="abc-t">{k === "A" ? "80% de la contribución" : k === "B" ? "siguiente 15%" : "último 5%"}</div>
            </div>
          ))}
        </div>
        <p className="nota">
          Los {conteo.A} artículos de clase A concentran la mayor parte del negocio. Un quiebre ahí
          cuesta mucho más que un quiebre en clase C.
        </p>
      </Panel>

      <Panel ancho={12} titulo="Detalle por artículo"
             sub={`${filas.length} artículos con movimiento. Ordenar por:`}>
        <div className="orden-btns">
          {[["usd", "Venta"], ["unid", "Unidades"], ["anual", "Últimos 12 meses"], ["contrib", "Contribución"]].map(([k, t]) => (
            <button key={k} className={"chip" + (orden === k ? " on" : "")} onClick={() => setOrden(k)}>{t}</button>
          ))}
        </div>
        <Tabla max={25} filas={filas} cols={[
          { k: "abc", t: "", r: (f) => <span className={"tag tag-" + f.abc}>{f.abc}</span> },
          { k: "cod", t: "Código" },
          { k: "nombre", t: "Artículo", r: (f) => <span title={f.nombre}>{f.nombre.replace(/^\S+\s/, "").slice(0, 46)}</span> },
          { k: "cat", t: "Categoría" },
          { k: "usd", t: "Venta", num: 1, r: (f) => fUSD(f.usd) },
          { k: "unid", t: "Unidades", num: 1, r: (f) => fNum(f.unid) },
          { k: "kg", t: "Kg", num: 1, r: (f) => fNum(f.kg) },
          { k: "margen", t: "Margen", num: 1, r: (f) => fPct(f.margen) },
          { k: "mov", t: "vs. mes previo", num: 1,
            r: (f) => f.mov == null ? "—" :
              <span className={f.mov >= 0 ? "pos" : "neg"}>{(f.mov >= 0 ? "▲ " : "▼ ") + fPct(Math.abs(f.mov), 0)}</span> },
        ]} />
      </Panel>
    </div>
  );
}

/* ── Vista: Pronóstico y pedidos ────────────────────────────────────────── */
function Pronostico({ modelo, pedidos, lt, setLt, ciclo, setCiclo, seg, setSeg }) {
  const { conVenta, pronMarca, cerrados, kgUnidad, hojaInfo } = modelo;
  const hist = conVenta.filter((s) => !s.parcial);
  const ultIdx = mesIdx(hist[hist.length - 1].mes);
  const futuro = pronMarca.valores.map((v, i) => {
    const t = ultIdx + i + 1;
    const m = (t % 12) + 1, y = Math.floor(t / 12);
    return { etiq: mesCorto(`${m}-${y}`), pron: v };
  });
  const data = [...hist.map((s) => ({ etiq: s.etiq, real: s.usd })), ...futuro];
  const promedio = hist.slice(-6).reduce((a, s) => a + s.usd, 0) / Math.min(6, hist.length);
  const totalSug = pedidos.reduce((a, p) => a + p.sug * (p.costo || 0), 0);
  const sinStock = pedidos.filter((p) => p.faltaStock).length;

  return (
    <div className="grid">
      <div className="kpis" style={{ gridColumn: "span 12" }}>
        <Kpi etiqueta="Promedio últimos 6 meses" valor={fUSD(promedio)} />
        <Kpi etiqueta="Pronóstico próximo mes" valor={fUSD(pronMarca.valores[0])}
             nota={pronMarca.metodo} tono={pronMarca.valores[0] >= promedio ? "ok" : "alerta"} />
        <Kpi etiqueta="Historia usada" valor={`${pronMarca.meses} meses`}
             nota={pronMarca.meses >= 24 ? "suficiente para estacionalidad" : "sin estacionalidad"} />
        <Kpi etiqueta="Artículos a pedir" valor={fNum(pedidos.filter((p) => p.sug > 0).length)}
             nota={totalSug ? `≈ ${fUSD(totalSug / 1000)} al costo` : "sin costo cargado"} />
      </div>

      <Panel ancho={12} titulo="Pronóstico de venta"
             sub={`${pronMarca.metodo}${pronMarca.rmse ? ` · error típico ${fUSD(pronMarca.rmse)}` : ""}`}>
        <ResponsiveContainer width="100%" height={300}>
          <ComposedChart data={data}>
            <CartesianGrid stroke="var(--rule)" vertical={false} />
            <XAxis dataKey="etiq" tick={{ fontSize: 11, fill: "var(--tenue)" }} interval="preserveStartEnd" />
            <YAxis tick={{ fontSize: 11, fill: "var(--tenue)" }} tickFormatter={(v) => "$" + Math.round(v) + "K"} />
            <Tooltip formatter={(v) => fUSD(v)} contentStyle={TT} />
            <Legend wrapperStyle={{ fontSize: 12 }} />
            <Area dataKey="real" name="Venta real" stroke="var(--pvc)" fill="var(--pvc-suave)" strokeWidth={2} />
            <Line dataKey="pron" name="Pronóstico" stroke="var(--laton)" strokeWidth={2.5} strokeDasharray="5 4" dot={{ r: 3 }} />
          </ComposedChart>
        </ResponsiveContainer>
      </Panel>

      <Panel ancho={12} titulo="Pedido sugerido"
             sub="Demanda pronosticada por artículo contra lo que hay y lo que viene en camino">
        <div className="params">
          {[["Tránsito (meses)", lt, setLt, 0.5], ["Ciclo de compra (meses)", ciclo, setCiclo, 0.5],
            ["Stock de seguridad (meses)", seg, setSeg, 0.25]].map(([t, v, set, step]) => (
            <label key={t} className="param">
              <span>{t}</span>
              <input type="number" step={step} min="0" value={v} onChange={(e) => set(parseFloat(e.target.value) || 0)} />
            </label>
          ))}
          <div className="param-res">
            Cobertura objetivo <b>{(lt + ciclo + seg).toFixed(2)} meses</b>
          </div>
        </div>
        {!hojaInfo && (
          <p className="aviso warn" style={{ marginBottom: 12 }}>
            Sin el infocompras cargado no hay stock ni tránsito en unidades: la columna de sugerido
            asume cero disponible y sale inflada. Carga el archivo de la marca para que el cálculo sirva.
          </p>
        )}
        <Tabla max={25} filas={pedidos} cols={[
          { k: "cod", t: "Código" },
          { k: "nombre", t: "Artículo", r: (f) => f.nombre.replace(/^\S+\s/, "").slice(0, 44) },
          { k: "demanda", t: "Demanda/mes", num: 1, r: (f) => fNum(f.demanda) },
          { k: "stock", t: "Disponible", num: 1, r: (f) => f.stock == null ? "—" : fNum(f.stock) },
          { k: "transito", t: "En tránsito", num: 1, r: (f) => f.transito == null ? "—" : fNum(f.transito) },
          { k: "cobertura", t: "Cobertura", num: 1,
            r: (f) => f.cobertura == null ? "—" :
              <span className={f.cobertura < lt ? "neg" : f.cobertura > 6 ? "warn-t" : "pos"}>
                {fNum(f.cobertura, 1)} m
              </span> },
          { k: "sug", t: "Sugerido", num: 1, r: (f) => <b>{f.sug > 0 ? fNum(Math.ceil(f.sug)) : "—"}</b> },
          { k: "kg", t: "Peso", num: 1, r: (f) => kgUnidad && f.sug > 0 ? fNum(f.sug * kgUnidad / 1000, 1) + " t" : "—" },
        ]} />
        <p className="nota">
          Cobertura en rojo: llega por debajo del tiempo de tránsito, hay riesgo de quiebre.
          En ámbar: más de seis meses encima, es inventario dormido.
        </p>
      </Panel>
    </div>
  );
}

/* ── Vista: Comercial ───────────────────────────────────────────────────── */
function Comercial({ ds, modelo }) {
  const arma = (p, dim) => {
    if (!p) return { filas: [], mes: null };
    const mes = modelo.cerrados[modelo.cerrados.length - 1];
    const map = new Map();
    for (const r of p.registros) {
      if (r.mes !== mes) continue;
      const k = r[dim]; if (!k) continue;
      if (!map.has(k)) map.set(k, { nombre: k, usd: 0, contrib: 0 });
      if (r.ind === "Venta Neta") map.get(k).usd += r.v;
      if (r.ind === "Contribución") map.get(k).contrib += r.v;
    }
    const filas = [...map.values()].filter((x) => x.usd !== 0)
      .map((x) => ({ ...x, margen: x.usd ? x.contrib / x.usd : null }))
      .sort((a, b) => b.usd - a.usd);
    return { filas, mes };
  };

  const vend = arma(ds.vendedor, "Vendedor");
  const est = arma(ds.geo, "Estado");
  const reg = arma(ds.geo, "Región");
  const sup = arma(ds.geo, "Supervisor");

  const cols = [
    { k: "nombre", t: "Nombre" },
    { k: "usd", t: "Venta neta", num: 1, r: (f) => fUSD(f.usd) },
    { k: "contrib", t: "Contribución", num: 1, r: (f) => fUSD(f.contrib) },
    { k: "margen", t: "Margen", num: 1, r: (f) => fPct(f.margen) },
  ];

  return (
    <div className="grid">
      <Panel ancho={6} titulo="Top vendedores" sub={vend.mes ? mesCorto(vend.mes) : ""}>
        <Tabla filas={vend.filas} cols={cols} max={15} />
      </Panel>
      <Panel ancho={6} titulo="Top estados" sub={est.mes ? mesCorto(est.mes) : ""}>
        <Tabla filas={est.filas} cols={cols} max={15} />
      </Panel>
      <Panel ancho={6} titulo="Regiones" sub="Ordenadas por venta neta">
        <ResponsiveContainer width="100%" height={280}>
          <ComposedChart data={reg.filas.slice(0, 10).reverse()} layout="vertical" margin={{ left: 110 }}>
            <CartesianGrid stroke="var(--rule)" horizontal={false} />
            <XAxis type="number" tick={{ fontSize: 11, fill: "var(--tenue)" }} tickFormatter={(v) => "$" + Math.round(v) + "K"} />
            <YAxis type="category" dataKey="nombre" width={110} tick={{ fontSize: 10, fill: "var(--tinta)" }} />
            <Tooltip formatter={(v) => fUSD(v)} contentStyle={TT} />
            <Bar dataKey="usd" fill="var(--verde)" radius={[0, 2, 2, 0]} />
          </ComposedChart>
        </ResponsiveContainer>
      </Panel>
      <Panel ancho={6} titulo="Supervisores" sub={sup.mes ? mesCorto(sup.mes) : ""}>
        <Tabla filas={sup.filas} cols={cols} max={12} />
      </Panel>
      <div style={{ gridColumn: "span 12" }}>
        <p className="nota">
          El corte de vendedores no trae el cliente, así que el botón de EPA no aplica en esta pestaña.
          Si hace falta, se resuelve con una descarga extra de EPA por vendedor.
        </p>
      </div>
    </div>
  );
}

/* ── Vista: Clientes ────────────────────────────────────────────────────── */
function Clientes({ ds, conEpa, modelo }) {
  const p = ds.cliente;
  if (!p) return <p className="vacio">Falta cargar el archivo de clientes.</p>;
  const meses = p.meses.filter((m) => mesIdx(m) <= mesIdx(modelo.cerrados[modelo.cerrados.length - 1]));
  const mes = meses[meses.length - 1];

  const map = new Map();
  let activados = null, inactivos = null;
  for (const r of p.registros) {
    if (r.mes !== mes) continue;
    const k = r.Cliente; if (!k) continue;
    if (!conEpa && esEpa(k)) continue;
    if (!map.has(k)) map.set(k, { nombre: k, usd: 0, contrib: 0 });
    if (r.ind === "Venta Neta") map.get(k).usd += r.v;
    if (r.ind === "Contribución") map.get(k).contrib += r.v;
  }
  for (const [ind, set] of [["Clientes activados", (v) => (activados = v)], ["Clientes Inactivos", (v) => (inactivos = v)]]) {
    const t = p.totales?.[mes]?.[ind];
    if (t != null) set(t);
  }
  if (activados == null) activados = [...map.values()].filter((c) => c.usd > 0).length;

  const filas = [...map.values()].filter((c) => c.usd !== 0)
    .map((c) => ({ ...c, margen: c.usd ? c.contrib / c.usd : null }))
    .sort((a, b) => b.usd - a.usd);
  const total = filas.reduce((a, c) => a + c.usd, 0);
  const top10 = filas.slice(0, 10).reduce((a, c) => a + c.usd, 0);

  const serieAct = meses.map((m) => ({
    etiq: mesCorto(m),
    act: p.totales?.[m]?.["Clientes activados"] ?? null,
    inact: p.totales?.[m]?.["Clientes Inactivos"] ?? null,
  }));

  return (
    <div className="grid">
      <div className="kpis" style={{ gridColumn: "span 12" }}>
        <Kpi etiqueta="Clientes con compra" valor={fNum(filas.length)} nota={mesCorto(mes)} />
        <Kpi etiqueta="Clientes activados" valor={fNum(activados)} />
        <Kpi etiqueta="Clientes inactivos" valor={inactivos == null ? "—" : fNum(inactivos)}
             tono="alerta" nota={inactivos == null ? "indicador no descargado" : null} />
        <Kpi etiqueta="Concentración top 10" valor={fPct(total ? top10 / total : null)}
             nota={total ? `${fUSD(top10)} de ${fUSD(total)}` : null}
             tono={top10 / total > 0.5 ? "alerta" : "ok"} />
      </div>

      <Panel ancho={7} titulo="Top de clientes" sub={`${mesCorto(mes)} · ${conEpa ? "con EPA incluido" : "sin EPA"}`}>
        <Tabla max={20} filas={filas} cols={[
          { k: "nombre", t: "Cliente", r: (f) => <span className={esEpa(f.nombre) ? "epa" : ""}>{f.nombre.slice(0, 44)}</span> },
          { k: "usd", t: "Venta neta", num: 1, r: (f) => fUSD(f.usd) },
          { k: "margen", t: "Margen", num: 1, r: (f) => fPct(f.margen) },
          { k: "peso", t: "Peso", num: 1, r: (f) => fPct(total ? f.usd / total : null) },
        ]} />
      </Panel>

      <Panel ancho={5} titulo="Activos contra inactivos" sub="Movimiento de la base de clientes">
        {serieAct.some((s) => s.act != null) ? (
          <ResponsiveContainer width="100%" height={280}>
            <ComposedChart data={serieAct}>
              <CartesianGrid stroke="var(--rule)" vertical={false} />
              <XAxis dataKey="etiq" tick={{ fontSize: 11, fill: "var(--tenue)" }} />
              <YAxis tick={{ fontSize: 11, fill: "var(--tenue)" }} />
              <Tooltip contentStyle={TT} />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              <Bar dataKey="act" name="Activados" fill="var(--verde)" radius={[2, 2, 0, 0]} />
              <Line dataKey="inact" name="Inactivos" stroke="var(--oxido)" strokeWidth={2} dot={false} />
            </ComposedChart>
          </ResponsiveContainer>
        ) : <p className="vacio">El archivo de clientes no trae los indicadores de activados e inactivos.</p>}
      </Panel>
    </div>
  );
}

/* ── Vista: Archivos ────────────────────────────────────────────────────── */
function Archivos({ ds, info, avisos, onPick }) {
  const esperados = ["art_usd", "art_unid", "art_ton", "geo", "vendedor", "cliente", "epa_art_usd", "epa_art_unid", "oc"];
  return (
    <div className="grid">
      <Panel ancho={7} titulo="Archivos cargados" sub="Lo que el tablero reconoció en esta sesión">
        <table className="tabla">
          <thead><tr><th>Corte</th><th>Archivo</th><th style={{ textAlign: "right" }}>Meses</th><th>Estado</th></tr></thead>
          <tbody>
            {esperados.map((k) => {
              const p = ds[k];
              return (
                <tr key={k}>
                  <td>{ETIQUETAS[k]}</td>
                  <td className="tenue">{p?.nombreArchivo || "—"}</td>
                  <td className="num">{p ? p.meses.length : "—"}</td>
                  <td>{!p ? <span className="tag tag-C">falta</span>
                        : p.truncado ? <span className="tag tag-B">truncado</span>
                        : <span className="tag tag-A">bien</span>}</td>
                </tr>
              );
            })}
            <tr>
              <td>{ETIQUETAS.infocompras}</td>
              <td className="tenue">{info ? Object.keys(info).length + " marcas" : "—"}</td>
              <td className="num">—</td>
              <td>{info ? <span className="tag tag-A">bien</span> : <span className="tag tag-C">falta</span>}</td>
            </tr>
          </tbody>
        </table>
        <button className="btn" style={{ marginTop: 16 }} onClick={onPick}>Cargar más archivos</button>
      </Panel>
      <Panel ancho={5} titulo="Lectura de la última carga">
        {avisos.length
          ? avisos.map((a, i) => <div key={i} className={"aviso " + a.t}>{a.m}</div>)
          : <p className="vacio">Nada cargado todavía en esta sesión.</p>}
      </Panel>
    </div>
  );
}

const TT = {
  background: "var(--panel)", border: "1px solid var(--rule)", borderRadius: 4,
  fontSize: 12, color: "var(--tinta)", boxShadow: "0 4px 16px rgba(16,32,42,.12)",
};

/* ── Estilos ────────────────────────────────────────────────────────────── */
const CSS = `
@import url('https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700&display=swap');

.app {
  --tinta: #16232B;
  --papel: #EEF1F0;
  --panel: #FFFFFF;
  --rule: #D4DAD8;
  --tenue: #6E7E85;
  --pvc: #2E6E8E;
  --pvc-suave: #2E6E8E22;
  --laton: #A8792C;
  --oxido: #B4452F;
  --verde: #3D7A56;
  font-family: 'Archivo', system-ui, sans-serif;
  background: var(--papel);
  color: var(--tinta);
  min-height: 100vh;
  font-variant-numeric: tabular-nums;
  -webkit-font-smoothing: antialiased;
}
.app.oscuro {
  --tinta: #E4EAE8; --papel: #0F1A20; --panel: #16242C; --rule: #27383F;
  --tenue: #8798A0; --pvc: #5AA8CC; --pvc-suave: #5AA8CC26;
  --laton: #D6A754; --oxido: #E0705A; --verde: #5EA87C;
}
.app * { box-sizing: border-box; }

/* Barra superior */
.top {
  display: flex; align-items: center; justify-content: space-between; gap: 16px;
  padding: 14px 24px; background: var(--panel); border-bottom: 1px solid var(--rule);
  position: sticky; top: 0; z-index: 20; flex-wrap: wrap;
}
.marca-bloque { display: flex; align-items: center; gap: 12px; }
.logo { font-weight: 700; font-size: 17px; letter-spacing: .14em; color: var(--pvc); }
.sep { width: 1px; height: 20px; background: var(--rule); }
.titulo { font-size: 14px; font-weight: 500; color: var(--tenue); }
.top-acciones { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }

.btn {
  background: var(--pvc); color: #fff; border: 0; border-radius: 3px;
  padding: 8px 15px; font: inherit; font-size: 13px; font-weight: 500; cursor: pointer;
}
.btn:hover { filter: brightness(1.08); }
.btn.grande { padding: 12px 26px; font-size: 15px; margin-top: 8px; }
.btn-ghost {
  background: transparent; color: var(--tenue); border: 1px solid var(--rule);
  border-radius: 3px; padding: 7px 13px; font: inherit; font-size: 13px; cursor: pointer;
}
.btn-ghost:hover { color: var(--tinta); border-color: var(--tenue); }
.toggle { display: flex; align-items: center; gap: 7px; font-size: 13px; cursor: pointer; color: var(--tenue); }
.toggle input { accent-color: var(--pvc); width: 15px; height: 15px; }
:focus-visible { outline: 2px solid var(--laton); outline-offset: 2px; }

/* Pestañas */
.tabs { display: flex; gap: 2px; padding: 0 24px; background: var(--panel); border-bottom: 1px solid var(--rule); overflow-x: auto; }
.tab {
  background: none; border: 0; border-bottom: 2px solid transparent; padding: 11px 15px;
  font: inherit; font-size: 13.5px; color: var(--tenue); cursor: pointer; white-space: nowrap;
}
.tab.on { color: var(--pvc); border-bottom-color: var(--pvc); font-weight: 600; }

/* Zona de carga */
.zona-carga { display: flex; align-items: center; justify-content: center; padding: 56px 24px; min-height: 70vh; }
.carga-caja {
  max-width: 620px; text-align: center; background: var(--panel);
  border: 1px dashed var(--rule); border-radius: 6px; padding: 48px 40px;
}
.carga-caja h1 { font-size: 24px; font-weight: 600; margin: 0 0 12px; letter-spacing: -.01em; }
.carga-caja p { color: var(--tenue); font-size: 14px; line-height: 1.6; margin: 0 auto; max-width: 52ch; }
.lista-req {
  list-style: none; padding: 0; margin: 28px 0 0; display: grid;
  grid-template-columns: repeat(2, 1fr); gap: 6px 20px; text-align: left;
  font-size: 12.5px; color: var(--tenue);
}
.lista-req li { padding-left: 15px; position: relative; }
.lista-req li::before { content: ""; position: absolute; left: 0; top: 8px; width: 6px; height: 6px; background: var(--rule); border-radius: 50%; }

/* Cuerpo */
.cuerpo { padding: 22px 24px 60px; }
.grid { display: grid; grid-template-columns: repeat(12, 1fr); gap: 16px; }
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; }

.kpi { background: var(--panel); border: 1px solid var(--rule); border-left: 3px solid var(--rule); border-radius: 3px; padding: 13px 15px; }
.kpi[data-tono="ok"] { border-left-color: var(--verde); }
.kpi[data-tono="alerta"] { border-left-color: var(--oxido); }
.kpi-et { font-size: 11.5px; color: var(--tenue); margin-bottom: 5px; }
.kpi-val { font-size: 23px; font-weight: 600; letter-spacing: -.02em; line-height: 1.1; }
.kpi-nota { font-size: 11.5px; color: var(--tenue); margin-top: 5px; line-height: 1.35; }

.panel { background: var(--panel); border: 1px solid var(--rule); border-radius: 4px; grid-column: span 12; overflow: hidden; }
.panel-h { padding: 14px 18px 0; }
.panel-h h2 { font-size: 14.5px; font-weight: 600; margin: 0; }
.panel-h p { font-size: 12px; color: var(--tenue); margin: 4px 0 0; }
.panel-b { padding: 14px 18px 18px; }

/* Tablas */
.tabla-wrap { overflow-x: auto; }
.tabla { width: 100%; border-collapse: collapse; font-size: 12.5px; }
.tabla th {
  text-align: left; font-weight: 500; color: var(--tenue); font-size: 11px;
  padding: 7px 9px; border-bottom: 1px solid var(--rule); white-space: nowrap;
}
.tabla td { padding: 8px 9px; border-bottom: 1px solid var(--rule); }
.tabla tbody tr:last-child td { border-bottom: 0; }
.tabla tbody tr:hover { background: var(--pvc-suave); }
.num { font-variant-numeric: tabular-nums; }
.tenue { color: var(--tenue); }
.pos { color: var(--verde); }
.neg { color: var(--oxido); }
.warn-t { color: var(--laton); }
.epa { font-weight: 600; color: var(--laton); }

.tag { display: inline-block; font-size: 10.5px; font-weight: 600; padding: 2px 7px; border-radius: 2px; }
.tag-A { background: #3D7A5622; color: var(--verde); }
.tag-B { background: #A8792C22; color: var(--laton); }
.tag-C { background: #B4452F22; color: var(--oxido); }

.chip {
  background: transparent; border: 1px solid var(--rule); border-radius: 3px;
  padding: 5px 11px; font: inherit; font-size: 12px; color: var(--tenue); cursor: pointer;
}
.chip.on { background: var(--pvc); border-color: var(--pvc); color: #fff; }
.orden-btns { display: flex; gap: 6px; margin-bottom: 12px; flex-wrap: wrap; }

/* Ritmo del mes */
.ritmo-fila { display: flex; justify-content: space-between; align-items: baseline; padding: 7px 0; border-bottom: 1px solid var(--rule); font-size: 13px; }
.ritmo-fila span { color: var(--tenue); }
.ritmo-fila.destacada b { font-size: 17px; color: var(--pvc); }
.barra { height: 7px; background: var(--rule); border-radius: 4px; margin: 16px 0 10px; overflow: hidden; }
.barra-in { height: 100%; border-radius: 4px; transition: width .4s ease; }
.ritmo-veredicto { font-size: 12.5px; line-height: 1.5; margin: 0; }
.ritmo-veredicto.ok { color: var(--verde); }
.ritmo-veredicto.alerta { color: var(--oxido); }

/* ABC */
.abc { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
.abc-caja { border: 1px solid var(--rule); border-radius: 3px; padding: 13px; text-align: center; }
.abc-A { border-top: 3px solid var(--verde); }
.abc-B { border-top: 3px solid var(--laton); }
.abc-C { border-top: 3px solid var(--rule); }
.abc-letra { font-size: 12px; color: var(--tenue); font-weight: 600; }
.abc-n { font-size: 27px; font-weight: 600; line-height: 1.2; }
.abc-t { font-size: 11px; color: var(--tenue); line-height: 1.3; }

/* Parámetros de pedido */
.params { display: flex; gap: 14px; align-items: flex-end; flex-wrap: wrap; margin-bottom: 14px; padding-bottom: 14px; border-bottom: 1px solid var(--rule); }
.param { display: flex; flex-direction: column; gap: 4px; font-size: 11.5px; color: var(--tenue); }
.param input {
  width: 92px; padding: 6px 8px; font: inherit; font-size: 13px;
  border: 1px solid var(--rule); border-radius: 3px; background: var(--panel); color: var(--tinta);
}
.param-res { font-size: 12.5px; color: var(--tenue); padding-bottom: 7px; }
.param-res b { color: var(--pvc); font-size: 14px; }

.nota { font-size: 12px; color: var(--tenue); line-height: 1.55; margin: 12px 0 0; max-width: 78ch; }
.vacio { font-size: 13px; color: var(--tenue); padding: 20px 0; margin: 0; }

.avisos { margin-top: 24px; text-align: left; display: grid; gap: 6px; }
.aviso { font-size: 12px; padding: 8px 11px; border-radius: 3px; line-height: 1.45; }
.aviso.ok { background: #3D7A561A; color: var(--verde); }
.aviso.warn { background: #A8792C1A; color: var(--laton); }
.aviso.err { background: #B4452F1A; color: var(--oxido); }

@media (max-width: 1100px) { .panel { grid-column: span 12 !important; } }
@media (max-width: 640px) {
  .cuerpo { padding: 14px 12px 40px; }
  .top { padding: 12px 14px; }
  .tabs { padding: 0 12px; }
  .lista-req { grid-template-columns: 1fr; }
  .carga-caja { padding: 32px 22px; }
}
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
`;
