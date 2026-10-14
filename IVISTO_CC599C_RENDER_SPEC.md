# Specifiche di rendering — Messaggio IVISTO CC599C

> Documento di riferimento per ricostruire la logica di visualizzazione e stampa del messaggio CC599C (Notifica di Uscita) nel sistema SIRIO.

---

## 1. Contesto

Il viewer IVISTO è interamente client-side (JavaScript + HTML). Non esiste una libreria PDF dedicata: la stampa/PDF avviene tramite `window.print()` con CSS `@media print` che trasforma il tema dark in layout chiaro. Il file sorgente è `main.py` (modulo singolo FastAPI), HTML inline nella variabile `HTML`.

Il flusso è:
1. Utente carica file `.xml` (drag-and-drop o click) **oppure** incolla XML nel textarea
2. `processXML(text)` valida il testo e chiama `renderDoc(xml)` per generare l'HTML
3. Il server viene contattato via `POST /api/ivisto/process` per consumare 1 token
4. L'HTML risultante viene inserito nel `<div id="out">` e reso visibile
5. Il pulsante **Stampa** esegue `window.print()`

---

## 2. Parsing XML — funzione `renderDoc(xml)`

### 2.1 Validazione

Parsing con `DOMParser` (browser). Se `parseerror` è presente → errore generico.

Tag obbligatori (se mancanti → errore con lista):

| Tag XML | Significato |
|---------|-------------|
| `MRN` | Movement Reference Number |
| `ExitControlResult` | Esito controllo uscita |
| `preparationDateAndTime` | Data conclusione uscita |
| `referenceNumber` | Codice ufficio doganale |

### 2.2 Campi estratti

```js
// Uffici letti dal loro elemento, non per posizione dei referenceNumber
// (anche i documenti di supporto hanno un referenceNumber).
const ufficio = (...nomi) => {
  for (const n of nomi) {
    const v = doc.getElementsByTagName(n)[0]?.getElementsByTagName("referenceNumber")[0]?.textContent?.trim();
    if (v) return v;
  }
  return null;
};
const exportRef = ufficio("CustomsOfficeOfExport");                            // ufficio esportazione
const exitRef   = ufficio("CustomsOfficeOfExitActual", "CustomsOfficeOfExit"); // ufficio uscita
const destRef   = ufficio("CustomsOfficeOfDestination");                       // destinazione transito

const mrn      = doc.getElementsByTagName("MRN")[0]?.textContent;
const transit  = doc.getElementsByTagName("transit")[0]?.textContent === "1";
const rc       = doc.getElementsByTagName("code")[0]?.textContent;       // es. "A2"
const exitDate = doc.getElementsByTagName("exitDate")[0]?.textContent;
const prepDate = doc.getElementsByTagName("preparationDateAndTime")[0]?.textContent;
const msgId    = doc.getElementsByTagName("messageIdentification")[0]?.textContent;
const sender   = doc.getElementsByTagName("messageSender")[0]?.textContent;

const suppDocs = [...doc.getElementsByTagName("SupportingDocument")].map(sd => ({
  type: sd.getElementsByTagName("type")[0]?.textContent || "",
  ref:  sd.getElementsByTagName("referenceNumber")[0]?.textContent || ""
}));
```

Valori derivati per l'esportazione seguita da transito (`transit = 1`):

```js
const tipoTransito = suppDocs.map(sd => DOC_TIPI[sd.type]).find(Boolean) || null; // da N820/N821/N822
const inTransito   = transit ? "Si" + (tipoTransito ? " — " + tipoTransito : "") : "No";
```

`DOC_TIPI`: `N820` Transito misto T (merci T1 e T2), `N821` Transito esterno T1, `N822` Transito comunitario interno T2.

### 2.3 Formattazione date — `ivistoFmtDate(d)`

Input: stringa ISO (`"2025-04-15T10:30:00"` o `"2025-04-15"`).  
Output: `"15 apr 2025"` (giorno intero + mese abbreviato italiano + anno 4 cifre).

```js
function ivistoFmtDate(d) {
  if (!d) return "—";
  const p = d.includes("T") ? d.split("T")[0] : d;
  const [y, m, dd] = p.split("-");
  const mo = ["gen","feb","mar","apr","mag","giu","lug","ago","set","ott","nov","dic"];
  return parseInt(dd) + " " + mo[parseInt(m)-1] + " " + y;
}
```

---

## 3. Tabella codici esito — `EXIT_CODES`

| Codice | Label | Classe CSS result | Dot | Badge |
|--------|-------|------------------|-----|-------|
| A1 | Conforme (A1) | `result-A1` | `dot-info` (blu) | `badge-info` |
| A2 | Ritenuto conforme (A2) | `result-A2` | `dot-ok` (verde) | `badge-ok` |
| A3 | Procedura semplificata (A3) | `result-A3` | `dot-warn` (arancio) | `badge-warn` |
| A4 | Difformità minori (A4) | `result-A3` | `dot-warn` | `badge-warn` |
| A5 | Sigilli non conformi (A5) | `result-A3` | `dot-warn` | `badge-warn` |
| B1 | Difformità maggiori (B1) | `result-B` | `dot-danger` (rosso) | `badge-err` |
| B2 | Non trovato (B2) | `result-B` | `dot-danger` | `badge-err` |
| B3 | Non applicabile (B3) | `result-default` | `dot-neutral` (grigio) | `badge-neutral` |

La classe del result block è `"result-" + code.cls` (A4 e A5 usano quindi `result-A3`, B3 `result-default`).

Codice non in tabella → `result-default`, label `"Codice <rc>"`, desc `"Codice esito non riconosciuto (tabella CL393)."`.

### Descrizioni complete

```
A1: Merce uscita dal territorio doganale UE a seguito di controllo fisico
    (totale o parziale) — nessuna irregolarità rilevata.

A2: Merce uscita dal territorio doganale UE a seguito di controllo
    esclusivamente documentale, senza ispezione fisica, oppure senza alcun
    controllo — nessuna irregolarità. Costituisce prova di esportazione
    valida ai fini IVA (art. 8 DPR 633/72).

A3: Uscita confermata tramite procedura semplificata — nessun controllo
    eseguito dall'Ufficio di Uscita (spedizioniere autorizzato / AEO).

A4: Rilevate difformità minori durante il controllo. La merce è rilasciata,
    ma l'Ufficio Doganale di Supervisione (SCO) verifica le discrepanze e
    può informare il dichiarante al di fuori del sistema. La dichiarazione
    non può essere emendata.

A5: I sigilli non sono risultati conformi (assenti, danneggiati o con
    discrepanze). La merce può essere comunque rilasciata se le
    difformità sono minori.

B1: Rilevate difformità maggiori durante il controllo doganale all'uscita.
    Contattare l'Ufficio Doganale di Esportazione.

B2: La merce non è stata trovata al momento dell'uscita dal territorio
    doganale UE.

B3: Risultato non applicabile per la tipologia di operazione.
```

---

## 4. Risoluzione codici ufficio doganale — `getOffice(code)`

Formato codice: `CCNNNNNN` (2 lettere paese ISO + 6 cifre, es. `IT273100`).

Logica:
1. Cerca `code` nella mappa `OFFICES` (rubrica hardcoded)
2. Se trovato → `{ name, code, unknown: false }`
3. Se non trovato → tenta risoluzione nazione dai primi 2 char via `NATIONS`
4. Se nazione nota → `"Ufficio doganale — <NomeNazione> (<codice>)"` con `unknown: true` (mostra tag `non in rubrica`)
5. Se nazione sconosciuta → mostra il codice grezzo

La rubrica `OFFICES` contiene 189 uffici: tutti gli UADM italiani (Lombardia, Emilia-Romagna, tutte le regioni) con sezioni e distaccamenti, principali aeroporti e porti europei (NL, DE, FR, BE, ES, GB, PL, AT, SE, DK, FI, HR), e dogane svizzere di confine.

`OFFICES`, `NATIONS` e `DOC_TIPI` sono una copia di quelle di App2DoReader (`alifresca.py`, `tools/ivisto_viewer.html`), che genera il PDF IVISTO: un ufficio nuovo va aggiunto in entrambi i progetti.

---

## 5. Struttura HTML generata da `renderDoc`

Il documento è un singolo `<div class="card">` con 4 sezioni interne più footer.

### 5.1 Header card

```html
<div class="card">
  <div class="card-head">
    <span>Notifica di Uscita — CC599C</span>
    <span class="badge {code.badge}">
      <span class="dot dot-{code.dot}" style="margin-right:4px"></span>
      {code.label}
    </span>
  </div>
  ...
</div>
```

### 5.2 Sezione 1 — Esito controllo uscita

```html
<div class="doc-section">
  <div class="doc-section-title">Esito controllo uscita</div>

  <!-- Result block colorato in base al codice -->
  <div class="result-block result-{A1|A2|A3|B|default}">
    <div class="result-code">{rc} — {code.label}</div>
    <div class="result-desc">{code.desc}</div>
  </div>

  <!-- 3 stat boxes: 2+1 a schermo, su una riga in stampa (stat-grid-3) -->
  <div class="stat-grid stat-grid-3">
    {ivSb(transit ? "Data uscita certificata" : "Data uscita effettiva", ivistoFmtDate(exitDate))}
    {ivSb("Uscita conclusa in data", ivistoFmtDate(prepDate))}
    {ivSb("Movimento in transito",   inTransito)}
  </div>
</div>
```

### 5.3 Sezione 2 — Dichiarazione di esportazione

```html
<div class="doc-section">
  <div class="doc-section-title">Dichiarazione di esportazione</div>
  <div class="stat-grid">

    <!-- MRN: full-width, monospace, link cliccabile -->
    <div class="stat-box full">
      <div class="stat-label">MRN — Movement Reference Number</div>
      <div class="stat-value mono">
        <a class="mrn-link" href="https://www.adm.gov.it/..." target="_blank"
           onclick="ivistoOpenMrn('{mrn}')">
          {mrn}<span class="screen-only"> ↗</span>
        </a>
      </div>
    </div>

    <!-- Ufficio esportazione (metà larghezza) -->
    {officeBox("Ufficio doganale di esportazione", exportRef)}

    <!-- Ufficio di uscita (metà larghezza) -->
    {officeBox(transit ? "Ufficio di uscita (partenza del transito)" : "Ufficio doganale di uscita effettiva", exitRef)}

    <!-- Ufficio destinazione (solo se presente, full-width) -->
    {destRef ? officeBox("Ufficio doganale di destinazione del transito", destRef, true) : ""}
  </div>
  {notaTransito}  <!-- solo se transit = 1 -->
</div>
```

**Nota transito** (`<p class="note-text">`, solo con `transit = 1`): l'ufficio di uscita è l'ufficio di partenza del transito (art. 329, par. 5-6, Reg. (UE) 2015/2447); la merce lascia il territorio doganale dell'Unione con la conclusione del transito all'ufficio di destinazione; la data di uscita certificata corrisponde al vincolo al transito esterno T1 o, per gli altri transiti, all'appuramento del transito (art. 333, par. 2, lett. b-c).

**`officeBox` genera:**
```html
<div class="stat-box [full]">
  <div class="stat-label">{label}<span class="print-only"> — {office.code}</span></div>  <!-- codice nell'etichetta solo in stampa -->
  <div class="stat-value">{office.name} [<span class="tag-unknown">non in rubrica</span>]</div>
  <div class="stat-sub">{office.code}</div>  <!-- solo a schermo, solo per uffici in rubrica -->
</div>
```

Per gli uffici fuori rubrica il codice è già nel nome, quindi non compare né nell'etichetta né nel `stat-sub`.

### 5.4 Sezione 3 — Documenti di supporto (condizionale)

Presente solo se `suppDocs.length > 0`.

```html
<div class="doc-section">
  <div class="doc-section-title">Documenti di supporto ({N})</div>
  <!-- Un blocco per ogni documento -->
  <div class="stat-grid" style="margin-bottom:8px">
    {ivSb("Tipo documento", DOC_TIPI[sd.type] ? sd.type + " — " + DOC_TIPI[sd.type] : sd.type)}
    {ivSb("Riferimento",    sd.ref, false, true)}  <!-- mono=true -->
  </div>
  ...
</div>
```

### 5.5 Sezione 4 — Dati messaggio

```html
<div class="doc-section">
  <div class="doc-section-title">Dati messaggio</div>
  <div class="stat-grid">
    {ivSb("Tipo messaggio",   "CC599C")}
    {ivSb("Mittente sistema", sender || "—")}
    {ivSb("ID messaggio",     msgId  || "—", true, true)}  <!-- full=true, mono=true -->
  </div>
</div>
```

### 5.6 Footer con nota legale

```html
<div style="border-top:1px solid var(--border);padding-top:12px;margin-top:4px">
  <p class="note-text">
    Il messaggio CC599C è la notifica ufficiale di uscita delle merci dal territorio
    doganale dell'Unione Europea, generata dal sistema AES/ECS2 PLUS. Sostituisce il
    precedente IE599 e costituisce prova di esportazione valida ai fini dell'aliquota
    IVA zero ex art. 8 DPR 633/72 (per esiti A1 e A2). Codici uffici aggiornati ad
    aprile 2025 — fonti: ADM lista uffici ufficiale + avviso CNSD 02/04/2025.
  </p>
  <!-- visibile solo in stampa -->
  <p id="printDate" style="display:none">
    Stampato il: <span id="printDateVal"></span>
  </p>
</div>
```

### 5.7 Helper `ivSb`

```js
function ivSb(label, value, full, mono) {
  return '<div class="stat-box' + (full ? " full" : "") + '">' +
    '<div class="stat-label">' + label + '</div>' +
    '<div class="stat-value' + (mono ? " mono" : "") + '">' + value + '</div>' +
    '</div>';
}
```

---

## 6. Sistema a griglia — `stat-grid` / `stat-box`

```css
.stat-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.stat-box {
  background: var(--surface2);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 12px 14px;
  text-align: left;
}
.stat-box.full {
  grid-column: 1 / -1;   /* occupa tutta la larghezza */
}
```

---

## 7. Palette colori — tema dark (schermo)

```css
/* definita su #ivisto-panel */
--bg:       #0f1117
--surface:  #181c27
--surface2: #1e2336
--border:   #2a3050
--border2:  #3a4570
--accent:   #4f8ef7   /* blu */
--accent2:  #2ecc8a   /* verde */
--warn:     #f5a623   /* arancio */
--danger:   #e05555   /* rosso */
--text:     #e8eaf0
--text2:    #8890a8
--text3:    #5a6280
--mono:     'IBM Plex Mono', monospace
--sans:     'IBM Plex Sans', sans-serif
```

### Colori result block (dark)

| Classe | Background | Border | Testo (code + desc) |
|--------|-----------|--------|---------------------|
| `result-A1` | `rgba(79,142,247, 0.08)` | `var(--accent)` #4f8ef7 | `#7fb3ff` |
| `result-A2` | `rgba(46,204,138, 0.08)` | `var(--accent2)` #2ecc8a | `var(--accent2)` |
| `result-A3` | `rgba(245,166,35, 0.08)` | `var(--warn)` #f5a623 | `var(--warn)` |
| `result-B`  | `rgba(224,85,85,  0.08)` | `var(--danger)` #e05555 | `var(--danger)` |
| `result-default` | `var(--surface2)` | `var(--border2)` | testo default |

Tutti i result block hanno `border-left: 3px solid <border-color>`.

### Colori badge

| Classe | Background | Colore testo |
|--------|-----------|--------------|
| `badge-ok`      | `rgba(46,204,138, 0.15)` | `var(--accent2)` verde |
| `badge-info`    | `rgba(79,142,247, 0.15)` | `var(--accent)` blu |
| `badge-warn`    | `rgba(245,166,35, 0.15)` | `var(--warn)` arancio |
| `badge-err`     | `rgba(224,85,85,  0.15)` | `var(--danger)` rosso |
| `badge-neutral` | `var(--surface2)` + border `var(--border)` | `var(--text3)` grigio |

### Dot (pallino colorato nel badge)

```css
.dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%; }
.dot-ok      { background: var(--accent2); }
.dot-info    { background: var(--accent); }
.dot-warn    { background: var(--warn); }
.dot-danger  { background: var(--danger); }
.dot-neutral { background: var(--text3); }
```

---

## 8. Tipografia

| Elemento | Font | Dimensione | Peso | Colore | Note |
|----------|------|-----------|------|--------|------|
| `card-head` | mono | 11px | normale | `var(--text3)` | UPPERCASE, letter-spacing 1px |
| `doc-section-title` | mono | 10px | normale | `var(--text3)` | UPPERCASE, letter-spacing 1px |
| `stat-label` | mono | 10px | normale | `var(--text3)` | UPPERCASE, letter-spacing 0.5px |
| `stat-value` | sans | 13px | 500 | `var(--text)` | |
| `stat-value.mono` | mono | 13px | normale | `var(--accent)` blu | |
| `stat-sub` | mono | 10px | normale | `var(--text3)` | codice ufficio sotto il nome |
| `result-code` | mono | 15px | 600 | dipende da result class | |
| `result-desc` | sans | 12px | normale | dipende da result class | opacity 0.85 |
| `badge` | mono | 10px | 600 | dipende da badge class | |
| `note-text` | sans | 11px | normale | `var(--text3)` | line-height 1.7 |
| `tag-unknown` | mono | 9px | normale | `var(--danger)` | inline, bg rosso chiaro |

---

## 9. Layout strutturale

Il contenuto del viewer è incapsulato in:

```html
<div class="tab-pane" id="tab-ivisto">
  <div id="ivisto-panel">
    <div class="main">                    <!-- max-width: 860px -->

      <div id="uploadCard" class="card"> <!-- nascosto dopo parse OK -->
        ...
      </div>

      <div id="errBox" style="display:none"></div>

      <div id="out" style="display:none">
        <!-- qui viene iniettato l'HTML di renderDoc() -->
      </div>

      <div class="toolbar" id="tb" style="display:none">  <!-- flex, justify-content: flex-end -->
        <button class="btn btn-ghost"   onclick="ivistoClearDoc()">Nuovo file</button>
        <button class="btn btn-primary" onclick="window.print()">Stampa</button>
      </div>

    </div>
  </div>
</div>
```

---

## 10. Stampa / generazione PDF — CSS `@media print`

### 10.1 Elementi nascosti in stampa

```css
.topbar, .tabs, #tab-rec, #tab-admin { display: none !important; }
#ivisto-panel .toolbar { display: none !important; }
#ivisto-panel #uploadCard { display: none !important; }
```

### 10.2 Elementi forzati visibili

```css
#tab-ivisto { display: block !important; }
```

### 10.3 Override layout

```css
body { background: #fff; color: #111; font-size: 11px; }
.wrap { max-width: 100%; padding: 0; margin: 0; }
#ivisto-panel .main { max-width: 100%; padding: 0; margin: 0; }
```

### 10.4 Override card e stat-box

```css
#ivisto-panel .card {
  background: #fff; border: 1px solid #ccc;
  padding: 12px; margin-bottom: 10px; box-shadow: none;
}
#ivisto-panel .card-head { color: #555; border-bottom-color: #ccc; }
#ivisto-panel .stat-box  { background: #f5f5f5; border-color: #ddd; padding: 8px 10px; }
#ivisto-panel .stat-label { color: #666; }
#ivisto-panel .stat-value { color: #111; font-size: 11px; }
#ivisto-panel .stat-value.mono { color: #1a4d8f; }
#ivisto-panel .stat-sub  { color: #888; }
#ivisto-panel .stat-grid { gap: 6px; }
```

### 10.5 Override result blocks (stampa — colori ad alta leggibilità)

| Classe | Background | Border | Testo (code + desc) |
|--------|-----------|--------|---------------------|
| `result-A1` | `#e8eef9` | `#3a6ec0` | `#1a3d8f` (blu scuro) |
| `result-A2` | `#e8f7ee` | `#2a9e6a` | `#1a5c3a` (verde scuro) |
| `result-A3` | `#fdf3e3` | `#c07a10` | `#7a4d00` (arancio scuro) |
| `result-B`  | `#fdeaea` | `#b03030` | `#8f1a1a` (rosso scuro) |

Tutti con `!important`.

### 10.6 Override tipografia stampa

```css
#ivisto-panel .result-block  { padding: 10px 12px; margin-bottom: 10px; }
#ivisto-panel .result-code   { font-size: 13px; }
#ivisto-panel .result-desc   { font-size: 10px; opacity: 1; }
#ivisto-panel .doc-section   { margin-bottom: 12px; }
#ivisto-panel .doc-section-title { font-size: 9px; color: #888; padding-bottom: 4px; margin-bottom: 6px; }
#ivisto-panel .badge         { font-size: 9px; }
#ivisto-panel .tag-unknown   { background: #fdeaea; color: #c00; border-color: #faa; }
#ivisto-panel .note-text     { font-size: 9px; color: #888; }
```

### 10.7 Impaginazione allineata al PDF IVISTO di App2DoReader

La stampa riproduce il PDF generato da `alifresca._generate_ivisto_pdf`:

```css
@page { size: A4 portrait; margin: 8mm 10mm; }
#ivisto-panel, #ivisto-panel .card { font-family: Helvetica, Arial, var(--sans); }  /* mono solo per MRN e riferimenti */
#ivisto-panel .card-head { background: #f3f3f3; border: 1px solid #ccc; font-size: 13px; font-weight: 600; text-transform: none; }
#ivisto-panel .card-head .badge { background: #fff; border: 1px solid currentColor; }  /* colore scuro per esito */
#ivisto-panel .card-head .dot { display: none; }
#ivisto-panel .stat-grid-3 { grid-template-columns: 1fr 1fr 1fr; }   /* esito su una riga */
#ivisto-panel .stat-value { font-weight: 600; }
#ivisto-panel .stat-sub, #ivisto-panel .screen-only { display: none !important; }
#ivisto-panel .print-only { display: inline; }   /* codice ufficio nell'etichetta */
#ivisto-panel .mrn-link { text-decoration: none; }
```

Spigoli vivi (`border-radius: 0`) per stat-box, result-block e badge, nota in testo giustificato.

### 10.8 Data di stampa

Il campo `#printDate` è `display:none` a schermo e viene reso visibile solo in stampa.  
Il testo viene impostato da:

```js
window.addEventListener("beforeprint", () => {
  const now = new Date();
  const mo = ["gen","feb","mar","apr","mag","giu","lug","ago","set","ott","nov","dic"];
  document.getElementById("printDateVal").textContent =
    now.getDate() + " " + mo[now.getMonth()] + " " + now.getFullYear();
  document.getElementById("printDate").style.display = "block";
});
window.addEventListener("afterprint", () => {
  document.getElementById("printDate").style.display = "none";
});
```

---

## 11. Interazione click MRN

Il testo MRN nella sezione "Dichiarazione di esportazione" è cliccabile:

```html
<a class="mrn-link"
   href="https://www.adm.gov.it/portale/notifica-di-esportazione-del-m.r.n.-movement-reference-number-"
   target="_blank" rel="noopener"
   onclick="ivistoOpenMrn('{mrn}')"
   title="Apri su ADM · MRN copiato negli appunti">
  {mrn} ↗
</a>
```

`ivistoOpenMrn(mrn)`: copia il valore MRN negli appunti via `navigator.clipboard.writeText` (fallback con `execCommand('copy')`). Il link apre la pagina ADM di ricerca MRN in una nuova scheda.

---

## 12. Validazione server-side — `POST /api/ivisto/process`

Chiamata effettuata **prima** di mostrare il risultato all'utente. Consuma 1 unità dalla quota token.

**Request body:**
```json
{ "xml": "<contenuto xml>" }
```

**Validazione Python:**
1. XML non vuoto
2. Contiene `<?xml` o `<MRN`
3. Contiene tutti i tag: `MRN`, `ExitControlResult`, `preparationDateAndTime`, `referenceNumber`

**Response:**
```json
{ "valid": true }
```
oppure
```json
{ "valid": false, "error": "Messaggio errore" }
```

---

## 13. Flusso errori

| Condizione | Comportamento |
|-----------|---------------|
| XML non parsabile | Messaggio generico "File XML non valido o non leggibile" in `#errBox`, `#uploadCard` rimane visibile |
| Tag obbligatori mancanti (client) | Lista tag mancanti in `#errBox`, `#uploadCard` rimane visibile |
| Server risponde `valid: false` | Errore server in `#errBox`, `#uploadCard` ri-mostrata |
| Errore fetch | Messaggio errore di connessione in `#errBox` |

---

## 14. Esempio XML CC599C minimo valido

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CC599C>
  <messageSender>SEND001</messageSender>
  <messageIdentification>MSG-2025-04-15-001</messageIdentification>
  <preparationDateAndTime>2025-04-15T10:30:00</preparationDateAndTime>
  <ExitControlResult>
    <code>A2</code>
    <exitDate>2025-04-14</exitDate>
  </ExitControlResult>
  <ExportOperation>
    <MRN>25IT273100AB123456</MRN>
    <transit>0</transit>
  </ExportOperation>
  <CustomsOfficeOfExport><referenceNumber>IT273100</referenceNumber></CustomsOfficeOfExport>
  <CustomsOfficeOfExitActual><referenceNumber>IT273102</referenceNumber></CustomsOfficeOfExitActual>
  <GoodsShipment>
    <SupportingDocument>
      <type>N380</type>
      <referenceNumber>FAT/2025/0042</referenceNumber>
    </SupportingDocument>
  </GoodsShipment>
</CC599C>
```

Gli uffici vanno dentro il loro elemento (`CustomsOfficeOfExport`, `CustomsOfficeOfExitActual` o `CustomsOfficeOfExit`, `CustomsOfficeOfDestination`): un `referenceNumber` fuori da questi elementi non viene letto come ufficio.

---

## 15. Note implementative per ricostruzione

1. **Il PDF è stampa browser** — non c'è conversione server-side. Per generare PDF programmatico (es. ReportLab, WeasyPrint) occorre ricostruire il layout come descritto nelle sezioni 5–10.

2. **La griglia 2 colonne** (`stat-grid`) ha colonne uguali. Il modificatore `.full` porta un elemento a coprire entrambe le colonne.

3. **I colori del result block** hanno una variante dark (semitrasparente) e una variante print (piena, alta leggibilità). Qualsiasi ricostruzione deve mantenere entrambe.

4. **I codici ufficio** hanno una rubrica hardcoded con 189 voci (vedi `OFFICES` in `main.py`), copia di quella di App2DoReader. Voci non trovate mostrano il badge `non in rubrica`.

5. **La sezione documenti di supporto** (§5.4) è condizionale: appare solo se il campo `SupportingDocument` è presente nell'XML.

6. **La sezione destinazione transito** (§5.3) è condizionale: appare solo se `CustomsOfficeOfDestination/referenceNumber` è presente nell'XML. Con `transit = 1` cambiano anche etichette (data certificata, ufficio di partenza del transito) e compare la nota normativa.

7. **Il font IBM Plex** (Mono + Sans) è caricato da Google Fonts; per uso offline serve una copia locale o un font monospazio alternativo.
