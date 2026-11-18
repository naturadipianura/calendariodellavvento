-- Eseguire quando si passa al calendario di dicembre, dopo 031.
-- Aggiornare anche month: 12 in _data/advent.yml e pubblicare il sito.
update calendar_private.calendar_settings set year=2026,month=12,preview=false where singleton=true;
