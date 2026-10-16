/// Short rules per game id, shown behind the "i" on the home screen and in
/// the lobby. Paragraphs are separated by blank lines, "• " starts a point.
const Map<String, String> gameRules = {
  'chess': '''
Ziel: den gegnerischen König schachmatt setzen.

• Weiß beginnt, dann wird abwechselnd gezogen.
• Alle Regeln gelten: Rochade, en passant, Bauernumwandlung.
• Remis bei Patt, dreifacher Stellungswiederholung, 50-Züge-Regel oder zu wenig Material.''',
  'battleship': '''
Ziel: die ganze gegnerische Flotte zuerst versenken.

• Flotte: 1× Fünfer, 1× Vierer, 2× Dreier, 1× Zweier. Schiffe dürfen sich nicht berühren.
• Abwechselnd wird auf ein Feld geschossen: Wasser, Treffer oder versenkt.
• Bei einem Treffer darfst du nochmal schießen.''',
  'connect_four': '''
Ziel: vier eigene Steine in eine Reihe bringen – waagerecht, senkrecht oder diagonal.

• Abwechselnd wird ein Stein in eine Spalte geworfen, er fällt nach unten.
• Mit 3 oder 4 Spielern wird das Brett größer.
• Ist das Brett voll ohne Viererreihe, endet es unentschieden.''',
  'checkers': '''
Ziel: dem Gegner keinen Zug mehr lassen (alle Steine schlagen oder blockieren).

• Steine ziehen ein Feld diagonal nach vorn.
• Schlagen ist Pflicht, Mehrfachsprünge müssen zu Ende gezogen werden.
• Wer die gegnerische Grundlinie erreicht, wird Dame. Damen ziehen und schlagen über beliebig viele Felder (fliegende Damen).''',
  'mill': '''
Ziel: dem Gegner so viele Steine nehmen, dass er nur noch 2 hat – oder ihn zugunfähig machen.

• Erst setzen beide abwechselnd ihre 9 Steine, dann wird entlang der Linien gezogen.
• Drei eigene Steine in einer Linie sind eine Mühle: Du nimmst dem Gegner einen Stein.
• Mit nur noch 3 Steinen darfst du springen.''',
  'yahtzee': '''
Ziel: die meisten Punkte auf dem Spielzettel.

• Pro Runde bis zu 3 Würfe mit 5 Würfeln. Würfel antippen hält sie fest.
• Danach trägst du das Ergebnis in ein freies Feld ein – auch mit 0 Punkten.
• Oben zählen die passenden Augen; ab 63 Punkten gibt es 35 Bonus.
• Unten: Dreier- und Viererpasch (Augensumme), Full House 25, kleine Straße 30, große Straße 40, Fünferpasch 50, Chance (Summe).
• Jeder weitere Fünferpasch bringt 100 Bonus, wenn dort schon 50 stehen.
• Joker: Ein weiterer Fünferpasch muss ins passende obere Feld, wenn es frei ist; sonst zählen Full House und Straßen voll.''',
  'boxes': '''
Ziel: die meisten Kästchen schließen.

• Abwechselnd zieht jeder einen Strich zwischen zwei benachbarten Punkten.
• Wer die vierte Seite eines Kästchens zieht, bekommt es und ist nochmal dran.''',
  'ludo': '''
Ziel: als Erster alle 4 Figuren ins Ziel bringen.

• Mit einer 6 kommt eine Figur heraus – das ist Pflicht, wenn es geht. Das Startfeld muss danach frei gemacht werden.
• Nach einer 6 darfst du nochmal würfeln.
• Ohne Figur auf dem Feld hast du 3 Versuche für eine 6.
• Landest du auf einer fremden Figur, muss sie zurück ins Haus.
• Im Ziel wird nicht übersprungen.''',
  'domino': '''
Ziel: als Erster 100 Punkte.

• Steine werden an ein Ende der Kette angelegt; die Augenzahl muss passen.
• Kannst du nicht anlegen, ziehst du; ist nichts mehr zu ziehen, passt du.
• Wer seine Steine zuerst los ist, bekommt die Augen aller anderen Hände.
• Geht nichts mehr, gewinnt die Runde, wer die wenigsten Augen hat.''',
  'halma': '''
Ziel: alle eigenen Figuren ins gegenüberliegende Dreieck bringen.

• Ein Zug geht auf ein freies Nachbarfeld – oder springt über eine Figur.
• Sprünge dürfen beliebig aneinandergereiht werden.
• Geschlagen wird nicht.''',
  'bingo': '''
Ziel: als Erster eine Reihe voll haben und BINGO rufen.

• Jeder hat eine Karte mit 25 Feldern, die Mitte ist frei.
• Es werden Kugeln von 1 bis 75 gezogen; gezogene Zahlen streichst du an.
• Eine Reihe zählt waagerecht, senkrecht oder diagonal.''',
  'lastcard': '''
Ziel: als Erster alle Karten loswerden.

• Jeder bekommt 7 Karten. Gelegt wird, was in Farbe oder Symbol passt.
• Aussetzen, Richtungswechsel und +2 wirken auf den nächsten Spieler.
• Farbwunsch und +4 passen immer; du wünschst dir eine Farbe.
• Kannst du nicht legen, ziehst du eine Karte und darfst sie gleich spielen.
• Vor der vorletzten Karte „Letzte Karte!“ rufen – sonst gibt es 2 Strafkarten.''',
  'prophet': '''
Ziel: die meisten Punkte, indem du deine Stiche genau vorhersagst.

• In Runde n bekommt jeder n Karten. Die nächste Karte zeigt Trumpf (Narr: kein Trumpf, Zauberer: der Geber wählt).
• Vor dem Spielen sagt jeder an, wie viele Stiche er macht.
• Farbe muss bedient werden; Zauberer und Narren dürfen immer.
• Der erste Zauberer gewinnt den Stich, sonst der höchste Trumpf, sonst die höchste Karte der ausgespielten Farbe.
• Genau getroffen: 20 + 10 pro Stich. Daneben: −10 pro Stich Unterschied.''',
  'stapelfix': '''
Ziel: als Erster den eigenen Stapel leeren.

• In der Mitte wird gemeinsam von 1 bis 12 gestapelt; Joker passen überall.
• Du darfst von Hand, Stapel und Ablagen beliebig viel anlegen.
• Dein Zug endet, wenn du eine Handkarte auf eine deiner 4 Ablagen legst.
• Ist deine Hand leer, ziehst du wieder 5 Karten.''',
  'darts': '''
Ziel je nach Modus:

• 501 / 301: von der Startzahl auf genau 0 herunterwerfen. Der letzte Pfeil muss ein Doppel sein; wer überwirft, verliert die Aufnahme.
• Rund um die Uhr: der Reihe nach 1 bis 20 treffen, zum Schluss das Bull.
• Pro Aufnahme 3 Pfeile. Zielen per Finger – oder werfen mit Handybewegung.''',
  'labyrinth': '''
Ziel: die Kugel ins Ziel rollen.

• Kippe das Handy, um die Kugel zu lenken.
• Fällt sie in ein Loch, geht es von vorn los.
• Die Level werden immer größer und haben mehr Löcher.''',
  'arrows': '''
Ziel: alle Pfeile vom Feld tippen.

• Ein angetippter Pfeil fliegt in seine Richtung hinaus.
• Steht ein anderer Pfeil im Weg, prallt er ab und du verlierst ein Herz.
• Ohne Herzen ist das Level verloren.''',
  'dice': '''
Würfel für Brettspiele.

• 1 bis 6 Würfel wählen, antippen oder Handy schütteln zum Würfeln.
• Ein angetippter Würfel wird beiseitegelegt und behält seine Zahl.
• Die letzten Würfe stehen mit ihrer Summe in der Liste.''',
  'snake': '''
Ziel: möglichst lang werden.

• Lenke die Schlange zum Futter; jedes Stück macht sie länger.
• Wand oder eigener Schwanz beendet das Spiel – außer im Modus ohne Wände.''',
  'klondike': '''
Ziel: alle Karten nach Farbe von Ass bis König auf die vier Ablagen bringen.

• Auf dem Tisch wird absteigend in wechselnden Farben (rot/schwarz) angelegt.
• Auf ein leeres Feld darf nur ein König.
• Vom Stapel ziehst du 1 oder 3 Karten, beliebig oft.
• Punkte wie bei Windows-Solitär, mit Zeitbonus beim Gewinnen.''',
  'mahjong': '''
Ziel: alle Steine paarweise abräumen.

• Zwei gleiche Steine antippen räumt sie ab.
• Ein Stein ist frei, wenn nichts auf ihm liegt und links oder rechts kein Stein anliegt.
• Geht nichts mehr, kannst du die übrigen Steine mischen.''',
  'billiard': '''
Allein: alle 15 Kugeln mit möglichst wenigen Stößen versenken. Fällt die weiße Kugel, kostet das einen Strafstoß.

8-Ball zu zweit:
• Wer zuerst eine Kugel versenkt, spielt diese Gruppe (Volle oder Halbe).
• Du bleibst dran, solange du eigene Kugeln versenkst.
• Foul (weiße Kugel fällt, nichts oder zuerst eine fremde Kugel getroffen): der Gegner ist dran.
• Die 8 zuletzt und ohne Foul versenken gewinnt – zu früh oder mit Foul verliert.''',
  'schocken': '''
Ziel: keine Deckel bekommen. Wer am Ende verliert, gibt eine Runde aus 🍺

• Jede Runde würfelt jeder einmal: bis zu 3 Würfe mit 3 Würfeln. Würfel antippen hält sie fest.
• Wer die Runde beginnt, legt vor: So oft er würfelt, so oft dürfen die anderen höchstens.
• Zwei Sechsen dürfen zu einer Eins gedreht werden (6 6 → 1).

Wertung, von hoch nach niedrig:
• Schock aus (1-1-1): Der Schlechteste verliert sofort die Hälfte.
• Schock 6 bis Schock 2 (1-1-x): x Deckel.
• General (drei Gleiche): 3 Deckel.
• Straße (z. B. 3-4-5): 2 Deckel.
• Alles andere als Zahl gelesen (6-4-2 = 642): 1 Deckel.
• Gleiche Würfe: Wer weniger Würfe gebraucht hat, ist besser, sonst wer zuerst geworfen hat.

Deckel:
• Der Schlechteste der Runde bekommt so viele Deckel, wie der beste Wurf wert ist – erst aus dem Topf (13 Deckel), danach vom Besten.
• Ist der Topf leer, ist raus, wer keine Deckel hat.
• Wer alle 13 Deckel hat, verliert die Hälfte. Der Verlierer einer Runde fängt die nächste an.
• Es gibt zwei Hälften. Verliert einer beide, hat er verloren; sonst spielen die beiden Verlierer das Finale.''',
};
