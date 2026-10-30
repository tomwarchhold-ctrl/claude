# Rechnungen (Ronny Hübscher Bauservice)
Neue Rechnung erstellen: `rechnung/erstellen.py` + `rechnung/vorlage.docx` nutzen (Format siehe Docstring im Skript).
Nur JSON schreiben und Skript ausführen, nicht die Vorlage neu analysieren.
Nächste Rechnungsnummer: letzte + 1 (zuletzt vergeben: 2026043, Fa. Exakt Madrid). Hinweis: 2026041 ging an Fa. Exakt (Branch claude/tender-goodall-ug4dey), 2026042 an Wundsch-Udvari.
Positionen netto, MwSt. 19 % wird ergänzt. Fertige .docx immer per SendUserFile als Download an den Nutzer schicken.
WICHTIG: Immer exakt das Format der Vorlage/der bisherigen Rechnungen einhalten (Zeilen "Summe (netto)", "zzgl. 19 % MwSt.", "Gesamtbetrag (brutto):"), nichts eigenmächtig ändern.
Abweichendes Zahlungsziel: im JSON "zahlungsziel_tage":14 (Standard 7).
