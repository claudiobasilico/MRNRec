# Deploy di MRNRec su server

**Destinatario:** sistemista che installa e aggiorna il server

Runbook operativo completo. Non rimanda a documenti esterni di proposito:
questo file è l'unico che arriva a chi esegue materialmente il deploy.

**Slug:** `mrnrec` · **Porta host:** `8013` · **`APP_HOME`:** `/opt/mrnrec`

Lo stack ha un solo container, `app`: l'applicazione web (riconciliazione
fatture/MRN, IVISTO CC599C, fatturazione, amministrazione token), porta
`8013` → 8000.

## 0. Differenza dallo standard della suite: niente `.env`

Questa app non ha variabili d'ambiente applicative. L'unica configurazione
sono i **token di accesso**, che stanno in `data/tokens.json` e si gestiscono
dalla scheda *Amministrazione* dell'app (token admin). Per questo non c'è
`.env` da creare né `.env.example` nel repo.

```
/opt/mrnrec/data/            → /data nel container
├── tokens.json              token di accesso, admin compreso (chmod 600)
├── usage.json               utilizzi consumati per token
├── profiles.json            profili di mappatura colonne salvati
├── activity_log.jsonl       log delle attività (letto dalla scheda Amministrazione)
└── server.log               log dell'applicazione
```

## 1. Preparare l'host

```bash
sudo mkdir -p /opt/mrnrec/data
```

## 2. Portare i dati dall'installazione attuale

> **Prima di tutto fermare l'installazione attuale** (`avvia.bat`, porta
> 8002). Token e contatori sono letti all'avvio e riscritti a ogni utilizzo:
> due installazioni attive consumerebbero ognuna i propri contatori, e i
> clienti si troverebbero con utilizzi diversi a seconda dell'indirizzo usato.

Copiare il contenuto della cartella `data/` del progetto attuale in
`/opt/mrnrec/data/`:

| Da copiare | Perché |
|---|---|
| `tokens.json` | **indispensabile**: senza, al primo avvio viene generato un nuovo token admin e i token dei clienti non funzionano più |
| `usage.json` | utilizzi già consumati: senza, i contatori ripartono da zero |
| `profiles.json` | profili di mappatura colonne salvati dagli utenti |
| `activity_log.jsonl` | storico attività mostrato nella scheda Amministrazione |

`server.log` non serve: il container ne apre uno nuovo.

```bash
# esempio da una macchina che vede la cartella del progetto
scp data/tokens.json data/usage.json data/profiles.json data/activity_log.jsonl utente@server:/tmp/mrnrec/
# sul server
sudo cp /tmp/mrnrec/* /opt/mrnrec/data/
sudo chmod 600 /opt/mrnrec/data/tokens.json
rm -r /tmp/mrnrec
```

**Prima installazione senza dati da migrare:** non copiare nulla. Al primo
avvio l'app genera il token admin e lo scrive nel log del container:

```bash
docker logs mrnrec-app-1 2>&1 | grep "Token admin"
```

Il token resta comunque in `/opt/mrnrec/data/tokens.json` (voce con
`"name": "SIRIO_ADMIN"`).

## 3. Creare lo stack in Portainer

- **Nome:** `mrnrec` (minuscolo: il container si chiama `mrnrec-app-1`)
- **Metodo:** Repository → URL del repo, branch `main`, token GitHub con
  permesso *Contents: read* (repo privato)
- **Environment variables** dello stack, **solo queste due**:

  | Nome | Valore |
  |---|---|
  | `APP_HOME` | `/opt/mrnrec` |
  | `APP_PORT` | `8013` |

## 4. `server` block nginx

L'app riceve file Excel/CSV (fatture, elenco MRN, cassetto doganale, registro
IVA): il limite di 1 MB di default di nginx respingerebbe gli export più
grandi con un 413 che l'app non vede. L'app non ha un limite proprio.

```nginx
server {
    listen 443 ssl;
    server_name mrnrec.<dominio>;

    # Export di registri ed elenchi MRN: alcuni MB, con margine.
    client_max_body_size 30m;

    location / {
        proxy_pass http://127.0.0.1:8013;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Riconciliazione e report di fatturazione su file grandi possono
        # superare i 60s di default.
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
}
```

## 5. Verifica dopo il deploy

```bash
docker ps --filter name=mrnrec                                    # container "healthy"
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8013/   # 200
docker logs mrnrec-app-1 --tail 20                                 # "Uvicorn running on http://0.0.0.0:8000"
date; docker exec mrnrec-app-1 date                               # stessa ora: il container è in Europe/Rome
```

Poi, dal browser: accesso con il token admin, la scheda *Amministrazione*
mostra i token dei clienti con gli utilizzi migrati.

## 6. Aggiornamenti

- **Codice:** push su `main` → in Portainer *Pull and redeploy* (ricostruisce
  l'immagine). I dati in `/opt/mrnrec/data` non vengono toccati.
- **Token:** dalla scheda *Amministrazione*. Non modificare `tokens.json` a
  mano con il container avviato: l'app lo tiene in memoria e lo riscrive a
  ogni modifica, sovrascrivendo la modifica manuale. Se serve, fermare lo
  stack, modificare il file, riavviare.

## 7. Backup

I dati sono file: basta copiare la cartella.

```bash
tar czf mrnrec-$(date +%F).tar.gz -C /opt/mrnrec data
```

## 8. Cosa guardare quando qualcosa non va

| Sintomo | Causa probabile |
|---|---|
| I token dei clienti non funzionano più | `tokens.json` non migrato (§2): l'app ne ha generato uno nuovo con un nuovo token admin |
| Gli utilizzi dei clienti sono ripartiti da zero | `usage.json` non migrato (§2) |
| Una modifica a mano di `tokens.json` sparisce | Fatta con il container avviato (§6) |
| L'upload di un file grande fallisce con una pagina di errore nginx (413) | Manca o è basso `client_max_body_size` (§4) |
| Gli orari nel log attività sono sbagliati di 1-2 ore | Il container non è in `Europe/Rome`: controllare `docker exec mrnrec-app-1 date` |
| "port already allocated" | `APP_PORT` già usata da un altro stack |

## 9. Esecuzione in locale con Docker

Dalla cartella del repo, senza configurare nulla:

```bash
docker compose up --build
# app su http://127.0.0.1:8013, dati nella cartella data/ del progetto
```

Fuori da Docker l'app funziona come sempre (`avvia.bat`, porta 8002): senza
`DATA_DIR`, i dati stanno nella cartella `data/` del progetto.
