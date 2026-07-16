# Design — Visualizzatore statico IVISTO CC599C

**Data:** 2026-07-16
**Obiettivo:** estrarre da `main.py` (HTML inline del sistema SIRIO) una pagina HTML statica autonoma, `ivisto_viewer.html`, che replica il viewer IVISTO CC599C con le stesse funzioni, apribile con doppio click senza server.

## Approccio scelto

Estrazione fedele del codice reale da `main.py` (non ricostruzione dalla spec `IVISTO_CC599C_RENDER_SPEC.md`): CSS scopato su `#ivisto-panel`, markup del tab IVISTO, e JavaScript verbatim (`renderDoc`, `EXIT_CODES`, `OFFICES` ~150 uffici, `NATIONS`, `getOffice`, `ivistoFmtDate`, `ivSb`, `officeBox`, `ivistoOpenMrn`, `ivistoClearDoc`, `ivistoSwitchTab`, handler drag-and-drop e stampa). Risultato visivamente identico all'originale.

## Funzioni mantenute

- Caricamento file XML via drag-and-drop o selezione, oppure incolla nel textarea
- Validazione client-side dei tag obbligatori (`MRN`, `ExitControlResult`, `preparationDateAndTime`, `referenceNumber`) con lista errori
- Rendering completo: esito colorato per codice CL393, badge, stat-grid, MRN cliccabile (copia negli appunti + link ADM), risoluzione uffici doganali con tag "non in rubrica", documenti di supporto condizionali, ufficio destinazione transito condizionale, dati messaggio, nota legale
- Pulsanti "Nuovo file" e "Stampa"; `@media print` con tema chiaro ad alta leggibilità e data di stampa

## Differenze rispetto all'originale

1. **Rimossa** la chiamata `POST /api/ivisto/process` (consumo token quota): in `processXML` il risultato viene mostrato direttamente dopo la validazione client-side, che controlla gli stessi tag.
2. Rimosso tutto il resto della suite (topbar, tabs Rec/Admin/Fatturazione, autenticazione).
3. Il contenitore `.main` è centrato (`margin: 0 auto`) invece che allineato a sinistra nel layout a tab.

## Font

IBM Plex Mono/Sans da Google Fonts (come l'originale). Offline la pagina funziona con i font di fallback di sistema.

## Fuori scope

Generazione PDF server-side, rubrica uffici estesa, altre tipologie di messaggio.
