# AutoMix — cosa manca rispetto a Spotify e Apple

Ricerca del 2026-11-23: nessun progetto open source riproduce davvero
Spotify Mix o Apple AutoMix, ma da loro e dalla ricerca escono sei passi.
Vincoli che restano validi: un solo percorso AutoMix senza ripieghi, mai
guadagno positivo durante un mix, niente normalizzazione di YouTube.

Stato: `[ ]` da fare, `[~]` in corso, `[x]` fatto.

## 1. [x] Mix sui confini di frase e sulle sezioni
Fatto (2026-11-23): feature per battuta (bassi/medi/acuti/attacchi a mezzo
secondo, analisi v4), novelty di Foote, confini sulle frasi da 8, sezioni
intro/body/breakdown/outro in `phrase_analysis.dart`; si esce sull'"1" di
una frase, il drop dell'entrante cade su una frase dell'uscente; tutto nel
registro del piano.
La transizione parte sull'"1" di una frase da 8/16/32 battute e rispetta
intro, strofa, ritornello, break, outro; oggi parte dove finisce la voce,
che puo' cadere a meta' frase.
- Strada leggera: novelty di Foote su feature per battuta, in Dart, sui
  downbeat che gia' abbiamo da Beat This!.
- Alternative: CUE-DETR (cue point, MIT, ISMIR'24, esportabile in ONNX) —
  https://github.com/ETH-DISCO/cue-detr ; all-in-one (sezioni etichettate,
  MIT, export ONNX difficile per NATTEN) — https://github.com/mir-aidj/all-in-one
- Riferimenti: https://lenvdv.github.io/2018-03-20-autodj ,
  https://github.com/robaerd/mosaikbox

## 2. [x] Piu' stili di transizione, scelti per coppia
Fatto (2026-11-23): `chooseMixStyle` sceglie fra blend, blend corto,
rolling (16-32 battute), cambio sul drop, salita col filtro, eco, taglio
filtrato e dissolvenza (solo a tempi incompatibili), con il perche' nel
registro.
Blend lungo, cambio sul drop, salita col filtro, echo-out, taglio pulito,
dissolvenza semplice: scelti in base a energia e sezioni dei due brani,
come Apple (che a volte fa solo un taglio) e i preset di Spotify
("Auto", "Fade", "Rise").
- Riferimenti: lenvdv/auto-dj (double drop, rolling, relaxed); Spotify
  `getAutoTransitionForTrackPair` (punti d'overlap, durata in battute,
  velocita' dell'entrante) — https://github.com/ranveerthapar025-bit/spicetify-DJ-MOD-automix

## 3. [x] Effetti automatizzati
Fatto (2026-11-23): `highpass`/`lowpass` (`@hp`/`@lp`, neutri col mix a 0)
mossi con `af-command`; eco a tempo (3/4 o 1/2 battito) calcolata nel
tratto separato dell'uscente, perche' `aecho`/`afir` non sono nel libmpv;
riverbero non fatto.
Filter sweep (highpass/lowpass), delay ed eco, riverbero sulla coda
dell'uscente, mossi durante il mix con `af-command` di libmpv.
- Filtri ffmpeg: `highpass`, `lowpass`, `aecho`, `afir` (riverbero),
  `flanger` — LGPL, compatibili.
- Riferimento sugli effetti di Apple (AURemixFX): https://github.com/Peyton-C/pink_diamond

## 4. [~] Separazione in 4 tracce (voce, basso, batteria, resto)
Misurato (2026-11-24), non integrato: nessun modello a quattro tracce oggi
regge su iPhone con la memoria che ci resta, e senza ripieghi non si puo'
tenerlo solo sul Mac. Numeri su Mac M5 Pro, ONNX Runtime 1.32 da Python,
un tratto vero di 30 s (opus a 44,1 kHz), picco = RSS massimo del processo:
- Voc_FT di oggi, per confronto: 64 MB; CoreML 0,12 s a blocco da 5,9 s e
  picco 330 MB; sulla CPU (Windows) 6,4 s per 30 s, picco 2,4-3,8 GB.
- htdemucs v4 (MIT, StemSplitio/htdemucs-onnx, STFT dentro il grafo): 166
  MB in fp16. CPU 5,0 s per 30 s ma picco 3,1 GB; con CoreML 27 s solo per
  caricarlo e 290 s per 30 s (26 partizioni, ScatterND), picco 3,9 GB.
  Scartato.
- SCNet-large (audiojs/scnet-large, int8, 45 MB): 19 s per 30 s, picco 5,4
  GB. Scartato.
- SCNet base (audiojs/scnet, int8, 12,9 MB; codice e pesi MIT, confermati
  dall'autore in starrytong/SCNet#35; addestrato su MUSDB18-HQ, come quasi
  tutti): l'unico candidato. CPU 0,76 s per segmento da 11 s (4 thread),
  1,0 s con un thread solo; 30 s in 4,7 s (9 thread, passo 3/4). CoreML non
  aiuta (le 12 LSTM restano sulla CPU, 13 partizioni: 0,54 s a segmento).
  Picco 1,6 GB anche col minimo (ottimizzazione "basic", arena della CPU
  spenta; 2,4 GB con le impostazioni di serie), e non scende coi thread: e'
  il segmento fisso da 476 fotogrammi.
- Qualita', 50 anteprime di MUSDB18 test, SDR globale mediano: voce SCNet
  9,78 contro Voc_FT 10,57 (peggio in 42 brani su 50), base senza voce
  14,24 contro 14,47; batteria 9,18, basso 8,03, resto 5,94.
Tempi: anche un iPhone due-tre volte piu' lento separa i due tratti di un
mix in 15-20 s, e il mix si decide minuti prima. Il problema e' la memoria:
1,6 GB per un attimo contro i 330 MB di oggi, quando heavy_work.dart ricorda
che due reti da qualche centinaio di MB insieme bastavano a far chiudere
Crocuta da iOS. Su Mac e Windows andrebbe (su Windows anzi meno di Voc_FT).
Riprovato a segmenti piu' corti (2026-11-24), e non basta: riesportato con
export-scnet.py di audiojs (il segmento e' una costante) e compattato in
int8 col loro compact.py (budget 40 dB), stessa macchina, demix di MSST
(dissolvenze di un decimo, bordi riflessi) su tutte e tre, picco della sola
rete con l'arena spenta e ottimizzazione "basic" (fra parentesi con le
impostazioni di serie), SDR mediano sulle stesse 50 anteprime, passo 3/4
(e 1/2):

| segmento | file | 30 s, CPU 4 thread | picco | voce | batteria | basso | resto | base (somma) |
|---|---|---|---|---|---|---|---|---|
| 11 s (audiojs) | 12,9 MB | 3,2 s | 1,6 GB (2,4) | 9,93 | 9,21 | 7,87 | 6,03 | 14,04 |
| 5,5 s | 11,5 MB | 3,3 s | 0,98 GB (1,28) | 9,63 (9,81) | 9,15 (9,32) | 7,77 (7,86) | 5,95 (6,05) | 13,90 (14,09) |
| 2,75 s | 12,9 MB | 3,6 s | 0,53 GB (0,72) | 9,14 (9,56) | 8,74 (8,69) | 7,52 (7,69) | 5,46 (5,68) | 13,59 (14,19) |

Voc_FT sulle stesse: voce 10,57, base 14,47. La memoria scala meno del
segmento (circa 400 MB fissi: 165 MB gia' al caricamento), e la voce
perde contesto: col segmento piu' corto, l'unico vicino ai 500 MB, la voce
e' 1,0-1,4 dB sotto Voc_FT e meglio solo in 3-5 brani su 50. Con 2,75 s
anche il compattatore tiene in int8 solo 39 pesi su 82 (con 11 s 77): il
file non cala. Nessuna variante sostituisce Voc_FT senza perdere la voce,
e la voce e' cio' su cui si decide il mix (pausa, passaggio). Resta da
aspettare un modello a quattro tracce piu' leggero; provarlo sull'iPhone
non serve finche' la voce e' peggio.
L'attesa della pausa nella voce e il controllo del tempo sugli attacchi
non dipendono dalle quattro tracce: si possono fare gia' con voce e base.

Fatto con voce e base (2026-11-24), le quattro tracce restano `[~]`:
- [x] Attesa della pausa nella voce (`vocal_pause.dart`): finita la
  separazione, il volume della voce dell'uscente ogni 20 ms; se lo
  spegnimento (o il passaggio all'entrante) cade mentre canta, va nella
  pausa di almeno un battito piu' vicina, meglio se su un battito, una
  battuta o l'"1" di una frase; mai dopo che canta l'entrante (il
  passaggio di voce fino a due battute dopo, come il piano), mai oltre la
  fine del mix. Senza pausa il piano resta. Nel registro: `mix: voce: ...`.
- [x] Controllo del tempo durante il mix (`mix_sync.dart`): la correzione
  della deriva di prima, che teneva l'entrante sull'orologio, nei mix a
  tempo lo tiene sulla fase dell'uscente che si sente, misurata sulle due
  griglie a ogni fotogramma (posizioni contate all'istante) e corretta ogni
  mezzo secondo sulla mediana: sopra 25 ms un filo di velocita', al massimo
  il 3%, mai un salto. Nel registro: `mix: a tempo a ...` e, alla fine,
  `mix: controllo del tempo: ...`. Sulle griglie e non sugli attacchi della
  batteria: con griglie regolari la fase sulla griglia e' gia' lo scarto
  fra le due casse, e costa niente.

Scambio di basso e batteria separati invece delle bande di EQ, attesa di
una pausa nella voce prima di cambiare, controllo a posteriori che il mix
sia rimasto a tempo (fase e attacchi della batteria).
- Demucs in ONNX (MIT): pesante, da misurare su iPhone.
- Riferimento: https://github.com/VertexSelection/automix-engine (LGPL,
  usa Rubber Band GPL: prendere le idee, non il codice).

## 5. [x] Correzione di tonalita' di un semitono
Fatto (2026-11-24): `keyShiftFor` sposta l'entrante di ±1 semitono con
`format=out-srate` di mpv (`asetrate` non e' nel libmpv) e la velocita'
divisa per il rapporto, cosi' scaletempo2 fa il key-lock; resta fino a
fine brano; nel registro del piano.
Quando le chiavi dei due brani stridono, spostare l'entrante di ±1
semitono, con key-lock sul cambio di velocita'.
- Verificare prima che mpv applichi gia' `scaletempo2` col cambio di
  velocita'.
- Pitch-shift: Signalsmith Stretch (MIT, C++ via FFI) —
  https://github.com/Signalsmith-Audio/signalsmith-stretch . Il filtro
  `rubberband` di ffmpeg e' GPL: da evitare o isolare.

## 6. [~] Curve imparate dai mix di DJ veri
Curve di fader ed EQ generate da un modello addestrato su mix reali.
- DJtransGAN (MIT, ICASSP 2022, modello pre-addestrato): esportare il
  generatore in ONNX, o ricavarne le forme delle curve —
  https://github.com/ChenPaulYu/DJtransGAN
- Beneficio incerto: da confrontare a orecchio con le curve attuali.

Studiato (2026-11-24); i tempi integrati come curve del rolling, la rete
no (sotto, "Fatto").
- Licenza: il codice e' MIT (Bo-Yu Chen, 2022). I pesi (due generatori,
  minmax e least square, 140 MB l'uno, su Google Drive) non hanno una
  licenza loro; sono addestrati su mix di Livetracklist non pubblicati
  "per problemi di licenza" e su brani EDM di MTG-Jamendo, lavoro fatto in
  stage da Sony. Per spedirli servirebbe un "si'" scritto dell'autore,
  come per SCNet.
- Cosa produce: niente curve libere. Per ciascun brano 14 sigmoidi: tre
  incroci di banda (rampe in 20-300, 300-5000, 5000-20000 Hz: quattro
  bande, basso fino a ~250 Hz, medio-basso fino a ~3 kHz, medio-alto fino a
  ~12 kHz, alto) e per ogni banda una dissolvenza lineare in ampiezza,
  inizio e fine dentro la regione di mix. Niente fader generale: le quattro
  bande sono il volume. La forma e' fissa (lineare), il modello sceglie
  solo i tempi. Ingresso: lo spettrogramma mel (128 bande, STFT 2048/512,
  in dB) di 60 s mono di ciascun brano attorno alla regione, l'uscente
  fino alla fine della regione e poi silenzio, l'entrante silenzio fino
  all'inizio, a -12 LUFS; la regione stessa non entra nella rete, scala
  solo i tempi.
- ONNX: si esporta senza problemi (conv, batch norm, tre lineari): 89 MB
  in float32, 22,3 MB coi pesi int8 (parametri entro 0,009), 11 ms a
  coppia sulla CPU, picco 260-375 MB al caricamento. In Dart servirebbe
  la STFT che stem_separator gia' fa, la matrice mel (1025x128, htk) e
  20·log10; la loudness solo per l'ingresso della rete, mai sull'audio.
- Le curve, mediane di 516 transizioni (216 sui due brani EDM del
  repository a molti punti di mix e lunghezze, 300 coppie a caso di
  anteprime MUSDB ripetute; il generatore least square da' le stesse
  entro 0,05), in frazione del mix:
  - uscente: bassi giu' subito e piano (0,02-0,79, -6 dB a 0,41); medio-alti
    0,42-0,98 (-6 dB a 0,70); medio-bassi pieni fino a 0,73 e via entro
    0,93; aria 0,71-0,95.
  - entrante: prima i medio-alti, 3-12 kHz (0,15-0,60, -6 dB a 0,38); poi
    medio-bassi (0,61-0,76) e bassi (0,62-0,90, -6 dB a 0,76) insieme;
    l'aria sopra 12 kHz per ultima (0,80-0,85).
  - Fra un ingresso e l'altro i tempi si spostano di 0,1-0,2 (p10-p90); in
    tre gruppi (k-means) cambia soprattutto quando entrano i medi
    dell'entrante (0,42-0,57 o 0,76-0,85). Anche sul silenzio e sul rumore
    lo schema resta: e' in gran parte una forma a priori.
- Contro blendStage: li' i medi si scambiano a 0,35-0,55 e i bassi a
  0,55-0,70, simmetrici, con l'entrante che sale di volume entro 0,3 con
  gli acuti pieni (-6 dB a 0,12). DJtransGAN fa uscire i bassi
  dell'uscente da subito e lascia un buco (somma dei bassi -13 dB a 0,62,
  blendStage -7 dB), porta i medi e i bassi dell'entrante molto piu' tardi
  (0,69 e 0,76 contro 0,45 e 0,65), tiene i medi dell'uscente fino in fondo
  (somma dei medi 1,84 a 0,76: i due medi pieni insieme per un attimo) e
  non ha un volume a parte. Incroci piu' alti dei nostri (bassi fino a ~250
  Hz contro lo scaffale a 120, medi fino a ~3 kHz contro la campana a 1
  kHz e lo scaffale a 5).
- Proposta: niente rete. Uno stile in piu', `learnedStage`, con i tempi
  mediani qui sopra come rampe smussate (_smooth) sulle nostre tre bande
  (bassi, medi = medio-bassi, acuti = medio-alti), il volume = la banda
  piu' alta e le altre in dB sotto di lui fino ai tagli di sempre, mai
  sopra lo zero (mixGains normalizza la somma dei medi); da provare a
  orecchio contro blendStage sugli stessi mix lunghi. Solo se piace e si
  sente il bisogno di adattarlo alla coppia: chiedere all'autore la
  licenza dei pesi e mettere la rete int8 (22 MB) nella coda di
  heavy_work.

Fatto (2026-11-24): `learnedStage` in automix.dart, la curva del rolling
(16-32 battute) al posto di `rollingStage`, che resta per tornarci con una
riga; blend e blend corto restano su `blendStage`, cosi' si confrontano a
orecchio. Nel registro il perche' del rolling finisce con "curve dai DJ".
- I tempi, in frazione del mix, con le rampe _smooth (stesso inizio e
  stessa fine delle rampe lineari del modello):

  | banda | uscente | entrante |
  |---|---|---|
  | bassi | 0,02-0,50 fino a -7 dB, poi via in 0,63-0,76 (-6 dB a 0,41) | 0,62-0,90 (-6 dB a 0,76) |
  | medi | pieni fino a 0,73, via entro 0,93 | 0,61-0,76 |
  | acuti | 0,42-0,98 (-6 dB a 0,70) | 0,15-0,60 (-6 dB a 0,38) |

- Il volume del player e' la banda piu' alta; le altre in dB sotto di
  lui fino ai tagli di sempre (-26/-12/-12), mai sopra lo zero; mixGains
  normalizza la potenza dei due.
- Differenze dal modello: i bassi dell'uscente non scendono in linea fino
  a 0,79 (somma dei bassi -13 dB a 0,62, -18 con le rampe smussate) ma si
  fermano a -7 dB fra 0,50 e 0,63 e se ne vanno in passo con quelli
  dell'entrante: le casse s'incrociano a -14 dB l'una, la somma resta
  sopra -8 dB. L'aria (sopra 12 kHz) va con gli acuti: lo scaffale a 5 kHz
  non la separa. Prima del loro ingresso le bande dell'entrante stanno ai
  tagli (medi a -12 dB), non a zero.
- La rete non si spedisce: i pesi non hanno licenza, servirebbe il
  permesso scritto dell'autore. Da fare: il confronto a orecchio rolling
  contro blend sugli stessi mix lunghi.
