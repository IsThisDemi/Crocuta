/**
 * Crocuta — sincronizzazione fra dispositivi.
 *
 * Da incollare in https://script.google.com come nuovo progetto, poi
 * Distribuisci → Nuova distribuzione → Web app, con:
 *   Esegui come:        Io
 *   Chi ha accesso:     Chiunque
 *
 * Poi in Crocuta: Impostazioni -> Sync -> Set Up Sync, e incolla l'URL
 * della distribuzione (finisce con /exec). Sugli altri dispositivi si
 * incolla invece il codice di "Copy Setup Code".
 *
 * "Chiunque" e' necessario perche' l'app non fa il login con Google: la
 * protezione e' un segreto. Non serve sceglierlo: lo genera l'app, e lo
 * script adotta il primo che riceve e da li' in poi accetta solo quello.
 * Non e' autenticazione vera — chi avesse URL e segreto leggerebbe la
 * libreria — quindi qui non va niente che ti dispiacerebbe far leggere.
 * Per preferiti e ascolti va bene.
 *
 * Per ricominciare con un segreto nuovo: Impostazioni progetto -> Proprieta'
 * dello script, cancella "secret".
 *
 * I dati stanno in un file JSON dentro il TUO Drive, non in questo script.
 */

// Vuoto: si adotta il primo segreto ricevuto. Se preferisci fissarlo a
// mano, scrivilo qui e usa lo stesso nel codice di configurazione.
const SECRET = '';

// Il file viene creato al primo salvataggio.
const FILE_NAME = 'yeen-music-sync.json';

function doGet(e) {
  if (!_allowed(e.parameter.secret)) return _deny();
  return _json(_read());
}

function doPost(e) {
  var body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return _json({ error: 'corpo non leggibile' });
  }
  if (!_allowed(body.secret)) return _deny();
  if (body.action !== 'put') return _json({ error: 'azione sconosciuta' });

  // Il blocco evita che due dispositivi che salvano nello stesso istante
  // si sovrascrivano a meta' file.
  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    _write(body.data || {});
    return _json({ ok: true });
  } finally {
    lock.releaseLock();
  }
}

// Il segreto fissato qui sopra o, se vuoto, quello adottato alla prima
// richiesta. Uno corto non si adotta: sarebbe facile da indovinare.
function _allowed(given) {
  given = given || '';
  if (SECRET) return given === SECRET;
  var props = PropertiesService.getScriptProperties();
  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    var mine = props.getProperty('secret');
    if (!mine) {
      if (given.length < 32) return false;
      props.setProperty('secret', given);
      return true;
    }
    return given === mine;
  } finally {
    lock.releaseLock();
  }
}

function _read() {
  var files = DriveApp.getFilesByName(FILE_NAME);
  if (!files.hasNext()) return {};
  try {
    return JSON.parse(files.next().getBlob().getDataAsString());
  } catch (err) {
    return {};
  }
}

function _write(data) {
  var text = JSON.stringify(data);
  var files = DriveApp.getFilesByName(FILE_NAME);
  if (files.hasNext()) {
    files.next().setContent(text);
  } else {
    DriveApp.createFile(FILE_NAME, text, MimeType.PLAIN_TEXT);
  }
}

function _json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(
    ContentService.MimeType.JSON
  );
}

function _deny() {
  return _json({ error: 'segreto non valido' });
}
