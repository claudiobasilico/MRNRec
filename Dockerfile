FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /code

# tzdata per il fuso orario (vedi ENV TZ sotto).
RUN apt-get update && apt-get install -y --no-install-recommends tzdata \
    && rm -rf /var/lib/apt/lists/*

# Dipendenze PRIMA del codice: il layer resta in cache e un rebuild sul solo
# codice dura secondi invece di minuti.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Tutti i dati di esercizio (tokens.json, usage.json, profiles.json,
# activity_log.jsonl, server.log) stanno in DATA_DIR, che è il bind mount sull'host.
ENV DATA_DIR=/data
RUN mkdir -p /data

# main.py usa datetime.now() naive: i timestamp di token, activity log e
# server.log sono letti come ora italiana. In UTC (default dell'immagine)
# slitterebbero di una o due ore rispetto allo storico.
ENV TZ=Europe/Rome
RUN ln -snf /usr/share/zoneinfo/Europe/Rome /etc/localtime && \
    echo "Europe/Rome" > /etc/timezone

EXPOSE 8000

# "/" serve la pagina dell'app senza token: l'unica rotta che un container
# sano restituisce con 200 senza autenticazione.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/', timeout=3)" || exit 1

# Un processo solo: token e contatori di utilizzo sono caricati in memoria
# all'avvio (TOKENS, USAGE in main.py) e riscritti su file a ogni modifica.
# Con più worker ognuno avrebbe la sua copia e i contatori divergerebbero.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
