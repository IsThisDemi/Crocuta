/// Quanto puo' valere al massimo un ascolto, in secondi.
///
/// Un ascolto non dura piu' del brano: il tempo in piu' e' un errore, non
/// musica. Ne e' uscito uno da 39 ore, contato dall'orologio con dentro
/// una notte di pausa. Mezzo minuto di margine per le velocita' di
/// AutoMix; senza durata nota, un quarto d'ora.
int listenCap(int? durationSeconds) =>
    durationSeconds != null && durationSeconds > 0
    ? durationSeconds + 30
    : 15 * 60;
