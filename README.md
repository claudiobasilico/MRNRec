# SIRIO — Suite Doganale

Piattaforma integrata per operazioni doganali: riconciliazione fatture/MRN, analisi notifiche di uscita CC599C e reportistica fatturazione.
Singolo modulo Python — FastAPI — porta **8002**.

**Quattro moduli:**
1. **Riconciliazione Fatture** — fatture cliente ↔ dichiarazioni doganali MRN
2. **IVISTO CC599C** — visualizzazione e stampa notifiche di uscita (AES/ECS2 PLUS)
3. **Fatturazione** — report Excel per emissione fatture da estratto cassetto doganale (solo admin)
4. **Amministrazione** — gestione token clienti e log attività (solo admin)

---

## Setup rapido

```bash
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
python main.py
```

Apri **http://localhost:8002**

### Con Docker

```bash
docker compose up --build
```

Apri **http://127.0.0.1:8013**. I dati restano nella cartella `data/` del progetto
(nel container `DATA_DIR=/data`). Deploy su server (Portainer, nginx, migrazione dei
dati): `docs/DEPLOY.md`.

---

## Primo avvio — Token Admin

Al primo avvio il sistema genera automaticamente un **token admin** e lo
stampa in console. Salvalo: è l'unico modo per accedere al pannello di
amministrazione e creare token per i clienti.

Il token viene salvato in `data/tokens.json`.

---

## Architettura (singolo file `main.py`)

| Sezione | Contenuto |
|---------|-----------|
| Token Store | Carica/salva `data/tokens.json` — struttura `{token: {name, max_uses, active, ...}}` |
| Usage Store | Carica/salva `data/usage.json` — contatore `{token: int}` |
| Activity Log | Append JSONL su `data/activity_log.jsonl` — chi/cosa/quando/risultati |
| **Riconciliazione Fatture** | |
| Normalizzazione | raw → uppercase → rimuovi prefissi → alnum → numeric_core → suffix |
| Matching Engine | 5 metodi: esatto, normalizzato, numero+anno, suffix≥5, Levenshtein |
| Scoring | Fattura(60) + Data(15) + Cliente(10) + Paese(5) + Importo(10) = max 100 |
| Output Excel | Codice colore per classe match, tutte le colonne richieste |
| **IVISTO CC599C** | |
| Parser XML | DOMParser nativo — parsing e validazione messaggio CC599C (client-side) |
| Exit Codes | 8 codici esito (A1-A5, B1-B3) con descrizioni legali complete |
| Office DB | ~120 codici uffici doganali IT + CH + principali EU |
| MRN Link | Click sull'MRN apre il portale ADM e copia il valore negli appunti |
| Rendering | HTML con colori semantici per classe match, allineamento sinistra |
| Stampa | Tema light automatico, nasconde UI app, stampa pulita A4 |
| Token consumo | 1 token consumato per ogni visualizzazione documento IVISTO |
| **Fatturazione** | |
| Parser input | Legge file XLS (formato HTML) esportato da app2do.it — cassetto doganale |
| Filtro | Solo righe con almeno un file allegato (Nome File 1/2/3 non vuoti) |
| Categorizzazione | Export (01/1T/2T/02/3T/03) · Transito (8T/08) · Import (resto) |
| Registro MRN | Estratto da byte 8-9 dell'MRN |
| Output Excel | Tab Riepilogo + 1 tab per dichiarante con breakdown giornaliero per registro |
| **Frontend** | HTML inline — dark theme — drag&drop — 4 tab (Riconciliazione Fatture, IVISTO, Fatturazione, Amministrazione) |

---

## Endpoint API

### Riconciliazione (backend)

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/me` | Stato token corrente (utilizzi, limite) |
| POST | `/api/reconcile` | Riconciliazione → JSON |
| POST | `/api/export` | Riconciliazione → Excel download |

### IVISTO CC599C (backend)

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| POST | `/api/ivisto/process` | Valida XML e consuma 1 token — il parsing avviene client-side |

> Il file XML CC599C non viene mai inviato al server integralmente. Il server valida solo che il token sia attivo e scala il contatore utilizzi.

### Fatturazione (backend)

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| POST | `/api/fatturazione/report` | Analizza XLS cassetto doganale → Excel report multi-tab (solo admin) |

### Admin (backend)

| Metodo | Endpoint | Descrizione |
|--------|----------|-------------|
| GET | `/api/admin/tokens` | Lista token (solo admin) |
| POST | `/api/admin/tokens` | Crea token (solo admin) |
| PATCH | `/api/admin/tokens/{token}` | Modifica token (solo admin) |
| GET | `/api/admin/logs` | Log attività (solo admin) |

---

## Modulo Riconciliazione Fatture

1. Accedi con il tuo token
2. Carica file Excel/CSV: estratto cassetto doganale (MRN) + lista fatture
3. Configura mapping colonne (opzionale — salva profili per riuso)
4. Avvia riconciliazione
5. Visualizza risultati: CERTO (≥95), PROBABILE (85-94), POSSIBILE (70-84), DEBOLE (50-69), NO MATCH (<50)
6. Esporta Excel con colori codificati

---

## Modulo IVISTO CC599C

Visualizza notifiche di uscita doganale (CC599C) emesse dal sistema AES/ECS2 PLUS.

1. Accedi con il tuo token
2. Vai alla scheda **IVISTO CC599C**
3. Opzioni:
   - **Carica file**: seleziona o trascina file `.xml` CC599C
   - **Incolla XML**: incolla il contenuto direttamente
4. Visualizza:
   - Esito controllo uscita (A1-A5 = OK, B1-B3 = problemi)
   - MRN e dati movimento — **clicca sull'MRN** per aprire il portale ADM e copiarlo negli appunti
   - Uffici doganali di esportazione/uscita
   - Documenti di supporto
   - Data e mittente messaggio
5. **Stampa**: genera PDF/carta A4 — stampa pulita senza UI

> Ogni visualizzazione di un documento IVISTO consuma 1 utilizzo del token.

**Codici esito:**
- **A1**: Conforme (controllo fisico completo)
- **A2**: Ritenuto conforme (controllo documentale) — prova IVA art. 8 DPR 633/72
- **A3**: Procedura semplificata (nessun controllo)
- **A4-A5**: Difformità minori (rilascio comunque)
- **B1**: Difformità maggiori → contatta ufficio doganale
- **B2**: Merce non trovata
- **B3**: Non applicabile

### Scelte tecniche — rendering IVISTO

| Aspetto | Scelta | Motivazione |
|---------|--------|-------------|
| **PDF/Stampa** | `window.print()` nativo browser | Nessuna dipendenza server-side (ReportLab, WeasyPrint), zero latenza, output fedele al layout |
| **Parsing XML** | `DOMParser` browser nativo | Il file XML non viene mai inviato al server — privacy by design |
| **Tema stampa** | CSS `@media print` separato | Converte automaticamente dark theme → layout chiaro A4 senza codice aggiuntivo |
| **Colori semantici** | Classi `result-A1/A2/A3/B` con varianti dark + print | Stessa struttura HTML, solo la palette cambia tra schermo e carta |
| **Rubrica uffici** | ~150 voci hardcoded JS | Evita una chiamata API per ogni documento; aggiornabile centralizzando l'oggetto `OFFICES` |
| **Consumo token** | Validazione + decrement server-side su `/api/ivisto/process` | Il server non riceve l'XML completo (solo conferma), ma scala il contatore prima di mostrare il risultato |
| **MRN cliccabile** | Link verso portale ADM + copia clipboard | Evita copia manuale del codice a 18 caratteri; il link ADM non accetta parametri URL quindi si copia |

> Specifica di rendering dettagliata (struttura HTML, CSS completo, palette, stampa): `IVISTO_CC599C_RENDER_SPEC.md`

---

## Modulo Fatturazione (solo admin)

Genera un report Excel per l'emissione delle fatture del servizio di scarico dal cassetto doganale.

### Come estrarre il file di input da app2do.it

1. Accedi a [www.app2do.it](https://www.app2do.it)
2. Menu principale → **Bollette**
3. **Gestione → MRN pervenuti**
4. Applica filtro su **Data acquisizione**: `≥ data inizio` e `≤ data fine`
5. Clicca **Stampa** → **Esporta in Excel**
6. Carica il file `.xls` nella scheda Fatturazione di SIRIO

> Il file esportato da app2do.it è in formato HTML rinominato `.xls` — SIRIO lo gestisce nativamente.

### Utilizzo

1. Accedi con token ADMIN → scheda **Fatturazione**
2. Carica il file XLS estratto da app2do.it
3. Verifica l'anteprima: totali per categoria e breakdown registri
4. Clicca **Genera Report** → download automatico Excel

### Struttura del report Excel

| Tab | Contenuto |
|-----|-----------|
| `Riepilogo` | Una riga per dichiarante: Export / Transito / Import / Totale del periodo |
| `<Ragione Sociale>` × N | Per giorno: colonne per registro (01, 1T, ecc.) + totali categoria + totale giornaliero |

**Categorizzazione registri MRN (byte 8-9):**
- **Export**: `01` `1T` `2T` `02` `3T` `03`
- **Transito**: `8T` `08`
- **Import**: tutti gli altri (`04`, `4T`, ecc.)

> Sono incluse solo le righe con almeno un file allegato (Nome File 1/2/3 non vuoti). Le dichiarazioni senza documento scaricato vengono escluse dal computo.

---

## Gestione token clienti

1. Accedi con token ADMIN → scheda **Amministrazione**
2. Crea un nuovo token: nome cliente + numero utilizzi (es. 10)
3. Copia e invia il token al cliente
4. Il cliente lo incolla nel login box dell'app
5. Ogni riconciliazione, ogni export e ogni visualizzazione IVISTO consumano 1 utilizzo
6. Puoi sospendere, riattivare o estendere i token in qualsiasi momento

---

## Accesso e privacy

- Il token è richiesto ad ogni accesso
- È obbligatorio accettare l'informativa privacy prima di accedere
- I file caricati non vengono mai conservati sul server
- I dati sono elaborati in memoria e eliminati al termine dell'operazione

---

## Struttura file

```
MRNRec/
├── main.py                        # Tutto: server, logica, frontend HTML
├── requirements.txt
├── avvia.bat                      # Launcher Windows
├── Dockerfile, docker-compose.yml # Container (standard della suite, porta host 8013)
├── docs/DEPLOY.md                 # Runbook di deploy su server
├── README.md
├── ALGORITHM.md                   # Documentazione algoritmo di matching fatture/MRN
├── IVISTO_CC599C_RENDER_SPEC.md   # Specifiche di rendering CC599C (HTML, CSS, stampa)
└── data/                          # Auto-creata al primo avvio
    ├── tokens.json                # Token e configurazioni
    ├── usage.json                 # Contatori utilizzo
    ├── profiles.json              # Profili colonne salvati per utente
    ├── activity_log.jsonl         # Log attività (JSONL)
    └── server.log                 # Log server uvicorn
```
