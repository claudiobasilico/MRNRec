# SIRIO — Suite Doganale

Piattaforma integrata per operazioni doganali: riconciliazione fatture/MRN e analisi notifiche di uscita CC599C.
Singolo modulo Python — FastAPI — porta **8002**.

**Tre moduli:**
1. **Riconciliazione Fatture** — fatture cliente ↔ dichiarazioni doganali MRN
2. **IVISTO CC599C** — visualizzazione e stampa notifiche di uscita (AES/ECS2 PLUS)
3. **Amministrazione** — gestione token clienti e log attività (solo admin)

---

## Setup rapido

```bash
python -m venv .venv
.venv\Scripts\activate          # Windows
pip install -r requirements.txt
python main.py
```

Apri **http://localhost:8002**

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
| **Frontend** | HTML inline — dark theme — drag&drop — 3 tab (Riconciliazione Fatture, IVISTO, Amministrazione) |

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
├── main.py              # Tutto: server, logica, frontend HTML
├── requirements.txt
├── avvia.bat            # Launcher Windows
├── README.md
├── ALGORITHM.md         # Documentazione algoritmo di matching
└── data/                # Auto-creata al primo avvio
    ├── tokens.json      # Token e configurazioni
    ├── usage.json       # Contatori utilizzo
    ├── profiles.json    # Profili colonne salvati per utente
    ├── activity_log.jsonl  # Log attività (JSONL)
    └── server.log       # Log server uvicorn
```
